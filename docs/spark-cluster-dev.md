# Spark Development Cluster (Simple Setup)

Cụm Spark đơn giản cho môi trường development:
- **1 Master** (không HA)
- **3 Workers**
- **1 History Server**

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│         Spark Cluster (Dev)             │
│                                         │
│  ┌──────────────┐                      │
│  │ Spark Master │ (port 8080)          │
│  └──────┬───────┘                      │
│         │                               │
│    ┌────┴────┬────────┐                │
│    │         │        │                │
│ ┌──▼───┐ ┌──▼───┐ ┌──▼───┐           │
│ │Worker│ │Worker│ │Worker│            │
│ │  1   │ │  2   │ │  3   │            │
│ │8081  │ │8082  │ │8083  │            │
│ └──────┘ └──────┘ └──────┘            │
│                                         │
│  ┌────────────────┐                    │
│  │ History Server │ (port 18080)       │
│  └────────────────┘                    │
└─────────────────────────────────────────┘
```

## 📋 Components

| Component | Container Name | Ports | Web UI |
|-----------|---------------|-------|---------|
| **Master** | spark-master | 7077, 8080 | http://localhost:8080 |
| **Worker 1** | spark-worker-1 | 8081 | http://localhost:8081 |
| **Worker 2** | spark-worker-2 | 8082 | http://localhost:8082 |
| **Worker 3** | spark-worker-3 | 8083 | http://localhost:8083 |
| **History** | spark-history | 18080 | http://localhost:18080 |

## 🚀 Quick Start

### 1. Start Cluster

```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### 2. Verify Cluster

```bash
# Check Master UI
curl http://localhost:8080

# Check Worker 1 UI
curl http://localhost:8081

# Check History Server
curl http://localhost:18080
```

### 3. Submit Test Job

```bash
# Submit SparkPi example
docker exec -it spark-master spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode client \
  --class org.apache.spark.examples.SparkPi \
  /opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar 100

# Check result in Master UI
open http://localhost:8080

# After job completes, check History Server
open http://localhost:18080
```

## 📊 Resource Configuration

Mặc định trong `.env`:

```bash
# Per Worker
SPARK_WORKER_CORES=2       # 2 CPU cores
SPARK_WORKER_MEMORY=2G     # 2GB RAM

# Total Cluster Resources
# - 3 workers × 2 cores = 6 cores
# - 3 workers × 2GB = 6GB RAM
```

### Điều chỉnh resources:

```bash
# Edit .env file
SPARK_WORKER_CORES=4
SPARK_WORKER_MEMORY=4G

# Restart cluster
docker-compose restart
```

## 🔧 Common Operations

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f spark-master
docker-compose logs -f spark-worker-1
docker-compose logs -f spark-history
```

### Restart Services

```bash
# Restart all
docker-compose restart

# Restart specific service
docker-compose restart spark-master
docker-compose restart spark-worker-1
```

### Stop Cluster

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (delete all data)
docker-compose down -v
```

### Access Container Shell

```bash
# Access master
docker exec -it spark-master /bin/bash

# Access worker
docker exec -it spark-worker-1 /bin/bash

# Access history server
docker exec -it spark-history /bin/bash
```

## 📝 Submit Applications

### Client Mode (Driver runs on submitting machine)

```bash
docker exec -it spark-master spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode client \
  --executor-memory 1G \
  --executor-cores 1 \
  --total-executor-cores 3 \
  --class YourMainClass \
  /path/to/your-app.jar
```

### Cluster Mode (Driver runs on cluster)

```bash
docker exec -it spark-master spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode cluster \
  --executor-memory 1G \
  --executor-cores 1 \
  --total-executor-cores 3 \
  --class YourMainClass \
  /path/to/your-app.jar
```

### With Event Logging (for History Server)

```bash
docker exec -it spark-master spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode client \
  --conf spark.eventLog.enabled=true \
  --conf spark.eventLog.dir=/opt/spark/spark-events \
  --class org.apache.spark.examples.SparkPi \
  /opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar 100
```

## 🔍 Monitoring

### Master Web UI (http://localhost:8080)

