# Installation

Getting the bits, bit by bit

---

## Overview
There are several different methods available for installing `REX-Ray`.

## Manual Installs
Manual installations are in contrast to batch, automated installations.

### Install via curl
The following command will download the most recent, stable build of `REX-Ray`
and install it to `/usr/bin/rexray.` On Linux systems `REX-Ray` will also be
registered as either a SystemD or SystemV service.

```shell
curl -sSL https://dl.bintray.com/emccode/rexray/install | sh -
```

### Install a pre-built binary
There are also pre-built binaries available for the various release types.

Version  | Description
---------|------------
[Unstable](https://dl.bintray.com/emccode/rexray/unstable/latest/) | The most up-to-date, bleeding-edge, and often unstable REX-Ray binaries.
[Staged](https://dl.bintray.com/emccode/rexray/staged/latest/) | The most up-to-date, release candidate REX-Ray binaries.
[Stable]((https://dl.bintray.com/emccode/rexray/stable/latest/)) | The most up-to-date, stable REX-Ray binaries.

### Build and install from source
`REX-Ray` is also fairly simple to build from source, especially if you have `Docker` installed:

```shell
SRC=$(mktemp -d 2> /dev/null || mktemp -d -t rexray 2> /dev/null) && cd $SRC && docker run --rm -it -v $SRC:/usr/src/rexray -w /usr/src/rexray golang:1.5.1 bash -c "git clone https://github.com/emccode/rexray.git . && make build-all”
```

If you'd prefer to not use `Docker` to build `REX-Ray` then all you need is Go 1.5:

```shell
# clone the rexray repo
git clone https://github.com/emccode/rexray.git

# change directories into the freshly-cloned repo
cd rexray

# build rexray
make build-all
```

After either of the above methods for building `REX-Ray` there should be a `.bin` directory in the current directory, and inside `.bin` will be binaries for Linux-i386, Linux-x86-64,
and Darwin-x86-64.

```shell
[0]akutz@poppy:tmp.SJxsykQwp7$ ls .bin/*/rexray
-rwxr-xr-x. 1 root 14M Sep 17 10:36 .bin/Darwin-x86_64/rexray*
-rwxr-xr-x. 1 root 12M Sep 17 10:36 .bin/Linux-i386/rexray*
-rwxr-xr-x. 1 root 14M Sep 17 10:36 .bin/Linux-x86_64/rexray*
```

## Automated Installs
Because REX-Ray is simple to install using the `curl` script, installation
using configuration management tools is relatively easy as well. However,
there are a few areas that may prove to be tricky, such as writing the
configuration file.

This section provides examples of automated installations using common
configuration management and orchestration tools.

### Ansible
With Ansible, installing the latest REX-Ray binaries can be accomplished by
including the `codenrhoden.rexray` role from Ansible Galaxy.  The role accepts
all the necessary variables to properly fill out your `config.yml` file.

Install the role from Galaxy:

```shell
ansible-galaxy install codenrhoden.rexray
```

Example playbook for installing REX-Ray on GCE Docker hosts:

```yaml
- hosts: gce_docker_hosts
  roles:
  - { role: codenrhoden.rexray,
      rexray_service: true,
      rexray_storage_drivers: [gce],
      rexray_gce_keyfile: "/opt/gce_keyfile" }
```

Run the playbook:

```shell
ansible-playbook -i <inventory> playbook.yml
```

### AWS CloudFormation
With CloudFormation, the installation of the latest Docker and REX-Ray binaries
can be passed to the orchestrator using the 'UserData' property in a
CloudFormation template. While the payload could also be provided as raw user
data via the AWS GUI, it would not sustain scalable automation.

```json
"Properties": {
  "UserData": {
    "Fn::Base64": {
      "Fn::Join": ["", [
        "#!/bin/bash -xe\n",
        "apt-get update\n",
        "apt-get -y install python-setuptools\n",
        "easy_install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz\n",
        "ln -s /usr/local/lib/python2.7/dist-packages/aws_cfn_bootstrap-1.4-py2.7.egg/init/ubuntu/cfn-hup /etc/init.d/cfn-hup\n",
        "chmod +x /etc/init.d/cfn-hup\n",
        "update-rc.d cfn-hup defaults\n ",
        "service cfn-hup start\n",
        "/usr/local/bin/cfn-init --stack ", {
          "Ref": "AWS::StackName"
        }, " --resource RexrayInstance ", " --configsets InstallAndRun --region ", {
          "Ref": "AWS::Region"
        }, "\n",

        "# Install the latest Docker..\n",
        "/usr/bin/curl -o /tmp/install-docker.sh https://get.docker.com/\n",
        "chmod +x /tmp/install-docker.sh\n",
        "/tmp/install-docker.sh\n",

        "# add the ubuntu user to the docker group..\n",
        "/usr/sbin/usermod -G docker ubuntu\n",

        "# Install the latest REX-ray\n",
        "/usr/bin/curl -ssL -o /tmp/install-rexray.sh https://dl.bintray.com/emccode/rexray/install\n",
        "chmod +x /tmp/install-rexray.sh\n",
        "/tmp/install-rexray.sh\n",
        "chgrp docker /etc/rexray/config.yml\n",
        "reboot\n"
      ]]
    }
  }
}
```

### Docker Machine (VirtualBox)
SSH can be used to remotely deploy REX-Ray to a Docker Machine. While the
following example used VirtualBox as the underlying storage platform, the
provided `config.yml` file *could* be modified to use any of the supported
drivers.

1. SSH into the Docker machine and install REX-Ray.

        $ docker-machine ssh testing1 \
        "curl -sSL https://dl.bintray.com/emccode/rexray/install | sh -"

2. Install the udev extras package. This step is only required for versions of
   boot2docker older than 1.10.

        $ docker-machine ssh testing1 \
        "wget http://tinycorelinux.net/6.x/x86_64/tcz/udev-extra.tcz \
        && tce-load -i udev-extra.tcz && sudo udevadm trigger"

3. Create a basic REX-Ray configuration file inside the Docker machine.

    **Note**: It is recommended to replace the `volumePath` parameter with the
    local path VirtualBox uses to store its virtual media disk files.

        $ docker-machine ssh testing1 \
            "sudo tee -a /etc/rexray/config.yml << EOF
            rexray:
              storageDrivers:
              - virtualbox
              volume:
                mount:
                  preempt: false
            virtualbox:
              endpoint: http://10.0.2.2:18083
              tls: false
              volumePath: /Users/YourUser/VirtualBox Volumes
              controllerName: SATA
            "

4. Finally, start the `REX-Ray` service inside the Docker machine.

        $ docker-machine ssh testing1 "sudo rexray start"

### OpenStack Heat
Using OpenStack Heat, in the HOT template format (yaml):

```yaml
resources:
  my_server:
    type: OS::Nova::Server
    properties:
      user_data_format: RAW
      user_data:
        str_replace:
          template: |
            #!/bin/bash -v
            /usr/bin/curl -o /tmp/install-docker.sh https://get.docker.com
            chmod +x /tmp/install-docker.sh
            /tmp/install-docker.sh
            /usr/sbin/usermod -G docker ubuntu
            /usr/bin/curl -ssL -o /tmp/install-rexray.sh https://dl.bintray.com/emccode/rexray/install
            chmod +x /tmp/install-rexray.sh
            /tmp/install-rexray.sh
            chgrp docker /etc/rexray/config.yml
          params:
            dummy: ""
```

### Vagrant
Using Vagrant is a great option to deploy pre-configured `REX-Ray` nodes,
including Docker, using the VirtualBox driver. All volume requests are handled
using VirtualBox's Virtual Media.

A Vagrant environment and instructions using it are provided
[here](https://github.com/emccode/vagrant/tree/master/rexray).
