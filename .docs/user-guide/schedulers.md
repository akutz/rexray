# Schedulers

Scheduling storage one resource at a time...

---

## Overview
This page reviews the schedulers and container runtimes supported by REX-Ray.
Other platforms can be used with REX-Ray as a service as long as they adhere to
the `Docker Volume Plugin` [specification](https://docs.docker.com/engine/extend/plugins_volume/).

## Configuring REX-Ray
You should consult the configuration section of the user-guide for more details
relating to configuring REX-Ray. Here we focus on specific settings that can be
configured for integrating REX-Ray with container schedulers and runtimes.
These are covered in the [Volume Configuration](http://libstorage.readthedocs.io/en/stable/user-guide/config/#volume-properties)
section of the libStorage documentation.

The following is a valid example of using an integration property along
with the VirtualBox driver. The `size` setting here ensures that all new volumes
are created with a size of `1 GB`. Make sure to replace the `$PATH` variable in
`volumePath` is a valid path where VirtualBox is running from.

```yaml
libstorage:
  service: virtualbox
  integration:
    volume:
      operations:
        create:
          default:
            size: 1
virtualbox:
  volumePath: $PATH/VirtualBox Volumes
```


## Starting REX-Ray
Any approach to integrate with REX-Ray through HTTP/JSON requires that it be
running as a service. You can do this easily after it has been configured by
running the following command.

```sh
$ /usr/bin/rexray start
Starting REX-Ray...SUCCESS!

  The REX-Ray daemon is now running at PID 11309. To
  shutdown the daemon execute the following command:

    sudo /usr/bin/rexray stop
```

This should expose one or multiple UNIX socket endpoints as Docker compatible
plugin endoints. Each UNIX socket defined under `/run/docker/plugins` and
spec file defined under `/etc/docker/plugins` is engaged during the
Docker plugin initialization process.

```sh
$ ls /run/docker/plugins/
scaleio.sock  virtualbox.sock
```


## Docker
REX-Ray 0.4+ is compatible with Docker 1.10+.

The [libStorage Docker documentation](http://libstorage.readthedocs.io/en/stable/user-guide/schedulers/#docker)
can be found in the libStorage project which includes more information about
`integration` settings that can be defined for this interface.

### Volume Management
With Docker version 1.12, the `volume` sub-command looks as follows.

```sh
$ docker volume

Usage:	docker volume [OPTIONS] [COMMAND]

Manage Docker volumes

Commands:
  create                   Create a volume
  inspect                  Return low-level information on a volume
  ls                       List volumes
  rm                       Remove a volume
```

#### List Volumes
The list command will review a list of avaialble volumes that have been
discovered through the plugin endpoints. Each volume name is considered
unique, so the volume names must be unique across all drivers. The list of
volumes is returned based on the backend the response from the backend
storage platform, with the exception of `local`.

```sh
$ docker volume ls
DRIVER              VOLUME NAME
local               local1
scaleio             Volume-001
virtualbox          vbox1
```

#### Inspect Volume
The inspect command can be used to retrieve Docker related details as well as
storage platform details for a volume. The fields listed under `Status` are
all being returned by REX-Ray including things like `Size in GB`, `Volume Type`,
and `Availability Zone`.

The `Scope` parameter ensures that when the `Volume Driver` specified is
reviewed across multiple Docker hosts, the volumes with `global` defined
are all interpreted as the same volume. This reduces the unnecessary calls
if something like Docker Swarm is connected to hosts with REX-Ray configured.

```sh
$ docker volume inspect vbox1
[
    {
        "Name": "vbox1",
        "Driver": "virtualbox",
        "Mountpoint": "",
        "Status": {
            "availabilityZone": "",
            "fields": null,
            "iops": 0,
            "name": "vbox1",
            "server": "virtualbox",
            "service": "virtualbox",
            "size": 8,
            "type": ""
        },
        "Labels": {},
        "Scope": "global"
    }
]
```

#### Create Volume
The create volume allow you to create new volumes on the storage platform. These
volumes are immediately available to be consumed. It also includes the
additional `--opt` parameter where you can specify extra values.

```sh
$ docker volume create --driver=virtualbox --name=vbox2 --opt=size=2
vbox2
```

Additional valid options are specified below.

option|description
------|-----------
size|Size in GB
IOPS|IOPS
volumeType|Type of Volume or Storage Pool
volumeName|Create from an existing volume name
volumeID|Create from an existing volume ID
snapshotName|Create from an existing snapshot name
snapshotID|Create from an existing snapshot ID


#### Remove Volume
Removing a volume can be done once the volume is no longer in use by an started
or stopped containers. This can be done by deleting any containers
that are or have made use of the volume.

```sh
$ docker volume rm vbox2
```

### Containers with Volumes
Running a container with volumes is easy. Review the [applications](./application/)
section where we discuss some common applications and how to properly run
other containers with volumes.


## Mesos
In Mesos the frameworks are responsible for receiving requests from
consumers and then proceeding to schedule and manage tasks.  Some frameworks
are open to run any workload for sustained periods of time (ie. Marathon), and
others are use case specific (ie. Cassandra).  Further than this, frameworks can
receive requests from other platforms or schedulers instead of consumers such as
Cloud Foundry, Kubernetes, and Swarm.

Once frameworks decide to accept resource offers from Mesos, tasks are launched
to support workloads.  These tasks eventually make it down to Mesos agents
to spin up containers.  

REX-Ray provides the ability for any agent receiving a task to request
storage be orchestrated for that task.  

There are two primary methods that REX-Ray functions with Mesos.  It is up to
the framework to determine which is most appropriate.  Mesos (0.26) has two
containerizer options for tasks, `Docker` and `Mesos`.

### Docker Containerizer with Marathon
If the framework uses the Docker containerizer, it is required that both
`Docker` and REX-Ray are configured ahead of time and working.  It is best to
refer to the [Docker](#docker) page for more
information.  Once this is configured across all appropriate agents, the
following is an example of using Marathon to start an application with external
volumes.

```json
{
	"id": "nginx",
	"container": {
		"docker": {
			"image": "million12/nginx",
			"network": "BRIDGE",
			"portMappings": [{
				"containerPort": 80,
				"hostPort": 0,
				"protocol": "tcp"
			}],
			"parameters": [{
				"key": "volume-driver",
				"value": "rexray"
			}, {
				"key": "volume",
				"value": "nginx-data:/data/www"
			}]
		}
	},
	"cpus": 0.2,
	"mem": 32.0,
	"instances": 1
}
```

### Mesos Containerizer with Marathon
`Mesos 0.23+` includes modules that enables extensibility for different
portions the architecture.  The [dvdcli](https://github.com/emccode/dvdcli) and
[mesos-module-dvdi](https://github.com/emccode/mesos-module-dvdi) projects are
required for this method to enable external volume support with the native
containerizer.

The following is a similar example to the one above.  But here we are specifying
to use the the native containerizer and requesting volumes through The `env`
section.

```json
{
  "id": "hello-play",
  "cmd": "while [ true ] ; do touch /var/lib/rexray/volumes/test12345/hello ; sleep 5 ; done",
  "mem": 32,
  "cpus": 0.1,
  "instances": 1,
  "env": {
    "DVDI_VOLUME_NAME": "test12345",
    "DVDI_VOLUME_DRIVER": "rexray",
    "DVDI_VOLUME_OPTS": "size=5,iops=150,volumetype=io1,newfstype=xfs,overwritefs=true"
  }
}
```

This example also comes along with a couple of important settings for the
native method.  This is libStorage portion of a `config.yml` file that can be
used. Setting the `volume.operations.mount.preempt` flag ensures any host can
preempt control of a volume from other hosts.  Refer to the
[User-Guide](./config.md#preemption) for more information on preempt.  The
`volume.operations.unmount.ignoreusedcount` ensures that `mesos-module-dvdi` is
authoritative when it comes to deciding when to unmount volumes.

Note: `libstorage.volume.operations.remove.disable` is a flag to disable the
ability for the scheduler to remove volumes. With Mesos + Docker 1.9.1 or below
this setting is suggested.

```yaml
libstorage:
  service: virtualbox
  integration:
    volume:
      operations:
        mount:
          preempt: true
        unmount:
          ignoreusedcount: true
        remove:
          disable: true
```
