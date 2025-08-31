package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"time"

	"github.com/firecracker-microvm/firecracker-go-sdk"
	"github.com/firecracker-microvm/firecracker-go-sdk/client/models"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

// VM represents a virtual machine instance
type VM struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	CPU        int       `json:"cpu"`
	Memory     int       `json:"memory"`    // MB
	DiskSize   int       `json:"disk_size"` // GB
	Image      string    `json:"image"`
	Status     string    `json:"status"`
	IPAddress  string    `json:"ip_address"`
	CreatedAt  time.Time `json:"created_at"`
	SocketPath string    `json:"socket_path"`
	KernelPath string    `json:"kernel_path"`
	RootfsPath string    `json:"rootfs_path"`
	TapDevice  string    `json:"tap_device"`
	machine    *firecracker.Machine
}

// VMRequest represents a VM creation request
type VMRequest struct {
	Name     string `json:"name" binding:"required"`
	CPU      int    `json:"cpu" binding:"required,min=1,max=8"`
	Memory   int    `json:"memory" binding:"required,min=128,max=8192"`
	DiskSize int    `json:"disk_size" binding:"required,min=1,max=100"`
	Image    string `json:"image" binding:"required"`
}

// VMManager manages all VM instances
type VMManager struct {
	vms        map[string]*VM
	mutex      sync.RWMutex
	config     *Config
	ipPool     *IPPool
	tapManager *TapManager
}

// Config holds application configuration
type Config struct {
	APIPort       string
	VMDir         string
	KernelPath    string
	BaseImagesDir string
	NetworkBridge string
	NetworkSubnet string
	MaxVMsPerHost int
}

// IPPool manages IP address allocation
type IPPool struct {
	subnet    string
	allocated map[string]bool
	mutex     sync.RWMutex
}

// TapManager manages TAP network interfaces
type TapManager struct {
	tapDevices map[string]bool
	mutex      sync.RWMutex
}

// Response represents API response structure
type Response struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

