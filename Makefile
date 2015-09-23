# configure make
#export MAKEFLAGS := $(MAKEFLAGS) --no-print-directory -k

# store the current working directory
CWD := $(shell pwd)

# enable go 1.5 vendoring
export GO15VENDOREXPERIMENT := 1

# set the go os and architecture types as well the sed command to use based on 
# the os and architecture types
ifeq ($(OS),Windows_NT)
	GOOS ?= windows
	ifeq ($(PROCESSOR_ARCHITECTURE),AMD64)
		export GOARCH ?= amd64
	endif
	ifeq ($(PROCESSOR_ARCHITECTURE),x86)
		export GOARCH ?= 386
	endif
else
	UNAME_S := $(shell uname -s)
	UNAME_P := $(shell uname -p)
	ifeq ($(UNAME_S),Linux)
		export GOOS ?= linux
	endif
	ifeq ($(UNAME_S),Darwin)
		export GOOS ?= darwin
		export GOARCH ?= amd64
	endif
	ifeq ($(origin GOARCH), undefined)
		ifeq ($(UNAME_P),x86_64)
			export GOARCH = amd64
		endif
		ifneq ($(filter %86,$(UNAME_P)),)
			export GOARCH = 386
		endif
	endif
endif

# init the build platforms
BUILD_PLATFORMS ?= Linux-i386 Linux-x86_64 Darwin-x86_64

# init the internal go os and architecture variable values used for naming files
_GOOS ?= $(GOOS)
_GOARCH ?= $(GOARCH)

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

# the version's binary os and architecture type
ifeq ($(_GOOS),windows)
	V_OS := Windows_NT
endif
ifeq ($(_GOOS),linux)
	V_OS := Linux
endif
ifeq ($(_GOOS),darwin)
	V_OS := Darwin
endif
ifeq ($(_GOARCH),386)
	V_ARCH := i386
endif
ifeq ($(_GOARCH),amd64)
	V_ARCH := x86_64
endif
V_OS_ARCH := $(V_OS)-$(V_ARCH)

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

GOFLAGS := $(GOFLAGS)
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
PRINT_STATUS = export EC=$$?; cd $(CWD); if [ "$$EC" -eq "0" ]; then printf "SUCCESS!\n"; else exit $$EC; fi
PARSE_RESULT = export EC=$$?; cd $(CWD); if [ "$$EC" -ne "0" ]; then exit $$EC; fi

RPMBUILD := .rpmbuild

SRCS := $(shell find . -name "*.go" -type f -not -path './vendor/*' -not -path '*/*test.go' | tr '\n' ' ')
PKGS := $(shell find . -type f -name "*.go" -not -path "./vendor/*" | sed 's|[^/]\{1,\}$$||' | sort | uniq)

TEST_PKGS := $(shell find . -type f -name "*test.go" -not -path "./vendor/*" | sed 's|[^/]\{1,\}$$||' | sort | uniq)
TEST_SRCS := $(shell find . -name "*test.go" -type f -not -path './vendor/*' | tr '\n' ' ')
TESTS := $(shell for P in $(TEST_PKGS); do echo $$P$$(basename $$P).test; done)

DEPS := $(shell for P in $(PKGS); do if [ "$$P" = "." ]; then echo .goget; else echo $$P.goget; fi; done)

ALL_SRCS := $(SRCS) $(TEST_SRCS)
FMT_SRCS := $(shell for F in $(ALL_SRCS); do echo $$(dirname $$F)/.fmt/$$(basename $$F).fmt; done)
FIX_SRCS := $(shell for F in $(ALL_SRCS); do echo $$(dirname $$F)/.fix/$$(basename $$F).fix; done)

VENDOR := vendor

TGT := rexray

BLD := 		build/$(V_OS_ARCH)
BIN_FILE := $(TGT)
BIN := 		$(BLD)/$(BIN_FILE)

