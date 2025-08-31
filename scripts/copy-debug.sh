#!/bin/bash

# Debug script for copy operation issues

echo "=== Copy Operation Debug ==="
echo "Date: $(date)"
echo

# Check if running as root or with sudo
echo "Current user: $(whoami)"
echo "Groups: $(groups)"
echo

# Check source image
SOURCE_IMAGE="/var/lib/firecracker/images/ubuntu-24.04.ext4"
echo "=== Source Image Check ==="
echo "File exists: $(test -f "$SOURCE_IMAGE" && echo "YES" || echo "NO")"
if [ -f "$SOURCE_IMAGE" ]; then
    echo "File size: $(ls -lh "$SOURCE_IMAGE" | awk '{print $5}')"
    echo "File permissions: $(ls -l "$SOURCE_IMAGE")"
    echo "File owner: $(ls -l "$SOURCE_IMAGE" | awk '{print $3":"$4}')"
    echo "Readable by current user: $(test -r "$SOURCE_IMAGE" && echo "YES" || echo "NO")"
    
    # Check if file is actually complete (not corrupted)
    echo "File type: $(file "$SOURCE_IMAGE")"
else
    echo "ERROR: Source file does not exist!"
fi
echo

# Check destination directory
DEST_DIR="/var/lib/firecracker-vms"
echo "=== Destination Directory Check ==="
echo "Directory exists: $(test -d "$DEST_DIR" && echo "YES" || echo "NO")"
if [ -d "$DEST_DIR" ]; then
    echo "Directory permissions: $(ls -ld "$DEST_DIR")"
    echo "Directory owner: $(ls -ld "$DEST_DIR" | awk '{print $3":"$4}')"
    echo "Writable by current user: $(test -w "$DEST_DIR" && echo "YES" || echo "NO")"
else
    echo "Creating destination directory..."
    mkdir -p "$DEST_DIR"
fi
echo

# Check disk space
echo "=== Disk Space Check ==="
echo "Source directory space:"
df -h "$(dirname "$SOURCE_IMAGE")"
echo
echo "Destination directory space:"
df -h "$DEST_DIR"
echo

# Test copy operation with detailed error output
echo "=== Test Copy Operation ==="
TEST_DEST="$DEST_DIR/test-copy-$(date +%s).ext4"
echo "Testing copy from $SOURCE_IMAGE to $TEST_DEST"

if cp "$SOURCE_IMAGE" "$TEST_DEST" 2>&1; then
    echo "✓ Copy test SUCCESSFUL"
    echo "Copied file size: $(ls -lh "$TEST_DEST" | awk '{print $5}')"
    echo "Cleaning up test file..."
    rm -f "$TEST_DEST"
else
    echo "✗ Copy test FAILED"
    echo "Error details:"
    cp "$SOURCE_IMAGE" "$TEST_DEST"
fi
echo

# Check if it's a permissions issue
echo "=== Permission Test ==="
echo "Testing with sudo..."
if sudo cp "$SOURCE_IMAGE" "$DEST_DIR/sudo-test-$(date +%s).ext4" 2>&1; then
    echo "✓ Sudo copy SUCCESSFUL - This is a permissions issue!"
    sudo rm -f "$DEST_DIR"/sudo-test-*.ext4
else
    echo "✗ Even sudo copy failed - This is not just a permissions issue"
fi
echo

# Check SELinux if present
if command -v getenforce >/dev/null 2>&1; then
    echo "=== SELinux Check ==="
    echo "SELinux status: $(getenforce 2>/dev/null || echo 'Not installed')"
    echo "Source file context: $(ls -Z "$SOURCE_IMAGE" 2>/dev/null || echo 'N/A')"
    echo
fi

# Check AppArmor if present
if command -v aa-status >/dev/null 2>&1; then
    echo "=== AppArmor Check ==="
    echo "AppArmor status: $(sudo aa-status --enabled 2>/dev/null && echo 'Enabled' || echo 'Disabled/Not installed')"
    echo
fi

# Check if file is being used
echo "=== File Usage Check ==="
if command -v lsof >/dev/null 2>&1; then
    echo "Processes using source file:"
    sudo lsof "$SOURCE_IMAGE" 2>/dev/null || echo "No processes using the file"
else
    echo "lsof not available - cannot check file usage"
fi
echo

# Check mount points
echo "=== Mount Point Check ==="
echo "Source mount point:"
df "$SOURCE_IMAGE" | tail -1
echo "Destination mount point:"
df "$DEST_DIR" | tail -1
echo

# Final recommendations
echo "=== Recommendations ==="
if [ ! -r "$SOURCE_IMAGE" ]; then
    echo "1. Fix source file permissions:"
    echo "   sudo chmod 644 $SOURCE_IMAGE"
    echo "   sudo chown $USER:$USER $SOURCE_IMAGE"
fi

if [ ! -w "$DEST_DIR" ]; then
    echo "2. Fix destination directory permissions:"
    echo "   sudo chown -R $USER:$USER $DEST_DIR"
    echo "   sudo chmod 755 $DEST_DIR"
fi

echo "3. Try running the API server as the file owner:"
echo "   sudo -u $(ls -l "$SOURCE_IMAGE" | awk '{print $3}') ./bin/firecracker-vps"

echo "4. Or fix all permissions:"
echo "   sudo chown -R $USER:$USER /var/lib/firecracker*"
echo "   sudo chmod -R 755 /var/lib/firecracker*"
echo "   sudo chmod 644 /var/lib/firecracker/images/*.ext4"

echo
echo "=== Debug Complete ==="