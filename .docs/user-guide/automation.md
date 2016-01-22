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
You can use the Docker Machine ssh capabilities to remotely install REX-Ray.
 We are showing the VirtualBox based configuration, but you can update the
 `config.yml` file as displayed below per the correct driver.
 The only suggestion for VirtualBox would be to replace the `volumePath`
 parameter with the local path that VirtualBox would be storing your virtual
 media disks.
```bash
docker-machine ssh testing1 \
 "curl -sSL https://dl.bintray.com/emccode/rexray/install | sh -"

// not needed for boot2docker 1.10+
docker-machine ssh testing1 \
  "wget http://tinycorelinux.net/6.x/x86_64/tcz/udev-extra.tcz \
    && tce-load -i udev-extra.tcz && sudo udevadm trigger"

docker-machine ssh testing1 \
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

docker-machine ssh testing1 "sudo rexray start"
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
