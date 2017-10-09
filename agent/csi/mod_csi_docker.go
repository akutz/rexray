package csi

import (
	"fmt"
	"path"
	"strconv"
	"strings"
	"sync"

	gofig "github.com/akutz/gofig/types"
	"github.com/akutz/gotil"
	"github.com/codedellemc/gocsi"
	"github.com/codedellemc/gocsi/csi"
	dvol "github.com/docker/go-plugins-helpers/volume"
	"google.golang.org/grpc/metadata"

	apitypes "github.com/codedellemc/rexray/libstorage/api/types"
)

type dockerBridge struct {
	ctx    apitypes.Context
	config gofig.Config
	cs     *csiService

	fsType  string
	mntPath string

	byName    map[string]csi.VolumeInfo
	byNameRWL sync.RWMutex
}

func newDockerBridge(
	ctx apitypes.Context,
	config gofig.Config,
	cs *csiService) *dockerBridge {

	return &dockerBridge{
		ctx:     ctx,
		config:  config,
		cs:      cs,
		fsType:  config.GetString(apitypes.ConfigIgVolOpsCreateDefaultFsType),
		mntPath: config.GetString(apitypes.ConfigIgVolOpsMountPath),
		byName:  map[string]csi.VolumeInfo{},
	}
}

// cacheListResult caches the name-to-id mapping for a list of
// csi.VolumeInfo objects. This function replaces the existing list
// as the result of a ListVolumes RPC represents the most up-to-date
// view of the underlying storage platform
func (d *dockerBridge) cacheListResult(vols []*csi.VolumeInfo) {
	d.byNameRWL.Lock()
	defer d.byNameRWL.Unlock()
	d.byName = map[string]csi.VolumeInfo{}
	for _, vi := range vols {
		if vi.Id == nil {
			continue
		}
		name := getName(*vi)
		if name == "" {
			d.ctx.Warnf(
				"docker-csi-bridge: failed to cache id/name: %v", vi.Id.Values)
			continue
		}
		d.byName[name] = *vi
	}
}

func getName(vi csi.VolumeInfo) string {
	if vi.Metadata != nil {
		if v := vi.Metadata.Values[mdKeyName]; v != "" {
			return v
		}
	}
	return vi.Id.Values[idKeyID]
}

func (d *dockerBridge) getVolumeInfo(name string) (csi.VolumeInfo, bool) {
	d.byNameRWL.RLock()
	defer d.byNameRWL.RUnlock()
	vol, ok := d.byName[name]
	return vol, ok
}

func (d *dockerBridge) setVolumeInfo(name string, volInfo csi.VolumeInfo) {
	d.byNameRWL.Lock()
	defer d.byNameRWL.Unlock()
	d.byName[name] = volInfo
}

func (d *dockerBridge) delVolumeInfo(name string) {
	d.byNameRWL.Lock()
	defer d.byNameRWL.Unlock()
	delete(d.byName, name)
}

var (
	createParamCapabilities []*csi.VolumeCapability

	csiVersion = &csi.Version{
		Major: 0,
		Minor: 0,
		Patch: 0,
	}
)

const (
	idKeyID                = "id"
	mdKeyName              = "name"
	metadataKeyTargetPaths = "targetpaths"

	// GRPCMetadataTargetPaths is the key in gRPC metatdata that is set
	// to "true" if a ListVolumes RPC should return VolumeInfo objects
	// with associated mount path information.
	GRPCMetadataTargetPaths = "rexray.docker2csi.targetpaths"

	errCodeCreateVolAlreadyExits = int32(
		csi.Error_CreateVolumeError_VOLUME_ALREADY_EXISTS)
	errCodeDeleteVolDoesNotExit = int32(
		csi.Error_DeleteVolumeError_VOLUME_DOES_NOT_EXIST)
	errCodeCtrlPubVolDoesNotExit = int32(
		csi.Error_ControllerPublishVolumeError_VOLUME_DOES_NOT_EXIST)
	errCodeCtrlUnpubVolDoesNotExit = int32(
		csi.Error_ControllerUnpublishVolumeError_VOLUME_DOES_NOT_EXIST)
	errCodeNodePubVolDoesNotExit = int32(
		csi.Error_NodePublishVolumeError_VOLUME_DOES_NOT_EXIST)
	errCodeNodeUnpubVolDoesNotExit = int32(
		csi.Error_NodeUnpublishVolumeError_VOLUME_DOES_NOT_EXIST)
)

