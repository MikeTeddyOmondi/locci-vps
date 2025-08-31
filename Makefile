.PHONY: build run test clean docker-build docker-run cli-build install dev setup help

# Variables
BINARY_NAME=firecracker-vps
CLI_BINARY=fc-vps
GO_MODULE=firecracker-vps
DOCKER_IMAGE=firecracker-vps:latest
API_PORT=8080

GOBIN_PATH := $(shell go env GOBIN)
ifeq ($(GOBIN_PATH),)
    GOBIN_PATH := $(shell go env GOPATH)/bin
endif

# Colors for output
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Firecracker VPS Management Platform$(NC)"
	@echo "$(YELLOW)Available commands:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(GREEN)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development
setup: ## Setup development environment
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@which go >/dev/null || (echo "$(RED)Go is required but not installed$(NC)" && exit 1)
	@which cargo >/dev/null || (echo "$(RED)Rust/Cargo is required but not installed$(NC)" && exit 1)
	@which docker >/dev/null || (echo "$(RED)Docker is required but not installed$(NC)" && exit 1)
	@echo "$(GREEN)✓ All dependencies are available$(NC)"
	@echo "$(BLUE)Downloading Go dependencies...$(NC)"
	@go mod download
	@echo "$(GREEN)✓ Go dependencies downloaded$(NC)"
	@echo "$(BLUE)Creating required directories...$(NC)"
	@mkdir -p /var/lib/firecracker/{vms,images,logs}
	@echo "$(GREEN)✓ Development environment setup complete$(NC)"

build: ## Build the Go API server
	@echo "$(BLUE)Building Go API server...$(NC)"
	@CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o bin/$(BINARY_NAME) .
	@echo "$(GREEN)✓ API server built: bin/$(BINARY_NAME)$(NC)"

cli-build: ## Build the Rust CLI client
	@echo "$(BLUE)Building Rust CLI client...$(NC)"
	@cd cli && cargo build --release
	@mkdir -p bin/
	@cp cli/target/release/$(CLI_BINARY) bin/$(CLI_BINARY)
	@echo "$(GREEN)✓ CLI client built: bin/$(CLI_BINARY)$(NC)"

build-all: build cli-build ## Build both API server and CLI client
	@echo "$(GREEN)✓ All components built successfully$(NC)"

##@ Running
run: build ## Run the API server locally
	@echo "$(BLUE)Starting Firecracker VPS API server on port $(API_PORT)...$(NC)"
	@echo "$(YELLOW)Make sure you have the required permissions and Firecracker installed$(NC)"
	@VM_DIR=/var/lib/firecracker-vms/ \
	 BASE_IMAGES_DIR=/var/lib/firecracker/images \
	 KERNEL_PATH=/var/lib/firecracker/vmlinux.bin \
	 API_PORT=$(API_PORT) \
	 sudo -u mt0 ./bin/$(BINARY_NAME)

dev: ## Run in development mode with live reload
	@echo "$(BLUE)Starting development server with live reload...$(NC)"
	@which air >/dev/null || go install github.com/air-verse/air@latest
	@VM_DIR=/var/lib/firecracker-vms \
	 BASE_IMAGES_DIR=/var/lib/firecracker/images \
	 KERNEL_PATH=/var/lib/firecracker/vmlinux.bin \
	 API_PORT=$(API_PORT) \
	 $(GOBIN_PATH)/air

##@ Docker
docker-build: ## Build Docker image
	@echo "$(BLUE)Building Docker image...$(NC)"
	@docker build -t $(DOCKER_IMAGE) .
	@echo "$(GREEN)✓ Docker image built: $(DOCKER_IMAGE)$(NC)"

docker-run: docker-build ## Run the application in Docker
	@echo "$(BLUE)Starting Firecracker VPS in Docker...$(NC)"
	@docker run --rm -it \
		--privileged \
		--name firecracker-vps-dev \
		-p $(API_PORT):$(API_PORT) \
		-v /dev:/dev \
		$(DOCKER_IMAGE)

docker-compose-up: ## Start services with Docker Compose
	@echo "$(BLUE)Starting services with Docker Compose...$(NC)"
	@docker-compose up -d
	@echo "$(GREEN)✓ Services started$(NC)"
	@echo "$(YELLOW)API available at: http://localhost:$(API_PORT)$(NC)"
	@echo "$(YELLOW)Health check: curl http://localhost:$(API_PORT)/health$(NC)"

docker-compose-down: ## Stop Docker Compose services
	@echo "$(BLUE)Stopping Docker Compose services...$(NC)"
	@docker-compose down
	@echo "$(GREEN)✓ Services stopped$(NC)"

docker-compose-logs: ## View Docker Compose logs
	@docker-compose logs -f

##@ Testing
test: ## Run Go tests
	@echo "$(BLUE)Running Go tests...$(NC)"
	@go test -v ./...

test-cli: ## Run Rust CLI tests
	@echo "$(BLUE)Running Rust CLI tests...$(NC)"
	@cd cli && cargo test

test-all: test test-cli ## Run all tests

test-integration: docker-compose-up ## Run integration tests
	@echo "$(BLUE)Running integration tests...$(NC)"
	@sleep 5  # Wait for services to start
	@./scripts/integration-tests.sh
	@make docker-compose-down

##@ Installation
install: build-all ## Install binaries to system
	@echo "$(BLUE)Installing binaries...$(NC)"
	@sudo cp bin/$(BINARY_NAME) /usr/local/bin/
	@sudo cp bin/$(CLI_BINARY) /usr/local/bin/
	@echo "$(GREEN)✓ Binaries installed to /usr/local/bin/$(NC)"
	@echo "$(YELLOW)Run '$(CLI_BINARY) health' to test installation$(NC)"

