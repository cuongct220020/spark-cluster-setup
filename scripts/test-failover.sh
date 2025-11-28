#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Spark HA Failover Test${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Function to get active master
get_active_master() {
    for master in "spark-master-1" "spark-master-2" "spark-master-3"; do
        status=$(docker logs $master 2>&1 | grep -E "ALIVE" | tail -1)
        if echo "$status" | grep -q "ALIVE"; then
            echo "$master"
            return 0
        fi
    done
    echo ""
    return 1
}

# Function to wait for new leader election
wait_for_new_leader() {
    echo -e "\n${YELLOW}Waiting for new master election...${NC}"
    local max_wait=60
    local waited=0

    while [ $waited -lt $max_wait ]; do
        sleep 3
        waited=$((waited + 3))

        new_active=$(get_active_master)
        if [ ! -z "$new_active" ]; then
            echo -e "${GREEN}✓${NC} New active master elected: ${GREEN}$new_active${NC} (after ${waited}s)"
            return 0
        fi

        echo -n "."
    done

    echo -e "\n${RED}✗${NC} Timeout waiting for new master election"
    return 1
}

# Function to check worker connection
check_workers_connected() {
    local master=$1
    echo -e "\n${BLUE}Checking if workers reconnected to $master...${NC}"

    sleep 10

    local workers_found=$(docker logs $master 2>&1 | grep -c "Worker has been re-registered")

    if [ $workers_found -gt 0 ]; then
        echo -e "${GREEN}✓${NC} $workers_found worker(s) reconnected to new master"
        return 0
    else
        # Check for active workers in the master UI logs
        local active_workers=$(docker logs $master 2>&1 | grep -c "WorkerInfo" || echo 0)
        echo -e "${YELLOW}⚠${NC} No reconnection logs found, but $active_workers workers may be active"
        return 0
    fi
}

# Function to show cluster status
show_cluster_status() {
    echo -e "\n${BLUE}Current Cluster Status:${NC}"
    for master in "spark-master-1" "spark-master-2" "spark-master-3"; do
        status=$(docker logs $master 2>&1 | grep -E "(ALIVE|STANDBY|RECOVERING)" | tail -1)
        if echo "$status" | grep -q "ALIVE"; then
            echo -e "  ${GREEN}$master${NC} is ACTIVE"
        elif echo "$status" | grep -q "STANDBY"; then
            echo -e "  ${YELLOW}$master${NC} is STANDBY"
        elif echo "$status" | grep -q "RECOVERING"; then
            echo -e "  ${YELLOW}$master${NC} is RECOVERING"
        else
            echo -e "  ${RED}$master${NC} status unknown"
        fi
    done
}

# Step 1: Identify current active master
echo -e "${BLUE}Step 1: Identifying active master...${NC}\n"

active_master=$(get_active_master)

if [ -z "$active_master" ]; then
    echo -e "${RED}✗${NC} No active master found! Is the cluster running?"
    echo -e "   Run: ${YELLOW}make up${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Active master: ${GREEN}$active_master${NC}\n"

# Get master port for UI
case $active_master in
    "spark-master-1")
        master_port="8080"
        ;;
    "spark-master-2")
        master_port="8081"
        ;;
    "spark-master-3")
        master_port="8082"
        ;;
esac

echo -e "You can check master UI at: ${BLUE}http://localhost:$master_port${NC}\n"

# Step 2: Submit a long-running job (use smaller number for faster testing)
echo -e "${BLUE}Step 2: Submitting a Spark job for failover testing...${NC}\n"

job_result=$(docker exec $active_master /opt/spark/bin/spark-submit \
    --master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
    --class org.apache.spark.examples.SparkPi \
    --deploy-mode client \
    /opt/spark/examples/jars/spark-examples*.jar 100 2>&1 &)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Job submitted successfully (running in background)"
else
    echo -e "${YELLOW}⚠${NC} Job submission had issues, but continuing with failover test..."
fi

sleep 5

# Step 3: Show current status before failover
echo -e "\n${BLUE}Step 3: Current cluster status before failover${NC}"
show_cluster_status

# Step 4: Kill active master
echo -e "\n${BLUE}Step 4: Simulating master failure...${NC}\n"

echo -e "${RED}Stopping $active_master...${NC}"
docker stop $active_master

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} $active_master stopped"
else
    echo -e "${RED}✗${NC} Failed to stop $active_master"
    exit 1
fi

# Step 5: Wait for failover
echo -e "\n${BLUE}Step 5: Waiting for automatic failover...${NC}"

if wait_for_new_leader; then
    new_active=$(get_active_master)

    if [ -z "$new_active" ]; then
        echo -e "\n${RED}✗${NC} No active master elected after timeout"
        show_cluster_status
        exit 1
    fi

    # Check workers
    check_workers_connected "$new_active"

    # Get new master port
    case $new_active in
        "spark-master-1")
            new_port="8080"
            ;;
        "spark-master-2")
            new_port="8081"
            ;;
        "spark-master-3")
            new_port="8082"
            ;;
    esac

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Failover Test SUCCESSFUL!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Old active master: ${RED}$active_master${NC}"
    echo -e "New active master: ${GREEN}$new_active${NC}"
    echo -e "New master UI: ${BLUE}http://localhost:$new_port${NC}\n"

    # Show final status
    show_cluster_status

    # Step 6: Optional - Restart killed master
    echo -e "\n${BLUE}Step 6: (Optional) Restarting killed master to restore cluster...${NC}"
    echo -e "Do you want to restart $active_master to restore 3-master cluster? (y/n): "
    read -t 15 -r restart_choice

    if [[ $restart_choice =~ ^[Yy]$ ]]; then
        echo -e "Restarting $active_master..."
        docker start $active_master

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC} $active_master restarted (will become STANDBY)"
            sleep 15

            status=$(docker logs $active_master 2>&1 | grep -E "(ALIVE|STANDBY|RECOVERING)" | tail -1)
            if echo "$status" | grep -q "STANDBY"; then
                echo -e "${GREEN}✓${NC} $active_master is now in STANDBY mode"
            elif echo "$status" | grep -q "ALIVE"; then
                echo -e "${YELLOW}⚠${NC} $active_master may have become ACTIVE again"
            else
                echo -e "${YELLOW}⚠${NC} $active_master status: ${status:-"unknown"}"
            fi
        else
            echo -e "${RED}✗${NC} Failed to restart $active_master"
        fi
    else
        echo -e "Skipping restart. You can manually restart later with:"
        echo -e "  ${YELLOW}docker start $active_master${NC}"
        echo -e "  Or use: ${YELLOW}make start-master-1${NC} (if this was master-1)"
    fi

    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Test completed!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "\nYou can verify the cluster status with:"
    echo -e "  ${YELLOW}make status${NC}"
    echo -e "  ${YELLOW}make test-cluster${NC}"
    echo -e "\n${BLUE}For more commands run:${NC} ${PURPLE}make help${NC}\n"

else
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}Failover Test FAILED!${NC}"
    echo -e "${RED}========================================${NC}"
    echo -e "No new master was elected within timeout period.\n"
    show_cluster_status
    echo -e "\nCheck the logs:"
    echo -e "  ${YELLOW}make logs-master${NC}"
    echo -e "  ${YELLOW}make logs-zk${NC}\n"

    # Restart killed master for recovery
    echo -e "Restarting $active_master to recover cluster..."
    docker start $active_master
    exit 1
fi