func errIsVolAlreadyExists(err error) error {

	terr, ok := err.(*gocsi.Error)
	if !ok {
		return err
	}

	if terr.FullMethod == gocsi.FMCreateVolume &&
		terr.Code == errCodeCreateVolAlreadyExits {
		return nil
	}

	return err
}

func errIsVolDoesNotExist(err error) error {

	terr, ok := err.(*gocsi.Error)
	if !ok {
		return err
	}

	var exp int32 = -1

	switch terr.FullMethod {
	case gocsi.FMControllerPublishVolume:
		exp = errCodeCtrlPubVolDoesNotExit
	case gocsi.FMControllerUnpublishVolume:
		exp = errCodeCtrlUnpubVolDoesNotExit
	case gocsi.FMDeleteVolume:
		exp = errCodeDeleteVolDoesNotExit
	case gocsi.FMNodePublishVolume:
		exp = errCodeNodePubVolDoesNotExit
	case gocsi.FMNodeUnpublishVolume:
		exp = errCodeNodeUnpubVolDoesNotExit
	}

	if terr.Code == exp {
		return nil
	}

	return err
}

func errIsVolAttToNode(err error) error {

	terr, ok := err.(*gocsi.Error)
	if !ok {
		return err
	}

	var exp int32 = -1

	switch terr.FullMethod {
	case gocsi.FMNodePublishVolume:
		exp = errCodeNodePubVolDoesNotExit
	case gocsi.FMNodeUnpublishVolume:
		exp = errCodeNodeUnpubVolDoesNotExit
	}

	if terr.Code == exp {
		return nil
	}

	return err
}

func (d *dockerBridge) Create(req *dvol.CreateRequest) error {

	// Create a new gRPC, CSI client.
	c, err := d.cs.dial(d.ctx)
	if err != nil {
		d.ctx.Errorf("docker-csi-bridge: Create: client failure: %v", err)
		return err
	}
	defer c.Close()

	// Create a new CSI Controller client.
	cc := csi.NewControllerClient(c)

	// Check to see if the create option "size" is set.
	var (
		sizeGiB   int64
		sizeBytes uint64
	)
	for k, v := range req.Options {
		if strings.EqualFold(k, "size") {
			i, err := strconv.Atoi(v)
			if err != nil {
				return err
			}
			sizeGiB = int64(i)

			// Translate size from GiB to bytes.
			if sizeGiB > 0 {
				sizeBytes = uint64(sizeGiB * 1024 * 1024 * 1024)
			}

		}
	}

	// Call the CSI CreateVolume RPC.
	vol, err := gocsi.CreateVolume(
		d.ctx, cc, csiVersion,
		req.Name,
		sizeBytes, sizeBytes,
		createParamCapabilities,
		req.Options)

	// If there is an error, check to see if it is VOLUME_ALREADY_EXISTS.
	// If it is then the function below will return a nil value, otherwise
	// the original error is returned.
	if err != nil {
		return errIsVolAlreadyExists(err)
	}

	// Cache the volume.
	d.setVolumeInfo(req.Name, *vol)

	return nil
}

