# Production Deployment Guide

Hướng dẫn deploy Spark HA Cluster lên production environment.

## 🎯 Architecture Overview

### Recommended Setup

```
┌─────────────────── Production Cluster ───────────────────┐
│                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Server 1    │  │  Server 2    │  │  Server 3    │  │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤  │
│  │ ZooKeeper-1  │  │ ZooKeeper-2  │  │ ZooKeeper-3  │  │
│  │ Spark Master │  │ Spark Master │  │ Spark Master │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Worker 1    │  │  Worker 2    │  │  Worker N    │  │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤  │
│  │ Spark Worker │  │ Spark Worker │  │ Spark Worker │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└───────────────────────────────────────────────────────────┘
```

### Hardware Requirements

#### ZooKeeper + Spark Master Nodes (3 nodes)
- **CPU**: 4-8 cores
- **RAM**: 8-16 GB
- **Disk**: 100 GB SSD (ZooKeeper cần low latency)
- **Network**: 10 Gbps

#### Spark Worker Nodes (N nodes)
- **CPU**: 16-32 cores
- **RAM**: 64-128 GB
- **Disk**: 500 GB - 2 TB (tùy use case)
- **Network**: 10 Gbps

## 📋 Pre-deployment Checklist

### 1. Infrastructure

- [ ] Provisioned servers (physical hoặc VMs)
- [ ] Static IP addresses assigned
- [ ] DNS records configured
- [ ] Firewall rules configured
- [ ] SSH keys deployed
- [ ] Docker installed on all nodes
- [ ] NTP synchronized across all nodes

### 2. Network

- [ ] Low latency between ZooKeeper nodes (< 10ms)
- [ ] All required ports opened
- [ ] Load balancer configured (if needed)
- [ ] VPN/Private network setup

### 3. Security

- [ ] SSL certificates prepared
- [ ] Authentication credentials generated
- [ ] Network segmentation configured
- [ ] Backup strategy defined

## 🔧 Step-by-Step Deployment

### Step 1: Prepare Environment Files

Create separate `.env` files for each environment:

```bash
# production.env
IMAGE=apache/spark:3.5.0
ZOOKEEPER_IMAGE=zookeeper:3.9

# ZooKeeper Configuration
ZK_HEAP_SIZE=2048
ZK_TICK_TIME=2000
ZK_INIT_LIMIT=10
ZK_SYNC_LIMIT=5

# Spark Configuration
SPARK_WORKER_CORES=16
SPARK_WORKER_MEMORY=32G
SPARK_DAEMON_MEMORY=4G

# Security
SPARK_RPC_AUTHENTICATION_ENABLED=yes
SPARK_RPC_AUTHENTICATION_SECRET=${SPARK_SECRET}
SPARK_RPC_ENCRYPTION_ENABLED=yes

# Monitoring
SPARK_METRICS_ENABLED=true
```

### Step 2: Update Docker Compose for Production

Create `docker-compose.prod.yml` based on the current docker-compose.yml:

