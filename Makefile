SHELL := /bin/bash

# the name of the program being compiled. this word is in place of file names,
# directory paths, etc. changing the value of PROG is no guarantee everything
# continues to function.
PROG_ROOT := rexray
PROG := $(PROG_ROOT)

# the root import path. this may be override later, but it should still
# have a sane default
ROOT_IMPORT_PATH := github.com/codedellemc/rexray

# if the GOPATH is set, assign it the first element
GOPATH := $(word 1,$(subst :, ,$(GOPATH)))

ifneq (1,$(PORCELAIN))

# define the go version to use
GO_VERSION := $(TRAVIS_GO_VERSION)
ifeq (,$(strip $(GO_VERSION)))
GO_VERSION := $(shell grep -A 1 '^go:' .travis.yml | tail -n 1 | awk '{print $$2}')
endif

ifeq (undefined,$(origin BUILD_TAGS))
BUILD_TAGS := gofig pflag libstorage_integration_driver_linux
endif

ifeq (,$(findstring scripts_generated,$(BUILD_TAGS)))
BUILD_TAGS += scripts_generated
endif

ifneq (,$(REXRAY_BUILD_TYPE))
ifeq (client,$(REXRAY_BUILD_TYPE))
BUILD_TAGS += rexray_build_type_client
endif
ifeq (agent,$(REXRAY_BUILD_TYPE))
BUILD_TAGS += rexray_build_type_agent
endif
ifeq (controller,$(REXRAY_BUILD_TYPE))
BUILD_TAGS += rexray_build_type_controller
endif
endif

DEPEND_ON_GOBINDATA := true
BUILD_LIBSTORAGE_SERVER := true
EMBED_SCRIPTS := true
EMBED_SCRIPTS_FLEXREX := true

ifneq (,$(findstring rexray_build_type_client,$(BUILD_TAGS)))
PROG := $(PROG)-client
REXRAY_BUILD_TYPE := client
BUILD_LIBSTORAGE_SERVER := false
BUILD_TAGS := $(filter-out libstorage_storage_driver,$(BUILD_TAGS))
BUILD_TAGS := $(filter-out libstorage_storage_driver_%,$(BUILD_TAGS))
endif

ifneq (,$(findstring rexray_build_type_agent,$(BUILD_TAGS)))
PROG := $(PROG)-agent
REXRAY_BUILD_TYPE := agent
BUILD_LIBSTORAGE_SERVER := false
EMBED_SCRIPTS := false
EMBED_SCRIPTS_FLEXREX := false
DEPEND_ON_GOBINDATA := false
BUILD_TAGS := $(filter-out libstorage_storage_driver,$(BUILD_TAGS))
BUILD_TAGS := $(filter-out libstorage_storage_driver_%,$(BUILD_TAGS))
endif

ifneq (,$(findstring rexray_build_type_controller,$(BUILD_TAGS)))
PROG := $(PROG)-controller
REXRAY_BUILD_TYPE := controller
EMBED_SCRIPTS := false
EMBED_SCRIPTS_FLEXREX := false
BUILD_TAGS := $(filter-out libstorage_integration_driver_%,$(BUILD_TAGS))
endif

ifeq (true,$(BUILD_LIBSTORAGE_SERVER))
# if this is a controller build then consider the DRIVERS var as it may
# contain a list of drivers to include in the controller binary
ifneq (,$(DRIVERS))
BUILD_TAGS += libstorage_storage_driver
BUILD_TAGS += $(foreach d,$(DRIVERS),libstorage_storage_driver_$(d))
endif
endif

# remove leading and trailing whitespace from around the build tags
BUILD_TAGS := $(strip $(BUILD_TAGS))

all:
# if docker is running, then let's use docker to build it
ifneq (,$(shell if [ ! "$$NODOCKER" = "1" ] && docker version &> /dev/null; then echo -; fi))
	$(MAKE) docker-build
else
	$(MAKE) deps
	$(MAKE) build
endif

endif # ifneq (1,$(PORCELAIN))

# record the paths to these binaries, if they exist
GO := $(strip $(shell which go 2> /dev/null))
GIT := $(strip $(shell which git 2> /dev/null))


################################################################################
##                               CONSTANTS                                    ##
################################################################################
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
ASTERIK := *
LPAREN := (
RPAREN := )
COMMA := ,
5S := $(SPACE)$(SPACE)$(SPACE)$(SPACE)$(SPACE)


################################################################################
##                               OS/ARCH INFO                                 ##
################################################################################
GOOS := $(strip $(GOOS))
GOARCH := $(strip $(GOARCH))

ifneq (,$(GO)) # if go exists
GOOS_GOARCH := $(subst /, ,$(shell $(GO) version | awk '{print $$4}'))
ifeq (,$(GOOS))
GOOS := $(word 1,$(GOOS_GOARCH))
endif
ifeq (,$(GOARCH))
GOARCH := $(word 2,$(GOOS_GOARCH))
endif
else
ifeq (,$(GOOS))
GOOS := $(shell uname -s | tr A-Z a-z)
endif
ifeq (,$(GOARCH))
GOARCH := amd64
endif
endif
GOOS_GOARCH := $(GOOS)_$(GOARCH)

ifeq (,$(OS))
ifeq ($(GOOS),windows)
OS := Windows_NT
endif
ifeq ($(GOOS),linux)
OS := Linux
endif
ifeq ($(GOOS),darwin)
OS := Darwin
endif
endif

ifeq (,$(ARCH))

ifeq ($(GOARCH),386)
ARCH := i386
endif # ifeq ($(GOARCH),386)

ifeq ($(GOARCH),amd64)
ARCH := x86_64
endif # ifeq ($(GOARCH),amd64)

ifeq ($(GOARCH),arm)
ifeq (,$(strip $(GOARM)))
GOARM := 7
endif # ifeq (,$(strip $(GOARM)))
ARCH := ARMv$(GOARM)
endif # ifeq ($(GOARCH),arm)

ifeq ($(GOARCH),arm64)
ARCH := ARMv8
endif # ifeq ($(GOARCH),arm64)

endif # ifeq (,$(ARCH))


# if GOARCH=arm & GOARM="" then figure out what
# the correct GOARM version is and export it
ifeq (arm,$(GOARCH))
ifeq (,$(strip $(GOARM)))
ifeq (ARMv5,$(ARCH))
GOARM := 5
endif # ifeq (ARMv5,$(ARCH))
ifeq (ARMv6,$(ARCH))
GOARM := 6
endif # ifeq (ARMv6,$(ARCH))
ifeq (ARMv7,$(ARCH))
GOARM := 7
endif # ifeq (ARMv7,$(ARCH))
endif # ifeq (,$(strip $(GOARM)))
export GOARM
endif # ifeq (arm,$(GOARCH))


# if GOARCH is arm64 then undefine & unexport GOARM
ifeq (arm64,$(GOARCH))
ifneq (undefined,$(origin GOARM))
undefine GOARM
unexport GOARM
endif
endif # ifeq ($(GOARCH),arm64)


# ensure that GOARM is compatible with the GOOS &
# GOARCH per https://github.com/golang/go/wiki/GoArm
# when GOARCH=arm
ifeq (arm,$(GOARCH))
ifeq (darwin,$(GOOS))
GOARM_ALLOWED := 7
else
GOARM_ALLOWED := 5 6 7
endif # ifeq (darwin,$(GOOS))
ifeq (,$(strip $(filter $(GOARM),$(GOARM_ALLOWED))))
$(info incompatible GOARM version: $(GOARM))
$(info allowed GOARM versions are: $(GOARM_ALLOWED))
$(info plese see https://github.com/golang/go/wiki/GoArm)
exit 1
endif # ifeq (,$(strip $(filter $(GOARM),$(GOARM_ALLOWED))))
endif # ifeq (arm,$(GOARCH))

export OS
export ARCH


################################################################################
##                                  VERSION                                   ##
################################################################################
ifeq (,$(GIT)) # if git does not exist

V_MAJOR := 0
V_MINOR := 1
V_PATCH := 0
V_NOTES :=
V_BUILD :=
V_SHA_SHORT := 0123456
V_DIRTY :=
V_SHA_LONG := 0123456789ABCDEFGHIJKLMNOPQRSTUV
TRAVIS_BRANCH := master

else # if git does exit

# parse a semver
SEMVER_PATT := ^[^\d]*(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z].+?))?(?:-(\d+)-g(.+?)(?:-(dirty))?)?$$
PARSE_SEMVER = $(shell echo $(1) | perl -pe 's/$(SEMVER_PATT)/$(2)/gim')

# describe the git information and create a parsing function for it
GIT_DESCRIBE := $(shell $(GIT) describe --long --dirty)
PARSE_GIT_DESCRIBE = $(call PARSE_SEMVER,$(GIT_DESCRIBE),$(1))

