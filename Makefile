# configure make
#export MAKEFLAGS := $(MAKEFLAGS) --no-print-directory -k

# store the current working directory
CWD := $(shell pwd)

# enable go 1.5 vendoring
export GO15VENDOREXPERIMENT := 1

# set the go os and architecture types as well the sed command to use based on 
# the os and architecture types
ifeq ($(OS),Windows_NT)
	V_OS := windows
	ifeq ($(PROCESSOR_ARCHITECTURE),AMD64)
		V_ARCH := x86_64
	endif
	ifeq ($(PROCESSOR_ARCHITECTURE),x86)
		V_ARCH := i386
	endif
else
	V_OS := $(shell uname -s)
	V_ARCH := $(shell uname -p)
	ifeq ($(V_OS),Darwin)
		V_ARCH := x86_64
	endif
endif
V_OS_ARCH := $(V_OS)-$(V_ARCH)

# the go binary
GO := go

# init the build platforms
BUILD_PLATFORMS ?= Linux-i386 Linux-x86_64 Darwin-x86_64

# parse a semver
SEMVER_PATT := ^[^\d]*(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z].+?))?(?:-(\d+)-g(.+?)(?:-(dirty))?)?$$
PARSE_SEMVER = $(shell echo $(1) | perl -pe 's/$(SEMVER_PATT)/$(2)/gim')

# describe the git information and create a parsing function for it
GIT_DESCRIBE := $(shell git describe --long --dirty)
PARSE_GIT_DESCRIBE = $(call PARSE_SEMVER,$(GIT_DESCRIBE),$(1))

# parse the version components from the git information
V_MAJOR := $(call PARSE_GIT_DESCRIBE,$$1)
V_MINOR := $(call PARSE_GIT_DESCRIBE,$$2)
V_PATCH := $(call PARSE_GIT_DESCRIBE,$$3)
V_NOTES := $(call PARSE_GIT_DESCRIBE,$$4)
V_BUILD := $(call PARSE_GIT_DESCRIBE,$$5)
V_SHA_SHORT := $(call PARSE_GIT_DESCRIBE,$$6)
V_DIRTY := $(call PARSE_GIT_DESCRIBE,$$7)

# the long commit hash
V_SHA_LONG := $(shell git show HEAD -s --format=%H)

# the branch name, possibly from travis-ci
ifeq ($(origin TRAVIS_BRANCH), undefined)
	TRAVIS_BRANCH := $(shell git branch | grep '*' | awk '{print $$2}')
else
	ifeq ($(strip $(TRAVIS_BRANCH)),)
		TRAVIS_BRANCH := $(shell git branch | grep '*' | awk '{print $$2}')
	endif
endif
ifeq ($(origin TRAVIS_TAG), undefined)
	TRAVIS_TAG := $(TRAVIS_BRANCH)
else
	ifeq ($(strip $(TRAVIS_TAG)),)
		TRAVIS_TAG := $(TRAVIS_BRANCH)
	endif
endif
V_BRANCH := $(TRAVIS_TAG)

# the build date as an epoch
V_EPOCH := $(shell date +%s)

# the build date
V_BUILD_DATE := $(shell perl -e 'use POSIX strftime; print strftime("%a, %d %b %Y %H:%M:%S %Z", localtime($(V_EPOCH)))')

# the release date as required by bintray
V_RELEASE_DATE := $(shell perl -e 'use POSIX strftime; print strftime("%Y-%m-%d", localtime($(V_EPOCH)))')

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
			V_MAJOR := $(call PARSE_SEMVER,$(V_FILE),$$1)
			V_MINOR := $(call PARSE_SEMVER,$(V_FILE),$$2)
			V_PATCH := $(call PARSE_SEMVER,$(V_FILE),$$3)
			V_NOTES := $(call PARSE_SEMVER,$(V_FILE),$$4)
			V_SEMVER := $(V_MAJOR).$(V_MINOR).$(V_PATCH)
			ifneq ($(V_NOTES),)
				V_SEMVER := $(V_SEMVER)-$(V_NOTES)
			endif
		endif
		V_SEMVER := $(V_SEMVER)+$(V_BUILD)
	endif
endif
ifeq ($(V_DIRTY),dirty)
	V_SEMVER := $(V_SEMVER)+$(V_DIRTY)
endif

# the rpm version cannot have any dashes
V_RPM_SEMVER := $(subst -,+,$(V_SEMVER))