```yaml
version: '3.8'

networks:
  spark-network:
    driver: overlay
    attachable: true

volumes:
  zk1-data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server,rw
      device: ":/mnt/zk1-data"
  zk1-log:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server,rw
      device: ":/mnt/zk1-log"
  zk2-data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server,rw
      device: ":/mnt/zk2-data"
  zk2-log:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server,rw
      device: ":/mnt/zk2-log"
  zk3-data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server,rw
      device: ":/mnt/zk3-data"
  zk3-log:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server,rw
      device: ":/mnt/zk3-log"
  spark-events:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server,rw
      device: ":/mnt/spark-events"

services:
  # ============================================
  # ZooKeeper Cluster (3 nodes for HA)
  # ============================================
  zookeeper-1:
    image: ${ZOO_IMAGE}
    container_name: zookeeper-1
    hostname: zookeeper-1.production.local
    networks:
      - spark-network
    ports:
      - "2181:2181"
    environment:
      ZOO_MY_ID: 1
      ZOO_SERVERS: ${ZOO_SERVERS}
      ZOO_4LW_COMMANDS_WHITELIST: ${ZOO_4LW_COMMANDS_WHITELIST}
      ZOO_TICK_TIME: ${ZOO_TICK_TIME}
      ZOO_INIT_LIMIT: ${ZOO_INIT_LIMIT}
      ZOO_SYNC_LIMIT: ${ZOO_SYNC_LIMIT}
      ZOO_MAX_CLIENT_CNXNS: ${ZOO_MAX_CLIENT_CNXNS}
      ZOO_AUTOPURGE_SNAPRETAINCOUNT: ${ZOO_AUTOPURGE_SNAPRETAINCOUNT}
      ZOO_AUTOPURGE_PURGEINTERVAL: ${ZOO_AUTOPURGE_PURGEINTERVAL}
      ZOO_MAX_SESSION_TIMEOUT: ${ZOO_MAX_SESSION_TIMEOUT}
      ZOO_MIN_SESSION_TIMEOUT: ${ZOO_MIN_SESSION_TIMEOUT}
      ZOO_CLIENT_PORT: ${ZOO_CLIENT_PORT}
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
      JVMFLAGS: "-Xms${ZK_HEAP_SIZE:-1024m} -Xmx${ZK_HEAP_SIZE:-1024m}"
    volumes:
      - zk1-data:/data
      - zk1-log:/datalog
    restart: always
    healthcheck:
      test: ["CMD", "zkServer.sh", "status"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      placement:
        constraints:
          - node.hostname == server1
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G

  zookeeper-2:
    image: ${ZOO_IMAGE}
    container_name: zookeeper-2
    hostname: zookeeper-2.production.local
    networks:
      - spark-network
    ports:
      - "2182:2181"
    environment:
      ZOO_MY_ID: 2
      ZOO_SERVERS: ${ZOO_SERVERS}
      ZOO_4LW_COMMANDS_WHITELIST: ${ZOO_4LW_COMMANDS_WHITELIST}
      ZOO_TICK_TIME: ${ZOO_TICK_TIME}
      ZOO_INIT_LIMIT: ${ZOO_INIT_LIMIT}
      ZOO_SYNC_LIMIT: ${ZOO_SYNC_LIMIT}
      ZOO_MAX_CLIENT_CNXNS: ${ZOO_MAX_CLIENT_CNXNS}
      ZOO_AUTOPURGE_SNAPRETAINCOUNT: ${ZOO_AUTOPURGE_SNAPRETAINCOUNT}
      ZOO_AUTOPURGE_PURGEINTERVAL: ${ZOO_AUTOPURGE_PURGEINTERVAL}
      ZOO_MAX_SESSION_TIMEOUT: ${ZOO_MAX_SESSION_TIMEOUT}
      ZOO_MIN_SESSION_TIMEOUT: ${ZOO_MIN_SESSION_TIMEOUT}
      ZOO_CLIENT_PORT: ${ZOO_CLIENT_PORT}
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
      JVMFLAGS: "-Xms${ZK_HEAP_SIZE:-1024m} -Xmx${ZK_HEAP_SIZE:-1024m}"
    volumes:
      - zk2-data:/data
      - zk2-log:/datalog
    restart: always
    healthcheck:
      test: ["CMD", "zkServer.sh", "status"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      placement:
        constraints:
          - node.hostname == server2
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G

  zookeeper-3:
    image: ${ZOO_IMAGE}
    container_name: zookeeper-3
    hostname: zookeeper-3.production.local
    networks:
      - spark-network
    ports:
      - "2183:2181"
    environment:
      ZOO_MY_ID: 3
      ZOO_SERVERS: ${ZOO_SERVERS}
      ZOO_4LW_COMMANDS_WHITELIST: ${ZOO_4LW_COMMANDS_WHITELIST}
      ZOO_TICK_TIME: ${ZOO_TICK_TIME}
      ZOO_INIT_LIMIT: ${ZOO_INIT_LIMIT}
      ZOO_SYNC_LIMIT: ${ZOO_SYNC_LIMIT}
      ZOO_MAX_CLIENT_CNXNS: ${ZOO_MAX_CLIENT_CNXNS}
      ZOO_AUTOPURGE_SNAPRETAINCOUNT: ${ZOO_AUTOPURGE_SNAPRETAINCOUNT}
      ZOO_AUTOPURGE_PURGEINTERVAL: ${ZOO_AUTOPURGE_PURGEINTERVAL}
      ZOO_MAX_SESSION_TIMEOUT: ${ZOO_MAX_SESSION_TIMEOUT}
      ZOO_MIN_SESSION_TIMEOUT: ${ZOO_MIN_SESSION_TIMEOUT}
      ZOO_CLIENT_PORT: ${ZOO_CLIENT_PORT}
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
      JVMFLAGS: "-Xms${ZK_HEAP_SIZE:-1024m} -Xmx${ZK_HEAP_SIZE:-1024m}"
    volumes:
      - zk3-data:/data
      - zk3-log:/datalog
    restart: always
    healthcheck:
      test: ["CMD", "zkServer.sh", "status"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      placement:
        constraints:
          - node.hostname == server3
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G

  # ============================================
  # Spark Master Nodes (HA)
  # ============================================
  spark-master-1:
    image: ${SPARK_IMAGE}
    container_name: spark-master-1
    hostname: spark-master-1.production.local
    networks:
      - spark-network
    ports:
      - "7077:7077"
      - "8080:8080"
    environment:
      SPARK_MODE: master
      SPARK_MASTER_HOST: spark-master-1.production.local
      SPARK_MASTER_PORT: ${SPARK_MASTER_PORT}
      SPARK_MASTER_WEBUI_PORT: ${SPARK_MASTER_WEBUI_PORT}
      SPARK_DAEMON_JAVA_OPTS: |
        -Dspark.deploy.recoveryMode=${SPARK_RECOVERY_MODE}
        -Dspark.deploy.zookeeper.url=${SPARK_ZK_URL}
        -Dspark.deploy.zookeeper.dir=${SPARK_ZK_DIR}
        -Dspark.eventLog.enabled=${SPARK_EVENTLOG_ENABLED}
        -Dspark.eventLog.dir=${SPARK_EVENTLOG_DIR}
        -Dspark.history.fs.logDirectory=${SPARK_HISTORY_LOG_DIR}
        -Dspark.authenticate=${SPARK_RPC_AUTHENTICATION_ENABLED:-false}
        -Dspark.authenticate.secret=${SPARK_RPC_AUTHENTICATION_SECRET}
      SPARK_DRIVER_MEMORY: ${SPARK_DRIVER_MEMORY}
      SPARK_DRIVER_EXTRA_CLASSPATH: /opt/spark/jars/*
      SPARK_EXECUTOR_EXTRA_CLASSPATH: /opt/spark/jars/*
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
    volumes:
      - spark-events:/opt/spark/spark-events
      - /path/to/spark/jars:/opt/spark/jars  # Use shared storage
      - /path/to/spark/apps:/opt/spark/apps  # Use shared storage
    depends_on:
      - zookeeper-1
      - zookeeper-2
      - zookeeper-3
    command: >
      bash -c "
        echo 'Waiting for ZooKeeper to be ready...';
        sleep 10;
        mkdir -p /opt/spark/spark-events;
        echo 'Starting Spark Master 1...';
        /opt/spark/sbin/start-master.sh;
        tail -f /opt/spark/logs/*"
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      placement:
        constraints:
          - node.hostname == server1
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G

  spark-master-2:
    image: ${SPARK_IMAGE}
    container_name: spark-master-2
    hostname: spark-master-2.production.local
    networks:
      - spark-network
    ports:
      - "7078:7077"
      - "8081:8080"
    environment:
      SPARK_MODE: master
      SPARK_MASTER_HOST: spark-master-2.production.local
      SPARK_MASTER_PORT: ${SPARK_MASTER_PORT}
      SPARK_MASTER_WEBUI_PORT: ${SPARK_MASTER_WEBUI_PORT}
      SPARK_DAEMON_JAVA_OPTS: |
        -Dspark.deploy.recoveryMode=${SPARK_RECOVERY_MODE}
        -Dspark.deploy.zookeeper.url=${SPARK_ZK_URL}
        -Dspark.deploy.zookeeper.dir=${SPARK_ZK_DIR}
        -Dspark.eventLog.enabled=${SPARK_EVENTLOG_ENABLED}
        -Dspark.eventLog.dir=${SPARK_EVENTLOG_DIR}
        -Dspark.history.fs.logDirectory=${SPARK_HISTORY_LOG_DIR}
        -Dspark.authenticate=${SPARK_RPC_AUTHENTICATION_ENABLED:-false}
        -Dspark.authenticate.secret=${SPARK_RPC_AUTHENTICATION_SECRET}
      SPARK_DRIVER_MEMORY: ${SPARK_DRIVER_MEMORY}
      SPARK_DRIVER_EXTRA_CLASSPATH: /opt/spark/jars/*
      SPARK_EXECUTOR_EXTRA_CLASSPATH: /opt/spark/jars/*
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
    volumes:
      - spark-events:/opt/spark/spark-events
      - /path/to/spark/jars:/opt/spark/jars  # Use shared storage
      - /path/to/spark/apps:/opt/spark/apps  # Use shared storage
    depends_on:
      - zookeeper-1
      - zookeeper-2
      - zookeeper-3
    command: >
      bash -c "
        echo 'Waiting for ZooKeeper to be ready...';
        sleep 10;
        mkdir -p /opt/spark/spark-events;
        echo 'Starting Spark Master 2...';
        /opt/spark/sbin/start-master.sh;
        tail -f /opt/spark/logs/*"
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      placement:
        constraints:
          - node.hostname == server2
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G

  spark-master-3:
    image: ${SPARK_IMAGE}
    container_name: spark-master-3
    hostname: spark-master-3.production.local
    networks:
      - spark-network
    ports:
      - "7079:7077"
      - "8082:8080"
    environment:
      SPARK_MODE: master
      SPARK_MASTER_HOST: spark-master-3.production.local
      SPARK_MASTER_PORT: ${SPARK_MASTER_PORT}
      SPARK_MASTER_WEBUI_PORT: ${SPARK_MASTER_WEBUI_PORT}
      SPARK_DAEMON_JAVA_OPTS: |
        -Dspark.deploy.recoveryMode=${SPARK_RECOVERY_MODE}
        -Dspark.deploy.zookeeper.url=${SPARK_ZK_URL}
        -Dspark.deploy.zookeeper.dir=${SPARK_ZK_DIR}
        -Dspark.eventLog.enabled=${SPARK_EVENTLOG_ENABLED}
        -Dspark.eventLog.dir=${SPARK_EVENTLOG_DIR}
        -Dspark.history.fs.logDirectory=${SPARK_HISTORY_LOG_DIR}
        -Dspark.authenticate=${SPARK_RPC_AUTHENTICATION_ENABLED:-false}
        -Dspark.authenticate.secret=${SPARK_RPC_AUTHENTICATION_SECRET}
      SPARK_DRIVER_MEMORY: ${SPARK_DRIVER_MEMORY}
      SPARK_DRIVER_EXTRA_CLASSPATH: /opt/spark/jars/*
      SPARK_EXECUTOR_EXTRA_CLASSPATH: /opt/spark/jars/*
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
    volumes:
      - spark-events:/opt/spark/spark-events
      - /path/to/spark/jars:/opt/spark/jars  # Use shared storage
      - /path/to/spark/apps:/opt/spark/apps  # Use shared storage
    depends_on:
      - zookeeper-1
      - zookeeper-2
      - zookeeper-3
    command: >
      bash -c "
        echo 'Waiting for ZooKeeper to be ready...';
        sleep 10;
        mkdir -p /opt/spark/spark-events;
        echo 'Starting Spark Master 3...';
        /opt/spark/sbin/start-master.sh;
        tail -f /opt/spark/logs/*"
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8082"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      placement:
        constraints:
          - node.hostname == server3
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G

  # ============================================
  # Spark Worker Nodes
  # ============================================
  spark-worker-1:
    image: ${SPARK_IMAGE}
    container_name: spark-worker-1
    hostname: spark-worker-1.production.local
    networks:
      - spark-network
    ports:
      - "8083:8081"
    environment:
      SPARK_MODE: worker
      SPARK_WORKER_HOST: spark-worker-1.production.local
      SPARK_MASTER_URL: ${SPARK_MASTER_URL}
      SPARK_WORKER_CORES: ${SPARK_WORKER_CORES}
      SPARK_WORKER_MEMORY: ${SPARK_WORKER_MEMORY}
      SPARK_WORKER_WEBUI_PORT: ${SPARK_WORKER_WEBUI_PORT}
      SPARK_DRIVER_EXTRA_CLASSPATH: /opt/spark/jars/*
      SPARK_EXECUTOR_EXTRA_CLASSPATH: /opt/spark/jars/*
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
    volumes:
      - /path/to/spark/jars:/opt/spark/jars  # Use shared storage
    depends_on:
      - spark-master-1
      - spark-master-2
      - spark-master-3
    command: >
      bash -c "
        echo 'Waiting for Spark Masters...';
        sleep 15;
        echo 'Starting Spark Worker 1...';
        /opt/spark/sbin/start-worker.sh ${SPARK_MASTER_URL};
        tail -f /opt/spark/logs/*"
    restart: always
    deploy:
      placement:
        constraints:
          - node.hostname == worker1
      resources:
        limits:
          cpus: '16'
          memory: 64G
        reservations:
          cpus: '8'
          memory: 32G

  spark-worker-2:
    image: ${SPARK_IMAGE}
    container_name: spark-worker-2
    hostname: spark-worker-2.production.local
    networks:
      - spark-network
    ports:
      - "8084:8081"
    environment:
      SPARK_MODE: worker
      SPARK_WORKER_HOST: spark-worker-2.production.local
      SPARK_MASTER_URL: ${SPARK_MASTER_URL}
      SPARK_WORKER_CORES: ${SPARK_WORKER_CORES}
      SPARK_WORKER_MEMORY: ${SPARK_WORKER_MEMORY}
      SPARK_WORKER_WEBUI_PORT: ${SPARK_WORKER_WEBUI_PORT}
      SPARK_DRIVER_EXTRA_CLASSPATH: /opt/spark/jars/*
      SPARK_EXECUTOR_EXTRA_CLASSPATH: /opt/spark/jars/*
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
    volumes:
      - /path/to/spark/jars:/opt/spark/jars  # Use shared storage
    depends_on:
      - spark-master-1
      - spark-master-2
      - spark-master-3
    command: >
      bash -c "
        echo 'Waiting for Spark Masters...';
        sleep 15;
        echo 'Starting Spark Worker 2...';
        /opt/spark/sbin/start-worker.sh ${SPARK_MASTER_URL};
        tail -f /opt/spark/logs/*"
    restart: always
    deploy:
      placement:
        constraints:
          - node.hostname == worker2
      resources:
        limits:
          cpus: '16'
          memory: 64G
        reservations:
          cpus: '8'
          memory: 32G

  # ============================================
  # Spark History Server
  # ============================================
  spark-history:
    image: ${SPARK_IMAGE}
    container_name: spark-history
    hostname: spark-history.production.local
    networks:
      - spark-network
    ports:
      - "18080:18080"
    environment:
      SPARK_NO_DAEMONIZE: "true"
      SPARK_HISTORY_OPTS: |
        -Dspark.history.fs.logDirectory=${SPARK_HISTORY_LOG_DIR}
        -Dspark.history.retainedApplications=${SPARK_HISTORY_RETAINED_APP}
        -Dspark.history.ui.port=${SPARK_HISTORY_UI_PORT}
      TZ: ${TZ:-Asia/Ho_Chi_Minh}
    volumes:
      - spark-events:/opt/spark/spark-events:ro
    depends_on:
      - spark-master-1
      - spark-master-2
      - spark-master-3
    command: >
      bash -c "
        echo 'Waiting for Spark cluster to generate event logs...';
        sleep 20;
        mkdir -p /opt/spark/spark-events;
        echo 'Starting Spark History Server...';
        /opt/spark/sbin/start-history-server.sh;
        tail -f /opt/spark/logs/*"
    restart: always
    deploy:
      placement:
        constraints:
          - node.hostname == server1
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G
```