# parse the version components from the git information
V_MAJOR := $(call PARSE_GIT_DESCRIBE,$$1)
V_MINOR := $(call PARSE_GIT_DESCRIBE,$$2)
V_PATCH := $(call PARSE_GIT_DESCRIBE,$$3)
V_NOTES := $(call PARSE_GIT_DESCRIBE,$$4)
V_BUILD := $(call PARSE_GIT_DESCRIBE,$$5)
V_SHA_SHORT := $(call PARSE_GIT_DESCRIBE,$$6)
V_DIRTY := $(call PARSE_GIT_DESCRIBE,$$7)

V_SHA_LONG := $(shell $(GIT) show HEAD -s --format=%H)

# the branch name, possibly from travis-ci
ifeq ($(origin TRAVIS_BRANCH), undefined)
TRAVIS_BRANCH := $(shell $(GIT) branch | grep '*' | cut -c3-)
else
ifeq (,$(strip $(TRAVIS_BRANCH)))
TRAVIS_BRANCH := $(shell $(GIT) branch | grep '*' | cut -c3-)
endif
endif # ifeq ($(origin TRAVIS_BRANCH), undefined)

endif # if git does or does not exist


ifneq (,$(shell which date 2> /dev/null)) # if date exists
# the build date as an epoch
V_EPOCH := $(shell date +%s)
else
V_EPOCH := 0
endif # ifneq (,$(shell which date 2> /dev/null))

ifneq (,$(shell which perl 2> /dev/null)) # if perl exists
# the build date
V_BUILD_DATE := $(shell perl -e 'use POSIX strftime; print strftime("%a, %d %b %Y %H:%M:%S %Z", localtime($(V_EPOCH)))')
# the release date as required by bintray
V_RELEASE_DATE := $(shell perl -e 'use POSIX strftime; print strftime("%Y-%m-%d", localtime($(V_EPOCH)))')
else
V_BUILD_DATE := Thu, 01 Jan 1970 00:00:00
V_RELEASE_DATE := 1970-01-01
endif # ifneq (,$(shell which perl 2> /dev/null))

V_OS := $(OS)
V_ARCH := $(ARCH)
V_OS_ARCH := $(V_OS)-$(V_ARCH)

TRAVIS_BRANCH := $(subst $(ASTERIK) ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(LPAREN)HEAD detached at ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(LPAREN)detached at ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(LPAREN)HEAD detached from ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(LPAREN)detached from ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(RPAREN),,$(TRAVIS_BRANCH))

ifeq ($(origin TRAVIS_TAG), undefined)
TRAVIS_TAG := $(TRAVIS_BRANCH)
else

ifeq ($(strip $(TRAVIS_TAG)),)
TRAVIS_TAG := $(TRAVIS_BRANCH)
endif

endif # ifeq ($(origin TRAVIS_TAG), undefined)

V_BRANCH := $(TRAVIS_TAG)

# init the semver
V_SEMVER := $(V_MAJOR).$(V_MINOR).$(V_PATCH)
ifneq ($(V_NOTES),)
V_SEMVER := $(V_SEMVER)-$(V_NOTES)
endif

# get the version file's version
V_FILE := $(strip $(shell cat VERSION 2> /dev/null))

# append the build number and dirty values to the semver if appropriate
ifneq ($(V_BUILD),)
ifneq ($(V_BUILD),0)

# if the version file's version is different than the version parsed from the
# git describe information then use the version file's version
ifneq ($(V_SEMVER),$(V_FILE))

ifneq (,$(strip $(PARSE_SEMVER))) # if the PARSE_SEMVER cmd is defined
V_MAJOR := $(call PARSE_SEMVER,$(V_FILE),$$1)
V_MINOR := $(call PARSE_SEMVER,$(V_FILE),$$2)
V_PATCH := $(call PARSE_SEMVER,$(V_FILE),$$3)
V_NOTES := $(call PARSE_SEMVER,$(V_FILE),$$4)
else # if the PARSE_SEMVER cmd is NOT defined
V_MAJOR := 0
V_MINOR := 1
V_PATCH := 0
V_NOTES :=
endif # ifneq (,$(strip $(PARSE_SEMVER)))

V_SEMVER := $(V_MAJOR).$(V_MINOR).$(V_PATCH)

ifneq ($(V_NOTES),)
V_SEMVER := $(V_SEMVER)-$(V_NOTES)
endif # ifneq ($(V_NOTES),)

endif # ifneq ($(V_SEMVER),$(V_FILE))

V_SEMVER := $(V_SEMVER)+$(V_BUILD)

endif # ifneq ($(V_BUILD),0)
endif # ifneq ($(V_BUILD),)

ifeq ($(V_DIRTY),dirty)
V_SEMVER := $(V_SEMVER)+$(V_DIRTY)
endif

# the rpm version cannot have any dashes
V_RPM_SEMVER := $(subst -,+,$(V_SEMVER))

PRINTF_VERSION_CMD += @printf "SemVer: %s\nBinary: %s\nBranch: %s\nCommit:
PRINTF_VERSION_CMD += %s\nFormed: %s\n" "$(V_SEMVER)" "$(V_OS_ARCH)"
PRINTF_VERSION_CMD += "$(V_BRANCH)" "$(V_SHA_LONG)" "$(V_BUILD_DATE)"

version:
	$(PRINTF_VERSION_CMD)

version-porcelain:
	@echo $(V_SEMVER)

.PHONY: version version-porcelain

ifneq (1,$(PORCELAIN))

################################################################################
##                                  DOCKER                                    ##
################################################################################
ifneq (,$(shell if docker version &> /dev/null; then echo -; fi))

DPKG := github.com/codedellemc/rexray
DIMG := golang:$(GO_VERSION)
DGOHOSTOS := $(shell uname -s | tr A-Z a-z)
ifeq (undefined,$(origin DGOOS))
DGOOS := $(DGOHOSTOS)
endif
DGOARCH ?= amd64
DPRFX := build-rexray
DNAME := build-$(PROG)
ifeq (1,$(DBUILD_ONCE))
DNAME := $(DNAME)-$(shell date +%s)
endif
DPATH := /go/src/$(DPKG)

ifneq (,$(GIT))
DSRCS := $(shell git ls-files)
else
DSRCS := $(shell find . -type f -not \
	-path './vendor/*' -not \
	-path './.site/*' -not \
	-path './.git/*')
endif

ifneq (,$(DGLIDE_YAML))
DSRCS := $(filter-out glide.yaml,$(DSRCS))
DSRCS := $(filter-out glide.lock,$(DSRCS))
DSRCS := $(filter-out glide.lock.d,$(DSRCS))
endif
DPROG := /go/bin/$(PROG)
ifneq (linux,$(DGOOS))
DPROG := /go/bin/$(DGOOS)_$(DGOARCH)/$(PROG)
endif
ifeq (darwin,$(DGOHOSTOS))
DTARC := -
endif
DIMG_EXISTS := docker images --format '{{.Repository}}:{{.Tag}}' | grep $(DIMG) &> /dev/null
DTO_CLOBBER := docker ps -a --format '{{.Names}}' | grep $(DPRFX)
DNETRC := $(HOME)/.netrc

# DLOCAL_IMPORTS specifics a list of imported packages to copy into the
# container build's vendor directory instead of what is specified in the
# glide.lock file. If this variable is set and the GOPATH variable is not
# then the target will fail.
ifeq (undefined,$(DLOCAL_IMPORTS))
DLOCAL_IMPORTS :=
endif
ifneq (,$(DLOCAL_IMPORTS))
ifneq (,$(GOPATH))
ifneq (,$(GIT)) # if git exists
DLOCAL_IMPORTS_FILES := $(foreach I,$(DLOCAL_IMPORTS),$(addprefix $I/,$(shell $(GIT) --git-dir=$(GOPATH)/src/$(I)/.git --work-tree=$(GOPATH)/src/$(I) ls-files)))
DLOCAL_IMPORTS_FILES += $(foreach I,$(DLOCAL_IMPORTS),$I/.git)
endif
endif
endif

docker-init:
	@if ! $(DIMG_EXISTS); then docker pull $(DIMG); fi
	@docker run --name $(DNAME) -d $(DIMG) /sbin/init -D &> /dev/null || true && \
		docker exec $(DNAME) mkdir -p $(DPATH) && \
		tar -c $(DTARC) .git $(DSRCS) | docker cp - $(DNAME):$(DPATH)
ifneq (,$(DGLIDE_YAML))
	@docker cp $(DGLIDE_YAML) $(DNAME):$(DPATH)/glide.yaml
endif
ifneq (,$(wildcard $(DNETRC)))
	@docker cp $(DNETRC) $(DNAME):/root
endif
	docker exec -t $(DNAME) env make -C $(DPATH) deps
ifneq (,$(DLOCAL_IMPORTS))
ifeq (,$(GOPATH))
	@echo GOPATH must be set when using DLOCAL_IMPORTS && false
else
	@docker exec -t $(DNAME) rm -fr $(addprefix $(DPATH)/vendor/,$(DLOCAL_IMPORTS))
	@tar -C $(GOPATH)/src -c $(DTARC) $(DLOCAL_IMPORTS_FILES) | docker cp - $(DNAME):$(DPATH)/vendor
endif
endif

