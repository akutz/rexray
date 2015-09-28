SHELL:=/bin/bash
.PHONY: all build build-tests

all: build 

EMPTY :=
SPACE := $(EMPTY) $(EMPTY)

BINDIR := .bin
RPMDIR := .rpm
TSTDIR := .tst
VENDOR := vendor

PKG_PATHS := $(addsuffix .a,$(addprefix $(IMPORT_PATH)/,$(PKGS)))
PKG_FILES := $(foreach p,$(GO_BUILD_PLATFORMS),$(addprefix $(GOPATH)/pkg/$(p)/,$(PKG_PATHS)))
TEST_BINS := $(foreach p,$(TEST_PKGS),$(addsuffix /$(notdir $(p)).test,$(p)))
TEST_SRCS := $(foreach p,$(TEST_PKGS),$(wildcard $(p)/*test.go))
MAIN_SRCS := $(filter-out $(TEST_SRCS),$(foreach p,$(PKGS),$(wildcard $(p)/*.go)))

$(VENDOR): glide.yaml
	@$(call START_STATUS,"glide up")
	$(GLIDE) -q up 2> /dev/null
	$(PRINT_STATUS)

.SECONDEXPANSION:

build: $(PKG_FILES)
$(PKG_FILES) : $$(subst $$(SPACE),/,$$(wordlist 2,9999,\
               $$(subst /, ,$$(subst $$(IMPORT_PATH)/,,\
               $$(subst $$(GOPATH)/pkg/,,$$(basename $$@))))))/*.go
	@build_pkg $@

build-tests: $(TEST_BINS)
$(TEST_BINS): $$(dir $$@)*test.go $(MAIN_SRCS)
	@build_test $@

tgz:

tgz-latest:

rpm:

rpm-latest:

deb:

deb-latest:
