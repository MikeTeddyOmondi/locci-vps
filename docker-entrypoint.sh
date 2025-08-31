#!/bin/bash
set -e

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Function to check if running in privileged mode
check_privileges() {
    if ! ip link add dummy0 type dummy 2>/dev/null; then
        log "ERROR: Container must run in privileged mode or with NET_ADMIN capability"
        log "Use: docker run --privileged or --cap-add=NET_ADMIN"
        exit 1
    fi
    ip link delete dummy0 2>/dev/null || true
}

# Function to setup network bridge
setup_bridge() {
    local bridge_name="${NETWORK_BRIDGE:-br0}"
    local bridge_ip="${BRIDGE_IP:-192.168.100.1/24}"

    if ! ip link show "$bridge_name" >/dev/null 2>&1; then
        log "Creating bridge interface: $bridge_name"
        ip link add name "$bridge_name" type bridge
        ip addr add "$bridge_ip" dev "$bridge_name"
        ip link set "$bridge_name" up

        # Enable IP forwarding
        echo 1 > /proc/sys/net/ipv4/ip_forward

        # Setup iptables rules for NAT
        iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -j MASQUERADE
        iptables -A FORWARD -i "$bridge_name" -j ACCEPT
        iptables -A FORWARD -o "$bridge_name" -j ACCEPT

        log "Bridge $bridge_name created and configured"
    else
        log "Bridge $bridge_name already exists"
    fi
}

# Function to download Firecracker binary if not present
setup_firecracker() {
    local fc_version="${FIRECRACKER_VERSION:-v1.4.1}"
    local fc_arch="${FIRECRACKER_ARCH:-x86_64}"
    local fc_binary="/usr/local/bin/firecracker"
    local jailer_binary="/usr/local/bin/jailer"

    if [ ! -f "$fc_binary" ]; then
        log "Downloading Firecracker $fc_version"
        local download_url="https://github.com/firecracker-microvm/firecracker/releases/download/${fc_version}/firecracker-${fc_version}-${fc_arch}.tgz"

        cd /tmp
        curl -L "$download_url" | tar -xz

        # Move binaries to proper location
        mv "release-${fc_version}-${fc_arch}/firecracker-${fc_version}-${fc_arch}" "$fc_binary"
        mv "release-${fc_version}-${fc_arch}/jailer-${fc_version}-${fc_arch}" "$jailer_binary"

        chmod +x "$fc_binary" "$jailer_binary"
        rm -rf "release-${fc_version}-${fc_arch}"

        log "Firecracker binary installed successfully"
    else
        log "Firecracker binary already present"
    fi
}

# Function to setup kernel image
setup_kernel() {
    local kernel_path="${KERNEL_PATH:-/var/lib/firecracker/vmlinux.bin}"
    local kernel_version="${KERNEL_VERSION:-5.10.186}"

    if [ ! -f "$kernel_path" ]; then
        log "Downloading kernel image"
        local kernel_url="https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/${kernel_version}/vmlinux.bin"

        mkdir -p "$(dirname "$kernel_path")"
        curl -L "$kernel_url" -o "$kernel_path"

        log "Kernel image downloaded successfully"
    else
        log "Kernel image already present"
    fi
}

# Function to create default base images
setup_base_images() {
    local images_dir="${BASE_IMAGES_DIR:-/var/lib/firecracker/images}"

    mkdir -p "$images_dir"

    # Create sample Ubuntu base image if not present
    if [ ! -f "$images_dir/ubuntu-22.04.ext4" ]; then
        log "Creating default Ubuntu 22.04 base image"

        # Create a minimal rootfs (in production, use proper image building)
        local temp_img="/tmp/ubuntu-22.04.ext4"
        dd if=/dev/zero of="$temp_img" bs=1M count=1024
        mkfs.ext4 "$temp_img"

        # Mount and setup basic structure
        local mount_point="/tmp/rootfs"
        mkdir -p "$mount_point"
        mount "$temp_img" "$mount_point"

        # Create basic directory structure
        mkdir -p "$mount_point"/{bin,sbin,etc,proc,sys,dev,root,home,tmp,var,usr}
        mkdir -p "$mount_point/usr"/{bin,sbin,lib}
        mkdir -p "$mount_point/var"/{log,lib,tmp}

        # Create basic files
        echo "root:x:0:0:root:/root:/bin/bash" > "$mount_point/etc/passwd"
        echo "root:x:0:" > "$mount_point/etc/group"
        echo "ubuntu-firecracker" > "$mount_point/etc/hostname"

        # Create init script
        cat > "$mount_point/sbin/init" << 'EOF'
#!/bin/sh
echo "Firecracker VM started successfully"
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
/bin/sh
EOF
        chmod +x "$mount_point/sbin/init"

        umount "$mount_point"
        mv "$temp_img" "$images_dir/ubuntu-22.04.ext4"

        log "Default Ubuntu 22.04 image created"
    fi
}

# Function to validate environment
validate_environment() {
    log "Validating environment..."

    # Check required environment variables
    local required_dirs=(
        "${VM_DIR:-/var/lib/firecracker-vms}"
        "${BASE_IMAGES_DIR:-/var/lib/firecracker/images}"
    )

    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log "Creating directory: $dir"
            mkdir -p "$dir"
        fi
    done

    # Check permissions
    if [ ! -w "${VM_DIR:-/var/lib/firecracker-vms}" ]; then
        log "WARNING: No write permission to VM directory"
    fi

    log "Environment validation completed"
}

# Function to cleanup on exit
cleanup() {
    log "Shutting down Firecracker VPS service..."
    # Add cleanup logic here if needed
    exit 0
}

# Trap signals
trap cleanup SIGTERM SIGINT

# Main setup function
main() {
    log "Starting Firecracker VPS service initialization..."

    # Validate environment
    validate_environment

    # Check if we have required privileges
    check_privileges

    # Setup network bridge
    setup_bridge

    # Setup Firecracker binary
    setup_firecracker

    # Setup kernel image
    setup_kernel

    # Setup base images
    setup_base_images

    log "Initialization completed successfully"
    log "Starting Firecracker VPS API server..."

    # Execute the main command
    exec "$@"
}

# Run main function
main "$@"

