# ZooKeeper Configuration Guide

## Tổng quan

ZooKeeper là hệ thống phân tán để quản lý cấu hình, đồng bộ hóa và cung cấp dịch vụ naming cho các ứng dụng phân tán. Trong Spark HA, ZooKeeper được sử dụng để:

1. **Leader Election**: Bầu chọn Master nào sẽ là Active
2. **State Recovery**: Lưu trữ trạng thái cluster để recovery khi Master fail
3. **Coordination**: Đồng bộ giữa các Master nodes

## Kiến trúc ZooKeeper Cluster

### Ensemble (Cụm ZooKeeper)

ZooKeeper hoạt động theo mô hình **ensemble** - một cụm các server làm việc cùng nhau:

```
┌─────────────┐
│ ZooKeeper-1 │ ◄─── Leader (được bầu chọn)
└──────┬──────┘
       │
       ├──────┐
       │      │
┌──────▼──┐ ┌─▼────────┐
│ ZK-2    │ │ ZK-3     │ ◄─── Followers
│Follower │ │ Follower │
└─────────┘ └──────────┘
```

### Quorum

- **Quorum** = Số lượng tối thiểu nodes phải hoạt động để cluster available
- Công thức: **Quorum = (N/2) + 1**

| Số nodes | Quorum | Chịu được fail | Khuyến nghị |
|----------|--------|----------------|-------------|
| 1        | 1      | 0              | Dev only    |
| 2        | 2      | 0              | ❌ Không dùng |
| 3        | 2      | 1              | ✅ Tốt       |
| 4        | 3      | 1              | ❌ Lãng phí  |
| 5        | 3      | 2              | ✅ Rất tốt   |
| 6        | 4      | 2              | ❌ Lãng phí  |
| 7        | 4      | 3              | ✅ Xuất sắc  |

## Cấu hình ZooKeeper trong Docker

### Environment Variables

```yaml
environment:
  # ID duy nhất cho mỗi node (1, 2, 3, ...)
  ZOO_MY_ID: 1
  
  # Danh sách tất cả các servers trong ensemble
  ZOO_SERVERS: server.1=zookeeper-1:2888:3888;2181 server.2=zookeeper-2:2888:3888;2181 server.3=zookeeper-3:2888:3888;2181
  
  # Cho phép các lệnh 4-letter để monitoring
  ZOO_4LW_COMMANDS_WHITELIST: "*"
  
  # (Optional) Cấu hình thêm
  ZOO_TICK_TIME: 2000              # Thời gian tick cơ bản (ms)
  ZOO_INIT_LIMIT: 10               # Timeout để follower kết nối leader
  ZOO_SYNC_LIMIT: 5                # Timeout để follower đồng bộ với leader
  ZOO_MAX_CLIENT_CNXNS: 60         # Max connections từ 1 client
  ZOO_AUTOPURGE_SNAPRETAINCOUNT: 3 # Số snapshot giữ lại
  ZOO_AUTOPURGE_PURGEINTERVAL: 1   # Interval (giờ) để tự động dọn dẹp
```

### Port Explanation

ZooKeeper sử dụng 3 ports:

1. **2181** - Client port (Spark Masters kết nối vào đây)
2. **2888** - Follower port (followers kết nối leader)
3. **3888** - Election port (để bầu chọn leader)

## Cấu hình Spark với ZooKeeper

### Spark Master Configuration

```bash
SPARK_DAEMON_JAVA_OPTS="\
  -Dspark.deploy.recoveryMode=ZOOKEEPER \
  -Dspark.deploy.zookeeper.url=zookeeper-1:2181,zookeeper-2:2181,zookeeper-3:2181 \
  -Dspark.deploy.zookeeper.dir=/spark-ha"
```

### Parameters Explained

- **spark.deploy.recoveryMode=ZOOKEEPER**
  - Bật chế độ HA sử dụng ZooKeeper
  - Giá trị khác: `NONE`, `FILESYSTEM`

- **spark.deploy.zookeeper.url**
  - Danh sách các ZooKeeper nodes
  - Format: `host1:port1,host2:port2,host3:port3`
  - Nên liệt kê tất cả nodes (không chỉ 1)

- **spark.deploy.zookeeper.dir**
  - Thư mục trong ZooKeeper để lưu state
  - Mặc định: `/spark`
  - Có thể dùng path khác nếu có nhiều Spark clusters

## ZooKeeper Data Structure

Khi Spark sử dụng ZooKeeper, nó tạo cấu trúc dữ liệu như sau:

```
/spark-ha/                          # Root directory
├── leader_election/                # Leader election data
│   ├── ActiveStandbyElectorLock   # Lock for election
│   └── _c_xxx                     # Ephemeral nodes
├── master_status                   # Current master info
└── apps/                          # Application metadata
    └── app-xxx                    # Each application
```

### Kiểm tra data trong ZooKeeper

```bash
# Connect to ZooKeeper CLI
docker exec -it zookeeper-1 zkCli.sh

# List Spark HA directory
ls /spark-ha

# Get master status
get /spark-ha/master_status

# List all children recursively
ls -R /spark-ha
```

## Monitoring ZooKeeper

### 1. Check Status

