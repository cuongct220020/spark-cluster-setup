# Spark High Availability Cluster với ZooKeeper

Cụm Spark Standalone với High Availability sử dụng ZooKeeper cho master election và failover tự động.

## 🏗️ Kiến trúc

### ZooKeeper Cluster (3 nodes)
- `zookeeper-1`: Port 2181
- `zookeeper-2`: Port 2182  
- `zookeeper-3`: Port 2183

### Spark Master Cluster (3 nodes)
- `spark-master-1`: Port 7077 (Spark), 8080 (Web UI) - **ACTIVE hoặc STANDBY**
- `spark-master-2`: Port 7078 (Spark), 8081 (Web UI) - **ACTIVE hoặc STANDBY**
- `spark-master-3`: Port 7079 (Spark), 8082 (Web UI) - **ACTIVE hoặc STANDBY**

### Spark Workers (3 nodes)
- `spark-worker-1`: Port 8083 (Web UI)
- `spark-worker-2`: Port 8084 (Web UI)
- `spark-worker-3`: Port 8085 (Web UI)

## 🚀 Khởi động cụm

```bash
# Khởi động toàn bộ cluster
docker-compose up -d

# Xem logs
docker-compose logs -f

# Kiểm tra trạng thái
docker-compose ps
```

## 🔍 Kiểm tra trạng thái

### 1. Kiểm tra ZooKeeper Cluster

```bash
# Kiểm tra ZooKeeper node 1
docker exec -it zookeeper-1 zkServer.sh status

# Kiểm tra ZooKeeper node 2
docker exec -it zookeeper-2 zkServer.sh status

# Kiểm tra ZooKeeper node 3
docker exec -it zookeeper-3 zkServer.sh status
```

Kết quả sẽ hiển thị: **leader** (1 node) và **follower** (2 nodes)

### 2. Kiểm tra Spark Master Status

Truy cập Web UI của các Master:
- http://localhost:8080 (Master 1)
- http://localhost:8081 (Master 2)
- http://localhost:8082 (Master 3)

Chỉ có **1 Master** hiển thị status **ALIVE** (active), các Master khác sẽ hiển thị **STANDBY**.

### 3. Kiểm tra Spark Workers

Workers chỉ hiển thị trên Web UI của **Active Master**.

## 📝 Submit Spark Application

### Cú pháp submit với HA

```bash
docker exec -it spark-master-1 spark-submit \
  --master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
  --deploy-mode cluster \
  --class org.apache.spark.examples.SparkPi \
  /opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar \
  1000
```

### Ví dụ với Python

```bash
docker exec -it spark-master-1 spark-submit \
  --master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
  --deploy-mode client \
  /path/to/your/script.py
```

### Supervised Mode (Driver tự động restart)

```bash
docker exec -it spark-master-1 spark-submit \
  --master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
  --deploy-mode cluster \
  --supervise \
  --class YourMainClass \
  /path/to/your/app.jar
```

## 🧪 Test Failover

### Test 1: Kill Active Master

```bash
# Xác định Master nào đang ACTIVE (ví dụ: spark-master-1)
docker stop spark-master-1

# Chờ 10-20 giây và kiểm tra
# Một trong hai Master còn lại sẽ trở thành ACTIVE
# Workers và applications đang chạy sẽ tự động reconnect
```

Kiểm tra logs:
```bash
docker logs spark-master-2 | tail -20
docker logs spark-worker-1 | tail -20
```

Bạn sẽ thấy:
- Master 2 hoặc 3: `I have been elected leader! New state: ALIVE`
- Workers: `Master has changed, new master is at spark://...`

### Test 2: Kill ZooKeeper Node

```bash
# Kill 1 trong 3 ZooKeeper nodes
docker stop zookeeper-1

# Cluster vẫn hoạt động bình thường (quorum = 2/3)
# Spark Master vẫn hoạt động

# Kill thêm 1 node nữa (quorum mất)
docker stop zookeeper-2

# Cluster không thể election Master mới
# Nhưng Master hiện tại vẫn hoạt động
```

### Test 3: Restart Master đã kill

```bash
# Restart Master đã stop
docker start spark-master-1

# Master 1 sẽ khởi động lại ở chế độ STANDBY
```

## 🔧 Troubleshooting

### Kiểm tra logs chi tiết

```bash
# ZooKeeper logs
docker logs zookeeper-1
docker logs zookeeper-2
docker logs zookeeper-3

# Spark Master logs
docker logs spark-master-1
docker logs spark-master-2
docker logs spark-master-3

# Spark Worker logs
docker logs spark-worker-1
docker logs spark-worker-2
docker logs spark-worker-3
```

### Kiểm tra ZooKeeper data

```bash
# Kết nối vào ZooKeeper CLI
docker exec -it zookeeper-1 zkCli.sh

# Trong CLI, kiểm tra Spark HA data
ls /spark-ha
get /spark-ha/master_status
```

### Reset cluster

```bash
# Dừng và xóa tất cả containers
docker-compose down

# Xóa volumes (nếu cần reset hoàn toàn)
docker-compose down -v

# Khởi động lại
docker-compose up -d
```

## ⚙️ Cấu hình tùy chỉnh

### Thay đổi tài nguyên Worker

Chỉnh sửa trong `docker-compose.yml`:

```yaml
environment:
  - SPARK_WORKER_CORES=4      # Tăng số cores
  - SPARK_WORKER_MEMORY=4G    # Tăng memory
```

### Thêm Workers

Thêm service mới vào `docker-compose.yml`:

```yaml
spark-worker-4:
  image: apache/spark:3.5.0
  container_name: spark-worker-4
  # ... tương tự worker khác
```

### Enable Security (nếu cần)

Uncomment các dòng security trong file docker-compose:

```yaml
# - SPARK_RPC_AUTHENTICATION_ENABLED=yes
# - SPARK_RPC_AUTHENTICATION_SECRET=devsecret
# - SPARK_RPC_ENCRYPTION_ENABLED=yes
```

## 📊 Monitoring

### ZooKeeper Metrics

```bash
# Kiểm tra trạng thái
echo stat | nc localhost 2181

# Kiểm tra config
echo conf | nc localhost 2181

# Kiểm tra connections
echo cons | nc localhost 2181
```

### Spark Metrics

Truy cập Web UI:
- Active Master: http://localhost:8080
- Worker 1: http://localhost:8083
- Worker 2: http://localhost:8084
- Worker 3: http://localhost:8085

## 🛑 Dừng cluster

```bash
# Dừng tất cả services
docker-compose down

# Dừng và xóa volumes
docker-compose down -v
```

## 📚 Tham khảo

- [Spark Standalone Mode](https://spark.apache.org/docs/latest/spark-standalone.html)
- [Spark High Availability](https://spark.apache.org/docs/latest/spark-standalone.html#high-availability)
- [ZooKeeper Documentation](https://zookeeper.apache.org/doc/current/)

## ⚠️ Lưu ý quan trọng

1. **Production Setup**: Trong production, nên deploy ZooKeeper và Spark trên các máy vật lý khác nhau
2. **Network**: Đảm bảo network latency thấp giữa các nodes
3. **Resources**: ZooKeeper cần ít tài nguyên, nhưng Spark Master cần memory đủ lớn
4. **Backup**: Backup ZooKeeper data directory định kỳ
5. **Monitoring**: Sử dụng monitoring tools (Prometheus, Grafana) cho production