func NewConfig() *Config {
	return &Config{
		APIPort:       getEnvOrDefault("API_PORT", "8080"),
		VMDir:         getEnvOrDefault("VM_DIR", "/var/lib/firecracker-vms"),
		KernelPath:    getEnvOrDefault("KERNEL_PATH", "/var/lib/firecracker/vmlinux.bin"),
		BaseImagesDir: getEnvOrDefault("BASE_IMAGES_DIR", "/var/lib/firecracker/images"),
		NetworkBridge: getEnvOrDefault("NETWORK_BRIDGE", "br0"),
		NetworkSubnet: getEnvOrDefault("NETWORK_SUBNET", "192.168.100.0/24"),
		MaxVMsPerHost: getEnvInt("MAX_VMS_PER_HOST", 100),
	}
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

func NewVMManager(config *Config) *VMManager {
	return &VMManager{
		vms:        make(map[string]*VM),
		config:     config,
		ipPool:     NewIPPool(config.NetworkSubnet),
		tapManager: NewTapManager(),
	}
}

func NewIPPool(subnet string) *IPPool {
	return &IPPool{
		subnet:    subnet,
		allocated: make(map[string]bool),
	}
}

func NewTapManager() *TapManager {
	return &TapManager{
		tapDevices: make(map[string]bool),
	}
}

func (ip *IPPool) AllocateIP() string {
	ip.mutex.Lock()
	defer ip.mutex.Unlock()

	// Simple IP allocation - in production, use proper CIDR calculation
	for i := 10; i < 254; i++ {
		ipAddr := fmt.Sprintf("192.168.100.%d", i)
		if !ip.allocated[ipAddr] {
			ip.allocated[ipAddr] = true
			return ipAddr
		}
	}
	return ""
}

func (ip *IPPool) ReleaseIP(ipAddr string) {
	ip.mutex.Lock()
	defer ip.mutex.Unlock()
	delete(ip.allocated, ipAddr)
}

func (tm *TapManager) AllocateTap(vmID string) string {
	tm.mutex.Lock()
	defer tm.mutex.Unlock()

	tapName := fmt.Sprintf("tap-%s", vmID[:8])
	tm.tapDevices[tapName] = true
	return tapName
}

func (tm *TapManager) ReleaseTap(tapName string) {
	tm.mutex.Lock()
	defer tm.mutex.Unlock()
	delete(tm.tapDevices, tapName)
}

func (vmm *VMManager) CreateVM(req VMRequest) (*VM, error) {
	vmm.mutex.Lock()
	defer vmm.mutex.Unlock()

	// Generate unique VM ID
	vmID := uuid.New().String()

	// Allocate resources
	ipAddr := vmm.ipPool.AllocateIP()
	if ipAddr == "" {
		return nil, fmt.Errorf("no available IP addresses")
	}

	tapDevice := vmm.tapManager.AllocateTap(vmID)
	logrus.Info("Tap device allocated: ", tapDevice)

	// Create VM directory
	vmDir := filepath.Join(vmm.config.VMDir, vmID)
	if err := os.MkdirAll(vmDir, 0755); err != nil {
		vmm.ipPool.ReleaseIP(ipAddr)
		vmm.tapManager.ReleaseTap(tapDevice)
		return nil, fmt.Errorf("failed to create VM directory: %v", err)
	}

	// Create VM rootfs from base image
	baseImagePath := filepath.Join(vmm.config.BaseImagesDir, req.Image+".ext4")
	rootfsPath := filepath.Join(vmDir, "rootfs.ext4")

	if err := vmm.createVMRootfs(baseImagePath, rootfsPath, req.DiskSize); err != nil {
		vmm.cleanup(vmID, ipAddr, tapDevice)
		return nil, fmt.Errorf("failed to create VM rootfs: %v", err)
	}

	// Create TAP interface
	if err := vmm.createTapInterface(tapDevice); err != nil {
		vmm.cleanup(vmID, ipAddr, tapDevice)
		return nil, fmt.Errorf("failed to create TAP interface: %v", err)
	}

	vm := &VM{
		ID:         vmID,
		Name:       req.Name,
		CPU:        req.CPU,
		Memory:     req.Memory,
		DiskSize:   req.DiskSize,
		Image:      req.Image,
		Status:     "created",
		IPAddress:  ipAddr,
		CreatedAt:  time.Now(),
		SocketPath: filepath.Join(vmDir, "firecracker.socket"),
		KernelPath: vmm.config.KernelPath,
		RootfsPath: rootfsPath,
		TapDevice:  tapDevice,
	}

	vmm.vms[vmID] = vm
	return vm, nil
}

func (vmm *VMManager) StartVM(vmID string) error {
	vmm.mutex.Lock()
	defer vmm.mutex.Unlock()

	vm, exists := vmm.vms[vmID]
	if !exists {
		return fmt.Errorf("VM not found")
	}

	if vm.Status == "running" {
		return fmt.Errorf("VM is already running")
	}

	// Configure Firecracker
	cfg := firecracker.Config{
		SocketPath:      vm.SocketPath,
		KernelImagePath: vm.KernelPath,
		KernelArgs:      "console=ttyS0 reboot=k panic=1 pci=off",
		Drives: []models.Drive{
			{
				DriveID:      firecracker.String("rootfs"),
				PathOnHost:   firecracker.String(vm.RootfsPath),
				IsRootDevice: firecracker.Bool(true),
				IsReadOnly:   firecracker.Bool(false),
			},
		},
		NetworkInterfaces: []firecracker.NetworkInterface{{
			CNIConfiguration: &firecracker.CNIConfiguration{
				NetworkName: "default",
				IfName:      "eth0",
			},
			StaticConfiguration: &firecracker.StaticNetworkConfiguration{
				MacAddress:  generateMacAddress(),
				HostDevName: vm.TapDevice,
			},
		}},
		MachineCfg: models.MachineConfiguration{
			VcpuCount:  firecracker.Int64(int64(vm.CPU)),
			MemSizeMib: firecracker.Int64(int64(vm.Memory)),
		},
		// JailerCfg: &firecracker.JailerConfig{
		// 	GID:           firecracker.Int(1000),
		// 	UID:           firecracker.Int(1000),
		// 	ID:            vmID,
		// 	NumaNode:      firecracker.Int(0),
		// 	ExecFile:      "/usr/bin/firecracker",
		// 	JailerBinary:  "/usr/bin/jailer",
		// 	ChrootBaseDir: "/var/lib/firecracker",
		// },
		JailerCfg: nil,
	}

	ctx := context.Background()

	// Create and configure logrus logger
	logger := logrus.New()
	logger.SetOutput(os.Stdout)
	logger.SetFormatter(&logrus.TextFormatter{
		TimestampFormat: "2006-01-02 15:04:05", // Mimics log.LstdFlags
		FullTimestamp:   true,
	})

	m, err := firecracker.NewMachine(ctx, cfg, firecracker.WithLogger(logger.WithContext(ctx)))
	if err != nil {
		return fmt.Errorf("failed to create machine: %v", err)
	}

	if err := m.Start(ctx); err != nil {
		return fmt.Errorf("failed to start machine: %v", err)
	}

	vm.machine = m
	vm.Status = "running"

	return nil
}

func (vmm *VMManager) StopVM(vmID string) error {
	vmm.mutex.Lock()
	defer vmm.mutex.Unlock()

	vm, exists := vmm.vms[vmID]
	if !exists {
		return fmt.Errorf("VM not found")
	}

	if vm.Status != "running" {
		return fmt.Errorf("VM is not running")
	}

	if vm.machine != nil {
		if err := vm.machine.Shutdown(context.Background()); err != nil {
			return fmt.Errorf("failed to shutdown VM: %v", err)
		}
	}

	vm.Status = "stopped"
	vm.machine = nil

	return nil
}

func (vmm *VMManager) DeleteVM(vmID string) error {
	vmm.mutex.Lock()
	defer vmm.mutex.Unlock()

	vm, exists := vmm.vms[vmID]
	if !exists {
		return fmt.Errorf("VM not found")
	}

	// Stop VM if running
	if vm.Status == "running" && vm.machine != nil {
		vm.machine.Shutdown(context.Background())
	}

	// Cleanup resources
	vmm.ipPool.ReleaseIP(vm.IPAddress)
	vmm.tapManager.ReleaseTap(vm.TapDevice)

	// Remove TAP interface
	vmm.removeTapInterface(vm.TapDevice)

	// Remove VM directory
	vmDir := filepath.Dir(vm.SocketPath)
	os.RemoveAll(vmDir)

	delete(vmm.vms, vmID)
	return nil
}

func (vmm *VMManager) GetVM(vmID string) (*VM, error) {
	vmm.mutex.RLock()
	defer vmm.mutex.RUnlock()

	vm, exists := vmm.vms[vmID]
	if !exists {
		return nil, fmt.Errorf("VM not found")
	}

	return vm, nil
}

func (vmm *VMManager) ListVMs() []*VM {
	vmm.mutex.RLock()
	defer vmm.mutex.RUnlock()

	vms := make([]*VM, 0, len(vmm.vms))
	for _, vm := range vmm.vms {
		vms = append(vms, vm)
	}

	return vms
}

// Enhanced createVMRootfs function with detailed error reporting
func (vmm *VMManager) createVMRootfs(baseImage, rootfsPath string, sizeGB int) error {
	// 1. Validate source image exists
	logrus.Println("Base Image: ", baseImage)
	sourceInfo, err := os.Stat(baseImage)
	if os.IsNotExist(err) {
		return fmt.Errorf("base image not found: %s", baseImage)
	}
	if err != nil {
		return fmt.Errorf("cannot access base image %s: %v", baseImage, err)
	}

	// 2. Check if source is readable
	sourceFile, err := os.Open(baseImage)
	if err != nil {
		return fmt.Errorf("cannot read base image %s: %v (permissions: %s)",
			baseImage, err, sourceInfo.Mode().String())
	}
	sourceFile.Close()

	// 3. Ensure destination directory exists
	destDir := filepath.Dir(rootfsPath)
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return fmt.Errorf("cannot create destination directory %s: %v", destDir, err)
	}

	// 4. Check destination directory permissions
	destDirInfo, err := os.Stat(destDir)
	if err != nil {
		return fmt.Errorf("cannot access destination directory %s: %v", destDir, err)
	}

	// 5. Check if we can write to destination directory
	testFile := filepath.Join(destDir, ".write-test")
	if testFileHandle, err := os.Create(testFile); err != nil {
		return fmt.Errorf("cannot write to destination directory %s: %v (permissions: %s)",
			destDir, err, destDirInfo.Mode().String())
	} else {
		testFileHandle.Close()
		os.Remove(testFile)
	}

	// 6. Check available disk space
	if err := vmm.checkDiskSpace(destDir, sizeGB); err != nil {
		return fmt.Errorf("insufficient disk space: %v", err)
	}

	log.Printf("Copying base image: %s -> %s (source size: %d bytes)",
		baseImage, rootfsPath, sourceInfo.Size())

	// 7. Perform the copy with better error handling
	if err := vmm.copyFileWithProgress(baseImage, rootfsPath); err != nil {
		return fmt.Errorf("failed to copy base image: %v", err)
	}

	// 8. Verify the copy was successful
	destInfo, err := os.Stat(rootfsPath)
	if err != nil {
		return fmt.Errorf("copy verification failed - destination file not found: %v", err)
	}

	if destInfo.Size() != sourceInfo.Size() {
		return fmt.Errorf("copy verification failed - size mismatch: source %d bytes, destination %d bytes",
			sourceInfo.Size(), destInfo.Size())
	}

	log.Printf("Successfully copied image (size: %d bytes)", destInfo.Size())

	// 9. Resize filesystem if needed
	if sizeGB > 1 {
		if err := vmm.resizeRootfs(rootfsPath, sizeGB); err != nil {
			return fmt.Errorf("failed to resize rootfs: %v", err)
		}
	}

	return nil
}

