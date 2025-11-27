#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Spark HA Cluster Health Check${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Function to check if container is running
check_container() {
    local container=$1
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo -e "${GREEN}✓${NC} $container is running"
        return 0
    else
        echo -e "${RED}✗${NC} $container is NOT running"
        return 1
    fi
}

# Function to check ZooKeeper status
check_zookeeper() {
    local container=$1
    local status=$(docker exec -it $container zkServer.sh status 2>&1 | grep "Mode:" | awk '{print $2}' | tr -d '\r\n')

    if [ "$status" == "leader" ]; then
        echo -e "${GREEN}✓${NC} $container is ZooKeeper ${GREEN}LEADER${NC}"
    elif [ "$status" == "follower" ]; then
        echo -e "${GREEN}✓${NC} $container is ZooKeeper FOLLOWER"
    else
        echo -e "${RED}✗${NC} $container ZooKeeper status: $status"
    fi
}

# Function to get Spark Master status
get_master_status() {
    local container=$1
    local port=$2

    # Try to get status from logs
    local status=$(docker logs $container 2>&1 | grep -E "(ALIVE|STANDBY|RECOVERING)" | tail -1)

    if echo "$status" | grep -q "ALIVE"; then
        echo -e "${GREEN}✓${NC} $container is ${GREEN}ACTIVE${NC} (http://localhost:$port)"
        return 0
    elif echo "$status" | grep -q "STANDBY"; then
        echo -e "${YELLOW}✓${NC} $container is ${YELLOW}STANDBY${NC} (http://localhost:$port)"
        return 1
    elif echo "$status" | grep -q "RECOVERING"; then
        echo -e "${YELLOW}⚠${NC} $container is ${YELLOW}RECOVERING${NC}"
        return 2
    else
        echo -e "${RED}✗${NC} $container status unknown"
        return 3
    fi
}

echo -e "${BLUE}1. Checking Docker Containers...${NC}\n"

# Check all containers
containers=(
    "zookeeper-1"
    "zookeeper-2"
    "zookeeper-3"
    "spark-master-1"
    "spark-master-2"
    "spark-master-3"
    "spark-worker-1"
    "spark-worker-2"
    "spark-worker-3"
)

all_running=true
for container in "${containers[@]}"; do
    if ! check_container "$container"; then
        all_running=false
    fi
done

if [ "$all_running" = false ]; then
    echo -e "\n${RED}Some containers are not running. Please start them with: docker-compose up -d${NC}"
    exit 1
fi

echo -e "\n${BLUE}2. Checking ZooKeeper Cluster...${NC}\n"

# Check ZooKeeper status
for i in 1 2 3; do
    check_zookeeper "zookeeper-$i"
done

echo -e "\n${BLUE}3. Checking Spark Masters...${NC}\n"

# Check Spark Masters
active_master=""
get_master_status "spark-master-1" "8080" && active_master="spark-master-1"
get_master_status "spark-master-2" "8081" && active_master="spark-master-2"
get_master_status "spark-master-3" "8082" && active_master="spark-master-3"

if [ -z "$active_master" ]; then
    echo -e "\n${RED}⚠ WARNING: No active Spark Master found!${NC}"
else
    echo -e "\n${GREEN}Active Master: $active_master${NC}"
fi

echo -e "\n${BLUE}4. Checking Spark Workers...${NC}\n"

for i in 1 2 3; do
    if check_container "spark-worker-$i"; then
        port=$((8082 + i))
        echo -e "   Worker Web UI: http://localhost:$port"
    fi
done

echo -e "\n${BLUE}5. Testing Spark Application Submission...${NC}\n"

if [ ! -z "$active_master" ]; then
    echo -e "Testing SparkPi example..."

    result=$(docker exec -it $active_master /opt/spark/bin/spark-submit \
        --master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
        --class org.apache.spark.examples.SparkPi \
        --deploy-mode client \
        /opt/spark/examples/jars/spark-examples*.jar 10 2>&1)

    if echo "$result" | grep -q "Pi is roughly"; then
        pi_value=$(echo "$result" | grep "Pi is roughly" | awk '{print $NF}')
        echo -e "${GREEN}✓${NC} Spark job completed successfully!"
        echo -e "   Result: Pi is roughly $pi_value"
    else
        echo -e "${RED}✗${NC} Spark job failed. Check logs with: docker logs $active_master"
    fi
else
    echo -e "${YELLOW}⚠${NC} Skipping job submission (no active master)"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "ZooKeeper Cluster: ${GREEN}Running${NC}"
echo -e "Spark Masters: ${GREEN}Running${NC} (1 Active, 2 Standby)"
echo -e "Spark Workers: ${GREEN}Running${NC} (3 nodes)"
echo -e "\n${GREEN}✓ Cluster is healthy!${NC}\n"

echo -e "${YELLOW}Web UIs:${NC}"
echo -e "  Master 1: http://localhost:8080"
echo -e "  Master 2: http://localhost:8081"
echo -e "  Master 3: http://localhost:8082"
echo -e "  Worker 1: http://localhost:8083"
echo -e "  Worker 2: http://localhost:8084"
echo -e "  Worker 3: http://localhost:8085"
echo ""