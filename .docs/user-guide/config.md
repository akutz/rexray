# Configuring REX-Ray

Tweak this, turn that, peek behind the curtain...

---

## Overview
This page reviews how to configure REX-Ray to suit any environment, beginning
with the the most common use cases, exploring recommended guidelines, and
finally, delving into the details of more advanced settings.

!!! note "note"

    Please remember to replace the placeholders in the following examples
    with values valid for the systems on which the examples are executed.
    We provide explicit examples here for the `VirtualBox` driver.

    The `volumePath` property should reflect a path on the
    system on which the VirtualBox server is running, and that is not always
    the same system on which the `libStorage` server is running.

    So please, make sure to update the `volumePath` property for the VirtualBox
    driver to a path valid on the system on which the VirtualBox server is
    running.

    The same goes for VirtualBox property `endpoint` as the VirtualBox
    web service is not always available at `10.0.2.2:18083`.

## Basic Configuration
This section outlines the two most common configuration scenarios encountered
by REX-Ray's users:

 1. REX-Ray as a stand-alone CLI tool
 2. REX-Ray as a service

### Stand-alone CLI Mode
It is possible to use REX-Ray directly from the command line without any
configuration files. The following example uses REX-Ray to list the storage
volumes available to a Linux VM hosted by VirtualBox:

