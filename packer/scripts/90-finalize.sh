#!/usr/bin/env bash
# Removes build-time credentials and state so that every instance launched from this AMI starts
# clean: no SSH keys, no host keys, no cached cloud-init data, no shell history.
set -euo pipefail

log() { printf '[90-finalize] %s\n' "$*"; }

log "removing build SSH keys and disabling sshd at boot"
rm -f /home/ec2-user/.ssh/authorized_keys /root/.ssh/authorized_keys
rm -f /etc/ssh/ssh_host_*
systemctl disable sshd.service

log "removing temporary build artifacts and shell history"
rm -rf /tmp/golden /tmp/sample-app
rm -f /root/.bash_history /home/ec2-user/.bash_history

log "resetting cloud-init so user data runs on the next boot"
cloud-init clean --logs --seed

log "truncating logs and machine identity"
find /var/log -type f -name '*.gz' -delete
find /var/log -type f -exec truncate -s 0 {} +
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
truncate -s 0 /etc/machine-id

dnf clean all
rm -rf /var/cache/dnf/*
sync
log "done"
