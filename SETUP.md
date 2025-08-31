# Setup Guide

This guide explains where to place rootfs files and how to configure the service properly.

## 📁 Directory Structure

After setup, your system should have this structure:

```
/var/lib/firecracker/
├── vmlinux.bin                    # Firecracker kernel (auto-downloaded)
└── images/                        # Base rootfs images (you place these here)
    ├── ubuntu-20.04.ext4
    ├── ubuntu-22.04.ext4
    ├── debian-11.ext4
    ├── centos-7.ext4
    └── alpine-3.18.ext4

/var/lib/firecracker-vms/          # Individual VM storage (auto-managed)
├── {vm-id-1}/
│   ├── firecracker.socket
│   └── rootfs.ext4               # VM's individual rootfs copy
├── {vm-id-2}/
│   └── ...

/usr/local/bin/
├── firecracker                    # Firecracker binary
├── jailer                        # Jailer binary
├── firecracker-vps               # Your API server
└── fc-vps                        # Your CLI tool
```

## 🖼 Where to Place Rootfs Images

### Base Images Location
Place your `.ext4` rootfs images in:
```bash
/var/lib/firecracker/images/
```

### Supported Image Names
The system looks for these image names:
- `ubuntu-20.04.ext4`
- `ubuntu-22.04.ext4` 
- `ubuntu-24.04.ext4` 
- `debian-11.ext4`
- `centos-7.ext4`
- `alpine-3.18.ext4`

## 🔧 Configuration with .env File

### 1. Copy the Environment File
```bash
cp .env.example .env
# Edit the .env file to match your system
```

### 2. Key Configuration Sections

#### Storage Paths
```bash
# Where VM instances are stored
VM_DIR=/var/lib/firecracker-vms

# Where base rootfs images are stored
BASE_IMAGES_DIR=/var/lib/firecracker/images

# Firecracker kernel location
KERNEL_PATH=/var/lib/firecracker/vmlinux.bin
```

#### Network Configuration
```bash
# Network bridge for VMs
NETWORK_BRIDGE=br0
NETWORK_SUBNET=192.168.100.0/24
BRIDGE_IP=192.168.100.1/24
```

#### Resource Limits
```bash
MAX_VMS_PER_HOST=100
MAX_CPU_PER_VM=8
MAX_MEMORY_PER_VM=8192
```

## 🚀 Quick Setup Commands

### 1. Automatic Setup (Recommended)
```bash
# Create directories and download essentials
make setup-host

# This creates:
# - /var/lib/firecracker/images/
# - /var/lib/firecracker-vms/
# - Downloads kernel and Firecracker binaries
```

### 2. Manual Setup
```bash
# Create directories
sudo mkdir -p /var/lib/firecracker/images
sudo mkdir -p /var/lib/firecracker-vms
sudo mkdir -p /var/log/firecracker

# Set permissions
sudo chown -R $USER:$USER /var/lib/firecracker*
sudo chown -R $USER:$USER /var/log/firecracker

# Download kernel
make download-kernel

# Download Firecracker binaries
make download-firecracker
```

## 📦 Getting Base Images

### Option 1: Download Pre-built Images

#### Ubuntu 22.04
```bash
# Download official cloud image
wget https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img -O /tmp/ubuntu-22.04.img

# Convert to ext4 (if needed)
qemu-img convert -f qcow2 -O raw /tmp/ubuntu-22.04.img /tmp/ubuntu-22.04.raw
sudo mount /tmp/ubuntu-22.04.raw /mnt
sudo dd if=/dev/zero of=/var/lib/firecracker/images/ubuntu-22.04.ext4 bs=1M count=2048
sudo mkfs.ext4 /var/lib/firecracker/images/ubuntu-22.04.ext4
sudo mount /var/lib/firecracker/images/ubuntu-22.04.ext4 /mnt2
sudo cp -a /mnt/* /mnt2/
sudo umount /mnt /mnt2
```

