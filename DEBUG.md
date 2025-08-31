# FlameCloud Debugging Guide

## 🔍 Debugging "failed to copy base image: exit status 1"

This error occurs in the `createVMRootfs` function when copying the base image fails.

### Step 1: Check if Base Image Exists

```bash
# Check what images are available
ls -la /var/lib/firecracker/images/

# Specifically check for ubuntu-24.04
ls -la /var/lib/firecracker/images/ubuntu-24.04.ext4
```

**If the file doesn't exist:**
- You specified `--image ubuntu-24.04` but the file `ubuntu-24.04.ext4` doesn't exist
- Available images are only what you've placed in the directory

### Step 2: Check Available Images

```bash
# List all available base images
fc-vps list-images  # (if implemented)

# Or check directory directly
find /var/lib/firecracker/images/ -name "*.ext4" -exec basename {} .ext4 \;
```

### Step 3: Check Permissions

```bash
# Check directory permissions
ls -ld /var/lib/firecracker/images/
ls -ld /var/lib/firecracker-vms/

# Check if user can read base images
whoami
groups
ls -la /var/lib/firecracker/images/
```

### Step 4: Test Manual Copy

```bash
# Test if you can manually copy an existing image
sudo cp /var/lib/firecracker/images/ubuntu-22.04.ext4 /tmp/test-copy.ext4

# If this fails, check disk space
df -h /var/lib/firecracker-vms/
```

## 🛠 Quick Fixes

### Fix 1: Use Existing Image
```bash
# Check what images you actually have
ls /var/lib/firecracker/images/

# Use an existing image instead
fc-vps create --image ubuntu-22.04  # Instead of ubuntu-24.04
```

### Fix 2: Create Ubuntu 24.04 Image

#### Option A: Download Official Image
```bash
# Download Ubuntu 24.04 cloud image
wget https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img -O /tmp/ubuntu-24.04.img

# Convert to ext4 format
qemu-img convert -f qcow2 -O raw /tmp/ubuntu-24.04.img /tmp/ubuntu-24.04.raw

# Create ext4 filesystem
dd if=/dev/zero of=/var/lib/firecracker/images/ubuntu-24.04.ext4 bs=1M count=1024
mkfs.ext4 /var/lib/firecracker/images/ubuntu-24.04.ext4

# Mount and copy files
sudo mkdir -p /mnt/{source,target}
sudo mount /tmp/ubuntu-24.04.raw /mnt/source
sudo mount /var/lib/firecracker/images/ubuntu-24.04.ext4 /mnt/target
sudo cp -a /mnt/source/* /mnt/target/
sudo umount /mnt/{source,target}
```

#### Option B: Create Minimal Image
```bash
# Create a basic Ubuntu 24.04 using debootstrap
sudo debootstrap --arch=amd64 noble /tmp/ubuntu-24.04-root http://archive.ubuntu.com/ubuntu/

# Create ext4 image
dd if=/dev/zero of=/var/lib/firecracker/images/ubuntu-24.04.ext4 bs=1M count=1024
mkfs.ext4 /var/lib/firecracker/images/ubuntu-24.04.ext4

# Copy files
sudo mount /var/lib/firecracker/images/ubuntu-24.04.ext4 /mnt
sudo cp -a /tmp/ubuntu-24.04-root/* /mnt/
sudo umount /mnt
sudo rm -rf /tmp/ubuntu-24.04-root
```

### Fix 3: Fix Permissions
```bash
# Ensure correct ownership
sudo chown -R firecracker:firecracker /var/lib/firecracker/images/
sudo chown -R firecracker:firecracker /var/lib/firecracker-vms/

# Or run as root for testing
sudo fc-vps create --image ubuntu-22.04
```

## 🔧 Enhanced Error Handling

Let's improve the Go code to give better error messages:

### Update createVMRootfs function:
```go
func (vmm *VMManager) createVMRootfs(baseImage, rootfsPath string, sizeGB int) error {
	// Check if base image exists
	if _, err := os.Stat(baseImage); os.IsNotExist(err) {
		return fmt.Errorf("base image not found: %s", baseImage)
	}
	
	// Check if source is readable
	if file, err := os.Open(baseImage); err != nil {
		return fmt.Errorf("cannot read base image %s: %v", baseImage, err)
	} else {
		file.Close()
	}
	
	// Check destination directory
	destDir := filepath.Dir(rootfsPath)
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return fmt.Errorf("cannot create destination directory %s: %v", destDir, err)
	}
	
	// Copy base image to VM rootfs with detailed error
	cmd := exec.Command("cp", baseImage, rootfsPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to copy base image from %s to %s: %v (output: %s)", 
			baseImage, rootfsPath, err, string(output))
	}
	
	// Rest of function...
}
```