// Enhanced copy function with detailed error reporting
func (vmm *VMManager) copyFileWithProgress(src, dst string) error {
	// Try different copy methods in order of preference

	// Method 1: Go's built-in copy (most reliable)
	if err := vmm.copyFileGo(src, dst); err == nil {
		return nil
	} else {
		log.Printf("Go copy failed: %v, trying cp command", err)
	}

	// Method 2: System cp command
	if err := vmm.copyFileCommand(src, dst); err == nil {
		return nil
	} else {
		log.Printf("cp command failed: %v, trying dd command", err)
	}

	// Method 3: dd command (most robust for disk images)
	return vmm.copyFileDD(src, dst)
}

// Go-based file copy
func (vmm *VMManager) copyFileGo(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("cannot open source: %v", err)
	}
	defer sourceFile.Close()

	destFile, err := os.Create(dst)
	if err != nil {
		return fmt.Errorf("cannot create destination: %v", err)
	}
	defer destFile.Close()

	written, err := io.Copy(destFile, sourceFile)
	if err != nil {
		return fmt.Errorf("copy operation failed: %v", err)
	}

	if err := destFile.Sync(); err != nil {
		return fmt.Errorf("sync failed: %v", err)
	}

	log.Printf("Copied %d bytes using Go copy", written)
	return nil
}