```bash
# Check if node is leader or follower
docker exec -it zookeeper-1 zkServer.sh status

# Output example:
# Mode: leader    (hoặc follower)
```

### 2. Four Letter Words (4LW Commands)

ZooKeeper cung cấp các lệnh 4-letter để monitoring:

```bash
# Server statistics
echo stat | nc localhost 2181

# Configuration
echo conf | nc localhost 2181

# Environment
echo envi | nc localhost 2181

# Server running status
echo ruok | nc localhost 2181
# Output: imok (if running fine)

# Connections
echo cons | nc localhost 2181

# Watch information
echo wchs | nc localhost 2181
```

### 3. JMX Monitoring

Enable JMX trong docker-compose:

```yaml
environment:
  JMXPORT: 9010
  JMXHOST: localhost
```

## ommon Issues và Troubleshooting

### Issue 1: Split-brain (Cluster bị tách)

**Triệu chứng**: Có 2 leaders cùng tồn tại

**Nguyên nhân**: 
- Network partition
- Quorum không đủ

**Giải pháp**:
- Luôn dùng số lẻ nodes (3, 5, 7)
- Đảm bảo network stable
- Kiểm tra firewall rules

### Issue 2: Master không election được

**Triệu chứng**: Tất cả Masters đều STANDBY

**Kiểm tra**:
```bash
# Check ZooKeeper logs
docker logs zookeeper-1

# Check Spark Master logs
docker logs spark-master-1 | grep -i election
```

**Giải pháp**:
- Restart ZooKeeper cluster
- Xóa stale data: `rmr /spark-ha` trong zkCli
- Kiểm tra ZooKeeper quorum

### Issue 3: ZooKeeper connection timeout

**Triệu chứng**: 
```
Connection refused
Could not connect to ZooKeeper
```

**Giải pháp**:
```bash
# Check if ZooKeeper is running
docker ps | grep zookeeper

# Check network connectivity
docker exec spark-master-1 ping zookeeper-1

# Check ZooKeeper ports
docker exec zookeeper-1 netstat -tulpn | grep 2181
```

### Issue 4: Quorum lost

**Triệu chứng**: Cluster không thể write

**Nguyên nhân**: Quá nhiều nodes die

**Giải pháp**:
```bash
# Check how many nodes are running
docker ps | grep zookeeper

# Start stopped nodes
docker start zookeeper-1
docker start zookeeper-2
```

## Performance Tuning

### 1. Disk I/O

ZooKeeper rất nhạy cảm với disk latency:

```yaml
volumes:
  zk-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /path/to/fast/ssd  # Use SSD!
```

### 2. Memory

```yaml
environment:
  JVMFLAGS: "-Xms512m -Xmx2048m"  # Tăng heap size
```

### 3. Network

- Deploy ZooKeeper nodes trên các racks khác nhau
- Sử dụng dedicated network cho ZooKeeper traffic
- Latency giữa nodes < 10ms là tốt

### 4. Snapshot và Log Cleanup

```yaml
environment:
  ZOO_AUTOPURGE_SNAPRETAINCOUNT: 3   # Giữ 3 snapshots
  ZOO_AUTOPURGE_PURGEINTERVAL: 1     # Cleanup mỗi 1 giờ
```

## Security (Production)

### 1. Authentication (SASL)

```yaml
environment:
  ZOO_ENABLE_AUTH: "yes"
  ZOO_SERVER_USERS: "spark"
  ZOO_SERVER_PASSWORDS: "spark_password"
```

### 2. Encryption (TLS/SSL)

```yaml
environment:
  ZOO_TLS_CLIENT_ENABLE: "true"
  ZOO_TLS_PORT: 2281
  ZOO_TLS_CLIENT_KEYSTORE_FILE: "/path/to/keystore"
  ZOO_TLS_CLIENT_KEYSTORE_PASSWORD: "password"
```

### 3. ACLs (Access Control Lists)

```bash
# In ZooKeeper CLI
create /spark-ha data digest:username:password:cdrwa

# Set ACL for Spark path
setAcl /spark-ha digest:spark:encryptedpassword:cdrwa
```

## Best Practices

### Development
- ✅ 1 node ZooKeeper là đủ
- ✅ Không cần volumes persistence
- ✅ Dùng default settings

### Staging/Testing
- ✅ 3 nodes ZooKeeper
- ✅ Enable volumes
- ✅ Test failover scenarios

### Production
- ✅ 3 hoặc 5 nodes (tùy requirements)
- ✅ Dedicated hardware/VMs cho ZooKeeper
- ✅ SSD disks
- ✅ Enable monitoring (JMX, 4LW commands)
- ✅ Enable auto-purge snapshots
- ✅ Backup `/datalog` và `/data` regularly
- ✅ Network latency < 10ms
- ✅ Enable authentication và encryption
- ✅ Separate network cho ZooKeeper ensemble
- ✅ Monitor disk usage (snapshots có thể lớn)

## 🔗 References

- [ZooKeeper Documentation](https://zookeeper.apache.org/doc/current/)
- [ZooKeeper Administrator's Guide](https://zookeeper.apache.org/doc/current/zookeeperAdmin.html)
- [Spark Standalone Mode HA](https://spark.apache.org/docs/latest/spark-standalone.html#high-availability)