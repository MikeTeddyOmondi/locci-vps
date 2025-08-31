# Firecracker VPS Management Platform

A lightweight, high-performance VPS/IaaS platform built on AWS Firecracker microVMs. This platform provides ultra-fast VM provisioning (5ms boot times), strong security isolation, and efficient resource utilization for cloud hosting businesses.

## 🚀 Features

- **Ultra-Fast Provisioning**: 5ms boot times with Firecracker microVMs
- **Strong Security**: Hardware-level isolation for each VM
- **High Density**: Run hundreds of VMs per server
- **RESTful API**: Complete API for VM lifecycle management
- **Modern CLI**: Beautiful, interactive command-line interface
- **Docker Support**: Easy deployment with Docker Compose
- **Real-time Management**: Interactive console for VM operations
- **Resource Efficiency**: Minimal overhead compared to traditional hypervisors

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Installation](#installation)
- [API Reference](#api-reference)
- [CLI Usage](#cli-usage)
- [Configuration](#configuration)
- [Development](#development)
- [Monitoring](#monitoring)
- [Production Deployment](#production-deployment)
- [Troubleshooting](#troubleshooting)

## 🚀 Quick Start

### Prerequisites

- Linux host with KVM support
- Docker and Docker Compose
- Root or sudo access (for network management)

### 1. Clone and Start

```bash
git clone https://github.com/MikeTeddyOmondi/firecracker-vps
cd firecracker-vps

# Start the platform
make docker-compose-up
```

### 2. Install CLI

```bash
# Build and install CLI
make cli-build
sudo cp bin/fc-vps /usr/local/bin/

# Verify installation
fc-vps health
```

### 3. Create Your First VPS

```bash
# Interactive creation
fc-vps create --interactive

# Or specify parameters directly
fc-vps create \
    --name "my-first-vps" \
    --cpu 2 \
    --memory 1024 \
    --disk 20 \
    --image ubuntu-22.04
```

### 4. Manage VPS Instances

```bash
# List all VPS
fc-vps list

# Start a VPS
fc-vps start my-first-vps

# Get detailed information
fc-vps get my-first-vps

# Interactive console
fc-vps console
```

## 🏗 Architecture

### Core Components

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CLI Client    │───▶│   API Server    │───▶│  Firecracker    │
│   (Rust/Clap)  │    │   (Go/Gin)      │    │   Instances     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   VM Manager    │
                       │ • IP Management │
                       │ • TAP Devices   │
                       │ • Storage       │
                       │ • Lifecycle     │
                       └─────────────────┘
```

### Technology Stack

- **API Server**: Go with Gin framework
- **CLI Client**: Rust with Clap derive
- **Virtualization**: AWS Firecracker
- **Networking**: Linux bridge + TAP interfaces
- **Storage**: Copy-on-write disk images
- **Containerization**: Docker with privileged mode

## 💻 Installation

### Option 1: Docker Compose (Recommended)

```bash
# Clone the repository
git clone https://github.com/MikeTeddyOmondi/firecracker-vps
cd firecracker-vps

# Start services
make docker-compose-up

# Install CLI locally
make cli-build
sudo cp bin/fc-vps /usr/local/bin/
```

### Option 2: Native Installation

```bash
# Install dependencies
sudo apt update
sudo apt install -y build-essential curl

# Install Go (1.21+)
curl -L https://go.dev/dl/go1.21.0.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
export PATH=$PATH:/usr/local/go/bin

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Setup the project
make setup
make download-firecracker
make download-kernel
make build-all
make install
```

### Option 3: Development Setup

```bash
# Setup development environment
make setup
make setup-host
make download-kernel
make dev  # Starts with live reload
```

## 🔌 API Reference

### Base URL

```
http://localhost:8080/api/v1
```

### Endpoints

#### Create VM

```http
POST /vms
Content-Type: application/json

{
    "name": "my-vm",
    "cpu": 2,
    "memory": 1024,
    "disk_size": 20,
    "image": "ubuntu-22.04"
}
```

#### List VMs

```http
GET /vms
```

#### Get VM Details

```http
GET /vms/{id}
```

#### Start VM

```http
POST /vms/{id}/start
```

#### Stop VM

```http
POST /vms/{id}/stop
```

#### Delete VM

```http
DELETE /vms/{id}
```

#### Health Check

```http
GET /health
```

### Response Format

```json
{
  "success": true,
  "message": "Operation completed successfully",
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "my-vm",
    "cpu": 2,
    "memory": 1024,
    "disk_size": 20,
    "image": "ubuntu-22.04",
    "status": "running",
    "ip_address": "192.168.100.10",
    "created_at": "2024-01-15T10:30:00Z"
  }
}
```

## 🖥 CLI Usage

### Basic Commands

```bash
# Health check
fc-vps health

# Create VM (interactive)
fc-vps create --interactive

# Create VM (direct)
fc-vps create --name web-server --cpu 4 --memory 2048 --disk 40

# List all VMs
fc-vps list

# List with details
fc-vps list --detailed

# Filter by status
fc-vps list --status running

# Get VM information
fc-vps get web-server
fc-vps get web-server --json

# Start VM
fc-vps start web-server
fc-vps start web-server --wait

# Stop VM
fc-vps stop web-server
fc-vps stop web-server --force

# Delete VM
fc-vps delete web-server
fc-vps delete web-server --force

# Interactive console
fc-vps console
```

### Environment Variables

```bash
# Set default server
export FC_VPS_SERVER=http://your-server:8080

# Use custom server for single command
fc-vps --server http://remote-server:8080 list
```

### CLI Features

- **Interactive Mode**: Guided VM creation with input validation
- **Progress Bars**: Visual feedback for long-running operations
- **Colored Output**: Status indicators and beautiful formatting
- **Table Display**: Clean tabular output for VM listings
- **JSON Output**: Machine-readable output for automation
- **Auto-completion**: Tab completion for commands (when installed)

## ⚙️ Configuration

### Environment Variables

| Variable              | Default                            | Description             |
| --------------------- | ---------------------------------- | ----------------------- |
| `API_PORT`            | `8080`                             | API server port         |
| `VM_DIR`              | `/var/lib/firecracker-vms`         | VM storage directory    |
| `BASE_IMAGES_DIR`     | `/var/lib/firecracker/images`      | Base images directory   |
| `KERNEL_PATH`         | `/var/lib/firecracker/vmlinux.bin` | Firecracker kernel path |
| `NETWORK_BRIDGE`      | `br0`                              | Network bridge name     |
| `NETWORK_SUBNET`      | `192.168.100.0/24`                 | VM network subnet       |
| `MAX_VMS_PER_HOST`    | `100`                              | Maximum VMs per host    |
| `FIRECRACKER_VERSION` | `v1.4.1`                           | Firecracker version     |
| `FC_VPS_SERVER`       | `http://localhost:8080`            | CLI default server      |

### Docker Configuration

```yaml
# docker-compose.override.yml
name: "fc-vps"
services:
  firecracker-vps:
    environment:
      - API_PORT=9090
      - MAX_VMS_PER_HOST=200
      - NETWORK_SUBNET=10.0.0.0/24
    ports:
      - "9090:9090"
```

### Network Configuration

The platform creates a bridge network for VM communication:

```bash
# Default network setup
ip link add name br0 type bridge
ip addr add 192.168.100.1/24 dev br0
ip link set br0 up

# NAT for internet access
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -j MASQUERADE
iptables -A FORWARD -i br0 -j ACCEPT
iptables -A FORWARD -o br0 -j ACCEPT
```

## 🛠 Development

### Development Environment

```bash
# Setup development environment
make setup

# Start development server with live reload
make dev

# Run tests
make test-all

# Format code
make fmt

# Lint code
make lint
```

### Project Structure

```bash
firecracker-vps/
├── main.go                # API server main file
├── go.mod                 # Go dependencies
├── cli/
│   ├── Cargo.toml         # Rust CLI dependencies
│   └── src/main.rs        # CLI main file
├── compose.yml            # Docker compose configuration
├── Dockerfile             # API server container
├── Makefile               # Development commands
├── scripts/
│   ├── create-base-image.sh
│   ├── integration-tests.sh
│   └── firecracker-vps.service
└── monitoring/
    ├── prometheus.yml
    └── grafana/
```

### Adding New Features

1. **API Endpoints**: Add to main.go in the API routes section
2. **CLI Commands**: Add to cli/src/main.rs in the Commands enum
3. **VM Operations**: Extend the VMManager methods
4. **Storage**: Modify createVMRootfs function
5. **Networking**: Update TAP management functions

### Testing

```bash
# Unit tests
make test

# Integration tests (requires Docker)
make test-integration

# CLI tests
make test-cli

# Manual API testing
curl -X POST http://localhost:8080/api/v1/vms \
  -H "Content-Type: application/json" \
  -d '{"name":"test-vm","cpu":1,"memory":512,"disk_size":10,"image":"ubuntu-22.04"}'
```

## 📊 Monitoring

### Built-in Monitoring

Start the monitoring stack:

```bash
make monitoring-up
```

This provides:

- **Grafana**: http://localhost:3000 (admin/admin123)
- **Prometheus**: http://localhost:9090

### Custom Metrics

The API server exposes metrics at `/metrics`:

- `firecracker_vms_total`: Total number of VMs
- `firecracker_vms_running`: Number of running VMs
- `firecracker_api_requests_total`: API request counter
- `firecracker_vm_creation_duration`: VM creation time

### Logging

```bash
# View logs in Docker
make docker-compose-logs

# View systemd logs
make logs

# Application logs location
/var/log/firecracker/
```

## 🚀 Production Deployment

### System Requirements

**Minimum:**

- 4 CPU cores
- 8GB RAM
- 100GB SSD storage
- Ubuntu 20.04+ or similar

**Recommended:**

- 16+ CPU cores
- 32GB+ RAM
- 500GB+ NVMe SSD
- Dedicated server with KVM support

### Production Setup

1. **Prepare the host:**

```bash
# Enable KVM
sudo modprobe kvm kvm_intel  # or kvm_amd
echo 'kvm_intel' | sudo tee -a /etc/modules  # or kvm_amd
```

# Configure networking

sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf

# Create firecracker user

sudo useradd -r -s /bin/false firecracker

2. **Deploy with systemd:**

```bash
make install-service
sudo systemctl start firecracker-vps
sudo systemctl status firecracker-vps
```

3. **Setup reverse proxy (nginx):**

```nginx
server {
 listen 80;
 server_name your-domain.com;

 location /api/ {
     proxy_pass http://127.0.0.1:8080;
     proxy_set_header Host $host;
     proxy_set_header X-Real-IP $remote_addr;
 }
}
```

4. **Configure firewall:**

```bash
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw --force enable
```

### Scaling Considerations

**Single Host Limits:**

- ~100-200 VMs per host (depending on specs)
- Monitor CPU and memory usage
- Consider NUMA topology for large hosts

**Multi-Host Setup:**

- Deploy API server on each host
- Use load balancer for API distribution
- Implement shared storage for VM images
- Consider etcd for distributed state management

### Security Hardening

1. **API Security:**

```go
// Add authentication middleware
func authMiddleware() gin.HandlerFunc {
 return gin.BasicAuth(gin.Accounts{
     "admin": "secure-password",
 })
}
```

2. **Network Security:**

```bash
# Restrict VM network access
iptables -A FORWARD -s 192.168.100.0/24 -d 192.168.100.0/24 -j DROP
iptables -A FORWARD -s 192.168.100.0/24 -p tcp --dport 22 -j ACCEPT
```

3. **File Permissions:**

```bash
sudo chmod 750 /var/lib/firecracker-vms
sudo chown -R firecracker:firecracker /var/lib/firecracker-vms
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Permission Denied

```bash
# Solution: Ensure proper permissions
sudo usermod -a -G kvm $USER
sudo chmod 666 /dev/kvm
```

#### 2. Network Issues

```bash
# Check bridge configuration
ip addr show br0

# Verify iptables rules
sudo iptables -L -n -v

# Test connectivity
ping 192.168.100.1
```

#### 3. VM Won't Start

```bash
# Check Firecracker logs
journalctl -u firecracker-vps -f

# Verify kernel and rootfs paths
ls -la /var/lib/firecracker/vmlinux.bin
ls -la /var/lib/firecracker/images/
```

#### 4. High CPU Usage

```bash
# Check VM resource allocation
fc-vps list --detailed

# Monitor host resources
htop
iostat -x 1
```

### Debug Mode

Enable verbose logging:

```bash
# API server
FC_DEBUG=true ./bin/firecracker-vps

# CLI client
fc-vps --verbose list
```

### Performance Tuning

1. **Kernel Parameters:**

```bash
echo 'vm.swappiness = 1' >> /etc/sysctl.conf
echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
```

2. **CPU Affinity:**

```go
// Pin VMs to specific CPU cores
cfg.MachineCfg.CpuTemplate = models.CPUTemplateT2
```

3. **Storage Optimization:**

```bash
# Use faster storage for VM images
mount -t tmpfs -o size=10G tmpfs /var/lib/firecracker/images
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run `make test-all`
6. Submit a pull request

### Code Standards

- **Go**: Follow `gofmt` and `golangci-lint` standards
- **Rust**: Use `cargo fmt` and `cargo clippy`
- **Commits**: Use conventional commit format
- **Documentation**: Update README and code comments

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **AWS Firecracker Team** - For the amazing microVM technology
- **Gin Framework** - For the fast HTTP framework
- **Clap** - For the excellent CLI framework
- **Community Contributors** - For feedback and contributions

## 📞 Support

- **Documentation**: [Wiki](https://github.com/yourusername/firecracker-vps/wiki)
- **Issues**: [GitHub Issues](https://github.com/yourusername/firecracker-vps/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/firecracker-vps/discussions)
- **Email**: support@your-domain.com

---

**Built with ❤️ for the cloud hosting community**

---