#### Quick Alpine Linux
```bash
# Minimal Alpine rootfs (smallest option)
curl -L https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-minirootfs-3.18.4-x86_64.tar.gz -o /tmp/alpine.tar.gz

# Create ext4 image
dd if=/dev/zero of=/var/lib/firecracker/images/alpine-3.18.ext4 bs=1M count=512
mkfs.ext4 /var/lib/firecracker/images/alpine-3.18.ext4
sudo mount /var/lib/firecracker/images/alpine-3.18.ext4 /mnt
sudo tar -xzf /tmp/alpine.tar.gz -C /mnt
sudo umount /mnt
```

### Option 2: Use Our Image Builder
```bash
# Build Ubuntu 22.04 image
make create-base-image

# This creates a minimal but functional Ubuntu image
```

### Option 3: Custom Image Creation Script

Create `scripts/build-rootfs.sh`:
```bash
#!/bin/bash
# Custom rootfs builder
IMAGE_NAME=$1
IMAGE_SIZE=${2:-1024}  # MB

case $IMAGE_NAME in
    "ubuntu-22.04")
        # Use debootstrap to build Ubuntu
        sudo debootstrap --arch=amd64 jammy /tmp/rootfs http://archive.ubuntu.com/ubuntu/
        ;;
    "debian-11")
        # Use debootstrap for Debian
        sudo debootstrap --arch=amd64 bullseye /tmp/rootfs http://deb.debian.org/debian/
        ;;
    *)
        echo "Unsupported image: $IMAGE_NAME"
        exit 1
        ;;
esac

# Create ext4 image
dd if=/dev/zero of="/var/lib/firecracker/images/${IMAGE_NAME}.ext4" bs=1M count=$IMAGE_SIZE
mkfs.ext4 "/var/lib/firecracker/images/${IMAGE_NAME}.ext4"

# Copy rootfs
sudo mount "/var/lib/firecracker/images/${IMAGE_NAME}.ext4" /mnt
sudo cp -a /tmp/rootfs/* /mnt/
sudo umount /mnt

# Cleanup
sudo rm -rf /tmp/rootfs
```

## 🔄 Environment Loading

### Development Mode
```bash
# Copy development config
cp .env.development .env

# Uses paths like:
# VM_DIR=/tmp/firecracker-dev/vms
# BASE_IMAGES_DIR=/tmp/firecracker-dev/images
```

### Production Mode
```bash
# Copy production config
cp .env.production .env

# Uses system paths:
# VM_DIR=/var/lib/firecracker-vms
# BASE_IMAGES_DIR=/var/lib/firecracker/images
```

### Docker Mode
```bash
# Docker Compose automatically uses:
# Container internal paths with volume mounts
```

## 🧪 Testing Your Setup

### 1. Verify Directories
```bash
ls -la /var/lib/firecracker/images/
# Should show your .ext4 files

ls -la /var/lib/firecracker/vmlinux.bin
# Should show the kernel
```

### 2. Test Image Creation
```bash
# Start the service
make run

# Create a test VM
fc-vps create --name test --image ubuntu-22.04

# Check if VM files were created
ls -la /var/lib/firecracker-vms/
```

### 3. Verify Network
```bash
# Check bridge exists
ip addr show br0

# Should show:
# br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
#     inet 192.168.100.1/24 scope global br0
```

## ⚠️ Common Issues

### Permission Denied
```bash
# Fix ownership
sudo chown -R $USER:$USER /var/lib/firecracker*

# Or run with proper user
sudo -u firecracker /usr/local/bin/firecracker-vps
```

### Network Issues
```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Check iptables
sudo iptables -L -n -v
```

### Missing Images
```bash
# List available images
fc-vps list-images  # (if implemented)

# Or check directory
ls /var/lib/firecracker/images/
```

## 📝 Environment Variables Reference