// Command-based file copy
func (vmm *VMManager) copyFileCommand(src, dst string) error {
	cmd := exec.Command("cp", src, dst)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("cp command failed: %v (output: %s)", err, string(output))
	}
	return nil
}

// DD-based file copy (most robust for disk images)
func (vmm *VMManager) copyFileDD(src, dst string) error {
	cmd := exec.Command("dd", fmt.Sprintf("if=%s", src), fmt.Sprintf("of=%s", dst), "bs=1M")
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("dd command failed: %v (output: %s)", err, string(output))
	}
	return nil
}

// Check available disk space
func (vmm *VMManager) checkDiskSpace(dir string, requiredGB int) error {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(dir, &stat); err != nil {
		return fmt.Errorf("cannot check disk space: %v", err)
	}

	availableBytes := stat.Bavail * uint64(stat.Bsize)
	requiredBytes := uint64(requiredGB) * 1024 * 1024 * 1024

	if availableBytes < requiredBytes {
		return fmt.Errorf("insufficient disk space: need %d GB, have %d GB",
			requiredGB, availableBytes/(1024*1024*1024))
	}

	return nil
}

// Enhanced resize function
func (vmm *VMManager) resizeRootfs(rootfsPath string, sizeGB int) error {
	// First, resize the file
	resizeCmd := exec.Command("truncate", "-s", fmt.Sprintf("%dG", sizeGB), rootfsPath)
	if output, err := resizeCmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to resize file: %v (output: %s)", err, string(output))
	}

	// Then, resize the filesystem
	fsckCmd := exec.Command("e2fsck", "-f", "-y", rootfsPath)
	fsckCmd.Run() // Ignore errors, might not be needed

	resizeFsCmd := exec.Command("resize2fs", rootfsPath)
	if output, err := resizeFsCmd.CombinedOutput(); err != nil {
		log.Printf("Warning: filesystem resize failed: %v (output: %s)", err, string(output))
		// Don't fail the entire operation for this
	}

	return nil
}

func (vmm *VMManager) createTapInterface(tapName string) error {
	// Create TAP interface
	cmd := exec.Command("ip", "tuntap", "add", tapName, "mode", "tap")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to create TAP interface: %v", err)
	}

	// Bring interface up
	upCmd := exec.Command("ip", "link", "set", tapName, "up")
	if err := upCmd.Run(); err != nil {
		return fmt.Errorf("failed to bring up TAP interface: %v", err)
	}

	// Add to bridge
	bridgeCmd := exec.Command("ip", "link", "set", tapName, "master", vmm.config.NetworkBridge)
	return bridgeCmd.Run()
}