### Step 3: Deploy on Docker Swarm

```bash
# Initialize Swarm on manager node
docker swarm init --advertise-addr <MANAGER-IP>

# Deploy stack
docker stack deploy -c docker-compose.prod.yml spark-ha
```

### Step 3: Deploy on Docker Swarm

```bash
# Initialize Swarm on manager node
docker swarm init --advertise-addr <MANAGER-IP>

# Join worker nodes
docker swarm join --token <TOKEN> <MANAGER-IP>:2377

# Create overlay network
docker network create --driver overlay --attachable spark-network

# Deploy stack
docker stack deploy -c docker-compose.prod.yml spark-ha
```

### Step 4: Deploy on Kubernetes (Alternative)

Create Kubernetes manifests:

```yaml
# zookeeper-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: zookeeper
spec:
  serviceName: zookeeper
  replicas: 3
  selector:
    matchLabels:
      app: zookeeper
  template:
    metadata:
      labels:
        app: zookeeper
    spec:
      containers:
      - name: zookeeper
        image: zookeeper:3.9
        ports:
        - containerPort: 2181
          name: client
        - containerPort: 2888
          name: follower
        - containerPort: 3888
          name: election
        env:
        - name: ZOO_MY_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
```

Deploy to K8s:

```bash
kubectl apply -f zookeeper-statefulset.yaml
kubectl apply -f spark-master-deployment.yaml
kubectl apply -f spark-worker-deployment.yaml
```