| Variable | Purpose | Example |
|----------|---------|---------|
| `BASE_IMAGES_DIR` | Where to find `.ext4` rootfs images | `/var/lib/firecracker/images` |
| `VM_DIR` | Where to store individual VM data | `/var/lib/firecracker-vms` |
| `KERNEL_PATH` | Firecracker kernel location | `/var/lib/firecracker/vmlinux.bin` |
| `NETWORK_BRIDGE` | Bridge interface for VMs | `br0` |
| `API_PORT` | API server port | `8080` |

---

Great questions! Let me clarify the rootfs location and create a proper `.env` configuration file for you.## 📍 **Rootfs Files Location & .env Configuration**

### **🖼 Where to Place Rootfs Images**

**Base images go in:**
```bash
/var/lib/firecracker/images/
├── ubuntu-20.04.ext4      # Your Ubuntu 20.04 rootfs
├── ubuntu-22.04.ext4      # Your Ubuntu 22.04 rootfs  
├── debian-11.ext4         # Your Debian rootfs
├── centos-7.ext4          # Your CentOS rootfs
└── alpine-3.18.ext4       # Your Alpine rootfs
```

**Individual VM storage (auto-managed):**
```bash
/var/lib/firecracker-vms/
├── {vm-uuid-1}/
│   ├── firecracker.socket
│   └── rootfs.ext4        # Copy-on-write from base image
├── {vm-uuid-2}/
│   └── ...
```

### **⚙️ .env Configuration**

The `.env` file I created above centralizes all configuration. Key sections:

**Storage Paths:**
```bash
BASE_IMAGES_DIR=/var/lib/firecracker/images    # Your .ext4 files here
VM_DIR=/var/lib/firecracker-vms                # Individual VM storage  
KERNEL_PATH=/var/lib/firecracker/vmlinux.bin   # Firecracker kernel
```

**Network:**
```bash
NETWORK_BRIDGE=br0                    # Bridge interface
NETWORK_SUBNET=192.168.100.0/24      # VM IP range
BRIDGE_IP=192.168.100.1/24           # Gateway IP
```

### **🚀 Quick Setup Process**

1. **Create the directories:**
```bash
make setup-host  # Creates all directories + downloads kernel/binaries
```

2. **Get your rootfs images:**
```bash
# Option A: Download pre-built
wget https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img

# Option B: Build minimal (our script creates basic Ubuntu)
make create-base-image

# Option C: Use existing .ext4 files you have
cp your-rootfs.ext4 /var/lib/firecracker/images/ubuntu-22.04.ext4
```

3. **Configure environment:**
```bash
cp .env .env.local  # Copy and customize if needed
```

4. **Start the platform:**
```bash
make docker-compose-up  # OR
make run               # For native execution
```

### **📁 Complete Directory Structure After Setup**

```
/var/lib/firecracker/
├── vmlinux.bin                    # Firecracker kernel (auto-downloaded)
└── images/                        # YOUR ROOTFS FILES GO HERE
    ├── ubuntu-22.04.ext4         # ← Place your images here
    ├── debian-11.ext4
    └── alpine-3.18.ext4

/var/lib/firecracker-vms/          # Auto-managed VM storage
├── {uuid-1}/rootfs.ext4          # Individual VM disks
├── {uuid-2}/rootfs.ext4
└── ...

/usr/local/bin/
├── firecracker                    # Downloaded automatically
├── jailer
├── firecracker-vps               # Your API binary
└── fc-vps                        # Your CLI binary
```

The system automatically:
- ✅ **Copies** base images to individual VM directories
- ✅ **Resizes** them based on requested disk size
- ✅ **Manages** networking with TAP interfaces
- ✅ **Handles** cleanup when VMs are deleted

**When you create a VM with `--image ubuntu-22.04`, it looks for `/var/lib/firecracker/images/ubuntu-22.04.ext4` and copies it to the VM's private directory.**

This gives you complete control over your base images while keeping the platform simple to use.

---



