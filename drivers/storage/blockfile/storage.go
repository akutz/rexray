package blockfile

import (
    "os"
    "log"
    "runtime"
    
    "github.com/emccode/rexray/drivers/storage"
)

const GOOS = runtime.GOOS
const LOOPBACK_VOLPATH = "/var/lib/docker/volumes/.loopback"

var (
    providerName string
)

type Driver struct {

}

func init() {
    providerName = "blockfile"
    storagedriver.Register("loopback", Init)
}

func Init() (storagedriver.Driver, error) {
    
    if os.Getenv("REXRAY_DEBUG") == "true" {
        log.Println("Storage Driver Initialized: " + providerName)
	}

    driver := &Driver{}
    
    return driver, nil
}

// Lists the block devices that are attached to the instance
func (driver *Driver) GetVolumeMapping() (interface{}, error) {
    
    
    return nil, nil
}

// Get the local instance
func (driver *Driver) GetInstance() (interface{}, error) {
    return nil, nil
}

// Get all Volumes available from infrastructure and storage platform
func (driver *Driver) GetVolume(string, string) (interface{}, error) {
    return nil, nil
}

// Get the currently attached Volumes
func (driver *Driver) GetVolumeAttach(string, string) (interface{}, error) {
    return nil, nil
}

// Create a snpashot of a Volume
func (driver *Driver) CreateSnapshot(bool, string, string, string) (interface{}, error) {
    return nil, nil
}

// Get all Snapshots or specific Snapshots
func (driver *Driver) GetSnapshot(string, string, string) (interface{}, error) {
    return nil, nil
}

// Remove Snapshot
func (driver *Driver) RemoveSnapshot(string) error {
    return nil
}

// Create a Volume from scratch, from a Snaphot, or from another Volume
func (driver *Driver) CreateVolume(bool, string, string, string, string, int64, int64, string) (interface{}, error) {
    
    // hdiutil create -megabytes 100 -type SPARSE -volname docker-000 docker-000
    
    return nil, nil
}

// Remove Volume
func (driver *Driver) RemoveVolume(string) error {
    return nil
}

// Get the next available Linux device for attaching external storage
func (driver *Driver) GetDeviceNextAvailable() (string, error) {
    return "", nil
}

// Attach a Volume to an Instance
func (driver *Driver) AttachVolume(bool, string, string) (interface{}, error) {
    return nil, nil
}

// Detach a Volume from an Instance
func (driver *Driver) DetachVolume(bool, string, string) error {
    return nil
}

// Copy a Snapshot to another region
func (driver *Driver) CopySnapshot(bool, string, string, string, string, string) (interface{}, error)  {
    return nil, nil
}