## 🔒 Security Configuration

### 1. Enable Spark RPC Authentication

```bash
# Generate secret
SPARK_SECRET=$(openssl rand -base64 32)

# Add to .env
echo "SPARK_RPC_AUTHENTICATION_SECRET=$SPARK_SECRET" >> production.env
```

### 2. Enable SSL/TLS

Generate certificates:

```bash
# Generate keystore
keytool -genkeypair -alias spark -keyalg RSA -keysize 2048 \
  -validity 365 -keystore spark-keystore.jks

# Generate truststore
keytool -export -alias spark -file spark-cert.pem \
  -keystore spark-keystore.jks
keytool -import -alias spark -file spark-cert.pem \
  -keystore spark-truststore.jks
```

Update docker-compose:

```yaml
environment:
  - SPARK_SSL_ENABLED=true
  - SPARK_SSL_KEYSTORE=/opt/spark/conf/spark-keystore.jks
  - SPARK_SSL_KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD}
  - SPARK_SSL_TRUSTSTORE=/opt/spark/conf/spark-truststore.jks
  - SPARK_SSL_TRUSTSTORE_PASSWORD=${TRUSTSTORE_PASSWORD}
volumes:
  - ./certs/spark-keystore.jks:/opt/spark/conf/spark-keystore.jks:ro
  - ./certs/spark-truststore.jks:/opt/spark/conf/spark-truststore.jks:ro
```