docker-do-build: docker-init
	docker exec -t $(DNAME) \
		env BUILD_TAGS="$(BUILD_TAGS)" GOOS=$(DGOOS) GOARCH=$(DGOARCH) NOSTAT=1 \
		make -C $(DPATH) -j build

build-docker: docker-build
docker-build: docker-do-build
	@docker cp $(DNAME):$(DPROG) $(PROG)
	@bytes=$$(stat --format '%s' $(PROG) 2> /dev/null || \
		stat -f '%z' $(PROG) 2> /dev/null) && mb=$$(($$bytes / 1024 / 1024)) && \
		printf "\nThe $(PROG) binary is $${mb}MB and located at: \n\n" && \
		printf "  ./$(PROG)\n\n"
ifeq (1,$(DBUILD_ONCE))
	docker stop $(DNAME) &> /dev/null && docker rm $(DNAME) &> /dev/null
endif

docker-build-client:
	REXRAY_BUILD_TYPE=client $(MAKE) docker-build

docker-build-agent:
	REXRAY_BUILD_TYPE=agent $(MAKE) docker-build

docker-build-controller:
	REXRAY_BUILD_TYPE=controller $(MAKE) docker-build

docker-test: DGOOS=linux
docker-test: docker-do-build
	docker exec -t $(DNAME) \
		env BUILD_TAGS="$(BUILD_TAGS)" \
		make -C $(DPATH) test

docker-clean:
	-docker stop $(DNAME) &> /dev/null && docker rm $(DNAME) &> /dev/null

docker-clean-client:
	REXRAY_BUILD_TYPE=client $(MAKE) docker-clean

docker-clean-agent:
	REXRAY_BUILD_TYPE=agent $(MAKE) docker-clean

docker-clean-controller:
	REXRAY_BUILD_TYPE=controller $(MAKE) docker-clean

docker-info: docker-init
	docker exec -t $(DNAME) \
		env BUILD_TAGS="$(BUILD_TAGS)" GOOS=$(DGOOS) GOARCH=$(DGOARCH) NOSTAT=1 \
		make -C $(DPATH) info

docker-info-client:
	REXRAY_BUILD_TYPE=client $(MAKE) docker-info

docker-info-agent:
	REXRAY_BUILD_TYPE=agent $(MAKE) docker-info

docker-info-controller:
	REXRAY_BUILD_TYPE=controller $(MAKE) docker-info

docker-clobber:
	-CNAMES=$$($(DTO_CLOBBER)); if [ "$$CNAMES" != "" ]; then \
		docker stop $$CNAMES && docker rm $$CNAMES; \
	fi

docker-list:
	-$(DTO_CLOBBER)


################################################################################
##                          DOCKER PLUGINS                                    ##
################################################################################
ifneq (,$(TRAVIS_BRANCH))
DOCKER_REQ_BRANCH := $(TRAVIS_BRANCH)
else

ifneq (,$(GIT))
DOCKER_REQ_BRANCH := $(shell $(GIT) branch | grep '*' | cut -c3-)
else
DOCKER_REQ_BRANCH := master
endif

endif

DOCKER_REQ_VERSION := $(V_SEMVER).Branch.$(V_BRANCH).Sha.$(V_SHA_LONG)
V_DOCKER_SEMVER := $(subst +,-,$(V_SEMVER))
DOCKER_PLUGIN_DRIVERS := $(subst $(SPACE),-,$(DRIVERS))

ifeq (undefined,$(origin DOCKER_PLUGIN_ROOT))
DOCKER_PLUGIN_ROOT := $(PROG)
endif
DOCKER_PLUGIN_NAME := $(DOCKER_PLUGIN_ROOT)/$(DOCKER_PLUGIN_DRIVERS):$(V_DOCKER_SEMVER)
DOCKER_PLUGIN_NAME_UNSTABLE := $(DOCKER_PLUGIN_ROOT)/$(DOCKER_PLUGIN_DRIVERS):edge
DOCKER_PLUGIN_NAME_STAGED := $(DOCKER_PLUGIN_NAME)
DOCKER_PLUGIN_NAME_STABLE := $(DOCKER_PLUGIN_ROOT)/$(DOCKER_PLUGIN_DRIVERS):latest

DOCKER_PLUGIN_BUILD_PATH := .docker/plugins/$(DOCKER_PLUGIN_DRIVERS)

DOCKER_PLUGIN_DOCKERFILE := $(DOCKER_PLUGIN_BUILD_PATH)/.Dockerfile
ifeq (,$(strip $(wildcard $(DOCKER_PLUGIN_DOCKERFILE))))
DOCKER_PLUGIN_DOCKERFILE := .docker/plugins/Dockerfile
endif
DOCKER_PLUGIN_DOCKERFILE_TGT := $(DOCKER_PLUGIN_BUILD_PATH)/Dockerfile
$(DOCKER_PLUGIN_DOCKERFILE_TGT): $(DOCKER_PLUGIN_DOCKERFILE)
	sed -e 's/$${VERSION}/$(V_SEMVER)/g' \
	    -e 's/$${DRIVERS}/$(DRIVERS)/g' \
	    $? > $@

DOCKER_PLUGIN_ENTRYPOINT := $(DOCKER_PLUGIN_BUILD_PATH)/.rexray.sh
ifeq (,$(strip $(wildcard $(DOCKER_PLUGIN_ENTRYPOINT))))
DOCKER_PLUGIN_ENTRYPOINT := .docker/plugins/rexray.sh
endif
DOCKER_PLUGIN_ENTRYPOINT_TGT := $(DOCKER_PLUGIN_BUILD_PATH)/$(PROG).sh
$(DOCKER_PLUGIN_ENTRYPOINT_TGT): $(DOCKER_PLUGIN_ENTRYPOINT)
	cp -f $? $@


DOCKER_PLUGIN_CONFIGFILE := $(DOCKER_PLUGIN_BUILD_PATH)/.rexray.yml
DOCKER_PLUGIN_CONFIGFILE_TGT := $(DOCKER_PLUGIN_BUILD_PATH)/$(PROG).yml
ifeq (,$(strip $(wildcard $(DOCKER_PLUGIN_CONFIGFILE))))
DOCKER_PLUGIN_CONFIGFILE := .docker/plugins/rexray.yml
SPACE6 := $(SPACE)$(SPACE)$(SPACE)$(SPACE)$(SPACE)$(SPACE)
SPACE8 := $(SPACE6)$(SPACE)$(SPACE)
$(DOCKER_PLUGIN_CONFIGFILE_TGT): $(DOCKER_PLUGIN_CONFIGFILE)
	sed -e 's/$${DRIVERS}/$(firstword $(DRIVERS))/g' \
	    $? > $@
	for d in $(DRIVERS); do \
	    echo "$(SPACE6)$$d:" >> $@; \
	    echo "$(SPACE8)driver: $$d" >> $@; \
	done
else
$(DOCKER_PLUGIN_CONFIGFILE_TGT): $(DOCKER_PLUGIN_CONFIGFILE)
	cp -f $? $@
endif

DOCKER_PLUGIN_REXRAYFILE ?= $(PROG)
ifeq (,$(strip $(wildcard $(DOCKER_PLUGIN_REXRAYFILE))))
DOCKER_PLUGIN_REXRAYFILE := $(DOCKER_PLUGIN_BUILD_PATH)/.$(PROG)
ifeq (,$(strip $(wildcard $(DOCKER_PLUGIN_REXRAYFILE))))
DOCKER_PLUGIN_REXRAYFILE := $(GOPATH)/bin/$(PROG)
endif
endif
DOCKER_PLUGIN_REXRAYFILE_TGT := $(DOCKER_PLUGIN_BUILD_PATH)/$(PROG)
$(DOCKER_PLUGIN_REXRAYFILE_TGT): $(DOCKER_PLUGIN_REXRAYFILE)
	cp -f $? $@

DOCKER_PLUGIN_CONFIGJSON_TGT := $(DOCKER_PLUGIN_BUILD_PATH)/config.json

DOCKER_PLUGIN_ENTRYPOINT_ROOTFS_TGT := $(DOCKER_PLUGIN_BUILD_PATH)/rootfs/$(PROG).sh
docker-build-plugin: build-docker-plugin
build-docker-plugin: $(DOCKER_PLUGIN_ENTRYPOINT_ROOTFS_TGT)
$(DOCKER_PLUGIN_ENTRYPOINT_ROOTFS_TGT): $(DOCKER_PLUGIN_CONFIGJSON_TGT) \
										$(DOCKER_PLUGIN_DOCKERFILE_TGT) \
										$(DOCKER_PLUGIN_ENTRYPOINT_TGT) \
										$(DOCKER_PLUGIN_CONFIGFILE_TGT) \
										$(DOCKER_PLUGIN_REXRAYFILE_TGT)
	docker plugin rm $(DOCKER_PLUGIN_NAME) 2> /dev/null || true
	sudo rm -fr $(@D)
	docker build -t rootfsimage $(<D) && \
		id=$$(docker create rootfsimage true) && \
		sudo mkdir -p $(@D) && \
		sudo docker export "$$id" | sudo tar -x -C $(@D) && \
		docker rm -vf "$$id" && \
		docker rmi rootfsimage
	sudo docker plugin create $(DOCKER_PLUGIN_NAME) $(<D)
	docker plugin ls

