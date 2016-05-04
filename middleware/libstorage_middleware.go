package middleware

import (
	"net/http"

	apihandlers "github.com/emccode/libstorage/api/server/handlers"
	apivolroute "github.com/emccode/libstorage/api/server/router/volume"
	apitypes "github.com/emccode/libstorage/api/types"
)

func init() {
	apihandlers.OnRequest = onRequest
	apivolroute.OnVolume = onVolume
}

func onRequest(
	ctx apitypes.Context,
	w http.ResponseWriter,
	req *http.Request,
	store apitypes.Store) error {

	if err := logIncomingRequests(ctx, w, req, store); err != nil {
		return err
	}

	return nil
}

func logIncomingRequests(
	ctx apitypes.Context,
	w http.ResponseWriter,
	req *http.Request,
	store apitypes.Store) error {

	ctx.WithField("rexray.route", ctx.Route()).Info(
		"rex-ray embedded libStorage onRequest")

	return nil
}

func onVolume(
	ctx apitypes.Context,
	req *http.Request,
	store apitypes.Store,
	volume *apitypes.Volume) (bool, error) {

	if volume.Fields == nil {
		volume.Fields = map[string]string{}
	}
	volume.Fields["rexray.tag"] = "rexray example"

	return true, nil
}