### 3. ZooKeeper Authentication

```yaml
environment:
  - ZOO_ENABLE_AUTH=yes
  - ZOO_SERVER_USERS=spark
  - ZOO_SERVER_PASSWORDS=${ZK_PASSWORD}
  - ZOO_CLIENT_USER=spark
  - ZOO_CLIENT_PASSWORD=${ZK_PASSWORD}
```

## 📊 Monitoring Setup

### 1. Prometheus + Grafana

Create `prometheus.yml`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'spark-master'
    static_configs:
      - targets:
        - 'spark-master-1:8080'
        - 'spark-master-2:8081'
        - 'spark-master-3:8082'

  - job_name: 'spark-workers'
    static_configs:
      - targets:
        - 'spark-worker-1:8081'
        - 'spark-worker-2:8081'
        - 'spark-worker-3:8081'

  - job_name: 'zookeeper'
    static_configs:
      - targets:
        - 'zookeeper-1:7000'
        - 'zookeeper-2:7000'
        - 'zookeeper-3:7000'
```

Add to docker-compose:

```yaml
prometheus:
  image: prom/prometheus:latest
  ports:
    - "9090:9090"
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml
    - prometheus-data:/prometheus
  networks:
    - spark-net

grafana:
  image: grafana/grafana:latest
  ports:
    - "3000:3000"
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
  volumes:
    - grafana-data:/var/lib/grafana
  networks:
    - spark-net