push-docker-plugin:
ifeq (1,$(DOCKER_PLUGIN_$(DOCKER_PLUGIN_DRIVERS)_NOPUSH))
	echo "docker plugin push disabled"
else
	@docker login -u $(DOCKER_USER) -p $(DOCKER_PASS)
ifeq (unstable,$(DOCKER_PLUGIN_TYPE))
	sudo docker plugin create $(DOCKER_PLUGIN_NAME_UNSTABLE) $(DOCKER_PLUGIN_BUILD_PATH)
	docker plugin push $(DOCKER_PLUGIN_NAME_UNSTABLE)
endif
ifeq (staged,$(DOCKER_PLUGIN_TYPE))
	docker plugin push $(DOCKER_PLUGIN_NAME_STAGED)
endif
ifeq (stable,$(DOCKER_PLUGIN_TYPE))
	docker plugin push $(DOCKER_PLUGIN_NAME)
	sudo docker plugin create $(DOCKER_PLUGIN_NAME_UNSTABLE) $(DOCKER_PLUGIN_BUILD_PATH)
	docker plugin push $(DOCKER_PLUGIN_NAME_UNSTABLE)
	sudo docker plugin create $(DOCKER_PLUGIN_NAME_STABLE) $(DOCKER_PLUGIN_BUILD_PATH)
	docker plugin push $(DOCKER_PLUGIN_NAME_STABLE)
endif
ifeq (,$(DOCKER_PLUGIN_TYPE))
	docker plugin push $(DOCKER_PLUGIN_NAME)
endif
endif


endif # ifneq (,$(shell if docker version &> /dev/null; then echo -; fi))


################################################################################
##                             GO CONSTANTS                                   ##
################################################################################
ifneq (,$(shell which go 2> /dev/null)) # if go exists

# a list of the go 1.6 stdlib pacakges as grepped from https://golang.org/pkg/
GO_STDLIB := archive archive/tar archive/zip bufio builtin bytes compress \
			 compress/bzip2 compress/flate compress/gzip compress/lzw \
			 compress/zlib container container/heap container/list \
			 container/ring crypto crypto/aes crypto/cipher crypto/des \
			 crypto/dsa crypto/ecdsa crypto/elliptic crypto/hmac crypto/md5 \
			 crypto/rand crypto/rc4 crypto/rsa crypto/sha1 crypto/sha256 \
			 crypto/sha512 crypto/subtle crypto/tls crypto/x509 \
			 crypto/x509/pkix database database/sql database/sql/driver debug \
			 debug/dwarf debug/elf debug/gosym debug/macho debug/pe \
			 debug/plan9obj encoding encoding/ascii85 encoding/asn1 \
			 encoding/base32 encoding/base64 encoding/binary encoding/csv \
			 encoding/gob encoding/hex encoding/json encoding/pem encoding/xml \
			 errors expvar flag fmt go go/ast go/build go/constant go/doc \
			 go/format go/importer go/parser go/printer go/scanner go/token \
			 go/types hash hash/adler32 hash/crc32 hash/crc64 hash/fnv html \
			 html/template image image/color image/color/palette image/draw \
			 image/gif image/jpeg image/png index index/suffixarray io \
			 io/ioutil log log/syslog math math/big math/cmplx math/rand mime \
			 mime/multipart mime/quotedprintable net net/http net/http/cgi \
			 net/http/cookiejar net/http/fcgi net/http/httptest \
			 net/http/httputil net/http/pprof net/mail net/rpc net/rpc/jsonrpc \
			 net/smtp net/textproto net/url os os/exec os/signal os/user path \
			 path/filepath reflect regexp regexp/syntax runtime runtime/cgo \
			 runtime/debug runtime/msan runtime/pprof runtime/race \
			 runtime/trace sort strconv strings sync sync/atomic syscall \
			 testing testing/iotest testing/quick text text/scanner \
			 text/tabwriter text/template text/template/parse time unicode \
			 unicode/utf16 unicode/utf8 unsafe


################################################################################
##                                SYSTEM INFO                                 ##
################################################################################

GOPATH := $(shell go env | grep GOPATH | sed 's/GOPATH="\(.*\)"/\1/')
GOPATH := $(word 1,$(subst :, ,$(GOPATH)))
GOHOSTOS := $(shell go env | grep GOHOSTOS | sed 's/GOHOSTOS="\(.*\)"/\1/')
GOHOSTARCH := $(shell go env | grep GOHOSTARCH | sed 's/GOHOSTARCH="\(.*\)"/\1/')
ifneq (,$(TRAVIS_GO_VERSION))
GOVERSION := $(TRAVIS_GO_VERSION)
else
GOVERSION := $(shell go version | awk '{print $$3}' | cut -c3-)
endif

################################################################################
##                                  PATH                                      ##
################################################################################
PATH := $(GOPATH)/bin:$(PATH)
export $(PATH)


################################################################################
##                               PROJECT INFO                                 ##
################################################################################

GO_LIST_BUILD_INFO_CMD := go list -f '{{with $$ip:=.}}{{with $$ctx:=context}}{{printf "%s %s %s %s %s 0,%s" $$ip.ImportPath $$ip.Name $$ip.Dir $$ctx.GOOS $$ctx.GOARCH (join $$ctx.BuildTags ",")}}{{end}}{{end}}'
ifneq (,$(BUILD_TAGS))
GO_LIST_BUILD_INFO_CMD += -tags "$(BUILD_TAGS)"
endif

BUILD_INFO := $(shell $(GO_LIST_BUILD_INFO_CMD))
ROOT_IMPORT_PATH := $(word 1,$(BUILD_INFO))
ROOT_IMPORT_NAME := $(word 2,$(BUILD_INFO))
ROOT_DIR := $(word 3,$(BUILD_INFO))
GOOS ?= $(word 4,$(BUILD_INFO))
GOARCH ?= $(word 5,$(BUILD_INFO))
BUILD_TAGS := $(word 6,$(BUILD_INFO))
BUILD_TAGS := $(subst $(COMMA), ,$(BUILD_TAGS))
BUILD_TAGS := $(wordlist 2,$(words $(BUILD_TAGS)),$(BUILD_TAGS))
VENDORED := 0
ifneq (,$(strip $(findstring vendor,$(ROOT_IMPORT_PATH))))
VENDORED := 1
endif


################################################################################
##                                MAKE FLAGS                                  ##
################################################################################
ifeq (,$(MAKEFLAGS))
MAKEFLAGS := --no-print-directory
export $(MAKEFLAGS)
endif


################################################################################
##                              PROJECT DETAIL                                ##
################################################################################

GO_LIST_IMPORT_PATHS_INFO_CMD := go list -f '{{with $$ip:=.}}{{if $$ip.ImportPath | le "$(ROOT_IMPORT_PATH)"}}{{if $$ip.ImportPath | gt "$(ROOT_IMPORT_PATH)/vendor" }}{{printf "%s;%s;%s;%s;%v;0,%s,%s,%s,%s;0,%s;0,%s;0,%s" $$ip.ImportPath $$ip.Name $$ip.Dir $$ip.Target $$ip.Stale (join $$ip.GoFiles ",") (join $$ip.CgoFiles ",") (join $$ip.CFiles ",") (join $$ip.HFiles ",") (join $$ip.TestGoFiles ",") (join $$ip.Imports ",") (join $$ip.TestImports ",")}};{{end}}{{end}}{{end}}'
ifneq (,$(BUILD_TAGS))
GO_LIST_IMPORT_PATHS_INFO_CMD += -tags "$(BUILD_TAGS)"
endif
GO_LIST_IMPORT_PATHS_INFO_CMD += ./...

IMPORT_PATH_INFO := $(shell $(GO_LIST_IMPORT_PATHS_INFO_CMD))

# this runtime ruleset acts as a pre-processor, processing the import path
# information completely before creating the build targets for the project
define IMPORT_PATH_PREPROCS_DEF

IMPORT_PATH_INFO_$1 := $$(subst ;, ,$2)

DIR_$1 := $1
IMPORT_PATH_$1 := $$(word 1,$$(IMPORT_PATH_INFO_$1))
NAME_$1 := $$(word 2,$$(IMPORT_PATH_INFO_$1))
TARGET_$1 := $$(word 4,$$(IMPORT_PATH_INFO_$1))
STALE_$1 := $$(word 5,$$(IMPORT_PATH_INFO_$1))

ifeq (1,$$(DEBUG))
$$(info name=$$(NAME_$1), target=$$(TARGET_$1), stale=$$(STALE_$1), dir=$$(DIR_$1))
endif

SRCS_$1 := $$(subst $$(COMMA), ,$$(word 6,$$(IMPORT_PATH_INFO_$1)))
SRCS_$1 := $$(wordlist 2,$$(words $$(SRCS_$1)),$$(SRCS_$1))
SRCS_$1 := $$(addprefix $$(DIR_$1)/,$$(SRCS_$1))
SRCS += $$(SRCS_$1)