GLIDE := $(GOPATH)/bin/glide
NV := $$($(GLIDE) novendor)

BASEPKG := github.com/emccode/rexray

BASEDIR := $(GOPATH)/src/$(BASEPKG)
BASEDIR_NAME := $(shell basename $(BASEDIR))
BASEDIR_PARENTDIR := $(shell dirname $(BASEDIR))
BASEDIR_TEMPMVLOC := $(BASEDIR_PARENTDIR)/.$(BASEDIR_NAME)-$(shell date +%s)
BASEDIR_MV := if [ -e "$(BASEDIR)" ]; then mv $(BASEDIR) $(BASEDIR_TEMPMVLOC); fi;
BASEDIR_MKP := mkdir -p "$(BASEDIR_PARENTDIR)"
BASEDIR_LN := ln -s "$(CWD)" "$(BASEDIR)"
BASEIDR_RMLN := rm -f $(BASEDIR)
BASEDIR_MVBACK := mv $(BASEDIR_TEMPMVLOC) $(BASEDIR)
PRE := if [ "$(CWD)" != "$(BASEDIR)" ]; then $(BASEDIR_MV); $(BASEDIR_MKP); $(BASEDIR_LN); fi
PST := if [ -e "$(BASEDIR_TEMPMVLOC)" -a -L $(BASEDIR) ]; then $(BASEIDR_RMLN); $(BASEDIR_MVBACK); fi

VERSIONPKG := $(BASEPKG)/version_info
LDF_SEMVER := -X $(VERSIONPKG).SemVer=$(V_SEMVER)
LDF_BRANCH := -X $(VERSIONPKG).Branch=$(V_BRANCH)
LDF_EPOCH := -X $(VERSIONPKG).Epoch=$(V_EPOCH)
LDF_SHA_LONG := -X $(VERSIONPKG).ShaLong=$(V_SHA_LONG)
LDF_ARCH = -X $(VERSIONPKG).Arch=$(V_OS_ARCH)
LDFLAGS = -ldflags "$(LDF_SEMVER) $(LDF_BRANCH) $(LDF_EPOCH) $(LDF_SHA_LONG) $(LDF_ARCH)"

