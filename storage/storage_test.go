package storage

import (
	"testing"
	"github.com/emccode/rexray/storage"
)

func TestGetDriverNames(t *testing.T) {
	names := storage.GetDriverNames();
	if names == nil || len(names) == 0 {
	    t.Error("failed to find at least 'loopback' driver")
	}
}