ifneq (,$$(strip $$(SRCS_$1)))
PKG_A_$1 := $$(TARGET_$1)
PKG_D_$1 := $$(DIR_$1)/$$(NAME_$1).d

ALL_PKGS += $$(PKG_A_$1)

DEPS_$1 := $$(subst $$(COMMA), ,$$(word 8,$$(IMPORT_PATH_INFO_$1)))
DEPS_$1 := $$(wordlist 2,$$(words $$(DEPS_$1)),$$(DEPS_$1))
DEPS_$1 := $$(filter-out $$(GO_STDLIB),$$(DEPS_$1))

INT_DEPS_$1 := $$(filter-out $$(ROOT_IMPORT_PATH)/vendor/%,$$(DEPS_$1))
INT_DEPS_$1 := $$(filter $$(ROOT_IMPORT_PATH)%,$$(INT_DEPS_$1))

EXT_VENDORED_DEPS_$1 := $$(filter $$(ROOT_IMPORT_PATH)/vendor/%,$$(DEPS_$1))
EXT_DEPS_$1 := $$(filter-out $$(ROOT_IMPORT_PATH)%,$$(DEPS_$1))
EXT_DEPS_$1 += $$(EXT_VENDORED_DEPS_$1)
EXT_DEPS += $$(EXT_DEPS_$1)
EXT_DEPS_SRCS_$1 := $$(addprefix $$(GOPATH)/src/,$$(addsuffix /*.go,$$(EXT_DEPS_$1)))
EXT_DEPS_SRCS_$1 := $$(subst $$(GOPATH)/src/$$(ROOT_IMPORT_PATH)/vendor/,./vendor/,$$(EXT_DEPS_SRCS_$1))
ifneq (,$$(filter $$(GOPATH)/src/C/%,$$(EXT_DEPS_SRCS_$1)))
EXT_DEPS_SRCS_$1 := $$(filter-out $$(GOPATH)/src/C/%,$$(EXT_DEPS_SRCS_$1))
ifeq (main,$$(NAME_$1))
C_$1 := 1
endif
endif
EXT_DEPS_SRCS += $$(EXT_DEPS_SRCS_$1)

DEPS_ARKS_$1 := $$(addprefix $$(GOPATH)/pkg/$$(GOOS)_$$(GOARCH)/,$$(addsuffix .a,$$(INT_DEPS_$1)))
endif

TEST_SRCS_$1 := $$(subst $$(COMMA), ,$$(word 7,$$(IMPORT_PATH_INFO_$1)))
TEST_SRCS_$1 := $$(wordlist 2,$$(words $$(TEST_SRCS_$1)),$$(TEST_SRCS_$1))
TEST_SRCS_$1 := $$(addprefix $$(DIR_$1)/,$$(TEST_SRCS_$1))
TEST_SRCS += $$(TEST_SRCS_$1)

ifneq (,$$(strip $$(TEST_SRCS_$1)))
PKG_TA_$1 := $$(DIR_$1)/$$(NAME_$1).test
PKG_TD_$1 := $$(DIR_$1)/$$(NAME_$1).test.d
PKG_TC_$1 := $$(DIR_$1)/$$(NAME_$1).test.out

ALL_TESTS += $$(PKG_TA_$1)

-include $1/coverage.mk
TEST_COVERPKG_$1 ?= $$(IMPORT_PATH_$1)

TEST_DEPS_$1 := $$(subst $$(COMMA), ,$$(word 9,$$(IMPORT_PATH_INFO_$1)))
TEST_DEPS_$1 := $$(wordlist 2,$$(words $$(TEST_DEPS_$1)),$$(TEST_DEPS_$1))
TEST_DEPS_$1 := $$(filter-out $$(GO_STDLIB),$$(TEST_DEPS_$1))

TEST_INT_DEPS_$1 := $$(filter-out $$(ROOT_IMPORT_PATH)/vendor/%,$$(TEST_DEPS_$1))
TEST_INT_DEPS_$1 := $$(filter $$(ROOT_IMPORT_PATH)%,$$(TEST_INT_DEPS_$1))

TEST_EXT_VENDORED_DEPS_$1 := $$(filter $$(ROOT_IMPORT_PATH)/vendor/%,$$(TEST_DEPS_$1))
TEST_EXT_DEPS_$1 := $$(filter-out $$(ROOT_IMPORT_PATH)%,$$(TEST_DEPS_$1))
TEST_EXT_DEPS_$1 := $$(filter-out $$(GOPATH)/src/C/%,$$(TEST_EXT_DEPS_$1))
TEST_EXT_DEPS_$1 += $$(TEST_EXT_VENDORED_DEPS_$1)
TEST_EXT_DEPS += $$(TEST_EXT_DEPS_$1)
TEST_EXT_DEPS_SRCS_$1 := $$(addprefix $$(GOPATH)/src/,$$(addsuffix /*.go,$$(TEST_EXT_DEPS_$1)))
TEST_EXT_DEPS_SRCS_$1 := $$(subst $$(GOPATH)/src/$$(ROOT_IMPORT_PATH)/vendor/,./vendor/,$$(TEST_EXT_DEPS_SRCS_$1))
ifneq (,$$(filter $$(GOPATH)/src/C/%,$$(TEST_EXT_DEPS_SRCS_$1)))
TEST_EXT_DEPS_SRCS_$1 := $$(filter-out $$(GOPATH)/src/C/%,$$(TEST_EXT_DEPS_SRCS_$1))
ifeq (main,$$(NAME_$1))
TEST_C_$1 := 1
endif
endif

TEST_EXT_DEPS_SRCS += $$(TEST_EXT_DEPS_SRCS_$1)

TEST_DEPS_ARKS_$1 := $$(addprefix $$(GOPATH)/pkg/$$(GOOS)_$$(GOARCH)/,$$(addsuffix .a,$$(TEST_INT_DEPS_$1)))
endif

ALL_SRCS_$1 += $$(SRCS_$1) $$(TEST_SRCS_$1)
ALL_SRCS += $$(ALL_SRCS_$1)

endef
$(foreach i,\
	$(IMPORT_PATH_INFO),\
	$(eval $(call IMPORT_PATH_PREPROCS_DEF,$(subst $(ROOT_DIR),.,$(word 3,$(subst ;, ,$(i)))),$(i))))


################################################################################
##                               DEPENDENCIES                                 ##
################################################################################
GO_BINDATA := $(GOPATH)/bin/go-bindata
go-bindata: $(GO_BINDATA)

GLIDE := $(GOPATH)/bin/glide
GLIDE_VER := 0.11.1
GLIDE_TGZ := glide-v$(GLIDE_VER)-$(GOHOSTOS)-$(GOHOSTARCH).tar.gz
GLIDE_URL := https://github.com/Masterminds/glide/releases/download/v$(GLIDE_VER)/$(GLIDE_TGZ)
GOGET_LOCK := goget.lock
GLIDE_LOCK := glide.lock
GLIDE_YAML := glide.yaml
GLIDE_LOCK_D := glide.lock.d

EXT_DEPS := $(sort $(EXT_DEPS))
EXT_DEPS_SRCS := $(sort $(EXT_DEPS_SRCS))
TEST_EXT_DEPS := $(sort $(TEST_EXT_DEPS))
TEST_EXT_DEPS_SRCS := $(sort $(TEST_EXT_DEPS_SRCS))
ALL_EXT_DEPS := $(sort $(EXT_DEPS) $(TEST_EXT_DEPS))
ALL_EXT_DEPS_SRCS := $(sort $(EXT_DEPS_SRCS) $(TEST_EXT_DEPS_SRCS))

ifneq (1,$(VENDORED))
$(GLIDE):
	@curl -SLO $(GLIDE_URL) && \
		tar xzf $(GLIDE_TGZ) && \
		rm -f $(GLIDE_TGZ) && \
		mkdir -p $(GOPATH)/bin && \
		mv $(GOHOSTOS)-$(GOHOSTARCH)/glide $(GOPATH)/bin && \
		rm -fr $(GOHOSTOS)-$(GOHOSTARCH)
glide: $(GLIDE)
GO_DEPS += $(GLIDE)

GO_DEPS += $(GLIDE_LOCK_D)
$(ALL_EXT_DEPS_SRCS): $(GLIDE_LOCK_D)

ifeq (,$(strip $(wildcard $(GLIDE_LOCK))))
$(GLIDE_LOCK_D): $(GLIDE_LOCK) | $(GLIDE)
	touch $@

$(GLIDE_LOCK): $(GLIDE_YAML)
	$(GLIDE) up

else #ifeq (,$(strip $(wildcard $(GLIDE_LOCK))))

$(GLIDE_LOCK_D): $(GLIDE_LOCK) | $(GLIDE)
	$(GLIDE) install && touch $@

$(GLIDE_LOCK): $(GLIDE_YAML)
	$(GLIDE) up && touch $@ && touch $(GLIDE_LOCK_D)

endif #ifeq (,$(strip $(wildcard $(GLIDE_LOCK))))

$(GLIDE_YAML):
	$(GLIDE) init

$(GLIDE_LOCK)-clean:
	rm -f $(GLIDE_LOCK)
GO_PHONY += $(GLIDE_LOCK)-clean
#GO_CLOBBER += $(GLIDE_LOCK)-clean
endif

ifeq (true,$(DEPEND_ON_GOBINDATA))
GO_BINDATA_IMPORT_PATH := vendor/github.com/jteeuwen/go-bindata/go-bindata
ifneq (1,$(VENDORED))
GO_BINDATA_IMPORT_PATH := $(ROOT_IMPORT_PATH)/$(GO_BINDATA_IMPORT_PATH)
else
GO_BINDATA_IMPORT_PATH := $(firstword $(subst /vendor/, ,$(ROOT_IMPORT_PATH)))/$(GO_BINDATA_IMPORT_PATH)
endif

$(GO_BINDATA): $(GLIDE_LOCK_D)
	GOOS="" GOARCH="" go install $(GO_BINDATA_IMPORT_PATH)
	@touch $@
GO_DEPS += $(GO_BINDATA)
endif

################################################################################
##                               GOMETALINTER                                 ##
################################################################################
ifneq (1,$(GOMETALINTER_DISABLED))
GOMETALINTER := $(GOPATH)/bin/gometalinter

$(GOMETALINTER): | $(GOMETALINTER_TOOLS)
	GOOS="" GOARCH="" go get -u github.com/alecthomas/gometalinter
gometalinter: $(GOMETALINTER)
GO_DEPS += $(GOMETALINTER)

GOMETALINTER_TOOLS_D := .gometalinter.tools.d
$(GOMETALINTER_TOOLS_D): $(GOMETALINTER)
	GOOS="" GOARCH="" $(GOMETALINTER) --install --update && touch $@
GO_DEPS += $(GOMETALINTER_TOOLS_D)

GOMETALINTER_ARGS := --vendor \
					 --fast \
					 --tests \
					 --cyclo-over=16 \
					 --deadline=30s \
					 --enable=gofmt \
					 --enable=goimports \
					 --enable=misspell \
					 --enable=lll \
					 --disable=gotype \
					 --severity=gofmt:error \
					 --severity=goimports:error \
					 --exclude=_generated.go \
					 --linter='gofmt:gofmt -l ./*.go:^(?P<path>[^\n]+)$''

gometalinter-warn: | $(GOMETALINTER_TOOLS_D) $(GLIDE)
	-$(GOMETALINTER) $(GOMETALINTER_ARGS) $(shell $(GLIDE) nv)

gometalinter-error: | $(GOMETALINTER_TOOLS_D) $(GLIDE)
	$(GOMETALINTER) $(GOMETALINTER_ARGS) --errors $(shell $(GLIDE) nv)

gometalinter-all:
ifeq (1,$(GOMETALINTER_WARN_ENABLED))
	$(MAKE) gometalinter-warn
endif
	$(MAKE) gometalinter-error
else
gometalinter-all:
	@echo gometalinter disabled
endif


################################################################################
##                               GENERATED CORE SRC                            ##
################################################################################
GENERATED_BUILD_TYPE := client+agent+controller
ifneq (,$(strip $(REXRAY_BUILD_TYPE)))
GENERATED_BUILD_TYPE := $(REXRAY_BUILD_TYPE)
endif

define CORE_GENERATED_CONTENT
package core

import (
	"time"

	apitypes "github.com/codedellemc/libstorage/api/types"
)

func init() {
	Version = &apitypes.VersionInfo{}
	Version.Arch = "$(V_OS_ARCH)"
	Version.Branch = "$(V_BRANCH)"
	Version.BuildTimestamp = time.Unix($(V_EPOCH), 0)
	Version.SemVer = "$(V_SEMVER)"
	Version.ShaLong = "$(V_SHA_LONG)"
	BuildType = "$(GENERATED_BUILD_TYPE)"
}
endef
export CORE_GENERATED_CONTENT

CORE_GENERATED_SRC := ./core/core_generated.go
print-generated-core-src:
	echo $(CORE_GENERATED_CONTENT)
$(CORE_GENERATED_SRC):
	echo generating $@
	@echo "$$CORE_GENERATED_CONTENT" > $@

$(CORE_GENERATED_SRC)-clean:
	rm -f $(CORE_GENERATED_SRC)
GO_CLEAN += $(CORE_GENERATED_SRC)-clean
GO_PHONY += $(CORE_GENERATED_SRC)-clean

CORE_A := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/core.a
$(CORE_A): $(CORE_GENERATED_SRC)


################################################################################
##                               PROJECT BUILD                                ##
################################################################################

define IMPORT_PATH_BUILD_DEF

ifneq (,$$(strip $$(SRCS_$1)))
ifneq (1,$$(C_$1))

DEPS_SRCS_$1 := $$(foreach d,$$(INT_DEPS_$1),$$(SRCS_.$$(subst $$(ROOT_IMPORT_PATH),,$$(d))))

$$(PKG_D_$1): $$(filter-out %_generated.go,$$(SRCS_$1))
	$$(file >$$@,$$(PKG_A_$1) $$(PKG_D_$1): $$(filter-out %_generated.go,$$(DEPS_SRCS_$1)))

-include $$(PKG_D_$1)

$$(PKG_D_$1)-clean:
	rm -f $$(PKG_D_$1)
GO_CLEAN += $$(PKG_D_$1)-clean

$$(PKG_A_$1): $$(EXT_DEPS_SRCS_$1) $$(SRCS_$1) | $$(DEPS_ARKS_$1)
ifeq (,$$(BUILD_TAGS))
	GOOS=$(GOOS) GOARCH=$(GOARCH) go install $1
else
	GOOS=$(GOOS) GOARCH=$(GOARCH) go install -tags "$$(BUILD_TAGS)" $1
endif

ifeq (true,$$(STALE_$1))
GO_PHONY += $$(PKG_A_$1)
endif

$$(PKG_A_$1)-clean:
	go clean -i -x $1 && rm -f $$(PKG_A_$1)

GO_BUILD += $$(PKG_A_$1)
GO_CLEAN += $$(PKG_A_$1)-clean

endif
endif


################################################################################
##                               PROJECT TESTS                                ##
################################################################################
ifneq (,$$(strip $$(TEST_SRCS_$1)))
ifneq (1,$$(TEST_C_$1))

TEST_DEPS_SRCS_$1 := $$(foreach d,$$(TEST_INT_DEPS_$1),$$(SRCS_.$$(subst $$(ROOT_IMPORT_PATH),,$$(d))))

$$(PKG_TD_$1): $$(filter-out %_generated.go,$$(TEST_SRCS_$1))
	$$(file >$$@,$$(PKG_TA_$1) $$(PKG_TD_$1): $$(filter-out %_generated.go,$$(TEST_DEPS_SRCS_$1)))

$$(PKG_TD_$1)-clean:
	rm -f $$(PKG_TD_$1)
GO_CLEAN += $$(PKG_TD_$1)-clean

-include $$(PKG_TD_$1)

ifneq (,$$(strip $$(PKG_A_$1)))
$$(PKG_TA_$1): $$(PKG_A_$1)
ifeq (true,$$(STALE_$1))
GO_PHONY += $$(PKG_TA_$1)
endif
endif
ifneq (,$$(strip $$(SRCS_$1)))
$$(PKG_TA_$1): $$(SRCS_$1)
endif

$$(PKG_TA_$1): $$(TEST_SRCS_$1) $$(TEST_EXT_DEPS_SRCS_$1) | $$(TEST_DEPS_ARKS_$1)
ifeq (,$$(BUILD_TAGS))
	go test -cover -coverpkg '$$(TEST_COVERPKG_$1)' -c -o $$@ $1
else
	go test -cover -coverpkg '$$(TEST_COVERPKG_$1)' -tags "$$(BUILD_TAGS)" -c -o $$@ $1
endif

$$(PKG_TA_$1)-clean:
	rm -f $$(PKG_TA_$1)
GO_PHONY += $$(PKG_TA_$1)-clean
GO_CLEAN += $$(PKG_TA_$1)-clean

$$(PKG_TC_$1): $$(PKG_TA_$1)
	$$(PKG_TA_$1) -test.coverprofile $$@ $$(GO_TEST_FLAGS)
TEST_PROFILES += $$(PKG_TC_$1)

$$(PKG_TC_$1)-clean:
	rm -f $$(PKG_TC_$1)
GO_PHONY += $$(PKG_TC_$1)-clean

GO_TEST += $$(PKG_TC_$1)
GO_BUILD_TESTS += $$(PKG_TA_$1)
GO_CLEAN += $$(PKG_TC_$1)-clean

endif
endif

endef
$(foreach i,\
	$(IMPORT_PATH_INFO),\
	$(eval $(call IMPORT_PATH_BUILD_DEF,$(subst $(ROOT_DIR),.,$(word 3,$(subst ;, ,$(i)))),$(i))))


################################################################################
##                                  COVERAGE                                  ##
################################################################################
COVERAGE := coverage.out
GO_COVERAGE := $(COVERAGE)
$(COVERAGE): $(TEST_PROFILES)
	printf "mode: set\n" > $@
	$(foreach f,$?,grep -v "mode: set" $(f) >> $@ &&) true

$(COVERAGE)-clean:
	rm -f $(COVERAGE)
GO_CLEAN += $(COVERAGE)-clean
GO_PHONY += $(COVERAGE)-clean

codecov: $(COVERAGE)
ifneq (1,$(CODECOV_OFFLINE))
	curl -sSL https://codecov.io/bash | bash -s -- -f $?
else
	@echo codecov offline
endif


################################################################################
##                                LIBSTORAGE                                  ##
################################################################################

LIBSTORAGE_DIR := vendor/github.com/codedellemc/libstorage
LIBSTORAGE_API := $(LIBSTORAGE_DIR)/api/api_generated.go
$(LIBSTORAGE_API):
	cd $(LIBSTORAGE_DIR) && \
		BUILD_TAGS="$(BUILD_TAGS)" $(MAKE) $(subst $(LIBSTORAGE_DIR)/,,$@) && \
		cd -
build-libstorage: $(LIBSTORAGE_API)

clean-libstorage:
	if [ -f $(LIBSTORAGE_API) ]; then $(MAKE) -C $(LIBSTORAGE_DIR) clean; fi
	rm -fr $(LIBSTORAGE_API)
	find $(LIBSTORAGE_DIR) -name "*.d" -type f -delete

GO_CLEAN += clean-libstorage
GO_PHONY += clean-libstorage

################################################################################
##                                 SCRIPTS                                    ##
################################################################################
ifeq (true,$(EMBED_SCRIPTS))

ifeq (true,$(EMBED_SCRIPTS_FLEXREX))
SCRIPTS += ./scripts/scripts/flexrex
endif

SCRIPTS_GENERATED_SRC := ./scripts/scripts_generated.go
SCRIPTS_A := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/scripts.a

IGNORE_TEST_SCRIPT_PATT := test(?:\.sh)?$
$(SCRIPTS_GENERATED_SRC): $(SCRIPTS)
	$(GO_BINDATA) -ignore '$(IGNORE_TEST_SCRIPT_PATT)' -tags "scripts_generated,!rexray_build_type_agent,!rexray_build_type_controller" -md5checksum -pkg scripts -prefix $(@D)/scripts -o $@ $(@D)/scripts/...

$(SCRIPTS_GENERATED_SRC)-clean:
	rm -f $(SCRIPTS_GENERATED_SRC)
GO_PHONY += $(SCRIPTS_GENERATED_SRC)-clean
GO_CLEAN += $(SCRIPTS_GENERATED_SRC)-clean

$(SCRIPTS_A): $(SCRIPTS_GENERATED_SRC)

build-scripts: $(SCRIPTS_GENERATED_SRC)

endif


################################################################################
##                                   CLI                                      ##
################################################################################
CLI_LINUX := $(shell GOOS=linux GOARCH=amd64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/$(PROG_ROOT)/$(PROG))
CLI_LINUX_ARM := $(shell GOOS=linux GOARCH=arm go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/$(PROG_ROOT)/$(PROG))
CLI_LINUX_ARM64 := $(shell GOOS=linux GOARCH=arm64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/$(PROG_ROOT)/$(PROG))
CLI_DARWIN := $(shell GOOS=darwin GOARCH=amd64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/$(PROG_ROOT)/$(PROG))
CLI_WINDOWS := $(shell GOOS=windows GOARCH=amd64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/$(PROG_ROOT)/$(PROG))

ifeq (linux,$(GOOS))

ifeq (amd64,$(GOARCH))
CLI := $(CLI_LINUX)
endif

ifeq (arm,$(GOARCH))
CLI := $(CLI_LINUX_ARM)
endif

ifeq (arm64,$(GOARCH))
CLI := $(CLI_LINUX_ARM64)
endif

endif # ifeq (linux,$(GOOS))

ifeq (darwin,$(GOOS))
CLI := $(CLI_DARWIN)
endif # ifeq (darwin,$(GOOS))

ifeq (windows,$(GOOS))
CLI := $(CLI_WINDOWS)
endif # ifeq (windows,$(GOOS))

build-cli-linux: $(CLI_LINUX)
build-cli-linux-arm: $(CLI_LINUX_ARM)
build-cli-linux-arm64: $(CLI_LINUX_ARM64)
build-cli-darwin: $(CLI_DARWIN)
build-cli-windows: $(CLI_WINDOWS)

define CLI_RULES
ifneq ($2_$3,$$(GOOS)_$$(GOARCH))
$1:
	GOOS=$2 GOARCH=$3 $$(MAKE) $$@
$1-clean:
	rm -f $1
GO_PHONY += $1-clean
GO_CLEAN += $1-clean
endif

ifeq (linux,$2)

ifeq (amd64,$3)
CLI_BINS += $1
endif

ifeq (arm,$3)
ifeq (1,$$(BUILD_LINUX_ARM))
CLI_BINS += $1
endif
endif

ifeq (arm64,$3)
ifeq (1,$$(BUILD_LINUX_ARM64))
CLI_BINS += $1
endif
endif

endif
endef

$(eval $(call CLI_RULES,$(CLI_LINUX),linux,amd64))
$(eval $(call CLI_RULES,$(CLI_LINUX_ARM),linux,arm))
$(eval $(call CLI_RULES,$(CLI_LINUX_ARM64),linux,arm64))
$(eval $(call CLI_RULES,$(CLI_DARWIN),darwin,amd64))

build-cli: $(CLI_BINS)


################################################################################
##                                  INFO                                      ##
################################################################################
info:
	$(info Project Import Path.........$(ROOT_IMPORT_PATH))
	$(info Project Name................$(ROOT_IMPORT_NAME))
	$(info OS / Arch...................$(OS)_$(ARCH))
	$(info Program.....................$(CLI))
	$(info Build Type..................$(GENERATED_BUILD_TYPE))
	$(info Build Tags..................$(BUILD_TAGS))
	$(info Vendored....................$(VENDORED))
	$(info GOPATH......................$(GOPATH))
	$(info GOOS........................$(GOOS))
	$(info GOARCH......................$(GOARCH))
ifneq (,$(GOARM))
	$(info GOARM.......................$(GOARM))
endif
	$(info GOHOSTOS....................$(GOHOSTOS))
	$(info GOHOSTARCH..................$(GOHOSTARCH))
	$(info GOVERSION...................$(GOVERSION))
ifneq (,$(strip $(SRCS)))
	$(info Sources.....................$(patsubst ./%,%,$(firstword $(SRCS))))
	$(foreach s,$(patsubst ./%,%,$(wordlist 2,$(words $(SRCS)),$(SRCS))),\
		$(info $(5S)$(5S)$(5S)$(5S)$(5S)$(SPACE)$(SPACE)$(SPACE)$(s)))
endif
ifneq (,$(strip $(TEST_SRCS)))
	$(info Test Sources................$(patsubst ./%,%,$(firstword $(TEST_SRCS))))
	$(foreach s,$(patsubst ./%,%,$(wordlist 2,$(words $(TEST_SRCS)),$(TEST_SRCS))),\
		$(info $(5S)$(5S)$(5S)$(5S)$(5S)$(SPACE)$(SPACE)$(SPACE)$(s)))
endif
ifneq (,$(strip $(EXT_DEPS_SRCS)))
	$(info Dependency Sources..........$(patsubst ./%,%,$(firstword $(EXT_DEPS_SRCS))))
	$(foreach s,$(patsubst ./%,%,$(wordlist 2,$(words $(EXT_DEPS_SRCS)),$(EXT_DEPS_SRCS))),\
		$(info $(5S)$(5S)$(5S)$(5S)$(5S)$(SPACE)$(SPACE)$(SPACE)$(s)))
endif
ifneq (,$(strip $(TEST_EXT_DEPS_SRCS)))
	$(info Test Dependency Sources.....$(patsubst ./%,%,$(firstword $(TEST_EXT_DEPS_SRCS))))
	$(foreach s,$(patsubst ./%,%,$(wordlist 2,$(words $(TEST_EXT_DEPS_SRCS)),$(TEST_EXT_DEPS_SRCS))),\
		$(info $(5S)$(5S)$(5S)$(5S)$(5S)$(SPACE)$(SPACE)$(SPACE)$(s)))
endif


################################################################################
##                                TGZ                                         ##
################################################################################

define TGZ_RULES
TGZ_$1 := $(PROG)-$1-$$(ARCH)-$$(V_SEMVER).tar.gz

$$(TGZ_$1): $2
	tar -czf $$@ -C $$(dir $$?) $(PROG)

$$(TGZ_$1)-clean:
	rm -f $$(TGZ_$1)
GO_PHONY += $$(TGZ_$1)-clean
GO_CLEAN += $$(TGZ_$1)-clean

ifeq (Linux,$1)
TGZ += $$(TGZ_$1)
endif
endef

$(eval $(call TGZ_RULES,Linux,$(CLI_LINUX)))
$(eval $(call TGZ_RULES,Darwin,$(CLI_DARWIN)))

build-tgz: $(TGZ)


################################################################################
##                                RPM                                         ##
################################################################################
RPMDIR := .rpm
RPM := $(PROG)-$(V_RPM_SEMVER)-1.$(V_ARCH).rpm

$(RPM)-clean:
	rm -f $(RPM)
GO_PHONY += $(RPM)-clean
GO_CLEAN += $(RPM)-clean

$(RPM): $(CLI_LINUX)
	rm -fr $(RPMDIR)
	mkdir -p $(RPMDIR)/BUILD \
			 $(RPMDIR)/RPMS \
			 $(RPMDIR)/SRPMS \
			 $(RPMDIR)/SPECS \
			 $(RPMDIR)/SOURCES \
			 $(RPMDIR)/tmp
	cp rpm.spec $(RPMDIR)/SPECS/$(PROG).spec
	cd $(RPMDIR) && \
		setarch $(V_ARCH) rpmbuild -ba \
			-D "rpmbuild $(abspath $(RPMDIR))" \
			-D "v_semver $(V_RPM_SEMVER)" \
			-D "v_arch $(V_ARCH)" \
			-D "prog_name $(PROG)" \
			-D "prog_path $?" \
			SPECS/$(PROG).spec
	mv $(RPMDIR)/RPMS/$(V_ARCH)/$(RPM) $@

build-rpm: $(RPM)


################################################################################
##                                ALIEN                                       ##
################################################################################
ALIEN_HOME := $(HOME)/.opt/alien/8.86
ALIEN_PKG := alien_8.86_all.deb
ALIEN_URL := http://archive.ubuntu.com/ubuntu/pool/main/a/alien/$(ALIEN_PKG)
ALIEN := $(ALIEN_HOME)/usr/bin/alien

$(ALIEN):
	wget $(ALIEN_URL)
	mkdir -p $(ALIEN_HOME)
	dpkg -X $(ALIEN_PKG) $(ALIEN_HOME)
	rm -f $(ALIEN_PKG)
	touch $@

PATH := $(ALIEN_HOME)/usr/bin:$(PATH)
PERL5LIB := $(ALIEN_HOME)/usr/share/perl5:$(PERL5LIB)

export PATH
export PERL5LIB


################################################################################
##                                DEB                                         ##
################################################################################
DEB := $(PROG)_$(V_RPM_SEMVER)-1_$(GOARCH).deb

$(DEB)-clean:
	rm -f $(DEB)
GO_PHONY += $(DEB)-clean
GO_CLEAN += $(DEB)-clean

$(DEB): $(RPM) | $(ALIEN)
	fakeroot $(ALIEN) -k -c --bump=0 $?

build-deb: $(DEB)


################################################################################
##                                BINTRAY                                     ##
################################################################################
BINTRAY_SUBJ ?= emccode
BINTRAY_JSON := bintray.json
BINTRAY_UNSTABLE := bintray-unstable.json
BINTRAY_STAGED := bintray-staged.json
BINTRAY_STABLE := bintray-stable.json

$(BINTRAY_UNSTABLE) $(BINTRAY_STAGED) $(BINTRAY_STABLE): $(BINTRAY_JSON)
	sed -e 's/$${SUBJ}/$(BINTRAY_SUBJ)/g' \
		-e 's/$${PROG}/$(PROG)/g' \
		-e 's/$${PROG_ROOT}/$(PROG_ROOT)/g' \
		-e 's/$${REPO}/$(subst bintray-,,$(subst .json,,$@))/g' \
		-e 's/$${SEMVER}/$(V_SEMVER)/g' \
		-e 's|$${DSCRIP}|$(V_SEMVER).Branch.$(V_BRANCH).Sha.$(V_SHA_LONG)|g' \
		-e 's/$${RELDTE}/$(V_RELEASE_DATE)/g' \
		$? > $@

bintray: $(BINTRAY_UNSTABLE) $(BINTRAY_STAGED) $(BINTRAY_STABLE)
bintray-clean:
	rm -f bintray-*.json
GO_PHONY += bintray-clean
GO_CLEAN += bintray-clean


################################################################################
##                                PROG Markers                                ##
################################################################################
PROG_$(GOOS)_$(GOARCH) := $(PROG)-$(GOOS)_$(GOARCH).d

ifeq ($(GOOS)_$(GOARCH),$(GOHOSTOS)_$(GOHOSTARCH))
PROG_BIN := $(GOPATH)/bin/$(PROG)
else
PROG_BIN := $(GOPATH)/bin/$(GOOS)_$(GOARCH)/$(PROG)
endif

PROG_BIN_SIZE = stat --format '%s' $(PROG_BIN) 2> /dev/null || \
				stat -f '%z' $(PROG_BIN) 2> /dev/null

$(PROG_$(GOOS)_$(GOARCH)): $(PROG_BIN)
	@bytes=$$($(PROG_BIN_SIZE)) && mb=$$(($$bytes / 1024 / 1024)) && \
		printf "\nThe $(PROG) binary is $${mb}MB and located at: \n\n" && \
		printf "  $?\n\n"
stat-prog: $(PROG_$(GOOS)_$(GOARCH))

$(PROG_$(GOOS)_$(GOARCH))-clean:
	rm -f $(PROG_$(GOOS)_$(GOARCH))
GO_PHONY += $(PROG_$(GOOS)_$(GOARCH))-clean
GO_CLEAN += $(PROG_$(GOOS)_$(GOARCH))-clean


################################################################################
##                                TARGETS                                     ##
################################################################################
deps: $(GO_DEPS)

build-tests: $(GO_BUILD_TESTS)

build-$(PROG): $(GO_BUILD)

build-generated:
	$(MAKE) $(CORE_GENERATED_SRC)
ifeq (true,$($EMBED_SCRIPTS))
	$(MAKE) $(SCRIPTS_GENERATED_SRC)
endif

clean-build:
	$(MAKE) clean-libstorage
	$(MAKE) $(CORE_GENERATED_SRC)-clean
	$(MAKE) $(SCRIPTS_GENERATED_SRC)-clean
	$(MAKE) build

build:
	$(MAKE) build-libstorage
	$(MAKE) build-generated
	$(MAKE) -j build-$(PROG)
ifneq (1,$(NOSTAT))
	$(MAKE) stat-prog
endif

build-client:
	REXRAY_BUILD_TYPE=client $(MAKE) build

build-agent:
	REXRAY_BUILD_TYPE=agent $(MAKE) build

build-controller:
	REXRAY_BUILD_TYPE=controller $(MAKE) build

info-client:
	REXRAY_BUILD_TYPE=client $(MAKE) info

info-agent:
	REXRAY_BUILD_TYPE=agent $(MAKE) info

info-controller:
	REXRAY_BUILD_TYPE=controller $(MAKE) info

cli: build-cli

tgz: build-tgz

rpm: build-rpm

deb: build-deb

pkg: build
	$(MAKE) tgz rpm deb

pkg-clean:
	rm -f $(PROG)*.tar.gz && rm -f *.rpm && rm -f *.deb

test: $(GO_TEST)

test-client:
	REXRAY_BUILD_TYPE=client $(MAKE) test

test-agent:
	REXRAY_BUILD_TYPE=agent $(MAKE) test

test-controller:
	REXRAY_BUILD_TYPE=controller $(MAKE) test

test-debug:
	REXRAY_DEBUG=true $(MAKE) test

cover: codecov

clean: $(GO_CLEAN) pkg-clean

clean-client:
	REXRAY_BUILD_TYPE=client $(MAKE) clean

clean-agent:
	REXRAY_BUILD_TYPE=agent $(MAKE) clean

clean-controller:
	REXRAY_BUILD_TYPE=controller $(MAKE) clean

.PHONY: $(.PHONY) info clean $(GO_PHONY)

endif # ifneq (,$(shell which go 2> /dev/null))

endif # ifneq (1,$(PORCELAIN))

clobber:
	@if [ "$(GOPATH)" = "" ]; then exit 1; fi
	rm -fr vendor
	rm -f  $(GOPATH)/bin/$(PROG_ROOT) \
       $(GOPATH)/bin/$(PROG_ROOT)-agent \
       $(GOPATH)/bin/$(PROG_ROOT)-client \
       $(GOPATH)/bin/$(PROG_ROOT)-controller \
       $(GOPATH)/bin/*/$(PROG_ROOT) \
       $(GOPATH)/bin/*/$(PROG_ROOT)-agent \
       $(GOPATH)/bin/*/$(PROG_ROOT)-client \
       $(GOPATH)/bin/*/$(PROG_ROOT)-controller
	rm -fr $(GOPATH)/pkg/$(ROOT_IMPORT_PATH) \
       $(GOPATH)/pkg/*/$(ROOT_IMPORT_PATH)
ifneq (1,$(CLOBBER_NOCLEAN))
	PORCELAIN=0 $(MAKE) clean
endif
	for f in $$(find . -name "*_generated.go" \
       -or -name "*_generated_test.go" \
       -or -name "*.d" \
       -type f \
       -not -path './.docker/*' \
       2>&1 | grep -v 'Permission denied'); do echo $$f; rm -f $$f; done

.PHONY: $(.PHONY) clobber
