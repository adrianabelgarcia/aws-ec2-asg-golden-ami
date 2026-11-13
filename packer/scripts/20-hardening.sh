#!/usr/bin/env bash
# OS hardening baseline: kernel parameters, module blacklist, SSH daemon policy, audit rules,
# login defaults and file permissions. Each change is idempotent so the script can be re-run.
set -euo pipefail

log() { printf '[20-hardening] %s\n' "$*"; }

log "kernel network and information-leak parameters"
install -o root -g root -m 0644 "${GOLDEN_FILES}/sysctl/90-golden-hardening.conf" \
  /etc/sysctl.d/90-golden-hardening.conf
sysctl --system >/dev/null

log "disabling unused filesystems and protocols"
install -o root -g root -m 0644 "${GOLDEN_FILES}/modprobe/golden-blacklist.conf" \
  /etc/modprobe.d/golden-blacklist.conf

log "disabling core dumps"
printf '* hard core 0\n' > /etc/security/limits.d/90-no-core.conf
chmod 0644 /etc/security/limits.d/90-no-core.conf

log "restricting su to the wheel group"
if ! grep -q 'pam_wheel.so' /etc/pam.d/su; then
  sed -i '/pam_rootok.so/a auth       required   pam_wheel.so use_uid' /etc/pam.d/su
fi

log "default umask 027 for new files"
sed -i -E 's/^UMASK[[:space:]]+[0-9]+/UMASK 027/' /etc/login.defs

log "SSH daemon policy (sshd stays disabled at boot; see 90-finalize.sh)"
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/90-golden.conf <<'SSHD'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
Banner /etc/issue.net
SSHD
chmod 0644 /etc/ssh/sshd_config.d/90-golden.conf

log "login warning banner"
printf 'Authorized use only. Sessions are logged and audited.\n' > /etc/issue.net
cp /etc/issue.net /etc/issue

log "audit rules"
install -o root -g root -m 0640 "${GOLDEN_FILES}/audit/99-golden.rules" /etc/audit/rules.d/99-golden.rules
augenrules --load >/dev/null

log "sensitive file permissions"
chmod 0000 /etc/shadow /etc/gshadow
chmod 0644 /etc/passwd /etc/group
log "done"
