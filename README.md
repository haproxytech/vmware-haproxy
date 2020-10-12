# VMware + HAProxy

This project enables customers to build an OSS virtual appliance with HAProxy and its [Data Plane API](https://www.haproxy.com/documentation/dataplaneapi/latest) designed to enable Kubernetes workload management with Project Pacific on vSphere 7.

* [Download](#download)
* [Deploy](#deploy)
* [Build](#build)
* [Test](#test)

## Download

The latest version of the appliance OVA is always available from the [releases](https://github.com/haproxytech/vmware-haproxy/releases) page:

| Version | SHA256 |
|---|---|
| [v0.1.8](https://cdn.haproxy.com/download/haproxy/vsphere/ova/vmware-haproxy-v0.1.8.ova) | `eac73c1207c05aeeece6d17dd1ac1dde0e557d94812f19082751cfb6925ad082` |

## Deploy

Please see the [_vSphere with Tanzu Quick Start Guide_](https://core.vmware.com/resource/vsphere-tanzu-quick-start-guide) on how to deploy the appliance on vSphere with Tanzu.

## Build

Documentation on how to build the appliance is available [here](./docs/how-to-build-ova.md).

## Test

Documentation on how to test the components in the appliance with Docker containers is available [here](./docs/how-to-container.md).
