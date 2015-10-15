package core

var (
	driverCtors map[string]NewDriver
)

func initDrivers() {
	driverCtors = map[string]NewDriver{}
}

// Driver represents a REX-Ray driver.
type Driver interface {
	// The name of the driver.
	Name() string

	// Init initalizes the driver so that it is in a state to communicate to
	// its underlying platform / storage provider.
	Init(rexray *RexRay) error
}

// NewDriver is a function that constructs a new driver.
type NewDriver func() Driver

// RegisterDriver is used by drivers to notify the driver manager of their
// availability to be used.
func RegisterDriver(driverName string, ctor NewDriver) {
	driverCtors[driverName] = ctor
}