TGZ_FILE := 		$(BIN_FILE)-$(V_OS_ARCH).$(V_SEMVER).tar.gz
TGZ_FILE_LATEST := 	$(BIN_FILE)-$(V_OS_ARCH).tar.gz
TGZ :=				$(BLD)/$(TGZ_FILE)
TGZ_LATEST := 		$(BLD)/$(TGZ_FILE_LATEST)

RPM_FILE := 		$(BIN_FILE)-$(V_RPM_SEMVER)-1.$(V_ARCH).rpm
RPM_FILE_LATEST :=	$(BIN_FILE)-latest-$(V_ARCH).rpm
RPM :=				$(BLD)/$(RPM_FILE)
RPM_LATEST :=		$(BLD)/$(RPM_FILE_LATEST)

DEB_FILE := 		$(BIN_FILE)_$(V_RPM_SEMVER)-1_amd64.deb
DEB_FILE_LATEST :=	$(BIN_FILE)-latest-$(V_ARCH).deb
DEB :=				$(BLD)/$(DEB_FILE)
DEB_LATEST :=		$(BLD)/$(DEB_FILE_LATEST)

ifeq (Linux,$(UNAME_S))
all: deps fmt fix build tgz tgz-latest rpm rpm-latest deb deb-latest
else
all: deps fmt fix build tgz tgz-latest
endif

define DEPS_TARGET
$1: $$(wildcard $$(dir $1)*.go)
ifeq ($(origin OFFLINE), undefined)
	@printf "go get $$(dir $1)..."
	@go get -d $$(GOFLAGS) $$(dir $1); \
		$$(PRINT_STATUS); \
		touch $1
endif
endef
$(foreach d,$(DEPS),$(eval $(call DEPS_TARGET,$(d))))
deps: $(DEPS) .goglide

.goglide : glide.yaml
ifeq ($(origin OFFLINE), undefined)
	@printf "glide up..."
	@$(GLIDE) -q up 2> /dev/null; \
		$(PRINT_STATUS); \
		touch .goglide
endif

