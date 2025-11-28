# Spark High Availability Cluster with ZooKeeper

A highly available Apache Spark Standalone cluster using ZooKeeper for master election and automatic failover.

## 🏗️ Architecture

### ZooKeeper Cluster (3 nodes)
- `zookeeper-1`: Port 2181
- `zookeeper-2`: Port 2182
- `zookeeper-3`: Port 2183

### Spark Master Cluster (3 nodes)
- `spark-master-1`: Port 7077 (Spark), 8080 (Web UI) - **ACTIVE or STANDBY**
- `spark-master-2`: Port 7078 (Spark), 8081 (Web UI) - **ACTIVE or STANDBY**
- `spark-master-3`: Port 7079 (Spark), 8082 (Web UI) - **ACTIVE or STANDBY**

### Spark Workers (3 nodes)
- `spark-worker-1`: Port 8083 (Web UI)
- `spark-worker-2`: Port 8084 (Web UI)
- `spark-worker-3`: Port 8085 (Web UI)

### Spark History Server
- `spark-history`: Port 18080 (Web UI)

## 🚀 Quick Start

### Prerequisites
- Docker 20.10+
- Docker Compose v2+
- Minimum 8GB RAM available to Docker

### 1. Clone and Setup
```bash
# Clone the repository
git clone <repository-url>
cd spark-cluster-setup

# Initialize configuration (create required directories)
make configure

# Copy environment file
cp .env.example .env
# Edit .env to customize configuration if needed
```

### 2. Start the Cluster
```bash
# Start the entire cluster with one command
make up

# Or start with quick start (includes health check and UI display)
make quickstart
```

### 3. Check Status
```bash
# Check cluster status
make status

# Run health check
make health-check

# View all UI addresses
make ui
```

### 4. Submit Applications
```bash
# Submit SparkPi example (client mode)
make submit-pi

# Submit SparkPi example (cluster mode)
make submit-pi-cluster

# Submit with supervision (auto-restart)
make submit-pi-supervised
```

## 📋 Management Commands

### Cluster Management
```bash
make up           # Start cluster
make down         # Stop cluster
make restart      # Restart cluster
make clean        # Stop cluster and remove all volumes
make status       # Show container status
make logs         # View all service logs
```

### Service-Specific Logs
```bash
make logs-zk      # ZooKeeper logs
make logs-master  # Spark Master logs
make logs-worker  # Spark Worker logs
make logs-history # Spark History logs
```

### Shell Access
```bash
make shell-master # Access spark-master-1 shell
make shell-worker # Access spark-worker-1 shell
make shell-zk     # Access ZooKeeper CLI
```

### Failover Testing
```bash
make stop-master-1  # Stop master 1 (for failover testing)
make start-master-1 # Start master 1
make test-failover  # Run failover test
make test-cluster   # Run cluster health check
```

## 🔧 Configuration

### Environment Variables
Edit `.env` file to customize settings:

```bash
# Spark Image Version
SPARK_IMAGE=apache/spark:3.5.0

# Spark Master Configuration
SPARK_MASTER_URL=spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077
SPARK_MASTER_PORT=7077
SPARK_MASTER_WEBUI_PORT=8080

# Spark Worker Configuration
SPARK_WORKER_CORES=2
SPARK_WORKER_MEMORY=2G
SPARK_WORKER_WEBUI_PORT=8081
SPARK_DRIVER_MEMORY=1G

# Spark HA Recovery (ZooKeeper)
SPARK_RECOVERY_MODE=ZOOKEEPER
SPARK_ZK_URL=zookeeper-1:2181,zookeeper-2:2181,zookeeper-3:2181
SPARK_ZK_DIR=/spark-ha

# Spark Event Logs + History Server
SPARK_EVENTLOG_ENABLED=true
SPARK_EVENTLOG_DIR=/opt/spark/spark-events
SPARK_HISTORY_LOG_DIR=/opt/spark/spark-events
SPARK_HISTORY_RETAINED_APP=50
SPARK_HISTORY_UI_PORT=18080

# ZooKeeper Image and Configuration
ZOO_IMAGE=zookeeper:3.9
ZOO_SERVERS="server.1=zookeeper-1:2888:3888;2181 server.2=zookeeper-2:2888:3888;2181 server.3=zookeeper-3:2888:3888;2181"
```

### Submitting Custom Applications
```bash
# Example: Submit a custom JAR file
make submit-app APP_PATH=/opt/spark/apps/my-app.jar CLASS=org.myorg.MyApp MODE=cluster

# Example: Submit a Python application
docker exec -it spark-master-1 /opt/spark/bin/spark-submit \
  --master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
  --deploy-mode cluster \
  /opt/spark/apps/my-script.py
```

## 🧪 Health Checks and Testing

### Cluster Health Check
```bash
# Run comprehensive health check
make test-cluster
```

### Failover Testing
```bash
# Test master failover
make test-failover

# Or manually test by stopping an active master
make stop-master-1
# Wait for failover, then check status with:
make status
```

### Monitoring
```bash
# View resource usage
make top

# Watch container status
make watch-logs
```

## 🌐 Web UI Access

- **Spark Master 1**: http://localhost:8080
- **Spark Master 2**: http://localhost:8081
- **Spark Master 3**: http://localhost:8082
- **Spark Worker 1**: http://localhost:8083
- **Spark Worker 2**: http://localhost:8084
- **Spark Worker 3**: http://localhost:8085
- **Spark History**: http://localhost:18080

## 🔍 Troubleshooting

### Check Component Status
```bash
# Check ZooKeeper status
make zk-status

# Check ZooKeeper data
make zk-data

# Access ZooKeeper CLI
make zk-cli

# View specific logs
make logs-master
make logs-worker
make logs-zk
```

### Common Issues

1. **Containers failing to start**: Check available system resources (RAM, disk space)
2. **Master failover not working**: Verify ZooKeeper quorum (at least 2 out of 3 nodes running)
3. **Applications not running**: Check that the active master is running and accessible
4. **Network issues**: Ensure containers can communicate on the `spark-network`

### Reset Cluster
```bash
# Clean restart (removes all data)
make clean
make up
```

## 💾 Backup and Maintenance

### Backup ZooKeeper Data
```bash
make backup-zk
```

### Update Images
```bash
make pull
make restart
```

## 📚 References

- [Spark Standalone Mode](https://spark.apache.org/docs/latest/spark-standalone.html)
- [Spark High Availability](https://spark.apache.org/docs/latest/spark-standalone.html#high-availability)
- [ZooKeeper Documentation](https://zookeeper.apache.org/doc/current/)
- [Docker Compose](https://docs.docker.com/compose/)

## ⚠️ Production Considerations

1. **Resource Planning**: Ensure sufficient RAM and CPU for all nodes
2. **Network**: Maintain low latency between cluster nodes
3. **Data Persistence**: Implement proper backup strategies for critical data
4. **Monitoring**: Add production-grade monitoring (Prometheus/Grafana recommended)
5. **Security**: Enable authentication and encryption for production deployments
6. **Separation**: Deploy ZooKeeper and Spark on separate physical machines in production
7. **Configuration**: Adjust memory and resource settings based on workloads