#!/usr/bin/env bash
# Patch the base OS and install the packages every instance in the fleet needs.
set -euo pipefail

log() { printf '[10-system-baseline] %s\n' "$*"; }

log "applying all available OS updates"
dnf -y upgrade --refresh

log "installing audit and time-sync packages"
dnf -y install audit chrony logrotate

log "enabling time sync, audit and the SSM agent"
systemctl enable chronyd.service auditd.service amazon-ssm-agent.service

dnf clean all
rm -rf /var/cache/dnf/*
log "done"
