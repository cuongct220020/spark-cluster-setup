.PHONY: help up down restart status logs logs-zk logs-master logs-worker test-cluster test-failover clean shell-master shell-worker shell-zk submit-pi submit-pi-cluster submit-pi-supervised stop-master-1 stop-master-2 stop-master-3 start-master-1 start-master-2 start-master-3 zk-status zk-data ui watch-logs top quickstart

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
CYAN := \033[0;36m
NC := \033[0m # No Color

# Variables
SPARK_MASTER_URL := spark://spark-master-1:7077,spark-master-2:7077,spark-master-3:7077

help: ## Show this help message
	@echo "$(BLUE)=========================================$(NC)"
	@echo "$(BLUE)Spark HA Cluster Management$(NC)"
	@echo "$(BLUE)=========================================$(NC)"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-30s$(NC) %s\n", $$1, $$2}'
	@echo ""

up: ## Start the entire cluster
	@echo "$(BLUE)Starting Spark HA Cluster...$(NC)"
	@docker-compose up -d
	@echo "$(GREEN)✓ Cluster started!$(NC)"
	@echo ""
	@echo "Waiting for services to be ready..."
	@sleep 15
	@make status
	@echo ""
	@echo "$(CYAN)To check cluster health run:$(NC) $(YELLOW)make health-check$(NC)"
	@echo "$(CYAN)To see UI addresses run:$(NC) $(YELLOW)make ui$(NC)"

down: ## Stop the entire cluster
	@echo "$(YELLOW)Stopping Spark HA Cluster...$(NC)"
	@docker-compose down
	@echo "$(GREEN)✓ Cluster stopped!$(NC)"

restart: ## Restart the entire cluster
	@echo "$(YELLOW)Restarting Spark HA Cluster...$(NC)"
	@make down
	@sleep 5
	@make up

status: ## Show cluster status
	@echo "$(BLUE)Cluster Status:$(NC)"
	@docker-compose ps --format "table {{.Name}}\t{{.Command}}\t{{.Status}}\t{{.Ports}}"

logs: ## Show logs from all services
	docker-compose logs -f

logs-zk: ## Show ZooKeeper logs only
	docker-compose logs -f zookeeper-1 zookeeper-2 zookeeper-3

logs-master: ## Show Spark Master logs only
	docker-compose logs -f spark-master-1 spark-master-2 spark-master-3

logs-worker: ## Show Spark Worker logs only
	docker-compose logs -f spark-worker-1 spark-worker-2 spark-worker-3

logs-history: ## Show Spark History Server logs
	docker-compose logs -f spark-history

health-check: test-cluster ## Check cluster health (alias for test-cluster)

test-cluster: ## Run cluster health check
	@echo "$(BLUE)Running cluster health check...$(NC)"
	@chmod +x scripts/test-cluster.sh
	@./scripts/test-cluster.sh

test-failover: ## Run failover test
	@echo "$(BLUE)Running failover test...$(NC)"
	@chmod +x scripts/test-failover.sh
	@./scripts/test-failover.sh

clean: ## Stop cluster and remove all containers/volumes
	@echo "$(YELLOW)Cleaning up cluster and volumes...$(NC)"
	@docker-compose down -v
	@echo "$(GREEN)✓ Cleanup completed!$(NC)"

shell-master: ## Open shell in spark-master-1
	docker exec -it spark-master-1 /bin/bash

shell-worker: ## Open shell in spark-worker-1
	docker exec -it spark-worker-1 /bin/bash

shell-zk: ## Open ZooKeeper CLI
	docker exec -it zookeeper-1 zkCli.sh

# ===== Spark Job Commands =====

submit-pi: ## Submit SparkPi example job (client mode)
	@echo "$(BLUE)Submitting SparkPi job (client mode)...$(NC)"
	docker exec -it spark-master-1 /opt/spark/bin/spark-submit \
		--master $(SPARK_MASTER_URL) \
		--deploy-mode client \
		--class org.apache.spark.examples.SparkPi \
		/opt/spark/examples/jars/spark-examples*.jar 100

submit-pi-cluster: ## Submit SparkPi in cluster mode
	@echo "$(BLUE)Submitting SparkPi job (cluster mode)...$(NC)"
	docker exec -it spark-master-1 /opt/spark/bin/spark-submit \
		--master $(SPARK_MASTER_URL) \
		--deploy-mode cluster \
		--class org.apache.spark.examples.SparkPi \
		/opt/spark/examples/jars/spark-examples*.jar 100

submit-pi-supervised: ## Submit SparkPi with supervision (auto-restart)
	@echo "$(BLUE)Submitting SparkPi job (supervised mode)...$(NC)"
	docker exec -it spark-master-1 /opt/spark/bin/spark-submit \
		--master $(SPARK_MASTER_URL) \
		--deploy-mode cluster \
		--supervise \
		--class org.apache.spark.examples.SparkPi \
		/opt/spark/examples/jars/spark-examples*.jar 1000

submit-app: ## Submit custom application (use APP_PATH variable)
	@echo "$(BLUE)Submitting custom application...$(NC)"
	@if [ -z "$(APP_PATH)" ]; then \
		echo "$(RED)Error: APP_PATH not set. Use: make submit-app APP_PATH=/path/to/your/app.jar$(NC)"; \
		exit 1; \
	fi
	docker exec -it spark-master-1 /opt/spark/bin/spark-submit \
		--master $(SPARK_MASTER_URL) \
		--deploy-mode $(MODE) \
		--class $(CLASS) \
		$(APP_PATH)

# ===== Master Management =====

stop-master-1: ## Stop spark-master-1 (for failover testing)
	@echo "$(YELLOW)Stopping spark-master-1...$(NC)"
	@docker stop spark-master-1
	@echo "$(GREEN)✓ spark-master-1 stopped$(NC)"

stop-master-2: ## Stop spark-master-2 (for failover testing)
	@echo "$(YELLOW)Stopping spark-master-2...$(NC)"
	@docker stop spark-master-2
	@echo "$(GREEN)✓ spark-master-2 stopped$(NC)"

stop-master-3: ## Stop spark-master-3 (for failover testing)
	@echo "$(YELLOW)Stopping spark-master-3...$(NC)"
	@docker stop spark-master-3
	@echo "$(GREEN)✓ spark-master-3 stopped$(NC)"

start-master-1: ## Start spark-master-1
	@echo "$(GREEN)Starting spark-master-1...$(NC)"
	@docker start spark-master-1
	@echo "$(GREEN)✓ spark-master-1 started$(NC)"

start-master-2: ## Start spark-master-2
	@echo "$(GREEN)Starting spark-master-2...$(NC)"
	@docker start spark-master-2
	@echo "$(GREEN)✓ spark-master-2 started$(NC)"

start-master-3: ## Start spark-master-3
	@echo "$(GREEN)Starting spark-master-3...$(NC)"
	@docker start spark-master-3
	@echo "$(GREEN)✓ spark-master-3 started$(NC)"

# ===== Worker Management =====

stop-worker-1: ## Stop spark-worker-1
	@echo "$(YELLOW)Stopping spark-worker-1...$(NC)"
	@docker stop spark-worker-1
	@echo "$(GREEN)✓ spark-worker-1 stopped$(NC)"

stop-worker-2: ## Stop spark-worker-2
	@echo "$(YELLOW)Stopping spark-worker-2...$(NC)"
	@docker stop spark-worker-2
	@echo "$(GREEN)✓ spark-worker-2 stopped$(NC)"

stop-worker-3: ## Stop spark-worker-3
	@echo "$(YELLOW)Stopping spark-worker-3...$(NC)"
	@docker stop spark-worker-3
	@echo "$(GREEN)✓ spark-worker-3 stopped$(NC)"

start-worker-1: ## Start spark-worker-1
	@echo "$(GREEN)Starting spark-worker-1...$(NC)"
	@docker start spark-worker-1
	@echo "$(GREEN)✓ spark-worker-1 started$(NC)"

start-worker-2: ## Start spark-worker-2
	@echo "$(GREEN)Starting spark-worker-2...$(NC)"
	@docker start spark-worker-2
	@echo "$(GREEN)✓ spark-worker-2 started$(NC)"

start-worker-3: ## Start spark-worker-3
	@echo "$(GREEN)Starting spark-worker-3...$(NC)"
	@docker start spark-worker-3
	@echo "$(GREEN)✓ spark-worker-3 started$(NC)"

# ===== ZooKeeper Management =====

zk-status: ## Check ZooKeeper cluster status
	@echo "$(BLUE)ZooKeeper Cluster Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)ZooKeeper-1:$(NC)"
	@docker exec zookeeper-1 zkServer.sh status 2>&1 | grep -E "(Mode|JMX)" | head -1 || echo "Not responding"
	@echo ""
	@echo "$(YELLOW)ZooKeeper-2:$(NC)"
	@docker exec zookeeper-2 zkServer.sh status 2>&1 | grep -E "(Mode|JMX)" | head -1 || echo "Not responding"
	@echo ""
	@echo "$(YELLOW)ZooKeeper-3:$(NC)"
	@docker exec zookeeper-3 zkServer.sh status 2>&1 | grep -E "(Mode|JMX)" | head -1 || echo "Not responding"
	@echo ""

zk-data: ## Show Spark HA data in ZooKeeper
	@echo "$(BLUE)Spark HA data in ZooKeeper:$(NC)"
	@docker exec zookeeper-1 zkCli.sh -c 'ls /spark-ha' 2>/dev/null | tail -1 || echo "No data found or ZooKeeper not responding"

zk-cli: ## Open ZooKeeper CLI
	docker exec -it zookeeper-1 zkCli.sh

# ===== Web UI URLs =====

ui: ## Show all Web UI URLs
	@echo "$(BLUE)=========================================$(NC)"
	@echo "$(BLUE)Web UI URLs$(NC)"
	@echo "$(BLUE)=========================================$(NC)"
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
	@echo "$(GREEN)Spark History Server:$(NC)"
	@echo "  History: http://localhost:18080"
	@echo ""

# ===== Monitoring =====

watch-logs: ## Watch logs with automatic refresh
	watch -n 2 'docker-compose ps --format "table {{.Name}}\t{{.Status}}"'

top: ## Show resource usage
	docker stats --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}"

# ===== Quick Start =====

quickstart: up health-check ui ## Quick start: up + health-check + show URLs

# ===== Backup and Restore =====

backup-zk: ## Backup ZooKeeper data
	@echo "$(BLUE)Creating ZooKeeper backup...$(NC)"
	@mkdir -p backups
	@tar -czvf backups/zk-backup-$(shell date +%Y%m%d-%H%M%S).tar.gz zk1/ zk2/ zk3/ 2>/dev/null || echo "No ZooKeeper data to backup"
	@echo "$(GREEN)✓ ZooKeeper backup created$(NC)"

# ===== Configuration =====

configure: ## Initialize configuration (create missing directories)
	@echo "$(BLUE)Initializing cluster configuration...$(NC)"
	@mkdir -p zk1/zk1-data zk1/zk1-log zk2/zk2-data zk2/zk2-log zk3/zk3-data zk3/zk3-log
	@mkdir -p spark-events spark/jars apps
	@echo "$(GREEN)✓ Configuration initialized$(NC)"

# ===== Build and Update =====

pull: ## Pull latest images
	@echo "$(BLUE)Pulling latest images...$(NC)"
	@docker-compose pull
	@echo "$(GREEN)✓ Images updated$(NC)"

# Default target
.DEFAULT_GOAL := help