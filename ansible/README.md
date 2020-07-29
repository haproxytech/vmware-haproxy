# Ansible Configuration for the HAProxy OVA

The OVA guest is customized using Ansible. As such, some of the playbooks are opinionated to the Guest OS selected.
Configuration parameters for the Ansible scripts are defined in ../packer.json

## Playbooks

The Ansible playbooks are indexed in playbook.yml here in the root and each playbook has its own folder in /roles

### cloudinit

Cloud-init is the way in which the OVA is configured on first boot.
This playbook adds the cloud-init packages and VMware datasource.
It then runs a configuration script and cleans up

### common

Common defines the core set of OS dependencies to add to the distribution and allows for some tweaks to the guest config
If additional OS dependencies should be installed, they can be added to /common/defaults/main.yaml

### haproxy

The haproxy playlist provides the following functions:

- Provides the default haproxy.cfg to be copied to the appliance
- Ensure that haproxy starts after the cloud-init boot stage
- Install the dataplane API (see ../packer.json)
- Configure and enable haproxy as a systemd service

### pki

The pki playlist copies two scripts into the guest at /usr/local/bin:

- new-ca.sh will create a new self-signed certificate authority
- new-cert.sh will create a new certificate

### sysprep

The sysprep playbook configures a bunch of guest OS internals
It's mostly concerned with restoring the OVA to a pristine state following the prior configuration steps

- Sets /etc/hostname and resets /etc/hosts
- Reset the IP tables to remove any firewall settings
- Reset /etc/machine-id and audit logs
- Remove SSH host keys and authorized users
- Clean up caches created by installing OS dependencies
- Clean cloud-init dependencies and temp files
- Clean shell history and /var/log