func (d *dockerBridge) List() (*dvol.ListResponse, error) {

	// Create a new gRPC, CSI client.
	c, err := d.cs.dial(d.ctx)
	if err != nil {
		d.ctx.Errorf("docker-csi-bridge: List: client failure: %v", err)
		return nil, err
	}
	defer c.Close()

	// Create a new CSI Controller client.
	cc := csi.NewControllerClient(c)

	// Create a context with gRPC metadata that instructs the CSI endpoint
	// to return volume mount point information.
	gctx := metadata.NewOutgoingContext(
		d.ctx, metadata.Pairs(GRPCMetadataTargetPaths, "true"))

	vols, _, err := gocsi.ListVolumes(gctx, cc, csiVersion, 0, "")
	if err != nil {
		d.ctx.Errorf("docker-csi-bridge: List: list volumes failed: %v", err)
		return nil, err
	}

	// Cache the list results in order to keep the name-to-id mappings
	// as up-to-date as possible.
	go d.cacheListResult(vols)

	res := &dvol.ListResponse{}
	res.Volumes = make([]*dvol.Volume, len(vols))
	for i, vi := range vols {
		if vi.Id == nil || len(vi.Id.Values) == 0 {
			d.ctx.Warn("docker-csi-bridge: List: skipped volume w missing id")
			continue
		}

		name := getName(*vi)
		if name == "" {
			d.ctx.WithField("volume", vi.Id.Values).Warn(
				"docker-csi-bridge: List: skipped volume w missing id and name")
			continue
		}

		v := &dvol.Volume{Name: name}
		res.Volumes[i] = v
		d.ctx.WithField("volume", vi.Id.Values).Debug(
			"docker-csi-bridge: List: found volume")
	}

	return res, nil
}

func (d *dockerBridge) Get(req *dvol.GetRequest) (*dvol.GetResponse, error) {

	vol, ok := d.getVolumeInfo(req.Name)
	if !ok {
		return nil, fmt.Errorf(
			"docker-csi-bridge: Get: unknown volume: %s", req.Name)
	}

	res := &dvol.GetResponse{}
	res.Volume = &dvol.Volume{Name: req.Name}
	if vol.Metadata != nil && len(vol.Metadata.Values) > 0 {
		res.Volume.Mountpoint = vol.Metadata.Values[metadataKeyTargetPaths]
	}

	return res, nil
}

// Remove the volume with the following steps:
//
// * Get volume from cache
// * Get the target path to unpublish
// * GetNodeID
// * NodeUnpublishVolume
// * ControllerUnpublishVolume
// * DeleteVolume
// * Remove volume from cache
func (d *dockerBridge) Remove(req *dvol.RemoveRequest) (failed error) {

	// Make sure the volume is removed from the cache if this function
	// completes successfully.
	defer func() {
		if failed == nil {
			d.delVolumeInfo(req.Name)
		}
	}()

	vol, ok := d.getVolumeInfo(req.Name)
	if !ok {
		return fmt.Errorf(
			"docker-csi-bridge: Remove: unknown volume: %s", req.Name)
	}

	// Create a new gRPC, CSI client.
	c, err := d.cs.dial(d.ctx)
	if err != nil {
		d.ctx.Errorf("docker-csi-bridge: Remove: client failure: %v", err)
		return err
	}
	defer c.Close()

	// Get the target path(s) to unpublish
	var targetPath string
	if vol.Metadata != nil {
		targetPath = vol.Metadata.Values[metadataKeyTargetPaths]
	}

	// Create a new CSI Node client.
	nc := csi.NewNodeClient(c)

	// First, unpublish the volume from this Node.
	if err := gocsi.NodeUnpublishVolume(
		d.ctx,
		nc,
		csiVersion,
		vol.Id,
		vol.Metadata,
		targetPath); err != nil {

		// If there is an error, check to see if it is VOLUME_DOES_NOT_EXIST.
		// If it is then the function below will return a nil value, otherwise
		// the original error is returned.
		return errIsVolDoesNotExist(err)
	}

	// Next, unpublish the volume at the Controller level. To do that this
	// Node's ID is required.
	nodeID, err := gocsi.GetNodeID(d.ctx, nc, csiVersion)
	if err != nil {
		return err
	}

	// Create a new CSI Controller client.
	cc := csi.NewControllerClient(c)

	// Unpublish the volume at the Controller level.
	if err := gocsi.ControllerUnpublishVolume(
		d.ctx, cc, csiVersion, vol.Id, vol.Metadata, nodeID); err != nil {

		// If there is an error, check to see if it is VOLUME_DOES_NOT_EXIST.
		// If it is then the function below will return a nil value, otherwise
		// the original error is returned.
		return errIsVolDoesNotExist(err)
	}

	// Delete the volume using the Controller.
	if err := gocsi.DeleteVolume(
		d.ctx, cc, csiVersion, vol.Id, vol.Metadata); err != nil {

		// If there is an error, check to see if it is VOLUME_DOES_NOT_EXIST.
		// If it is then the function below will return a nil value, otherwise
		// the original error is returned.
		return errIsVolDoesNotExist(err)
	}

	return nil
}

