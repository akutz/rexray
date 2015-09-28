#!/bin/bash

# require GOPATH
if [[ -z $GOPATH ]]; then echo GOPATH is undefined; exit 1; fi

# load the saved vars
if [[ -e .make.vars ]]; then 
    source .make.vars
fi

########################################################################
##                                                                    ##
##                             GLOBALS                                ##
##                                                                    ##
## the variables below are what ultimately control the build. some    ##
## may be set later in this build script if not initialized in this   ##
## section, but if set in this section they will be the values used   ##
## for the build                                                      ##
##                                                                    ##
## keep in mind that if values are loaded from .make.vars then it     ##
## may not be a good idea to blindly overwrite them. try using the    ##
## notation VAR=${VAR:-VAL_IF_NOT_DEFINED} to set a variables value   ##
## only if the variable is not already defined                        ##
##                                                                    ##
########################################################################

# the os and architecture strings. these are the values returned from
# a call to 'uname -s' and 'uname -p'. for windows the os string would
# be 'Windows'
#export OS=
#export ARCH=

# a space-delimited list of the platforms for which to build the code. 
# the format of a platform is $(uname -s)-$(uname -p). for windows 
# assume that the equivalent os value is Windows
#export BUILD_PLATFORMS="$OS-$ARCH"

# the version components
#export V_SEMVER=
#export V_BRANCH=
#export V_BUILD_DATE=
#export V_RELEASE_DATE=

# a space-delimited list of packages to build. this is the same value
# that would be given to the command go build
#export PKGS=

# a space-delimited list of the packages that contain tests. this is 
# the same value that would be give to the command go test
#export TEST_PKGS=

# the import path to this project. for example, if someone wanted to
# import a project hosted at github.com/akutz/golf, the value of this
# variable would be github.com/akutz/golf
#export IMPORT_PATH=

# the path of the directory to the binaries
#export BIN_DIR_PATH=

# the name of the binary produced the build, if any
#export BIN_FILE_NAME=

########################################################################
##                               DEV                                  ##
########################################################################

# flag for debug logging
DEBUG=${DEBUG:-false}

# the coprocess used to avoid subshells for small tasks
function init_echo() {
    if [[ -z $ECHO_PID ]]; then coproc ECHO { cat; }; fi
}

########################################################################
##                        var/zvar/VAR/ZVAR                           ##
########################################################################

# var is a shortcut for assigning the output of a command to an
# unexported variable.
#
# the function expects at least two arguments: the name of the variable 
# and the command to execute from which to get output. the function 
# also can take n-1 arguments to account for the command's possible 
# arguments
#
# in the example below the echo statement will print "again" to the 
# console because the var function will overwrite the value of the
# already-defined hello variable
#
#     hello=world
#     var hello again
#     echo $hello
#
function var() {
    init_echo
    local n=$1; shift; local c=$@; local v;
    if [[ $DEBUG = true ]]; then echo "varcmd=$c varname=$n"; fi
    $c >&${ECHO[1]}
    read v <&${ECHO[0]}
    if [[ $DEBUG = true ]]; then echo "varname=$n varval=$v"; fi
    if [[ -n $v ]]; then eval "$n='$v'"; fi
}

# same as var but ony sets value if var name is yet undefined. 
#
# in the example below the echo statement will print "world" to the 
# console because the zvar function did not override the 
# already-defined hello variable
#
#     hello=world
#     zvar hello again
#     echo $hello
#
function zvar() {
    eval "if [[ -z \$$1 ]]; then var \$@; fi"
}

# VAR is a shortcut for assigning the output of a cmmand to an 
# exported variable
#
# for more information on this function please see the function var
function VAR() {
    var $@ 
    eval "export $1=\$$1"
}

# same as VAR but ony sets value if var name is yet undefined
#
# # for more information on this function please see the function zvar
function ZVAR() {
    eval "if [[ -z \$$1 ]]; then VAR \$@; export $1=\$$1; fi"
}

########################################################################
##                              Paths                                 ##
########################################################################