define FMT_TARGET
fmt-$$(subst ./,,$$(subst //,/,$$(subst .fmt,,$1))): $1
$1: $$(subst ./,,$$(subst //,/,$$(subst .fmt,,$1)))
	@mkdir -p $$(dir $$@); \
		touch $$@; \
		R=$$$$(go fmt $$?); \
		EC=$$$$?; \
		if [ "$$$$EC" -ne "0" ]; then rm -f $$@; \
		elif [ "$$$$R" != "" ]; then \
			printf "formatting $$?...SUCCESS\n"; \
		fi
endef
$(foreach f,$(FMT_SRCS),$(eval $(call FMT_TARGET,$(f))))
fmt: $(FMT_SRCS)

define FIX_TARGET
fix-$$(subst ./,,$$(subst //,/,$$(subst .fix,,$1))): $1
$1: $$(subst ./,,$$(subst //,/,$$(subst .fix,,$1)))
	@mkdir -p $$(dir $$@); \
		touch $$@; \
		R=$$$$(go fix $$?); \
		EC=$$$$?; \
		if [ "$$$$EC" -ne "0" ]; then rm -f $$@; \
		elif [ "$$$$R" != "" ]; then \
			printf "fixing $$?...SUCCESS\n"; \
		fi
endef
$(foreach f,$(FIX_SRCS),$(eval $(call FIX_TARGET,$(f))))
fix: $(FIX_SRCS)

build: $(BIN) 
$(BIN): $(SRCS)
	@printf "building $(BIN_FILE)..."
	@cd $(BASEDIR); \
		go build -o $(BIN) $(GOFLAGS) $(LDFLAGS) ./$(TGT); \
		$(PRINT_STATUS)

define BUILD_TARGET
$1: $$(SRCS) $$(wildcard $$(dir $1)*test.go)
	@printf "building $1..."
	@go test -c ./$$(@D) -o $$@; \
		$$(PRINT_STATUS)
endef
$(foreach b,$(BUILD_PLATFORMS),$(eval $(call BUILD_TARGET,$(b))))
build-all:


tgz: $(TGZ)
$(TGZ): $(BIN)
	@printf "creating $(TGZ_FILE)..."
	@cd $(BASEDIR); \
		tar -C $(BLD) -czf $(TGZ) $(BIN_FILE); \
		$(PRINT_STATUS)
		
tgz-latest: $(TGZ_LATEST)
$(TGZ_LATEST):
	@printf "creating $(TGZ_FILE_LATEST)..."
	@cd $(BLD); \
		cp -f $(TGZ_FILE) $(TGZ_FILE_LATEST); \
		$(PRINT_STATUS)

ifeq (Linux,$(UNAME_S))
rpm: $(RPM)
$(RPM): $(BIN) rexray.spec
	@printf "creating $(RPM_FILE)..."
	@cd $(BASEDIR); \
		rm -fr $(RPMBUILD); \
		mkdir -p $(RPMBUILD)/BUILD \
				 $(RPMBUILD)/RPMS \
				 $(RPMBUILD)/SRPMS \
				 $(RPMBUILD)/SOURCES \
				 $(RPMBUILD)/tmp; \
		ln -s ../../$(BLD) $(RPMBUILD)/RPMS/$(V_ARCH); \
		ln -s .. $(RPMBUILD)/SPECS; \
		cd $(RPMBUILD); \
		setarch $(V_ARCH) rpmbuild -ba --quiet \
			-D "rpmbuild $(CWD)/$(RPMBUILD)" \
			-D "v_semver $(V_RPM_SEMVER)" \
			-D "v_arch $(V_ARCH)" \
			-D "rexray $(CWD)/$(BIN)" \
			../rexray.spec; \
		$(PRINT_STATUS)
		
rpm-latest: $(RPM_LATEST)
$(RPM_LATEST):
	@printf "creating $(RPM_FILE_LATEST)..."
	@cd $(BLD); \
		cp -f $(RPM_FILE) $(RPM_FILE_LATEST); \
		$(PRINT_STATUS)

deb: $(DEB)
$(DEB): $(RPM)
	@printf "creating $(DEB_FILE)..."
	@cd $(BLD); \
		fakeroot alien -k -c --bump=0 $(RPM_FILE) > /dev/null; \
		$(PRINT_STATUS)
		
deb-latest: $(DEB_LATEST)
$(DEB_LATEST):
	@printf "creating $(DEB_FILE_LATEST)..."
	@cd $(BLD); \
		cp -f $(DEB_FILE) $(DEB_FILE_LATEST); \
		$(PRINT_STATUS)
endif

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

install:
_install: _deps _fmt
	@echo "target: install"
	@printf "  ...installing rexray $(V_OS_ARCH)..."; \
		cd $(BASEDIR); \
		go clean -i $(VERSIONPKG); \
		go install $(GOFLAGS) $(LDFLAGS) $(NV); \
		$(PRINT_STATUS); \
		if [ "$$EC" -eq "0" ]; then \
			FILE=$(GOPATH)/bin/rexray; \
			BYTES=$$($(STAT_FILE_SIZE)); \
			SIZE=$$(($$BYTES / 1024 / 1024)); \
			printf "\nThe REX-Ray binary is $${SIZE}MB and located at:\n\n"; \
			printf "  $$FILE\n\n"; \
		fi

bench:
	@echo "target: bench"
	@printf "  ...benchmarking rexray..."; \
		cd $(BASEDIR); \
		go test -run=NONE -bench=. $(GOFLAGS) $(NV); \
		$(PRINT_STATUS)

clean:
	@echo "target: clean"; \
		rm -fr $(BLD)
		
version:
	@echo SemVer: $(V_SEMVER)
	@echo RpmVer: $(V_RPM_SEMVER)
	@echo Binary: $(V_OS_ARCH)
	@echo Branch: $(V_BRANCH)
	@echo Commit: $(V_SHA_LONG)
	@echo Formed: $(V_BUILD_DATE)
	
version-noarch:
	@echo SemVer: $(V_SEMVER)
	@echo RpmVer: $(V_RPM_SEMVER)
	@echo Branch: $(V_BRANCH)
	@echo Commit: $(V_SHA_LONG)
	@echo Formed: $(V_BUILD_DATE)
	@echo

rpm1: 
	@echo "target: rpm"
	@printf "  ...building rpm $(V_ARCH)..."; \
		mkdir -p .deploy/latest; \
		rm -fr $(RPMBUILD); \
		mkdir -p $(RPMBUILD)/BUILD \
				 $(RPMBUILD)/RPMS \
				 $(RPMBUILD)/SRPMS \
				 $(RPMBUILD)/SPECS \
				 $(RPMBUILD)/SOURCES \
				 $(RPMBUILD)/tmp; \
		cp rexray.spec $(RPMBUILD)/SPECS/rexray.spec; \
		cd $(RPMBUILD); \
		setarch $(V_ARCH) rpmbuild -ba --quiet \
			-D "rpmbuild $(RPMBUILD)" \
			-D "v_semver $(V_RPM_SEMVER)" \
			-D "v_arch $(V_ARCH)" \
			-D "rexray $(CWD)/.bin/$(V_OS_ARCH)/rexray" \
			SPECS/rexray.spec; \
		$(PRINT_STATUS); \
		if [ "$$EC" -eq "0" ]; then \
			FILE=$$(readlink -f $$(find $(RPMBUILD)/RPMS -name *.rpm)); \
			DEPLOY_FILE=.deploy/$(V_OS_ARCH)/$$(basename $$FILE); \
			mkdir -p .deploy/$(V_OS_ARCH); \
			rm -f .deploy/$(V_OS_ARCH)/*.rpm; \
			mv -f $$FILE $$DEPLOY_FILE; \
			FILE=$$DEPLOY_FILE; \
			cp -f $$FILE .deploy/latest/rexray-latest-$(V_ARCH).rpm; \
			BYTES=$$($(STAT_FILE_SIZE)); \
			SIZE=$$(($$BYTES / 1024 / 1024)); \
			printf "\nThe REX-Ray RPM is $${SIZE}MB and located at:\n\n"; \
			printf "  $$FILE\n\n"; \
		fi

rpm-linux-386:
	@if [ "" != "$(findstring Linux-i386,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=386 make rpm; \
	fi

rpm-linux-amd64:
	@if [ "" != "$(findstring Linux-x86_64,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=amd64 make rpm; \
	fi
	
rpm-all: rpm-linux-386 rpm-linux-amd64

deb1:
	@echo "target: deb"
	@printf "  ...building deb $(V_ARCH)..."; \
		cd .deploy/$(V_OS_ARCH); \
		rm -f *.deb; \
		fakeroot alien -k -c --bump=0 *.rpm > /dev/null; \
		$(PRINT_STATUS); \
		if [ "$$EC" -eq "0" ]; then \
			FILE=$$(readlink -f $$(find .deploy/$(V_OS_ARCH) -name *.deb)); \
			DEPLOY_FILE=.deploy/$(V_OS_ARCH)/$$(basename $$FILE); \
			FILE=$$DEPLOY_FILE; \
			cp -f $$FILE .deploy/latest/rexray-latest-$(V_ARCH).deb; \
			BYTES=$$($(STAT_FILE_SIZE)); \
			SIZE=$$(($$BYTES / 1024 / 1024)); \
			printf "\nThe REX-Ray DEB is $${SIZE}MB and located at:\n\n"; \
			printf "  $$FILE\n\n"; \
		fi

deb-linux-amd64: 
	@if [ "" != "$(findstring Linux-x86_64,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=amd64 make deb; \
	fi

deb-all: deb-linux-amd64

test1: install
	@echo "target: test"
	@printf "  ...testing rexray ..."; \
		cd $(BASEDIR); \
		./test.sh; \
		$(PRINT_STATUS)

.PHONY: all
