#!/bin/bash
set -x

# Simple script that reads the CIDRs from /etc/haproxy/anyip.cfg and sets up anyip routes
# It expects one CIDR per line and handles comments prefixed with #
# Used by anyip-routes systemd service

IFS=$'\n' read -d '' -r -a lines < /etc/haproxy/anyip.cfg
for line in "${lines[@]}";
do
    if [ "$line" != "" ] && [ "${line:0:1}" != "#" ]; then
        ip route add local "$line" dev lo
    fi
done
