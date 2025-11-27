.PHONY: help up down restart status logs test-cluster test-failover clean shell-master shell-worker shell-zk

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Spark HA Cluster Management$(NC)"
	@echo "=============================="
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

up: ## Start the entire cluster
	@echo "$(BLUE)Starting Spark HA Cluster...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)✓ Cluster started!$(NC)"
	@echo ""
	@echo "Waiting for services to be ready..."
	@sleep 15
	@make status

down: ## Stop the entire cluster
	@echo "$(YELLOW)Stopping Spark HA Cluster...$(NC)"
	docker-compose down
	@echo "$(GREEN)✓ Cluster stopped!$(NC)"

restart: ## Restart the entire cluster
	@make down
	@sleep 5
	@make up

status: ## Show cluster status
	@echo "$(BLUE)Cluster Status:$(NC)"
	@docker-compose ps

logs: ## Show logs from all services
	docker-compose logs -f

logs-zk: ## Show ZooKeeper logs only
	docker-compose logs -f zookeeper-1 zookeeper-2 zookeeper-3

logs-master: ## Show Spark Master logs only
	docker-compose logs -f spark-master-1 spark-master-2 spark-master-3

logs-worker: ## Show Spark Worker logs only
	docker-compose logs -f spark-worker-1 spark-worker-2 spark-worker-3

test-cluster: ## Run cluster health check
	@chmod +x scripts/test-cluster.sh
	@./scripts/test-cluster.sh

test-failover: ## Run failover test
	@chmod +x scripts/test-failover.sh
	@./scripts/test-failover.sh

clean: ## Stop cluster and remove all volumes
	@echo "$(YELLOW)Cleaning up cluster and volumes...$(NC)"
	docker-compose down -v
	@echo "$(GREEN)✓ Cleanup completed!$(NC)"

shell-master: ## Open shell in spark-master-1
	docker exec -it spark-master-1 /bin/bash

shell-worker: ## Open shell in spark-worker-1
	docker exec -it spark-worker-1 /bin/bash

shell-zk: ## Open ZooKeeper CLI
	docker exec -it zookeeper-1 zkCli.sh

# ===== Spark Job Commands =====

submit-pi: ## Submit SparkPi example job
	@echo "$(BLUE)Submitting SparkPi job...$(NC)"
	docker exec -it spark-master-1 /opt/spark/bin/spark-submit \
		--master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
		--deploy-mode client \
		--class org.apache.spark.examples.SparkPi \
		/opt/spark/examples/jars/spark-examples*.jar 100

submit-pi-cluster: ## Submit SparkPi in cluster mode
	@echo "$(BLUE)Submitting SparkPi job (cluster mode)...$(NC)"
	docker exec -it spark-master-1 /opt/spark/bin/spark-submit \
		--master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
		--deploy-mode cluster \
		--class org.apache.spark.examples.SparkPi \
		/opt/spark/examples/jars/spark-examples*.jar 100

submit-pi-supervised: ## Submit SparkPi with supervision (auto-restart)
	@echo "$(BLUE)Submitting SparkPi job (supervised mode)...$(NC)"
	docker exec -it spark-master-1 /opt/spark/bin/spark-submit \
		--master spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077 \
		--deploy-mode cluster \
		--supervise \
		--class org.apache.spark.examples.SparkPi \
		/opt/spark/examples/jars/spark-examples*.jar 1000

# ===== Master Management =====

stop-master-1: ## Stop spark-master-1 (test failover)
	@echo "$(YELLOW)Stopping spark-master-1...$(NC)"
	docker stop spark-master-1
	@echo "$(GREEN)✓ spark-master-1 stopped$(NC)"

stop-master-2: ## Stop spark-master-2 (test failover)
	@echo "$(YELLOW)Stopping spark-master-2...$(NC)"
	docker stop spark-master-2
	@echo "$(GREEN)✓ spark-master-2 stopped$(NC)"

stop-master-3: ## Stop spark-master-3 (test failover)
	@echo "$(YELLOW)Stopping spark-master-3...$(NC)"
	docker stop spark-master-3
	@echo "$(GREEN)✓ spark-master-3 stopped$(NC)"

start-master-1: ## Start spark-master-1
	@echo "$(GREEN)Starting spark-master-1...$(NC)"
	docker start spark-master-1
	@echo "$(GREEN)✓ spark-master-1 started$(NC)"

start-master-2: ## Start spark-master-2
	@echo "$(GREEN)Starting spark-master-2...$(NC)"
	docker start spark-master-2
	@echo "$(GREEN)✓ spark-master-2 started$(NC)"

start-master-3: ## Start spark-master-3
	@echo "$(GREEN)Starting spark-master-3...$(NC)"
	docker start spark-master-3
	@echo "$(GREEN)✓ spark-master-3 started$(NC)"

# ===== ZooKeeper Management =====

zk-status: ## Check ZooKeeper cluster status
	@echo "$(BLUE)ZooKeeper Cluster Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)ZooKeeper-1:$(NC)"
	@docker exec -it zookeeper-1 zkServer.sh status 2>&1 | grep "Mode:" || echo "Not responding"
	@echo ""
	@echo "$(YELLOW)ZooKeeper-2:$(NC)"
	@docker exec -it zookeeper-2 zkServer.sh status 2>&1 | grep "Mode:" || echo "Not responding"
	@echo ""
	@echo "$(YELLOW)ZooKeeper-3:$(NC)"
	@docker exec -it zookeeper-3 zkServer.sh status 2>&1 | grep "Mode:" || echo "Not responding"

zk-data: ## Show Spark HA data in ZooKeeper
	@echo "$(BLUE)Spark HA data in ZooKeeper:$(NC)"
	@docker exec -it zookeeper-1 zkCli.sh ls /spark-ha 2>/dev/null | tail -1

# ===== Web UI URLs =====

ui: ## Show all Web UI URLs
	@echo "$(BLUE)Web UI URLs:$(NC)"
	@echo ""
	@echo "$(GREEN)Spark Masters:$(NC)"
	@echo "  Master 1: http://localhost:8080"
	@echo "  Master 2: http://localhost:8081"
	@echo "  Master 3: http://localhost:8082"
	@echo ""
	@echo "$(GREEN)Spark Workers:$(NC)"
	@echo "  Worker 1: http://localhost:8083"
	@echo "  Worker 2: http://localhost:8084"
	@echo "  Worker 3: http://localhost:8085"
	@echo ""

# ===== Monitoring =====

watch-logs: ## Watch logs with automatic refresh
	watch -n 2 'docker-compose ps'

top: ## Show resource usage
	docker stats

# ===== Quick Start =====

quickstart: up test-cluster ui ## Quick start: up + test + show URLs

# Default target
.DEFAULT_GOAL := help