- **Running Applications**: Apps đang chạy
- **Completed Applications**: Apps đã hoàn thành
- **Workers**: Danh sách workers
- **Resources**: CPU, Memory available

### Worker Web UI (http://localhost:8081/8082/8083)

- **Executors**: Executors đang chạy trên worker này
- **Resources**: CPU, Memory được sử dụng
- **Logs**: Worker logs

### History Server (http://localhost:18080)

- **Completed Applications**: Tất cả apps đã hoàn thành
- **Job Details**: Chi tiết về Jobs, Stages, Tasks
- **DAG Visualization**: Xem execution plan
- **Metrics**: Performance metrics chi tiết

## 📦 Adding Custom JARs

### Option 1: Mount JARs directory

Uncomment trong `docker-compose.yml`:

```yaml
volumes:
  - ./spark/jars:/opt/spark/jars
```

Sau đó copy JARs vào `./spark/jars/`

### Option 2: Copy JARs into container

```bash
# Copy JAR into container
docker cp your-app.jar spark-master:/opt/spark/jars/

# Submit job
docker exec -it spark-master spark-submit \
  --master spark://spark-master:7077 \
  --class YourMainClass \
  /opt/spark/jars/your-app.jar
```

## 🛠️ Troubleshooting

### Worker không connect được Master

```bash
# Check network
docker exec spark-worker-1 ping spark-master

# Check master logs
docker logs spark-master

# Restart worker
docker-compose restart spark-worker-1
```

### History Server không hiển thị apps

```bash
# Check event logs directory
docker exec spark-master ls -la /opt/spark/spark-events

# Verify event logging is enabled
docker exec spark-master env | grep EVENTLOG

# Restart history server
docker-compose restart spark-history
```

### Out of Memory errors

```bash
# Increase worker memory in .env
SPARK_WORKER_MEMORY=4G

# Restart cluster
docker-compose restart
```

## 📈 Scaling Workers

Để thêm workers, thêm vào `docker-compose.yml`:

```yaml
spark-worker-4:
  image: ${SPARK_IMAGE}
  container_name: spark-worker-4
  hostname: spark-worker-4
  networks:
    - spark-network
  ports:
    - "8084:8081"
  environment:
    # ... same as worker-1, 2, 3
  volumes:
    - ./spark/worker-4-data:/opt/spark/work-dir
  # ... rest of config
```

## 🧹 Cleanup

```bash
# Stop cluster
docker-compose down

# Remove all data
docker-compose down -v

# Remove worker data directories
rm -rf ./spark/worker-*-data

# Remove all Docker resources
docker system prune -a --volumes
```

## 📚 Differences from HA Setup

| Feature | Simple (Dev) | HA (Production) |
|---------|-------------|-----------------|
| **Masters** | 1 | 3 |
| **Workers** | 3 | 1-N |
| **ZooKeeper** | ❌ None | ✅ 3 nodes |
| **Failover** | ❌ No | ✅ Yes |
| **Recovery Mode** | NONE | ZOOKEEPER |
| **Complexity** | Low | High |
| **Resource Usage** | Low | High |
| **Use Case** | Dev/Test | Production |

## 🎯 When to Upgrade to HA

Nên upgrade lên HA setup khi:

- ✅ Cần uptime cao (production)
- ✅ Không chấp nhận được downtime
- ✅ Có nhiều concurrent jobs
- ✅ Critical applications
- ✅ Team lớn hơn 5 người

Giữ simple setup khi:

- ✅ Development/Testing
- ✅ Learning Spark
- ✅ POC/Prototype
- ✅ Limited resources
- ✅ Single developer

## 🔗 Useful Links

- **Master UI**: http://localhost:8080
- **Worker 1**: http://localhost:8081
- **Worker 2**: http://localhost:8082
- **Worker 3**: http://localhost:8083
- **History Server**: http://localhost:18080

## 💡 Tips

1. **Start fresh**: `docker-compose down -v && docker-compose up -d`
2. **Watch logs**: `docker-compose logs -f | grep -i error`
3. **Check resources**: `docker stats`
4. **Monitor events**: `watch -n 2 docker-compose ps`

---

**Happy Sparking! 🚀**