```

### 2. ELK Stack for Logs

```yaml
elasticsearch:
  image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
  environment:
    - discovery.type=single-node
    - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
  ports:
    - "9200:9200"

logstash:
  image: docker.elastic.co/logstash/logstash:8.11.0
  volumes:
    - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf
  depends_on:
    - elasticsearch

kibana:
  image: docker.elastic.co/kibana/kibana:8.11.0
  ports:
    - "5601:5601"
  depends_on:
    - elasticsearch
```

### 3. Alerting

Create `alertmanager.yml`:

```yaml
route:
  receiver: 'team-notifications'

receivers:
  - name: 'team-notifications'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_URL}'
        channel: '#spark-alerts'
        text: 'Alert: {{ .CommonAnnotations.summary }}'
    email_configs:
      - to: 'team@company.com'
        from: 'alerts@company.com'
        smarthost: 'smtp.company.com:587'
```

## 🔄 Backup Strategy

### 1. ZooKeeper Data Backup

```bash
#!/bin/bash
# backup-zookeeper.sh

BACKUP_DIR="/backup/zookeeper"
DATE=$(date +%Y%m%d_%H%M%S)

for i in 1 2 3; do
  docker exec zookeeper-$i tar czf /tmp/zk-backup-$i-$DATE.tar.gz /data /datalog
  docker cp zookeeper-$i:/tmp/zk-backup-$i-$DATE.tar.gz $BACKUP_DIR/