func (d *dockerBridge) Path(req *dvol.PathRequest) (*dvol.PathResponse, error) {

	vol, ok := d.getVolumeInfo(req.Name)
	if !ok {
		return nil, fmt.Errorf(
			"docker-csi-bridge: Path: unknown volume: %s", req.Name)
	}

	var targetPath string
	if vol.Metadata != nil {
		targetPath = vol.Metadata.Values[metadataKeyTargetPaths]
	}

	if targetPath == "" {
		return nil, fmt.Errorf(
			"docker-csi-bridge: Path: volume not mounted: %s", req.Name)
	}

	return &dvol.PathResponse{Mountpoint: targetPath}, nil
}

// Mount the volume with the following steps:
//
// * Get volume from cache
// * If volume does not exist, attempt to create it
// * Check to see if volume is already mounted
// * GetNodeID
// * ControllerPublishVolume
// * NodePublishVolume
// * Update cache with volume's new state
func (d *dockerBridge) Mount(
	req *dvol.MountRequest) (*dvol.MountResponse, error) {

	// Create a new gRPC, CSI client.
	c, err := d.cs.dial(d.ctx)
	if err != nil {
		d.ctx.Errorf("docker-csi-bridge: Mount: client failure: %v", err)
		return nil, err
	}
	defer c.Close()

	// Create a new CSI Controller client.
	cc := csi.NewControllerClient(c)

	// Get the volume from the cache.
	vol, ok := d.getVolumeInfo(req.Name)

	// If the volume is not cached then create it.
	if !ok {
		newVol, err := gocsi.CreateVolume(
			d.ctx, cc, csiVersion,
			req.Name,
			0, 0,
			createParamCapabilities,
			nil)

		// If there's an error and it's not VOLUME_ALREADY_EXISTS then
		// fail this mount attempt.
		if errIsVolAlreadyExists(err) != nil {
			return nil, err
		}

		vol = *newVol
	}

	// Check to see if the volume is already mounted.
	var targetPath string
	if vol.Metadata != nil {
		targetPath = vol.Metadata.Values[metadataKeyTargetPaths]
	}

	// If the volume is already mounted then return that information
	if gotil.FileExists(targetPath) {
		return &dvol.MountResponse{Mountpoint: targetPath}, nil
	}

	// At this point it's known the volume is not mounted, so proceed
	// to do so:
	//
	// * GetNodeID
	// * ControllerPublishVolume
	// * NodePublishVolume
	// * Update cache with volume's new state

	// Create a new CSI Node client.
	nc := csi.NewNodeClient(c)

	// Next, public the volume at the Controller level. To do that this
	// Node's ID is required.
	nodeID, err := gocsi.GetNodeID(d.ctx, nc, csiVersion)
	if err != nil {
		return nil, err
	}

	// Create a new volume capability for publishing the volume
	// via the Controller and Node.
	volCap := newVolumeCapability(d.fsType)

	// Publish the volume via the Controller.
	pubInfo, err := gocsi.ControllerPublishVolume(
		d.ctx, cc, csiVersion,
		vol.Id, vol.Metadata, nodeID,
		volCap, false)
	if err != nil {
		return nil, err
	}

	// The target path of the volume is determined based on the
	// volume's name and the Docker-CSI bridge root path for
	// mounting volumes.
	targetPath = path.Join(d.mntPath, req.Name)

	// Publish the volume via the Node.
	if err := gocsi.NodePublishVolume(
		d.ctx, nc, csiVersion,
		vol.Id, vol.Metadata,
		pubInfo, targetPath,
		volCap, false); err != nil {

		return nil, err
	}

	// Update the cache to reflect the volume's new state.
	if vol.Metadata == nil {
		vol.Metadata = &csi.VolumeMetadata{}
	}
	if vol.Metadata.Values == nil {
		vol.Metadata.Values = map[string]string{}
	}
	vol.Metadata.Values[metadataKeyTargetPaths] = targetPath
	d.setVolumeInfo(req.Name, vol)

	return &dvol.MountResponse{Mountpoint: targetPath}, nil
}