EMCCODE := $(GOPATH)/src/github.com/emccode
STAT_FILE_SIZE = stat --format '%s' $$FILE 2> /dev/null || stat -f '%z' $$FILE 2> /dev/null
CALC_FILE_SIZE := BYTES=$$($(STAT_FILE_SIZE)); SIZE=$$(($$BYTES / 1024 / 1024)); printf "$${SIZE}MB"
PRINT_FILE_SIZE := $(STAT_FILE_SIZE) $(CALC_FILE_SIZE)
MAX_PAD := 80
STATUS_DELIM := ....................................................................................................
START_STATUS = export FILE=$(1); export PAD_LEN=$$(($(MAX_PAD) - $${\#FILE})); printf "$$FILE"
PRINT_STATUS = export EC=$$?; cd $(CWD); if [ "$$EC" -eq "0" ]; then printf "%*.*s%s\n" 0 $$PAD_LEN "$(STATUS_DELIM)" "SUCCESS!"; else exit $$EC; fi
PARSE_RESULT = export EC=$$?; cd $(CWD); if [ "$$EC" -ne "0" ]; then exit $$EC; fi

GET_GOOS = $(shell echo $(1) | tr A-Z a-z)
GET_GOARCH = $(shell if [ "$(1)" = "x86_64" ]; then echo amd64; else echo 386; fi)

BINDIR := .bin
RPMDIR := .rpm
OUTDIR := .out
TSTDIR := .tst

NOT_PATH := -not -path './.*' -not -path './vendor/*'
PKG_PARS := sed 's|[^/]\{1,\}$$||' | cut -c2- | rev | cut -c2- | rev | sort | uniq | awk 'NF > 0'

FIND_SRCS := find . -type f -name "*.go"
SRCS := $(shell $(FIND_SRCS) $(NOT_PATH) -not -path '*/*test.go' | tr '\n' ' ')
PKGS := $(shell $(FIND_SRCS) $(NOT_PATH) | $(PKG_PARS))

FIND_TSTS := find . -type f -name "*test.go"
TEST_PKGS := $(shell $(FIND_TSTS) $(NOT_PATH) | $(PKG_PARS))
TEST_SRCS := $(shell $(FIND_TSTS) $(NOT_PATH) | tr '\n' ' ')
TESTS := $(shell for P in $(TEST_PKGS); do echo $(BUILD)/$$P$$(basename $$P).test; done)

GET_DEPS := .goget $(shell for P in $(PKGS); do echo .$$P/.goget; done)
GLD_DEPS := .goglide
DEPS := $(GET_DEPS) $(GLD_DEPS)

ALL_SRCS := $(SRCS) $(TEST_SRCS)

EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
VPATH := $(subst $(SPACE),:,$(PKGS))

VENDOR := vendor
TGT := rexray

.NOTPARALLEL:
.PHONY: all print-version
all: | deps build tgz tgz-latest rpm rpm-latest deb deb-latest

define GET_DEPS_TARGET
$1: $$(wildcard $$(dir $1)*.go)
ifeq ($$(origin OFFLINE), undefined)
	@$$(call START_STATUS,"go get $$(dir $1)"); \
		go get -d $$(GOFLAGS) $$(dir $1); \
		$$(PRINT_STATUS); \
		touch $1
endif
endef
$(foreach d,$(GET_DEPS),$(eval $(call GET_DEPS_TARGET,$(d))))
goget: $(GET_DEPS)

$(GLD_DEPS): glide.yaml
ifeq ($(origin OFFLINE), undefined)
	@$(call START_STATUS,glide); \
		$(GLIDE) -q up 2> /dev/null; \
			$(PRINT_STATUS); \
			touch .goglide
endif
glide: $(GLD_DEPS)

deps: $(GET_DEPS) $(GLD_DEPS)

define OBJS_TARGET
OBJS_SRC_PKG_$1 := .$$(basename $$(subst $2,,$1))
ifeq ($$(OBJS_SRC_PKG_$1),.)
	OBJS_SRC_PKG_$1 := ./
endif
$1: $$(wildcard $$(OBJS_SRC_PKG_$1)/*.go)
	@$$(call START_STATUS,$$(BASEPKG)$$(subst $2,,$1)); \
		cd $$(BASEDIR); \
		$$(GO) fmt $$?; \
		$$(GO) fix $$?; \
		env GOOS=$3 \
			GOARCH=$4 \
			$$(GO) build \
				-o $1 \
				$$(GOFLAGS) $$(LDFLAGS) \
				$$(OBJS_SRC_PKG_$1); \
		$$(PRINT_STATUS)
endef

define BUILD_PLATFORM_TARGET
BLD_$1 := 		$$(BINDIR)/$1
BIN_FILE_$1 := 	$$(TGT)
BIN_$1 := 		$$(BLD_$1)/$$(BIN_FILE_$1)

TGZ_FILE_$1 := 			$$(BIN_FILE_$1)-$1.$$(V_SEMVER).tar.gz
TGZ_FILE_LATEST_$1 := 	$$(BIN_FILE_$1)-$1.tar.gz
TGZ_$1 :=				$$(BLD_$1)/$$(TGZ_FILE_$1)
TGZ_LATEST_$1 := 		$$(BLD_$1)/$$(TGZ_FILE_LATEST_$1)

RPM_FILE_$1 := 			$$(BIN_FILE_$1)-$$(V_RPM_SEMVER)-1.$$(V_ARCH).rpm
RPM_FILE_LATEST_$1 :=	$$(BIN_FILE_$1)-latest-$$(V_ARCH).rpm
RPM_$1 :=				$$(BLD_$1)/$$(RPM_FILE_$1)
RPM_LATEST_$1 :=		$$(BLD_$1)/$$(RPM_FILE_LATEST_$1)

DEB_FILE_$1 := 			$$(BIN_FILE_$1)_$$(V_RPM_SEMVER)-1_amd64.deb
DEB_FILE_LATEST_$1 :=	$$(BIN_FILE_$1)-latest-$$(V_ARCH).deb
DEB_$1 :=				$$(BLD_$1)/$$(DEB_FILE_$1)
DEB_LATEST_$1 :=		$$(BLD_$1)/$$(DEB_FILE_LATEST_$1)

V_OS_ARCH_$1 :=	$1
V_OS_$1 := 		$$(firstword $$(subst -, ,$$(V_OS_ARCH_$1)))
V_ARCH_$1 :=	$$(lastword $$(subst -, ,$$(V_OS_ARCH_$1)))
GOOS_$1 :=		$$(call GET_GOOS,$$(V_OS_$1))
GOARCH_$1 :=	$$(call GET_GOARCH,$$(V_ARCH_$1))

PKG_DIR_$1 :=	.obj/$$(V_OS_ARCH_$1)

OBJS_PREFIX_$1 := $$(GOPATH)/pkg/$$(GOOS_$1)_$$(GOARCH_$1)/$$(BASEPKG)
OBJS_$1 := $$(OBJS_PREFIX_$1).a $$(addsuffix .a,$$(addprefix $$(OBJS_PREFIX_$1),$$(PKGS)))
$$(foreach o,$$(OBJS_$1),$$(eval $$(call OBJS_TARGET,$$(o),$$(OBJS_PREFIX_$1),$$(GOOS_$1),$$(GOARCH_$1))))

build-$$(V_OS_ARCH_$1): $$(BIN_$1)
build-$$(GOOS_$1)-$$(GOARCH_$1): $$(BIN_$1)
$$(BIN_$1): $$(OBJS_$1)
	@$$(call START_STATUS,$$(BIN_$1)); \
		cd $$(BASEDIR); \
		env GOOS=$$(GOOS_$1) \
			GOARCH=$$(GOARCH_$1) \
			$$(GO) build \
				-o $$(BIN_$1) \
				$$(GOFLAGS) $$(LDFLAGS) \
				./$$(TGT); \
		$$(PRINT_STATUS)

tgz-$$(V_OS_ARCH_$1): $$(TGZ_$1)
tgz-$$(GOOS_$1)-$$(GOARCH_$1): $$(TGZ_$1)
$$(TGZ_$1): $$(BIN_$1)
	@$$(call START_STATUS,$$(TGZ_$1)); \
		cd $$(BASEDIR); \
		tar -C $$(BLD_$1) -czf $$(TGZ_$1) $$(BIN_FILE_$1); \
		$$(PRINT_STATUS)

tgz-latest-$$(V_OS_ARCH_$1): $$(TGZ_LATEST_$1)
tgz-latest-$$(GOOS_$1)-$$(GOARCH_$1): $$(TGZ_LATEST_$1)
$$(TGZ_LATEST_$1): $$(TGZ_$1)
	@$$(call START_STATUS,$$(TGZ_LATEST_$1)); \
		cd $$(BLD_$1); \
		cp -f $$(TGZ_FILE_$1) $$(TGZ_FILE_LATEST_$1); \
		$$(PRINT_STATUS)

rpm-$$(V_OS_ARCH_$1): $$(RPM_$1)
rpm-$$(GOOS_$1)-$$(GOARCH_$1): $$(RPM_$1)
$$(RPM_$1): $$(BIN_$1) rexray.spec
ifeq ($$(V_OS),Linux)
	@$$(call START_STATUS,$$(RPM_$1)); \
		cd $$(BASEDIR); \
		rm -fr $$(RPMDIR); \
		mkdir -p $$(RPMDIR)/BUILD \
				 $$(RPMDIR)/RPMS \
				 $$(RPMDIR)/SRPMS \
				 $$(RPMDIR)/SOURCES \
				 $$(RPMDIR)/tmp; \
		ln -s ../../$$(BLD_$1) $$(RPMDIR)/RPMS/$$(V_ARCH_$1); \
		ln -s .. $$(RPMDIR)/SPECS; \
		cd $$(RPMDIR); \
		setarch $$(V_ARCH_$1) rpmbuild -ba --quiet \
			-D "rpmbuild $$(CWD)/$$(RPMDIR)" \
			-D "v_semver $$(V_RPM_SEMVER)" \
			-D "v_arch $$(V_ARCH_$1)" \
			-D "rexray $$(CWD)/$$(BIN_$1)" \
			../rexray.spec; \
		$$(PRINT_STATUS)
endif
		
rpm-latest-$$(V_OS_ARCH_$1): $$(RPM_LATEST_$1)
rpm-latest-$$(GOOS_$1)-$$(GOARCH_$1): $$(RPM_LATEST_$1)
$$(RPM_LATEST_$1): $$(RPM_$1)
ifeq ($$(V_OS),Linux)
	@$$(call START_STATUS,$$(RPM_LATEST_$1)); \
		cd $$(BLD_$1); \
		cp -f $$(RPM_FILE_$1) $$(RPM_FILE_LATEST_$1); \
		$$(PRINT_STATUS)
endif
		
deb-$$(V_OS_ARCH_$1): $$(DEB_$1)
deb-$$(GOOS_$1)-$$(GOARCH_$1): $$(DEB_$1)
$$(DEB_$1): $$(RPM_$1)
ifeq ($$(V_OS),Linux)
	@$$(call START_STATUS,$$(DEB_$1)); \
		cd $$(BLD_$1); \
		fakeroot alien -k -c --bump=0 $$(RPM_FILE_$1) > /dev/null; \
		$$(PRINT_STATUS)
endif
		
deb-latest-$$(V_OS_ARCH_$1): $$(DEB_LATEST_$1)
deb-latest-$$(GOOS_$1)-$$(GOARCH_$1): $$(DEBLATEST_$1)
$$(DEB_LATEST_$1): $$(DEB_$1)
ifeq ($$(V_OS),Linux)
	@$$(call START_STATUS,$$(DEB_LATEST_$1)); \
		cd $$(BLD_$1); \
		cp -f $$(DEB_FILE_$1) $$(DEB_FILE_LATEST_$1); \
		$$(PRINT_STATUS)
endif
endef
$(foreach b,$(BUILD_PLATFORMS),$(eval $(call BUILD_PLATFORM_TARGET,$(b))))
build: build-$(V_OS_ARCH)
tgz: tgz-$(V_OS_ARCH)
rpm: rpm-$(V_OS_ARCH)
deb: deb-$(V_OS_ARCH)
tgz-latest: tgz-latest-$(V_OS_ARCH)
rpm-latest: rpm-latest-$(V_OS_ARCH)
deb-latest: deb-latest-$(V_OS_ARCH)

define TEST_TARGET
$1: $$(SRCS) $$(wildcard $$(dir $1)*test.go)
	@printf "building $1..."
	@go test -c ./$$(@D) -o $$@; \
		$$(PRINT_STATUS)
endef
$(foreach t,$(TESTS),$(eval $(call TEST_TARGET,$(t))))
test: $(TESTS)
	
deploy-prep:
	@echo "target: deploy-prep"
	@printf "  ...preparing deployment..."; \
		sed -e 's/$${SEMVER}/$(V_SEMVER)/g' \
			-e 's|$${DSCRIP}|$(V_SEMVER).Branch.$(V_BRANCH).Sha.$(V_SHA_LONG)|g' \
			-e 's/$${RELDTE}/$(V_RELEASE_DATE)/g' \
			.bintray-stupid.json > .bintray-stupid-filtered.json; \
		sed -e 's/$${SEMVER}/$(V_SEMVER)/g' \
			-e 's|$${DSCRIP}|$(V_SEMVER).Branch.$(V_BRANCH).Sha.$(V_SHA_LONG)|g' \
			-e 's/$${RELDTE}/$(V_RELEASE_DATE)/g' \
			.bintray-staged.json > .bintray-staged-filtered.json; \
		sed -e 's/$${SEMVER}/$(V_SEMVER)/g' \
			-e 's|$${DSCRIP}|$(V_SEMVER).Branch.$(V_BRANCH).Sha.$(V_SHA_LONG)|g' \
			-e 's/$${RELDTE}/$(V_RELEASE_DATE)/g' \
			.bintray-stable.json > .bintray-stable-filtered.json;\
		printf "SUCCESS!\n"

goinstall: $(GOPATH)/bin/$(TGT)
$(GOPATH)/bin/$(TGT): $(DEPS) $(SOURCES)
	@$(call START_STATUS,$(GOPATH)/bin/$(TGT)); \
		cd $(BASEDIR); \
		go clean -i $(VERSIONPKG); \
		go install $(GOFLAGS) $(LDFLAGS) ./$(TGT); \
		$(PRINT_STATUS)

bench:
	@echo "target: bench"
	@printf "  ...benchmarking rexray..."; \
		cd $(BASEDIR); \
		go test -run=NONE -bench=. $(GOFLAGS) $(NV); \
		$(PRINT_STATUS)

clean:
	@echo "target: clean"; \
		rm -fr $(BLD)
		
print-version:
	@echo SemVer: $(V_SEMVER)
	@echo RpmVer: $(V_RPM_SEMVER)
	@echo Binary: $(V_OS_ARCH)
	@echo Branch: $(V_BRANCH)
	@echo Commit: $(V_SHA_LONG)
	@echo Formed: $(V_BUILD_DATE)
	
print-version-noarch:
	@echo SemVer: $(V_SEMVER)
	@echo RpmVer: $(V_RPM_SEMVER)
	@echo Branch: $(V_BRANCH)
	@echo Commit: $(V_SHA_LONG)
	@echo Formed: $(V_BUILD_DATE)
	@echo