done

# Keep only last 7 days
find $BACKUP_DIR -name "zk-backup-*" -mtime +7 -delete
```

### 2. Spark Configuration Backup

```bash
#!/bin/bash
# backup-spark-config.sh

BACKUP_DIR="/backup/spark-config"
DATE=$(date +%Y%m%d_%H%M%S)

# Backup docker-compose and env files
tar czf $BACKUP_DIR/spark-config-$DATE.tar.gz \
  docker-compose.yml \
  .env \
  *.sh

# Keep only last 30 days
find $BACKUP_DIR -name "spark-config-*" -mtime +30 -delete
```

### 3. Automated Backup with Cron

```bash
# crontab -e
0 2 * * * /opt/spark-ha/backup-zookeeper.sh >> /var/log/zk-backup.log 2>&1
0 3 * * * /opt/spark-ha/backup-spark-config.sh >> /var/log/spark-config-backup.log 2>&1
```

## 🚀 Rolling Updates

### Update Strategy

```bash
#!/bin/bash
# rolling-update.sh

NEW_IMAGE="apache/spark:3.5.1"

# Update masters one by one
for i in 1 2 3; do
  echo "Updating spark-master-$i..."
  
  # Stop the master
  docker stop spark-master-$i
  
  # Update image
  docker rm spark-master-$i
  
  # Start with new image
  IMAGE=$NEW_IMAGE docker-compose up -d spark-master-$i
  
  # Wait for it to join
  sleep 30
  
  echo "spark-master-$i updated successfully"
done