## 📋 Diagnostic Commands

### Check System Status
```bash
# Check service logs
journalctl -u firecracker-vps -f

# Check available images
fc-vps --verbose list-images

# Test with existing image
fc-vps --verbose create --name test-vm --image ubuntu-22.04

# Check disk space
df -h /var/lib/firecracker*
```

### Verbose API Testing
```bash
# Test API directly with curl
curl -v -X POST http://localhost:8080/api/v1/vms \
  -H "Content-Type: application/json" \
  -d '{
    "name": "debug-vm",
    "cpu": 1,
    "memory": 512,
    "disk_size": 10,
    "image": "ubuntu-22.04"
  }'
```

### Check Available Images Endpoint
Add this to your Go API:
```go
func (vmm *VMManager) listImagesHandler(c *gin.Context) {
	files, err := os.ReadDir(vmm.config.BaseImagesDir)
	if err != nil {
		c.JSON(http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to read images directory: %v", err),
		})
		return
	}
	
	var images []string
	for _, file := range files {
		if filepath.Ext(file.Name()) == ".ext4" {
			imageName := strings.TrimSuffix(file.Name(), ".ext4")
			images = append(images, imageName)
		}
	}
	
	c.JSON(http.StatusOK, Response{
		Success: true,
		Message: "Available images",
		Data:    images,
	})
}

// Add to router:
api.GET("/images", vmManager.listImagesHandler)
```

## 🎯 Most Likely Solutions

1. **Wrong image name**: Use `ubuntu-22.04` instead of `ubuntu-24.04`
2. **Missing image file**: Create the `ubuntu-24.04.ext4` file  
3. **Permission issue**: Run with proper user or fix ownership
4. **Disk space**: Check if you have enough space in `/var/lib/firecracker-vms/`

Try these in order:
```bash
# 1. Check what's available
ls /var/lib/firecracker/images/

# 2. Use existing image
fc-vps create --image ubuntu-22.04

# 3. Create the missing image
make create-base-image

# 4. Fix permissions
sudo chown -R $USER:$USER /var/lib/firecracker*
```

---

## Notes

Let's debug this error step by step. The issue is that the base image `ubuntu-24.04.ext4` doesn't exist or there's a problem with the copy operation.## 🔍 **Quick Debug Steps**

**1. Check what base images you actually have:**
```bash
ls -la /var/lib/firecracker/images/
```

**2. The error says `ubuntu-24.04` but you probably have:**
```bash
# Available images might be:
ubuntu-22.04.ext4  # Use --image ubuntu-22.04
ubuntu-20.04.ext4  # Use --image ubuntu-20.04
```

**3. Quick fix - use existing image:**
```bash
fc-vps create --image ubuntu-22.04  # Instead of ubuntu-24.04
```

**4. Or create the Ubuntu 24.04 image:**
```bash
# Download official Ubuntu 24.04 Noble cloud image
wget https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img -O /tmp/ubuntu-24.04.qcow2

# Convert to raw format and create ext4
qemu-img convert -f qcow2 -O raw /tmp/ubuntu-24.04.qcow2 /tmp/ubuntu-24.04.raw
dd if=/dev/zero of=/var/lib/firecracker/images/ubuntu-24.04.ext4 bs=1M count=2048
mkfs.ext4 /var/lib/firecracker/images/ubuntu-24.04.ext4

# Mount and copy
sudo mkdir -p /mnt/{src,dst}
sudo mount /tmp/ubuntu-24.04.raw /mnt/src
sudo mount /var/lib/firecracker/images/ubuntu-24.04.ext4 /mnt/dst
sudo cp -a /mnt/src/* /mnt/dst/
sudo umount /mnt/{src,dst}
```

**5. Check permissions:**
```bash
sudo chown -R $USER:$USER /var/lib/firecracker*
# OR
sudo chown -R firecracker:firecracker /var/lib/firecracker*
```

The `.env` file now centralizes all configuration so you can easily adjust paths and settings without modifying code. 🎯

---