# the current, working directory in its symlink form when applicable.
# for example, if the current directory is /home/akutz but that is
# really a symlink to /media/homes/akutz, then pwd returns the physical 
# directory, /media/homes/akutz, whereas pwd -L returns /home/akutz
function init_cwd() {
    if [[ ! -z $CWD ]]; then return; fi
    init_echo && ZVAR CWD pwd -L
}

# initializes the binary directory
function init_bin_dir_path() {
    if [[ ! -z $BIN_DIR_PATH ]]; then return; fi
    init_echo && init_cwd && ZVAR BIN_DIR_PATH echo "$CWD/.bin"
}

# gets a space-delimited list of the packages to build
function init_packages() {

    if [[ ! -z $PKGS ]]; then return; fi

    init_echo

    { ls -GBAR * | \
        grep ':$' | \
        grep -v '^vendor' | \
        sed 's/:$//g'; } >&${ECHO[1]}
    echo EOF >&${ECHO[1]}

    local pd pkgs
    while read pd <&${ECHO[0]}; do
        if [[ $pd = EOF ]]; then break; fi
        ls $pd/*.go &> /dev/null
        if [[ $? -eq 0 && $pd != rexray ]]; then
            pkgs="${pkgs}$pd "
        fi
    done

    export PKGS=$pkgs
}

# gets a space-delimited list of the packages that contain tests
function init_test_packages {

    if [[ ! -z $TEST_PKGS ]]; then return; fi

    init_packages

    local test_pkgs
    for pd in $PKGS; do
        ls $pd/*test.go &> /dev/null
        if [[ $? -eq 0 ]]; then
            test_pkgs="${test_pkgs}$pd "
        fi
    done

    export TEST_PKGS=$test_pkgs
}

# gets this project's import path
function init_import_path {
    if [[ ! -z $IMPORT_PATH ]]; then return; fi
    init_cwd && export IMPORT_PATH=${CWD#$GOPATH/src/}
}

# gets this project's bin file name
function init_bin_file_name {
    if [[ ! -z $BIN_FILE_NAME ]]; then return; fi
    init_cwd && export BIN_FILE_NAME=${CWD##*/}
}

# initializes all the paths
function init_paths() {
    init_cwd
    init_packages
    init_test_packages
    init_import_path
    init_bin_dir_path
    init_bin_file_name
}

########################################################################
##                               MAKE                                 ##
########################################################################

# set make options (http://bit.ly/1MtVJfQ):
#
#   - directory names are not printed when entered or exited
#
#   - a target completes execution entirely before its output is 
#     emitted to stdout in order to sync statements during parallel
#     executions
function init_make() {
    VAR MAKE which make
    
    export MAKEFLAGS="--no-print-directory --output-sync"
    export MAX_PAD=${MAX_PAD:-80}

    if [[ -z $STATUS_DELIM ]]; then
        STATUS_DELIM="........................."
        STATUS_DELIM+="$STATUS_DELIM"
        STATUS_DELIM+="$STATUS_DELIM"
        STATUS_DELIM+="$STATUS_DELIM"
        export STATUS_DELIM
    fi
}

########################################################################
##                             OS & ARCH                              ##
########################################################################

# parses the go os string from the os string returned by uname -s
function to_goos {
    echo ${1:-$OS} | tr '[A-Z]' '[a-z]'
}

# parses the go arch string from the arch string returned by uname -p
function to_goarch {
    if [[ ${1:-$ARCH} = i386 ]]; then echo 386; else echo amd64; fi
}

function init_os_arch() {

    # the system's os and arch strings
    ZVAR OS uname -s
    if [[ -n $OS && $OS = Darwin ]]; then 
        export ARCH=x86_64
    else 
        ZVAR ARCH uname -p
    fi
    export OS_ARCH=${OS}-${ARCH}

    # the go os and arch strings
    VAR GOOS to_goos
    VAR GOARCH to_goarch
    export GOOS_GOARCH=${GOOS}_${GOARCH}
}

