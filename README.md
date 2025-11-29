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
- Minimum 6GB RAM available to Docker

### 1. Clone and Setup
```bash
# Clone the repository
git clone <repository-url>
cd spark-cluster-setup

# Copy environment file
cp .env.example .env
# Edit .env to customize configuration if needed
```

### 2. Security Configuration (Important)
Before starting the cluster, you need to set up security credentials. The `.env` file is not tracked by Git for security reasons, so you'll need to copy the example file and customize it:

```bash
# Copy the example environment file
cp .env.example .env

# Generate a new random secret for Spark RPC authentication
# Run this command on terminal and copy the output to replace SPARK_RPC_AUTHENTICATION_SECRET in your .env file
openssl rand -hex 64
```

Then edit your `.env` file to paste the generated secret:
```bash
# Edit the .env file and update:
SPARK_RPC_AUTHENTICATION_SECRET=your_newly_generated_secret_here
```

### 3. Start Cluster 
```bash
docker compose up -d
```

### 4. Stop Cluster
```bash
docker compose down
docker compose down -v
```