func newVolumeCapability(
	fsType string, flags ...string) *csi.VolumeCapability {

	return &csi.VolumeCapability{
		AccessMode: &csi.VolumeCapability_AccessMode{
			Mode: csi.VolumeCapability_AccessMode_SINGLE_NODE_WRITER,
		},
		AccessType: &csi.VolumeCapability_Mount{
			Mount: &csi.VolumeCapability_MountVolume{
				FsType:     fsType,
				MountFlags: flags,
			},
		},
	}
}

// Unmount the volume with the following steps:
//
// * Get volume from cache
// * Check to see if volume is already unmounted
// * GetNodeID
// * NodeUnpublishVolume
// * ControllerUnpublishVolume
// * Update cache with volume's new state
func (d *dockerBridge) Unmount(req *dvol.UnmountRequest) (failed error) {

	vol, ok := d.getVolumeInfo(req.Name)
	if !ok {
		return fmt.Errorf(
			"docker-csi-bridge: Unmount: unknown volume: %s", req.Name)
	}

	// If the function completes successfully, check the volume's
	// metadata. If it contains the key constant metadataKeyTargetPaths,
	// then delete it and update the cache.
	defer func() {
		if failed == nil && vol.Metadata != nil {
			if _, ok := vol.Metadata.Values[metadataKeyTargetPaths]; ok {
				delete(vol.Metadata.Values, metadataKeyTargetPaths)
				d.setVolumeInfo(req.Name, vol)
			}
		}
	}()

	// Create a new gRPC, CSI client.
	c, err := d.cs.dial(d.ctx)
	if err != nil {
		d.ctx.Errorf("docker-csi-bridge: Unmount: client failure: %v", err)
		return err
	}
	defer c.Close()

	// Get the target path(s) to unpublish
	var targetPath string
	if vol.Metadata != nil {
		targetPath = vol.Metadata.Values[metadataKeyTargetPaths]
	}

	// If there is no target path(s) to unpublish then return early,
	// with no error.
	if targetPath == "" {
		return nil
	}

	// Create a new CSI Node client.
	nc := csi.NewNodeClient(c)

	// First, unpublish the volume from this Node.
	if err := gocsi.NodeUnpublishVolume(
		d.ctx,
		nc,
		csiVersion,
		vol.Id,
		vol.Metadata,
		targetPath); err != nil {

		// If there is an error, check to see if it is VOLUME_DOES_NOT_EXIST.
		// If it is then the function below will return a nil value, otherwise
		// the original error is returned.
		return errIsVolDoesNotExist(err)
	}

	// Next, unpublish the volume at the Controller level. To do that this
	// Node's ID is required.
	nodeID, err := gocsi.GetNodeID(d.ctx, nc, csiVersion)
	if err != nil {
		return err
	}

	// Create a new CSI Controller client.
	cc := csi.NewControllerClient(c)

	// Unpublish the volume at the Controller level.
	if err := gocsi.ControllerUnpublishVolume(
		d.ctx, cc, csiVersion, vol.Id, vol.Metadata, nodeID); err != nil {

		// If there is an error, check to see if it is VOLUME_DOES_NOT_EXIST.
		// If it is then the function below will return a nil value, otherwise
		// the original error is returned.
		return errIsVolDoesNotExist(err)
	}

	return nil
}

func (d *dockerBridge) Capabilities() *dvol.CapabilitiesResponse {
	return &dvol.CapabilitiesResponse{}
}
