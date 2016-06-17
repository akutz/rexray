# Storage Providers

Connecting storage and platforms...

---

## Overview
The list of storage providers supported by REX-Ray now mirrors the validated
storage platform table from the [libStorage](https://github.com/emccode/libstorage)
project.

!!! note "note"

    The initial REX-Ray 0.4.x release omits support for several,
    previously verified storage platforms. These providers will be
    reintroduced incrementally, beginning with 0.4.1. If an absent driver
    prevents the use of REX-Ray, please continue to use 0.3.3 until such time
    the storage platform is introduced in REX-Ray 0.4.x. Instructions on how
    to install REX-Ray 0.3.3 may be found
    [here](./installation.md#rex-ray-033) and documentation and
    configuration details can be found
    [here](http://rexray.readthedocs.io/en/0.3.3).

## Supported Providers
The following storage providers and platforms are supported by REX-Ray. Please
refer to the libStorage drivers for these providers which are linked directly
from the list below.

Provider              | Storage Platform(s)
----------------------|--------------------
EMC | [ScaleIO](http://libstorage.readthedocs.io/en/stable/user-guide/storage-providers/#scaleio), [Isilon](http://libstorage.readthedocs.io/en/stable/user-guide/storage-providers/#isilon)
[Oracle VirtualBox](http://libstorage.readthedocs.io/en/stable/user-guide/storage-providers/#virtualbox) | Virtual Media

## Coming Soon
Support for the following storage providers will be reintroduced in upcoming
releases as libStorage introduces these drivers:

Provider              | Storage Platform(s)
----------------------|--------------------
Amazon EC2 | EBS
Google Compute Engine (GCE) | Disk
Open Stack | Cinder
Rackspace | Cinder
EMC | XtremIO, VMAX