install-service: install ## Install as systemd service
	@echo "$(BLUE)Installing systemd service...$(NC)"
	@sudo cp scripts/firecracker-vps.service /etc/systemd/system/
	@sudo systemctl daemon-reload
	@sudo systemctl enable firecracker-vps
	@echo "$(GREEN)✓ Service installed$(NC)"
	@echo "$(YELLOW)Start with: sudo systemctl start firecracker-vps$(NC)"

##@ Images and Setup
download-kernel: ## Download Firecracker kernel
	@echo "$(BLUE)Downloading Firecracker kernel...$(NC)"
	@mkdir -p /tmp/firecracker-dev
	@curl -L https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/5.10.186/vmlinux.bin \
		-o /var/lib/firecracker/vmlinux.bin
	@echo "$(GREEN)✓ Kernel downloaded to /var/lib/firecracker/vmlinux.bin$(NC)"

download-firecracker: ## Download Firecracker binaries
	@echo "$(BLUE)Downloading Firecracker binaries...$(NC)"
	@mkdir -p /tmp/firecracker-dev
	@curl -L https://github.com/firecracker-microvm/firecracker/releases/download/v1.4.1/firecracker-v1.4.1-x86_64.tgz | \
		tar -xz -C /tmp/firecracker-dev
	@sudo cp /tmp/firecracker-dev/release-v1.4.1-x86_64/firecracker-v1.4.1-x86_64 /usr/local/bin/firecracker
	@sudo cp /tmp/firecracker-dev/release-v1.4.1-x86_64/jailer-v1.4.1-x86_64 /usr/local/bin/jailer
	@sudo chmod +x /usr/local/bin/firecracker /usr/local/bin/jailer
	@echo "$(GREEN)✓ Firecracker binaries installed$(NC)"

create-base-image: ## Create a basic Ubuntu base image
	@echo "$(BLUE)Creating Ubuntu base image...$(NC)"
	@./scripts/create-base-image.sh ubuntu-22.04
	@echo "$(GREEN)✓ Base image created$(NC)"

setup-host: download-firecracker download-kernel ## Setup host system for development
	@echo "$(BLUE)Setting up host system...$(NC)"
	@sudo sysctl -w net.ipv4.ip_forward=1
	@echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
	@echo "$(GREEN)✓ Host system configured$(NC)"

##@ Cleanup
clean: ## Clean build artifacts
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@rm -rf bin/
	@cd cli && cargo clean
	@echo "$(GREEN)✓ Build artifacts cleaned$(NC)"

clean-docker: ## Clean Docker images and containers
	@echo "$(BLUE)Cleaning Docker artifacts...$(NC)"
	@docker-compose down -v 2>/dev/null || true
	@docker rmi $(DOCKER_IMAGE) 2>/dev/null || true
	@docker system prune -f
	@echo "$(GREEN)✓ Docker artifacts cleaned$(NC)"

clean-all: clean clean-docker ## Clean everything
	@echo "$(GREEN)✓ All artifacts cleaned$(NC)"

##@ Utilities
logs: ## View application logs
	@journalctl -u firecracker-vps -f

status: ## Check service status
	@systemctl status firecracker-vps

cli-help: ## Show CLI help
	@bin/$(CLI_BINARY) --help 2>/dev/null || echo "$(RED)CLI not built yet. Run 'make cli-build' first$(NC)"

api-docs: ## Generate API documentation
	@echo "$(BLUE)Generating API documentation...$(NC)"
	@which swag >/dev/null || go install github.com/swaggo/swag/cmd/swag@latest
	@swag init -g main.go
	@echo "$(GREEN)✓ API docs generated$(NC)"

fmt: ## Format code
	@echo "$(BLUE)Formatting Go code...$(NC)"
	@go fmt ./...
	@echo "$(BLUE)Formatting Rust code...$(NC)"
	@cd cli && cargo fmt
	@echo "$(GREEN)✓ Code formatted$(NC)"

lint: ## Lint code
	@echo "$(BLUE)Linting Go code...$(NC)"
	@which golangci-lint >/dev/null || go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	@golangci-lint run
	@echo "$(BLUE)Linting Rust code...$(NC)"
	@cd cli && cargo clippy -- -D warnings
	@echo "$(GREEN)✓ Code linting completed$(NC)"

##@ Monitoring
monitoring-up: ## Start monitoring stack
	@echo "$(BLUE)Starting monitoring stack...$(NC)"
	@docker-compose --profile monitoring up -d
	@echo "$(GREEN)✓ Monitoring started$(NC)"
	@echo "$(YELLOW)Grafana: http://localhost:3000 (admin/admin123)$(NC)"
	@echo "$(YELLOW)Prometheus: http://localhost:9090$(NC)"

monitoring-down: ## Stop monitoring stack
	@docker-compose --profile monitoring down

##@ Examples
example-create: ## Create example VPS
	@echo "$(BLUE)Creating example VPS...$(NC)"
	@bin/$(CLI_BINARY) create \
		--name "example-vm" \
		--cpu 2 \
		--memory 1024 \
		--disk 20 \
		--image ubuntu-22.04

example-list: ## List VPS instances
	@bin/$(CLI_BINARY) list --detailed

example-interactive: ## Start interactive console
	@bin/$(CLI_BINARY) console

# Default target
default: help