# Update workers
for i in 1 2 3; do
  echo "Updating spark-worker-$i..."
  docker stop spark-worker-$i
  docker rm spark-worker-$i
  IMAGE=$NEW_IMAGE docker-compose up -d spark-worker-$i
  sleep 10
done

echo "Rolling update completed!"
```

## 📈 Performance Tuning

### 1. JVM Tuning

```yaml
environment:
  - SPARK_DAEMON_JAVA_OPTS=-XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:InitiatingHeapOccupancyPercent=35
  - SPARK_EXECUTOR_JAVA_OPTS=-XX:+UseG1GC -XX:+PrintGCDetails -XX:+PrintGCTimeStamps
```

### 2. Network Optimization

```yaml
environment:
  - SPARK_NETWORK_TIMEOUT=600s
  - SPARK_SHUFFLE_IO_RETRIES=10
  - SPARK_SHUFFLE_IO_MAX_RETRIES=10
```

### 3. Resource Allocation

```yaml
environment:
  - SPARK_WORKER_CORES=24
  - SPARK_WORKER_MEMORY=64G
  - SPARK_EXECUTOR_CORES=4
  - SPARK_EXECUTOR_MEMORY=8G
  - SPARK_DRIVER_MEMORY=4G
```

## 🧪 Testing in Production

### 1. Smoke Test

```bash
# test-production.sh
#!/bin/bash

echo "Running smoke tests..."

# Test 1: Submit simple job
docker exec spark-master-1 spark-submit \
  --master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
  --class org.apache.spark.examples.SparkPi \
  /opt/spark/examples/jars/spark-examples*.jar 100

# Test 2: Check all services
curl -s http://spark-master-1:8080 | grep -q "ALIVE" || echo "Master 1 not ALIVE"
curl -s http://spark-master-2:8081 | grep -q "STANDBY" || echo "Master 2 not STANDBY"
curl -s http://spark-master-3:8082 | grep -q "STANDBY" || echo "Master 3 not STANDBY"

echo "Smoke tests completed"
```

### 2. Load Test

```bash
# Generate load
for i in {1..10}; do
  spark-submit \
    --master spark://masters:7077 \
    --deploy-mode cluster \
    your-application.jar &
done

wait
echo "Load test completed"
```

## 🆘 Disaster Recovery

### Scenario 1: All Masters Down

```bash
# 1. Start ZooKeeper if needed
docker start zookeeper-1 zookeeper-2 zookeeper-3

# 2. Clear stale data
docker exec zookeeper-1 zkCli.sh rmr /spark-ha

# 3. Start all masters
docker start spark-master-1 spark-master-2 spark-master-3

# 4. Verify election
docker logs spark-master-1 | grep "elected leader"
```

### Scenario 2: ZooKeeper Quorum Lost

```bash
# 1. Stop all ZooKeeper nodes
docker stop zookeeper-1 zookeeper-2 zookeeper-3

# 2. Restore from backup
for i in 1 2 3; do
  docker cp backup/zk-data-$i zookeeper-$i:/data
done

# 3. Start ZooKeeper cluster
docker start zookeeper-1 zookeeper-2 zookeeper-3

# 4. Verify quorum
docker exec zookeeper-1 zkServer.sh status
```

## 📚 Production Checklist

### Daily
- [ ] Check cluster health
- [ ] Review error logs
- [ ] Monitor resource usage
- [ ] Verify backups

### Weekly
- [ ] Review performance metrics
- [ ] Check disk space
- [ ] Update documentation
- [ ] Test failover

### Monthly
- [ ] Security audit
- [ ] Capacity planning review
- [ ] Update dependencies
- [ ] Disaster recovery drill

## 🔗 Additional Resources

- [Spark Production Best Practices](https://spark.apache.org/docs/latest/configuration.html)
- [ZooKeeper Operations Guide](https://zookeeper.apache.org/doc/current/zookeeperAdmin.html)
- [Docker Swarm Documentation](https://docs.docker.com/engine/swarm/)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)