########################################################################
##                        BUILD PLATFORMS                             ##
########################################################################

# the list of platforms for which to build the pgoram. the format of a
# platform is $(uname -s)-$(uname -p).
#
# the default action is to build just the current platform. to build 
# all supported platforms uncomment the next line and then comment out
# the one after that
#
# export BUILD_PLATFORMS="Linux-i386 Linux-x86_64 Darwin-x86_64"
function init_build_platforms() {
    export BUILD_PLATFORMS=${BUILD_PLATFORMS:-$OS_ARCH}

    if [[ -z $GO_BUILD_PLATFORMS ]]; then
        for bp in $BUILD_PLATFORMS; do 
            var goos to_goos ${bp%-*}
            var goarch to_goarch ${bp#*-}
            GO_BUILD_PLATFORMS="${GO_BUILD_PLATFORMS}${goos}_${goarch}"
        done
        export GO_BUILD_PLATFORMS
    fi
}

########################################################################
##                              GOLANG                                ##
########################################################################

function init_go() {
    # ensure GOROOT isn't in play
    unset GOROOT

    # the path to the go binary. set this explicitly to some other 
    # value if a version of go not in the default path is desired
    VAR GO which go

    VAR GLIDE which glide

    # enable go 1.5 vendoring
    export GO15VENDOREXPERIMENT=1

    # initialize glide
    ZVAR GLIDE which glide
    if [[ ! -z $GLIDE ]]; then
        $GO get "github.com/Masterminds/glide"
        export GLIDE=$GOPATH/bin/glide
    fi

    init_go_ldflags
}

# initializes the go build's ldflags flag. this function assumes that
# both the init_os_arch and init_version functions have been invoked, 
# but does not invoke them as the latter can be a bit expensive
function init_go_ldflags() {
    local vpkg=$IMPORT_PATH/version_info
    local ldf1="-X $vpkg.SemVer=$V_SEMVER"
    local ldf2="-X $vpkg.Branch=$V_BRANCH"
    local ldf3="-X $vpkg.Epoch=$V_EPOCH"
    local ldf4="-X $vpkg.ShaLong=$V_SHA_LONG"
    local ldf5="-X $vpkg.Arch=$V_OS_ARCH"
    export LDFLAGS="$ldf1 $ldf2 $ldf3 $ldf4 $ldf5"
}

function build_pkg() {
    local pkg_file_path=$1
    local pkg_dir=.${pkg_file_path#$GOPATH/pkg/*/$IMPORT_PATH}
    pkg_dir=${pkg_dir%.a}/
    
    local goos_goarch_pkg_file=${pkg_file_path#$GOPATH/pkg/}
    local pkg_file=${goos_goarch_pkg_file#*/}
    local file=${pkg_file#$IMPORT_PATH/}
    local goos_goarch=${goos_goarch_pkg_file%%/*}
    local goos=${goos_goarch%_*}
    local goarch=${goos_goarch#*_}

    local status_prefix="[$goos_goarch] $file"
    printf "${status_prefix}"

    env GOOS=$goos GOARCH=$goarch \
        $GO build \
            -buildmode=archive \
            -ldflags "$LDFLAGS" \
            -o $pkg_file_path \
            $pkg_dir
    EC=$?

    local pad_len
    let pad_len=${MAX_PAD}-${#status_prefix}
    printf "%*.*s%s" 0 $pad_len $STATUS_DELIM
    if [[ $EC -eq 0 ]]; then echo "SUCCESS!";
    else echo "FAILED!"; fi
}

function build_test() {
    local test_bin_path=$1
    local test_dir=${test_bin_path%/*}

    local status_prefix="[${GOOS}_${GOARCH}] $test_bin_path"
    printf "${status_prefix}"

    $GO test -c ./$test_dir -o $test_bin_path
    EC=$?

    local pad_len
    let pad_len=${MAX_PAD}-${#status_prefix}
    printf "%*.*s%s" 0 $pad_len $STATUS_DELIM
    if [[ $EC -eq 0 ]]; then echo "SUCCESS!";
    else echo "FAILED!"; fi
}

########################################################################
##                              SEMVER                                ##
########################################################################

SEMVER_IN_PATT='^[^\d]*(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z].+?))?(?:-(\d+)-g(.+?)(?:-(dirty))?)?$'
SEMVER_OUT_PATT='$1\n$2\n$3\n$4\n$5\n$6\n$7'

function perl_parse_semver {
    echo $1 | perl -pe 's/'$SEMVER_IN_PATT'/'$SEMVER_OUT_PATT'/gim'
}

# gets the current branch name
function branch_name() {
    git branch | grep '*' | awk '{print $2}'
}

# gets a long, dirty description
function git_describe() {
    git describe --dirty --long
}

# formats the epoch as a date/time string using perl
function perl_fmt_epoch() {
    perl -e 'use POSIX strftime; print strftime("'"$1"'\n", localtime('${2:-$EPOCH}'))'
}

# gets the build date from an epoch
function to_build_date() {
    perl_fmt_epoch '%a, %d %b %Y %H:%M:%S %Z'
}

# gets the release date from an epoch
function to_release_date() {
    perl_fmt_epoch '%Y-%m-%d'
}

# parse_semver parses a semantic version string and returns the 
# specified index (starting at 1). for example:
#
#   parse_semver 2 v0.2.0-rc4-23-g43d0dd2-dirty   # 2
#   parse_semver 4 v0.2.0-rc4-23-g43d0dd2-dirty   # rc4
#   parse_semver 6                                # 43d0dd2
function parse_semver() {

    # the function-scoped vars to temporarily hold the version 
    # components
    local major minor patch notes build shash dirty

    # if no version string was given to parse then parse the output
    # of a git describe call
    local to_parse=$1
    if [[ -z $to_parse ]]; then var to_parse git_describe; fi

    # write the parsed output to the coproc
    { perl_parse_semver $to_parse; } >&${ECHO[1]}

    # read the output from the coproc
    read major <&${ECHO[0]}
    read minor <&${ECHO[0]}
    read patch <&${ECHO[0]}
    read notes <&${ECHO[0]}
    read build <&${ECHO[0]}
    read shash <&${ECHO[0]}
    read dirty <&${ECHO[0]}

    # if the version component was not empty then export it
    if [[ -n $major ]]; then export V_MAJOR=$major; fi
    if [[ -n $minor ]]; then export V_MINOR=$minor; fi
    if [[ -n $patch ]]; then export V_PATCH=$patch; fi
    if [[ -n $notes ]]; then export V_NOTES=$notes; fi
    if [[ -n $build ]]; then export V_BUILD=$build; fi
    if [[ -n $shash ]]; then export V_SHASH=$shash; fi
    if [[ -n $dirty ]]; then export V_DIRTY=$dirty; fi

    # init the semver
    local semver=$V_MAJOR.$V_MINOR.$V_PATCH

    # append any notes
    if [[ -n $V_NOTES ]]; then 
        semver="$semver-$V_NOTES"; 
    fi

    # append a build number
    if [[ -n $V_BUILD && $V_BUILD -gt 0 ]]; then 
        semver=${semver}+${V_BUILD}; 
    fi

    # append a dirty flag 
    if [[ -n $V_DIRTY ]]; then 
        semver=${semver}+${V_DIRTY}; 
    fi

    export V_SEMVER=$semver
    export V_RPM_SEMVER=${V_SEMVER/\-/\+}
}

function init_version() {

    init_echo && init_os_arch
    
    # get the basic version components
    export V_OS_ARCH=$OS_ARCH

    # parse the semver if it's not already set
    if [[ -z $V_SEMVER ]]; then parse_semver; fi

    # the long commit hashes
    ZVAR V_SHA_LONG git show HEAD -s --format=%H

    # the branch name, possibly from travis-ci
    if [[ -z $V_BRANCH ]]; then
        zvar TRAVIS_BRANCH branch_name
        zvar TRAVIS_TAG echo $TRAVIS_BRANCH
        export V_BRANCH=$TRAVIS_TAG
    fi

    ZVAR ECOCH date +%s
    export V_EPOCH=$EPOCH

    # the build date
    ZVAR V_BUILD_DATE to_build_date

    # the release date as required by bintray
    ZVAR V_RELEASE_DATE to_release_date

    # if there's a version file then parse its content
    if [ -e VERSION ]; then

        # the contents of the version file
        var v_file cat VERSION
       
        # if the file's contents are different than the  
        if [[ $V_SEMVER != $v_file ]]; then
            parse_semver $v_file
        fi
    fi
}

function save_make_vars() {
    
    init 

    local f=.make.vars
    rm -f $f && echo "# saved make vars" > $f
    
    if [[ ! -z $OS ]]; then 
        echo export OS="\"$OS\"" >> $f
    fi
    if [[ ! -z $ARCH ]]; then 
        echo export ARCH="\"$ARCH\"" >> $f 
    fi

    if [[ ! -z $BUILD_PLATFORMS ]]; then 
        echo export BUILD_PLATFORMS="\"$BUILD_PLATFORMS\"" >> $f;
    fi
    if [[ ! -z $GO_BUILD_PLATFORMS ]]; then 
        echo export GO_BUILD_PLATFORMS="\"$GO_BUILD_PLATFORMS\"" >> $f
    fi
    
    if [[ ! -z $PKGS ]]; then 
        echo export PKGS="\"$PKGS\"" >> $f
    fi
    if [[ ! -z $TEST_PKGS ]]; then 
        echo export TEST_PKGS="\"$TEST_PKGS\"" >> $f
    fi
    if [[ ! -z $IMPORT_PATH ]]; then 
        echo export IMPORT_PATH="\"$IMPORT_PATH\"" >> $f
    fi

    if [[ ! -z $BIN_DIR_PATH ]]; then 
        echo export BIN_DIR_PATH="\"$BIN_DIR_PATH\"" >> $f
    fi
    if [[ ! -z $BIN_FILE_NAME ]]; then 
        echo export BIN_FILE_NAME="\"$BIN_FILE_NAME\"" >> $f
    fi

    if [[ ! -z $MAKE ]]; then 
        echo export MAKE="\"$MAKE\"" >> $f
    fi
    if [[ ! -z $MAKEFLAGS ]]; then 
        echo export MAKEFLAGS="\"$MAKEFLAGS\"" >> $f
    fi
    if [[ ! -z $MAX_PAD ]]; then 
        echo export MAX_PAD=$MAX_PAD >> $f
    fi
    if [[ ! -z $STATUS_DELIM ]]; then 
        echo export STATUS_DELIM="\"$STATUS_DELIM\"" >> $f
    fi
}

function export_functions() {
    export -f to_goos
    export -f to_goarch
    export -f build_pkg
    export -f build_test
}

function init() {
    init_os_arch
    init_build_platforms
    init_version
    init_paths
    init_go
    init_make
    export_functions
}

########################################################################
##                               MAIN                                 ##
########################################################################
case "$1" in
    cwd)
        init_cwd && echo $CWD
        ;;
    packages)
        init_packages && echo $PKGS
        ;;
    test-packages)
        init_test_packages && echo $TEST_PKGS
        ;;
    import-path)
        init_import_path && echo $IMPORT_PATH
        ;;
    bin-dir-path)
        init_bin_dir_path && echo $BIN_DIR_PATH
        ;;
    bin-file-name)
        init_bin_file_name && echo $BIN_FILE_NAME
        ;;
    save)
        save_make_vars
        ;;
    version)
        init_version
        echo "SemVer: $V_SEMVER"
        echo "RpmVer: $V_RPM_SEMVER"
        echo "OsArch: $V_OS_ARCH"
        echo "Branch: $V_BRANCH"
        echo "Commit: $V_SHA_LONG"
        echo "Formed: $V_BUILD_DATE"
        ;;
    *)
        init && exec $MAKE $@
esac