#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to create base image
create_image() {
  local VERSION=$1
  local IMG_URL=$2
  local DOWNLOAD_PATH="/tmp/ubuntu-${VERSION}.img"
  local RAW_PATH="/tmp/ubuntu-${VERSION}.raw"
  local FINAL_IMAGE="/var/lib/firecracker/images/ubuntu-${VERSION}.ext4"

  echo -e "${YELLOW}=== Creating Ubuntu ${VERSION} Base Image ===${NC}"

  # Check if final image already exists
  if [ -f "$FINAL_IMAGE" ]; then
    echo -e "${GREEN}✓ Base image already exists at $FINAL_IMAGE${NC}"
    ls -lh "$FINAL_IMAGE"
    return 0
  fi

  # Install required tools if not present
  if ! command -v qemu-img &>/dev/null; then
    echo -e "${YELLOW}Installing qemu-utils...${NC}"
    sudo apt-get update
    sudo apt-get install -y qemu-utils
  fi

  # Create mount points if they don't exist
  if [ ! -d "/mnt" ]; then
    sudo mkdir -p /mnt
  fi
  if [ ! -d "/mnt2" ]; then
    sudo mkdir -p /mnt2
  fi

  # Create directories if they don't exist
  sudo mkdir -p /var/lib/firecracker/images

  # Download image if not already present
  if [ ! -f "$DOWNLOAD_PATH" ]; then
    echo -e "${YELLOW}Downloading Ubuntu ${VERSION} image...${NC}"
    wget "$IMG_URL" -O "$DOWNLOAD_PATH"
  else
    echo -e "${GREEN}✓ Downloaded image already exists${NC}"
  fi

  # Detect image format and convert if needed
  echo -e "${YELLOW}Detecting image format...${NC}"
  IMG_FORMAT=$(sudo qemu-img info "$DOWNLOAD_PATH" | grep "file format:" | awk '{print $NF}')
  echo -e "${GREEN}Image format: $IMG_FORMAT${NC}"

  if [ "$IMG_FORMAT" != "raw" ]; then
    if [ ! -f "$RAW_PATH" ]; then
      echo -e "${YELLOW}Converting $IMG_FORMAT to raw...${NC}"
      sudo qemu-img convert -f "$IMG_FORMAT" -O raw "$DOWNLOAD_PATH" "$RAW_PATH"
    else
      echo -e "${GREEN}✓ Raw image already exists${NC}"
    fi
    MOUNT_IMG="$RAW_PATH"
  else
    echo -e "${GREEN}✓ Image is already raw format${NC}"
    MOUNT_IMG="$DOWNLOAD_PATH"
  fi

  # Mount the image (handle partitioned images)
  echo -e "${YELLOW}Mounting image...${NC}"
  if sudo losetup -f -P "$MOUNT_IMG" &>/dev/null; then
    LOOP_DEV=$(sudo losetup -j "$MOUNT_IMG" | cut -d: -f1 | head -1)
    if [ -b "${LOOP_DEV}p1" ]; then
      # Partitioned image - mount first partition
      sudo mount "${LOOP_DEV}p1" /mnt
    else
      # Raw image without partitions
      sudo mount -o loop "$MOUNT_IMG" /mnt
    fi
  else
    # Fallback to simple loop mount
    sudo mount -o loop "$MOUNT_IMG" /mnt
  fi

  # Create a 2GB ext4 filesystem
  echo -e "${YELLOW}Creating ext4 filesystem...${NC}"
  sudo dd if=/dev/zero of="$FINAL_IMAGE" bs=1M count=2048
  sudo mkfs.ext4 -F "$FINAL_IMAGE"

  # Mount the new filesystem
  echo -e "${YELLOW}Mounting new filesystem...${NC}"
  sudo mount "$FINAL_IMAGE" /mnt2

  # Copy filesystem
  echo -e "${YELLOW}Copying filesystem...${NC}"
  sudo cp -a /mnt/* /mnt2/ 2>/dev/null || true

  # Cleanup
  echo -e "${YELLOW}Cleaning up...${NC}"
  sudo umount /mnt /mnt2

  # Set proper permissions
  echo -e "${YELLOW}Setting permissions...${NC}"
  sudo chown firecracker:firecracker "$FINAL_IMAGE"
  sudo chmod 644 "$FINAL_IMAGE"

  echo -e "${GREEN}✓ Base image created at $FINAL_IMAGE${NC}"
  ls -lh "$FINAL_IMAGE"
  echo ""
}

# Main script
echo -e "${GREEN}=== Firecracker Base Image Creator ===${NC}\n"

if [ $# -eq 0 ]; then
  # Create both versions
  echo -e "${YELLOW}No version specified. Creating both 22.04 and 24.04...${NC}\n"

  create_image "22.04" "https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img"
  create_image "24.04" "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"

  echo -e "${GREEN}✓ All base images created successfully!${NC}"
elif [ "$1" == "22.04" ]; then
  create_image "22.04" "https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img"
elif [ "$1" == "24.04" ]; then
  create_image "24.04" "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
else
  echo -e "${RED}Usage: $0 [22.04|24.04]${NC}"
  echo -e "${YELLOW}Examples:${NC}"
  echo -e "  $0          # Create both 22.04 and 24.04"
  echo -e "  $0 22.04   # Create only 22.04"
  echo -e "  $0 24.04   # Create only 24.04"
  exit 1
fi
