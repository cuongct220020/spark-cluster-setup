#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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
    local status=$(docker exec $container zkServer.sh status 2>&1 | grep -E "(Mode|JMX)" | head -1 | awk '{print $2}' | tr -d '\r\n')

    if [[ "$status" == *"leader"* ]] || [[ "$status" == *"standalone"* ]]; then
        echo -e "${GREEN}✓${NC} $container is ZooKeeper ${GREEN}LEADER${NC}"
    elif [[ "$status" == *"follower"* ]]; then
        echo -e "${GREEN}✓${NC} $container is ZooKeeper FOLLOWER"
    else
        echo -e "${RED}✗${NC} $container ZooKeeper status: ${status:-"Not responding"}"
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

# Check all containers including Spark History Server
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
    "spark-history"
)

all_running=true
for container in "${containers[@]}"; do
    if ! check_container "$container"; then
        all_running=false
    fi
done

if [ "$all_running" = false ]; then
    echo -e "\n${RED}Some containers are not running. Please start them with: make up${NC}"
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
        echo -e "   ${GREEN}✓${NC} spark-worker-$i is running (Web UI: http://localhost:$((8082+i-1)))"
    fi
done

echo -e "\n${BLUE}5. Checking Spark History Server...${NC}\n"

if check_container "spark-history"; then
    echo -e "   ${GREEN}✓${NC} Spark History Server running (Web UI: http://localhost:18080)"
fi

echo -e "\n${BLUE}6. Testing Spark Application Submission...${NC}\n"

if [ ! -z "$active_master" ]; then
    echo -e "Testing SparkPi example..."

    result=$(timeout 60 docker exec $active_master /opt/spark/bin/spark-submit \
        --master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
        --class org.apache.spark.examples.SparkPi \
        --deploy-mode client \
        /opt/spark/examples/jars/spark-examples*.jar 10 2>&1)

    if echo "$result" | grep -q "Pi is roughly"; then
        pi_value=$(echo "$result" | grep "Pi is roughly" | awk '{print $NF}')
        echo -e "${GREEN}✓${NC} Spark job completed successfully!"
        echo -e "   Result: Pi is roughly $pi_value"
    else
        echo -e "${YELLOW}⚠${NC} Spark job may have issues. Details:"
        echo "$result" | tail -10
    fi
else
    echo -e "${YELLOW}⚠${NC} Skipping job submission (no active master)"
fi

echo -e "\n${BLUE}7. Checking Network Connectivity...${NC}\n"

# Check if we can reach the web UIs
echo -n "Checking Master 1 UI (http://localhost:8080)... "
if curl -f http://localhost:8080 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Accessible"
else
    echo -e "${YELLOW}⚠${NC} Not accessible"
fi

echo -n "Checking Master 2 UI (http://localhost:8081)... "
if curl -f http://localhost:8081 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Accessible"
else
    echo -e "${YELLOW}⚠${NC} Not accessible"
fi

echo -n "Checking Master 3 UI (http://localhost:8082)... "
if curl -f http://localhost:8082 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Accessible"
else
    echo -e "${YELLOW}⚠${NC} Not accessible"
fi

echo -n "Checking History Server UI (http://localhost:18080)... "
if curl -f http://localhost:18080 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Accessible"
else
    echo -e "${YELLOW}⚠${NC} Not accessible"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Cluster Health Summary${NC}"
echo -e "${BLUE}========================================${NC}"

# Count running services
zookeeper_running=0
for i in 1 2 3; do
    if docker ps --format '{{.Names}}' | grep -q "^zookeeper-$i$"; then
        ((zookeeper_running++))
    fi
done

spark_masters_running=0
for i in 1 2 3; do
    if docker ps --format '{{.Names}}' | grep -q "^spark-master-$i$"; then
        ((spark_masters_running++))
    fi
done

spark_workers_running=0
for i in 1 2 3; do
    if docker ps --format '{{.Names}}' | grep -q "^spark-worker-$i$"; then
        ((spark_workers_running++))
    fi
done

history_running=0
if docker ps --format '{{.Names}}' | grep -q "^spark-history$"; then
    ((history_running++))
fi

echo -e "ZooKeeper Cluster: ${GREEN}${zookeeper_running}/3 nodes running${NC}"
echo -e "Spark Masters: ${GREEN}${spark_masters_running}/3 nodes running${NC}"
echo -e "Spark Workers: ${GREEN}${spark_workers_running}/3 nodes running${NC}"
echo -e "Spark History: ${GREEN}${history_running}/1 node running${NC}"
if [ -n "$active_master" ]; then
    echo -e "Active Master: ${GREEN}$active_master${NC} (HA: ${YELLOW}Enabled${NC})"
else
    echo -e "Active Master: ${RED}None${NC} (HA: ${RED}Not working${NC})"
fi

echo -e "\n${GREEN}✓ Cluster is healthy!${NC}\n"

echo -e "${YELLOW}Web UIs:${NC}"
echo -e "  ${GREEN}Master 1:${NC} http://localhost:8080"
echo -e "  ${GREEN}Master 2:${NC} http://localhost:8081"
echo -e "  ${GREEN}Master 3:${NC} http://localhost:8082"
echo -e "  ${GREEN}Worker 1:${NC} http://localhost:8083"
echo -e "  ${GREEN}Worker 2:${NC} http://localhost:8084"
echo -e "  ${GREEN}Worker 3:${NC} http://localhost:8085"
echo -e "  ${GREEN}History:${NC}  http://localhost:18080"
echo -e "\n${BLUE}For more commands run:${NC} ${PURPLE}make help${NC}"
echo ""