!!! note "note"

    The examples below assume that the VirtualBox web server is running on the
    host OS with authentication disabled and accessible to the guest OS. For
    more information please refer to the VirtualBox storage driver
    [documentation](http://libstorage.readthedocs.io/en/stable/user-guide/storage-providers/#virtualbox).

```sh
$ rexray volume get --service virtualbox
- attachments:
  - instanceID:
      id: e71578b0-1bfb-4fa5-bcd5-4ae982fd4a9b
      driver: virtualbox
    status: /Users/akutz/VirtualBox/libStorage/libStorage.vmdk
    volumeID: 1b819454-a280-4cff-aff5-141f4e8fd154
  name: libStorage.vmdk
  size: 64
  status: /Users/akutz/VirtualBox/libStorage/libStorage.vmdk
  id: 1b819454-a280-4cff-aff5-141f4e8fd154
  type: ""
```

In addition to listing volumes, the CLI mode can perform operations including
those that create and remove volumes and snapshots.

### Services
There are two details that must be configured before looking into services
deeper. The `embedded server` and `auto services` section describe some of
things that make configuring REX-Ray as a service easier but is optional as
you will see later in the more advanced examples.

#### Embedded Server Mode
REX-Ray can be configured separately as a client and a server. But for
simplicity, the `embedded` mode can be used if both the `client integration`
activity and the `storage abstraction` responsibilities are being served
by the same REX-Ray instance. This means by default a temporary UNIX socket is
established that both the client and server side of REX-Ray communicate with one
another on. This mode does not advertise the libStorage server or API in a
static manner.

#### Auto Services Mode
Notice the `libstorage.service` definition in the configuration and the
`--service`  paramater specified in the CLI example. This flag's argument sets
the `libstorage.service` property, which has a special meaning inside of
REX-Ray.

Services represent unique libStorage endpoints that are available to libStorage
clients. Each service is associated with a storage driver. The `auto service
mode` minimizes configuration for simple environments.

The value of the `libstorage.service` property is used to create a
default service configured with a storage driver. This special mode is only
activated if all of the following conditions are met:

  * The `libstorage.service` property is set via:
    * The CLI flags `-s|--service` or `--libstorageService`
    * The environment variable `LIBSTORAGE_SERVICE`
    * The configuration file property `libstorage.service`
  * The `libstorage.host` property is *not* set. This property can be set via:
    * The CLI flags `-h|--host` or `--libstorageHost`
    * The environment variable `LIBSTORAGE_HOST`
    * The configuration file property `libstorage.host`
  * The configuration property `libstorage.server.services` must *not* be set.
    This property is only configurable via a configuration file.

Because the above example met the auto service mode conditions, REX-Ray
created a service named `virtualbox` configured to use the `virtualbox` driver.
When used in this manner, the service name must also be a valid driver name.

#### Service Modes
Running as a service is the most common approach to running REX-Ray. This method
involves advertising two separate types of APIs when running as a service.

1. Docker Volume Plugin
2. libStorage Server and Client

### Docker Volume Plugin
This method relates to the only operational mode that REX-Ray supported with
0.3.3 and prior. A UNIX socket is created by REX-Ray that serves as a
Docker Volume Plugin compliant API endpoint. All requests handled using this
communication path which enable volumes to be delivered on demand to Docker
and supporting platforms.

The following is a simple example of a configuration file that can be placed at
`/etc/rexray/config.yml`. This is the first time we have introduced this file,
which can be used to configure the same options that were specified in the
previous CLI example. Please see the
[advanced section](./config.md#advanced-configuration) for a complete list of
configuration options.

```yaml
libstorage:
  service: virtualbox
virtualbox:
  volumePath: /Users/your_user/VirtualBox Volumes
```

Following this a `rexray start` will start the service. At any point a debug
logging flag can be set with `-l debug` to expose more detailed information
related to failures. Sometimes it is also beneficial to start the service
in the foreground with a `-f` flag.

```sh
$ rexray start

Starting REX-Ray...SUCCESS!

  The REX-Ray daemon is now running at PID 15724. To
  shutdown the daemon execute the following command:

    sudo /go/bin/rexray stop
```

At this point requests can now be made to the default Docker Volume Plugin
and Volume Driver advertised by the name `rexray` existing at
`/run/docker/plugins/rexray.sock`. You can review the
[schedulers](./schedulers) section for more details on usage.

The previous examples of CLI and service mode represent the usage of two
additional features, `auto service` and `embedded` mode. The features were
configured implicitly based on the combination of parameters specified.

### libStorage Server and Client
Although the libStorage API is being used in the `embedded` mode within the
REX-Ray process, it is possible to expose the libStorage API for integration
purposes. This enables REX-Ray to serve as a libStorage server and perform
purely the storage abstraction role.

If the desire is to establish a centralized REX-Ray instance that is called
on from remote REX-Ray instances then the following example will be useful.
The first configuration is for running REX-Ray purely as a `libStorage server`.
The second defines how you would run REX-Ray(s) in a `libStorage client` role.
These examples require multiple OS instances to fulfill these different roles.

#### libStorage Server
We can expose REX-Ray to serve the storage abstraction role by defining
a few key parameters below. First, if we wish to disable the default Docker
module Volume Plugin, we would disable the `default-docker` module. The next
section within `libstorage` defines the server specific settings. The `host`
parameter will define the endpoint that is advertised which here is open to
all network interfaces at TCP port `7980`. The `client` flag determines that
the instance is only a `controller` and does not perform integration related
tasks which require introspection level activities.

```yaml
rexray:
  modules:
    default-docker:
      disabled: true
libstorage:
  host: tcp://:7980
  embedded: true
  client:
    type: controller
  server:
    services:
      virtualbox:
        driver: virtualbox
virtualbox:
  volumePath: /Users/your_user/VirtualBox Volumes
```

Start the REX-Ray process as normal with `rexray start`.

#### libStorage Client
The client is rather simple to configure at this point. See the following
example. On a separate OS instance running REX-Ray, we have defined two things.
The first is `libstorage.host` which points this instance to the proper
endpoint.

```yaml
libstorage:
  host: tcp://rexray_server_ip:7980
  service: virtualbox  
```

Start the REX-Ray process as normal with `rexray start`. You should then be able
to see that the socket file has been created under the default location and
name. Note that REX-Ray is running as a service, but it did not start a
libStorage server, it is connecting to a remote instance as a client.

```sh
$ ls /run/docker/plugins/

rexray.sock
```


### Example sans Modules
Lets review the major sections of the configuration file.

```yaml
rexray:
  logLevel: warn
libstorage:
  service: virtualbox
  integration:
    volume:
      operations:
        create:
          default:
            size: 1
virtualbox:
  volumePath: $HOME/VirtualBox/Volumes
```

Settings occur in three primary areas:

 1. `rexray`
 2. `libstorage`
 3. `virtualbox`

The `rexray` section contains all properties specific to REX-Ray. The
YAML property path `rexray.logLevel` defines the log level for REX-Ray and its
child components. All of the `rexray` properties are
[documented](#configuration-properties) below.

Next, the `libstorage` section defines the service with which REX-Ray will
communicate via the property `libstorage.service`. This property also enables
the [Auto Service Mode](#auto-service-mode) discussed above since this
configuration example does not define a host or services section. For all
information related to libStorage and its properties, please refer to the
[libStorage documentation](http://libstorage.readthedocs.io/).

Finally, the `virtualbox` section configures the VirtualBox driver selected
or loaded by REX-Ray, as indicated via the `libstorage.service` property). The
libStorage Storage Drivers page has information about the configuration details
of [each driver](http://libstorage.readthedocs.io/en/stable/user-guide/storage-providers),
including [VirtualBox](http://libstorage.readthedocs.io/en/stable/user-guide/storage-providers/#virtualbox).

### Logging
The `-l|--logLevel` option or `rexray.logLevel` configuration key can be set
to any of the following values to increase or decrease the verbosity of the
information logged to the console or the REX-Ray log file (defaults to
`/var/log/rexray/rexray.log`).

- panic
- fatal
- error
- warn
- info
- debug

### Troubleshooting
The command `rexray env` can be used to print out the runtime interpretation
of the environment, including configured properties, in order to help diagnose
configuration issues.

```
$ rexray env | grep DEFAULT | sort -r
REXRAY_MODULES_DEFAULT-DOCKER_TYPE=docker
REXRAY_MODULES_DEFAULT-DOCKER_SPEC=/etc/docker/plugins/rexray.spec
REXRAY_MODULES_DEFAULT-DOCKER_LIBSTORAGE_SERVICE=vfs
REXRAY_MODULES_DEFAULT-DOCKER_HOST=unix:///run/docker/plugins/rexray.sock
REXRAY_MODULES_DEFAULT-DOCKER_DISABLED=false
REXRAY_MODULES_DEFAULT-DOCKER_DESC=The default docker module.
REXRAY_MODULES_DEFAULT-ADMIN_TYPE=admin
REXRAY_MODULES_DEFAULT-ADMIN_HOST=unix:///var/run/rexray/server.sock
REXRAY_MODULES_DEFAULT-ADMIN_DISABLED=false
REXRAY_MODULES_DEFAULT-ADMIN_DESC=The default admin module.
LIBSTORAGE_INTEGRATION_VOLUME_OPERATIONS_CREATE_DEFAULT_TYPE=
LIBSTORAGE_INTEGRATION_VOLUME_OPERATIONS_CREATE_DEFAULT_SIZE=16
LIBSTORAGE_INTEGRATION_VOLUME_OPERATIONS_CREATE_DEFAULT_IOPS=
LIBSTORAGE_INTEGRATION_VOLUME_OPERATIONS_CREATE_DEFAULT_FSTYPE=ext4
LIBSTORAGE_INTEGRATION_VOLUME_OPERATIONS_CREATE_DEFAULT_AVAILABILITYZONE=
```

## Advanced Configuration
The following sections detail more advanced configurations and every last
aspect of how REX-Ray works and can be configured.

### Example with Modules
Modules enable a single REX-Ray instance to present multiple personalities or
volume endpoints, serving hosts that require access to multiple storage
platforms or the same platform with multiple default configurations.

#### Defining Modules
The following example demonstrates a basic configuration that presents two
modules using the VirtualBox driver: `default-docker` and `vb2-module`.

```yaml
rexray:
  logLevel: warn
  modules:
    default-docker:
      type: docker
      desc: The default docker module.
      host: unix:///run/docker/plugins/rexray.sock
      libstorage:
        service: virtualbox
      virtualbox:
        volumePath: $HOME/VirtualBox/Volumes
    vb2-module:
      type: docker
      desc: The second docker module.
      host: unix:///run/docker/plugins/vb2.sock
      libstorage:
        service: virtualbox
        integration:
          volume:
            operations:
              create:
                default:
                  size: 1
      virtualbox:
        volumePath: $HOME/VirtualBox/Volumes
libstorage:
  service: virtualbox
```

Whereas the previous examples did not use multiple modules and the example above
does, they both begin by defining the root section `rexray`. Unlike the previous
example, however, the majority of the `libstorage` section and all of the
`virtualbox` section are no longer at the root. Instead the section
`rexray.modules` is defined. The `modules` key in the `rexray` section is where
all modules are configured. Each key that is a child of `modules` represents the
name of a module.

!!! note "note"

    Please note that while most of the `libstorage` section has been relocated
    as a child of each module, the `libstorage.service` property is still
    defined at the root to activate [Auto Service Mode](#auto-service-mode) as
    a quick-start method of property configuring the embedded libStorage server.

The above example defines two modules:

 1. `default-module`

    This is a special module, and it's always defined, even if not explicitly
    listed. In the previous example without modules, the `libstorage` and
    `virtualbox` sections at the root actually informed the configuration of
    the implicit `default-docker` module. In this example the explicit
    declaration of the `default-docker` module enables several of its
    properties to be overridden and given desired values. The Advanced
    Configuration section has more information on
    [Default Modules](#default-modules).

 2. `vb2-module`

    This is a new, custom module configured almost identically to the
    `default-module` with the exception of a unique host address as defined
    by the module's `host` key.

Notice that both modules share many of the same properties and values. In fact,
when defining both modules, the top-level `libstorage` and `virtualbox` sections
were simply copied into each module as sub-sections. This is perfectly valid
as any configuration path that begins from the root of the REX-Ray
configuration file can be duplicated beginning as a child of a module
definition. This allows global settings to be overridden just for a specific
modules.

As noted, each module shares identical values with the exception of the module's
name and host. The host is the address used by Docker to communicate with
REX-Ray. The base name of the socket file specified in the address can be
used with `docker --volume-driver=`. With the current example the value of the
`--volume-driver` parameter would be either `rexray` of `vb2`.

#### Modules and Inherited Properties
There is also another way to write the previous example while reducing the
number of repeated, identical properties shared by two modules.

```yaml
rexray:
  logLevel: warn
  modules:
    default-docker:
      host: unix:///run/docker/plugins/rexray.sock
      libstorage:
        integration:
          volume:
            operations:
              create:
                default:
                  size: 1
    vb2:
      type: docker
libstorage:
  service: virtualbox
virtualbox:
  volumePath: $HOME/VirtualBox/Volumes
```

The above example may look strikingly different than the previous one, but it's
actually the same with just a few tweaks.

While there are still two modules defined, the second one has been renamed from
`vb2-module` to `vb2`. The change is a more succinct way to represent the same
intent, and it also provides a nice side-effect. If the `host` key is omitted
from a Docker module, the value for the `host` key is automatically generated
using the module's name. Therefore since there is no `host` key for the `vb2`
module, the value will be `unix:///run/docker/plugins/vb2.sock`.

Additionally, `virtualbox` sections from each module definition have been
removed and now only a single, global `virtualbox` section is present at the
root. When accessing properties, a module will first attempt to access a
property defined in the context of the module, but if that fails the property
lookup will resolve against globally defined keys as well.

Finally, the `libstorage` section has been completely removed from the `vb2`
module whereas it still remains in the `default-docker` section. Volume
creation requests without an explicit size value sent to the `default-docker`
module will result in 1GB volumes whereas the same request sent to the `vb2`
module will result in 16GB volumes (since 16GB is the default value for the
`libstorage.integration.volume.operations.create.default.size` property).

### Defining Service Endpoints
Multiple libStorage services can be defined which enable multiple drivers
and driver configurations to be leveraged. The following configuration is a bit
more in depth but takes advantage of the service endpoints through
`libstorage.server.services`. Each service is then assigned to a driver.

Once the services have been defined, it is then up to the modules to specify
which service to attach to. Notice how the `default-docker` module specifies
the `virtualbox` service as its `libstorage.service`. Any requests that come
through the UNIX socket and module will end up at this defined service.

```yaml
rexray:
  modules:
    default-docker:
      host:     unix:///run/docker/plugins/virtualbox.sock
      spec:     /etc/docker/plugins/virtualbox.spec
      libstorage:
        service: virtualbox
    scaleio-docker:
      type:     docker
      host:     unix:///run/docker/plugins/scaleio.sock
      spec:     /etc/docker/plugins/scaleio.spec
      libstorage:
        service: scaleio
libstorage:
  embedded: true
  server:
    services:
      scaleio:
        driver: scaleio
      virtualbox:
        driver: virtualbox
scaleio:
  endpoint: https://192.168.50.12/api
  insecure: true
  userName: admin
  password: Scaleio123
  systemName: cluster1
  protectionDomainName: pdomain
  storagePoolName: pool1
virtualbox:
  volumePath: /Users/your_user/VirtualBox Volumes
```

### Defining Remote Service Endpoints
The following examples are very similar to the previous. However, here we are
configuring a centralized REX-Ray controller which serves requests from
REX-Ray clients. You will notice a big difference here is that the server
removes the module definitions. This information is then transferred to the
client configuration.  Additionally we introduced the `host` and
`client.type` setting to define a remotable endpoint and to ensure client based
introspection does not take place on the server.

The following is the example server configuration.
```yaml
rexray:
  modules:
    default-docker:
      disabled: true
libstorage:
  embedded: true
  host: tcp://:7980
  client:
    type: controller
  server:
    services:
      scaleio:
        driver: scaleio
      virtualbox:
        driver: virtualbox
scaleio:
  endpoint: https://sio_gw_ip/api
  insecure: true
  userName: admin
  password: sio_pw
  systemName: cluster1
  protectionDomainName: pdomain
  storagePoolName: pool1
virtualbox:
  volumePath: /Users/your_user/VirtualBox Volumes
```

The client configuration is still rather simple. You can see that now the
`rexray.modules` configuration takes place here instead. This allows Docker
engines to run on the remote instances talking locally to the REX-Ray client
instance which makes use of the centralized REX-Ray server.

```yaml
rexray:
  modules:
    default-docker:
      host:     unix:///run/docker/plugins/virtualbox.sock
      spec:     /etc/docker/plugins/virtualbox.spec
      libstorage:
        service: virtualbox
    scaleio-docker:
      type:     docker
      host:     unix:///run/docker/plugins/scaleio.sock
      spec:     /etc/docker/plugins/scaleio.spec
      libstorage:
        service: scaleio
libstorage:
  host: tcp://rexray_server_ip:7980
```

### libStorage Configuration
REX-Ray embeds both the libStorage client as well as the libStorage server. For
information on configuring the following, please refer to the
[libStorage documentation](http://libstorage.readthedocs.io/en/stable):

 - [Volume options](http://libstorage.readthedocs.io/en/stable/user-guide/config/#volume-configuration)
   such as preemption, disabling operations, etc.
 - Fine-tuning [logging](http://libstorage.readthedocs.io/en/stable/user-guide/config/#logging-configuration)
 - [Configuring](http://libstorage.readthedocs.io/en/stable/user-guide/config/#driver-configuration)
   OS, integration, and storage drivers

### Data Directories
The first time REX-Ray is executed it will create several directories if
they do not already exist:

* `/etc/rexray`
* `/var/log/rexray`
* `/var/run/rexray`
* `/var/lib/rexray`

The above directories will contain configuration files, logs, PID files, and
mounted volumes. However, the location of these directories can also be
influenced with the environment variable `REXRAY_HOME`.

`REXRAY_HOME` can be used to define a custom home directory for REX-Ray.
This directory is irrespective of the actual REX-Ray binary. Instead, the
directory specified in `REXRAY_HOME` is the root directory where the REX-Ray
binary expects all of the program's data directories to be located.

For example, the following command sets a custom value for `REXRAY_HOME` and
then gets a volume list:

```
env REXRAY_HOME=/tmp/rexray rexray volume
```

The above command would produce a list of volumes and create the following
directories in the process:

* `/tmp/rexray/etc/rexray`
* `/tmp/rexray/var/log/rexray`
* `/tmp/rexray/var/run/rexray`
* `/tmp/rexray/var/lib/rexray`

The entire configuration section will refer to the global configuration file as
a file located inside of `/etc/rexray`, but it should be noted that if
`REXRAY_HOME` is set the location of the global configuration file can be
changed.

### Configuration Methods
There are three ways to configure REX-Ray:

* Command line options
* Environment variables
* Configuration files

The order of the items above is also the order of precedence when considering
options set in multiple locations that may override one another. Values set
via CLI flags have the highest order of precedence, followed by values set by
environment variables, followed, finally, by values set in configuration files.

### Configuration Files
There are two REX-Ray configuration files - global and user:

* `/etc/rexray/config.yml`
* `$HOME/.rexray/config.yml`

Please note that while the user configuration file is located inside the user's
home directory, this is the directory of the user that starts REX-Ray. And
if REX-Ray is being started as a service, then `sudo` is likely being used,
which means that `$HOME/.rexray/config.yml` won't point to *your* home
directory, but rather `/root/.rexray/config.yml`.

The next section has an example configuration with the default configuration.

### Configuration Properties
The section [Configuration Methods](#configuration-methods) mentions there are
three ways to configure REX-Ray: config files, environment variables, and the
command line. However, this section will illuminate the relationship between the
names of the configuration file properties, environment variables, and CLI
flags.

Here is a sample REX-Ray configuration:

```yaml
rexray:
  logLevel: warn
libstorage:
  service: virtualbox
virtualbox:
  volumePath: $HOME/VirtualBox/Volumes
```

The properties `rexray.logLevel`, `libstorage.service`, and
`virtualbox.volumePath` are strings. These values can also be set via
environment variables or command line interface (CLI) flags, but to do so
requires knowing the names of the environment variables or CLI flags to use.
Luckily those are very easy to figure out just by knowing the property names.

All properties that might appear in the REX-Ray configuration file
fall under some type of heading. For example, take the configuration above:

The rule for environment variables is as follows:

  * Each nested level becomes a part of the environment variable name followed
    by an underscore `_` except for the terminating part.
  * The entire environment variable name is uppercase.

Nested properties follow these rules for CLI flags:

  * The root level's first character is lower-cased with the rest of the root
    level's text left unaltered.
  * The remaining levels' first characters are all upper-cased with the the
    remaining text of that level left unaltered.
  * All levels are then concatenated together.
  * See the verbose help for exact global flags using `rexray --help -v`
    as they may be chopped to minimize verbosity.

The following table illustrates the transformations:

Property Name | Environment Variable | CLI Flag
--------------|----------------------|-------------
`rexray.logLevel`    | `REXRAY_LOGLEVEL`    | `--logLevel`
`libstorage.service`   | `LIBSTORAGE_SERVICE`   | `--libstorageService`
`virtualbox.volumePath`    | `VIRTUALBOX_VOLUMEPATH`   | `--virtualboxVolumePath`

### Logging Configuration
The REX-Ray log level determines the level of verbosity emitted by the
internal logger. The default level is `warn`, but there are three other levels
as well:

 Log Level | Description
-----------|-------------
`error`    | Log only errors
`warn`     | Log errors and anything out of place
`info`     | Log errors, warnings, and workflow messages
`debug`    | Log everything

For example, the following two commands may look slightly different, but they
are functionally the same, both printing a list of volumes using the `debug`
log level:

*Use the `debug` log level - Example 1*
```bash
rexray volume -l debug
```

*Use the `debug` log level - Example 2*
```bash
env REXRAY_LOGLEVEL=debug rexray volume
```
