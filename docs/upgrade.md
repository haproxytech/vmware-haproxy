# Upgrade

This document describes the recommended upgrade process. The upgrade process generally works by swapping out the currently deployed VM with a new VM. The cluster will automatically reconcile the routes assuming all current configuration is identical.

## Restrictions

- If upgrading to vSphere 7.0.1, then HAProxy _must_ be updated to v0.1.9 or later.
- Upgrade without downtime is currently not supported.
- Migration between network topologies during upgrade is not supported.

## Prerequisites

- A currently running HAProxy VM
- A target version greater than the current version
- The ability to deploy VMs

## Steps

- Confirm you have enough CPU and disk space for the new VM and the old VM.
- Find and copy `/etc/haproxy/server.crt` and `/etc/haproxy/server.key` out of the instance. Optionally copy the CA files if you need them.
- If you have made any customizations to `/etc/haproxy/haproxy.cfg` or `/etc/haproxy/dataplaneapi.cfg` then make backups or notes of those customizations at this time.
- Deploy the new VM with an _identical_ configuration as the currently running instance using the existing HAProxy `server.crt` and `server.key` as inputs.
- Power down the old instance. You can revert back to this instance if something goes wrong with the upgrade.
- Optionally add resource reservations for the new VM.
- Power on the new instance.
- Verify the configuration on the new VM. See [verification](#verification) below on the minimum recommended checks to perform.
- If you're confident the upgrade has succeeded, remove the old VM.

## Verification

After a short time to deploy, you should be able to log into the new instance. Verify services are up and running and the configuration is correct.

Minimum verification steps should include the following:

Verify haproxy and dataplaneapi services have started and are running:

```
   systemctl status haproxy
   systemctl status dataplaneapi
```

Re-apply any custom changes to the `haproxy.cfg` or `dataplaneapi.cfg` files and restart the services.

On the service side, ensure service-type load balancer external IPs are reachable on both the supervisor and Tanzu clusters.

Finally, ensure the cluster starts programming routes via dataplaneapi into `haproxy.cfg` and spawning a new HAProxy processes. If this happens, you should see the `haproxy.cfg` grow in size as routes are added. This make take some time if the cluster operator is in an exponential backoff loop. As a rule of thumb, if you don't have routes within 5 minutes then something is probably wrong. Double check dataplane api logs to ensure it is processing traffic.

```
   journalctl -xeu dataplaneapi
```

## Recovery

If things don't go according to plan and the upgrade cannot continue, then power off the new appliance and power on the old appliance. It is _very_ important to not run both appliances on the same network because they will ARP for the same IP addresses causing flaky connections.
