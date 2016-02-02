#Automation

Push Button, Receive REX-Ray...

---

## Overview
Because REX-Ray is simple to install using the `curl` script, installing using
configuration management tools is relatively easy as well. There are a few things
that can be tricky though - most notably writing out the configuration file.

We have provided some examples with common configuration management and
orchestration tools below.  Optionally, Docker is also listed in some examples.

<br>
## Ansible
ToDo

<br>
## AWS CloudFormation
With CloudFormation, the installation of the latest Docker and REX-Ray binaries
can be passed to the orchestrator using the 'UserData' property in a
CloudFormation template. Obviously this could also be passed in as raw userdata
from the AWS GUI... but that wouldn't really be automating things, now would it?

```json
      "Properties": {
        "UserData"       : { "Fn::Base64" : { "Fn::Join" : ["", [
             "#!/bin/bash -xe\n",
             "apt-get update\n",
             "apt-get -y install python-setuptools\n",
             "easy_install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz\n",
             "ln -s /usr/local/lib/python2.7/dist-packages/aws_cfn_bootstrap-1.4-py2.7.egg/init/ubuntu/cfn-hup /etc/init.d/cfn-hup\n",
             "chmod +x /etc/init.d/cfn-hup\n",
             "update-rc.d cfn-hup defaults\n ",
             "service cfn-hup start\n",
             "/usr/local/bin/cfn-init --stack ",{ "Ref":"AWS::StackName" }," --resource RexrayInstance "," --configsets InstallAndRun --region ",{"Ref":"AWS::Region"},"\n",

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
        ]]}}        
      }
    },
```

<br>
## CFEngine
ToDo

<br>
## Chef
ToDo

<br>
## Docker Machine (VirtualBox)
SSH can be used to remotely deploy REX-Ray to a Docker Machine. While the
following example used VirtualBox as the underlying storage platform, the
provided `config.yml` file *could* be modified to use any of the supported
drivers.

### Step 1 - Install REX-Ray
SSH into the Docker machine and install REX-Ray.
```bash
$ docker-machine ssh testing1 \
 "curl -sSL https://dl.bintray.com/emccode/rexray/install | sh -"
```

### Step 2 - Install udev Extras (Optional)
This step is not needed for boot2docker 1.10+, but for older versions the
`udev-extra` package needs to be installed.
```bash
$ docker-machine ssh testing1 \
  "wget http://tinycorelinux.net/6.x/x86_64/tcz/udev-extra.tcz \
    && tce-load -i udev-extra.tcz && sudo udevadm trigger"
```

### Step 3 - Configure REX-Ray
Create a basic REX-Ray configuration file inside the Docker machine.

**Note**: It is recommended to replace the `volumePath` parameter with the
local path VirtualBox uses to store its virtual media disk files.
```bash
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
```

### Step 4 - Start the REX-Ray Service
Finally, start the REX-Ray service inside the Docker machine.
```bash
$ docker-machine ssh testing1 "sudo rexray start"
```

<br>
## OpenStack Heat
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

<br>
## Puppet
ToDo

<br>
## Salt
ToDo

<br>
## Vagrant
ToDo
