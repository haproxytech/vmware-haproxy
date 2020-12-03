# A Guide to Virtual IP management in the HAProxy Appliance

## Summary

HAProxy setups are often configured to load-balance traffic on a single
endpoint, optionally using a floating IP in a Highly Available configuration.

This HAProxy appliance is designed to allow HAProxy to load balance traffic
across a range of Virtual IPs (VIP). This uses a capability of Linux called
AnyIP which allows the appliance to respond to all IP addresses within
specified ranges.

This capability works in symbiosis with HAProxy and the external control plane
managing HAProxy configuration. In the case of vSphere with Tanzu, the
Supervisor Cluster is that control plane. The external control plane manages
a pool of IPs that it can allocate to various services. When a new service is
defined, the external control plane configures HAProxy with a frontend
definition containing an IP it allocates from the pool, which should - if
everything is correctly configured - fall within a VIP range defined using
AnyIP.

## How does AnyIP work?

AnyIP works using the local routing table in Linux, defining Virtual IPs the
appliance can use. You can view the routing table with the following command:

```shell
ip route list table local
```

By adding an entry to the routing table containing an IP range in CIDR notation
assigned to the loopback inteface, the appliance will immediately start
responding to all IPs in the range. You can experiment with this in a Linux VM using:

```shell
ip route add local <range> dev lo
ping <IP in the range>
```

Removing the range is achieved by:

```shell
ip route delete local <range>
```

Note that these examples are purely for illustration. You don't have to manually
configure the routing tables in the appliance. That is managed for you
(see below).

## How do I configure VIP ranges in the appliance?

When you deploy the appliance, it will ask you for one or more VIP ranges which
it will then persist in a configuration file
[`/etc/vmware/anyip-routes.cfg`](../ansible/roles/vmware/files/etc/vmware/anyip-routes.cfg)
(see [video clip here](https://youtu.be/wfYDDbBJHfM?t=920)). The appliance will
then automatically ensure that the local routing table in the appliance is
kept in sync with this file. It does this using a simple utility running
as a systemd service which you can view using `systemctl status anyip-routes`.

Once the appliance is up and running, you can test that the AnyIP is working
by pinging IP addresses in the configured VIP ranges. You can do this from
within the appliance or outside. It should respond to all of them.

If you want to extend the VIP ranges of the appliance, you can modify the
[`/etc/vmware/anyip-routes.cfg`](../ansible/roles/vmware/files/etc/vmware/anyip-routes.cfg)
file and that will automatically update the routing tables. However, please
note that the external control plane managing the configuration of the HAProxy
instance *also* needs to be told that it can allocate IPs out of this new
range (see above).

## What precautions do I need to consider?

You need to be careful using AnyIP because the appliance will immediately
respond to *every* IP in the range. That means that anything else on the
network that has been assigned an IP in that range could be impacted. A
common misconfiguration is to define a range that overlaps with a gateway
or nameserver.

It also means that you cannot assume that just because a VIP is pingable,
that HAProxy has a frontend configured and defined for it. The way to test
that HAProxy is serving traffic is to use a utility like `curl`.

Note that HAProxy itself has no knowledge of the AnyIP configuration, but
does have a dependency on it. HAProxy will not start if it has a frontend
defined with an IP that it cannot bind. In other words, all frontend IPs
configured in HAProxy need to be within a defined VIP range.

## Troubleshooting

AnyIP is a fairly simple concept, so there's not too many things to check

- Check that you can ping VIPs from a shell within the appliance

- Ensure that the VIP ranges you want are in 
[`/etc/vmware/anyip-routes.cfg`](../ansible/roles/vmware/files/etc/vmware/anyip-routes.cfg)
and there are no typos

- Check that the VIP ranges you want are present in the local routing table:

    ```shell
    ip route list table local

    # you should see an entry that looks like this:
    local 192.168.20.128/25 dev lo scope host
    ```

- Make sure that DHCP is not assigning IP addresses in the same range

- Make sure the VIP ranges don't overlap with any infrastructure IPs, such as a gateway or nameserver

- Make sure that the anyip-routes service is enabled and running:

    ```shell
    systemctl status anyip-routes
    ```

- Check the output of the anyip-routes service to see if anything unexpected happened:

    ```shell
    journalctl -xeu anyip-routes
    ```

- Make sure that the configuration on the control plane managing HAProxy
frontends agrees with the configuration in the appliance. In the case of
vSphere with Tanzu Workload Management, it's the field marked "IP Address
Ranges for Virtual Servers" (see [video clip here](https://youtu.be/wfYDDbBJHfM?t=1947)).
The ranges in here should be the same or a subset of the ranges in
[`/etc/vmware/anyip-routes.cfg`](../ansible/roles/vmware/files/etc/vmware/anyip-routes.cfg).

## Advanced

If you want to dive deeper into the plumbing of the appliance VIP management,
you can look at [`/var/lib/vmware/anyiproutectl.sh`](../ansible/roles/vmware/files/var/lib/vmware/anyiproutectl.sh)
and [`/var/lib/vmware/routetablectl.sh`](../ansible/roles/vmware/files/var/lib/vmware/routetablectl.sh).