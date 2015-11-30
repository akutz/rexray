package test

import (
	"testing"

	"github.com/emccode/rexray/core"
	"github.com/emccode/rexray/core/errors"
	"github.com/emccode/rexray/drivers/mock"
)

func TestNewWithBadOSDriver(t *testing.T) {
	r := core.New(nil)
	r.Config.Set("rexray.osDrivers", []string{mock.BadMockOSDriverName})
	r.Config.Set("rexray.volumeDrivers", []string{mock.MockVolDriverName})
	r.Config.Set("rexray.storageDrivers", []string{mock.MockStorDriverName})
	if err := r.InitDrivers(); err != errors.ErrNoOSDrivers {
		t.Fatal(err)
	}
}

func TestNewWithBadVolumeDriver(t *testing.T) {
	r := core.New(nil)
	r.Config.Set("rexray.osDrivers", []string{mock.MockOSDriverName})
	r.Config.Set("rexray.volumeDrivers", []string{mock.BadMockVolDriverName})
	r.Config.Set("rexray.storageDrivers", []string{mock.MockStorDriverName})
	if err := r.InitDrivers(); err != errors.ErrNoVolumeDrivers {
		t.Fatal(err)
	}
}

func TestNewWithBadStorageDriver(t *testing.T) {
	r := core.New(nil)
	r.Config.Set("rexray.osDrivers", []string{mock.MockOSDriverName})
	r.Config.Set("rexray.volumeDrivers", []string{mock.MockVolDriverName})
	r.Config.Set("rexray.storageDrivers", []string{mock.BadMockStorDriverName})
	if err := r.InitDrivers(); err != errors.ErrNoStorageDrivers {
		t.Fatal(err)
	}
}