func (vmm *VMManager) removeTapInterface(tapName string) error {
	cmd := exec.Command("ip", "link", "delete", tapName)
	return cmd.Run()
}

func (vmm *VMManager) cleanup(vmID, ipAddr, tapDevice string) {
	vmDir := filepath.Join(vmm.config.VMDir, vmID)
	os.RemoveAll(vmDir)
	vmm.ipPool.ReleaseIP(ipAddr)
	vmm.tapManager.ReleaseTap(tapDevice)
	vmm.removeTapInterface(tapDevice)
}

func generateMacAddress() string {
	// Generate a random MAC address
	return fmt.Sprintf("02:00:%02x:%02x:%02x:%02x",
		time.Now().Unix()&0xff,
		time.Now().Unix()>>8&0xff,
		time.Now().Unix()>>16&0xff,
		time.Now().Unix()>>24&0xff)
}

// API Handlers
func (vmm *VMManager) createVMHandler(c *gin.Context) {
	var req VMRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, Response{
			Success: false,
			Message: fmt.Sprintf("Invalid request: %v", err),
		})
		return
	}

	vm, err := vmm.CreateVM(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to create VM: %v", err),
		})
		return
	}

	c.JSON(http.StatusCreated, Response{
		Success: true,
		Message: "VM created successfully",
		Data:    vm,
	})
}

func (vmm *VMManager) listVMsHandler(c *gin.Context) {
	vms := vmm.ListVMs()
	c.JSON(http.StatusOK, Response{
		Success: true,
		Message: "VMs retrieved successfully",
		Data:    vms,
	})
}

func (vmm *VMManager) getVMHandler(c *gin.Context) {
	vmID := c.Param("id")
	vm, err := vmm.GetVM(vmID)
	if err != nil {
		c.JSON(http.StatusNotFound, Response{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, Response{
		Success: true,
		Message: "VM retrieved successfully",
		Data:    vm,
	})
}

func (vmm *VMManager) startVMHandler(c *gin.Context) {
	vmID := c.Param("id")
	if err := vmm.StartVM(vmID); err != nil {
		c.JSON(http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to start VM: %v", err),
		})
		return
	}

	c.JSON(http.StatusOK, Response{
		Success: true,
		Message: "VM started successfully",
	})
}

func (vmm *VMManager) stopVMHandler(c *gin.Context) {
	vmID := c.Param("id")
	if err := vmm.StopVM(vmID); err != nil {
		c.JSON(http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to stop VM: %v", err),
		})
		return
	}

	c.JSON(http.StatusOK, Response{
		Success: true,
		Message: "VM stopped successfully",
	})
}

func (vmm *VMManager) deleteVMHandler(c *gin.Context) {
	vmID := c.Param("id")
	if err := vmm.DeleteVM(vmID); err != nil {
		c.JSON(http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to delete VM: %v", err),
		})
		return
	}

	c.JSON(http.StatusOK, Response{
		Success: true,
		Message: "VM deleted successfully",
	})
}

func setupRouter(vmManager *VMManager) *gin.Engine {
	r := gin.Default()

	// Enable CORS
	config := cors.DefaultConfig()
	config.AllowAllOrigins = true
	r.Use(cors.New(config))

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, Response{
			Success: true,
			Message: "Service is healthy",
		})
	})

	// API routes
	api := r.Group("/api/v1")
	{
		api.POST("/vms", vmManager.createVMHandler)
		api.GET("/vms", vmManager.listVMsHandler)
		api.GET("/vms/:id", vmManager.getVMHandler)
		api.POST("/vms/:id/start", vmManager.startVMHandler)
		api.POST("/vms/:id/stop", vmManager.stopVMHandler)
		api.DELETE("/vms/:id", vmManager.deleteVMHandler)
	}

	return r
}

func main() {
	config := NewConfig()
	vmManager := NewVMManager(config)

	// Ensure required directories exist
	os.MkdirAll(config.VMDir, 0755)
	os.MkdirAll(config.BaseImagesDir, 0755)

	router := setupRouter(vmManager)

	logger := logrus.New()
	logger.SetOutput(os.Stdout)
	logger.SetFormatter(&logrus.TextFormatter{
		TimestampFormat: "2006-01-02 15:04:05",
		FullTimestamp:   true,
	})

	logger.Infof("Starting Firecracker VPS API server on port %s", config.APIPort)
	if err := http.ListenAndServe(":"+config.APIPort, router); err != nil {
		logger.Fatalf("Failed to start server: %v", err)
	}
}
