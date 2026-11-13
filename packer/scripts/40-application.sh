#!/usr/bin/env bash
# Installs sample-app as a hardened systemd service together with its drain hook.
set -euo pipefail

log() { printf '[40-application] %s\n' "$*"; }

log "creating the unprivileged service account"
if ! id -u sampleapp >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/sample-app --no-create-home --shell /sbin/nologin sampleapp
fi

log "installing the application binary"
install -o root -g root -m 0755 "${APP_BINARY}" /usr/local/bin/sample-app

log "creating runtime directories"
install -d -o sampleapp -g sampleapp -m 0750 /var/log/sample-app
install -d -o root -g root -m 0755 /etc/sample-app

log "installing systemd units, logrotate and the lifecycle drain hook"
install -o root -g root -m 0644 "${GOLDEN_FILES}/systemd/sample-app.service" /etc/systemd/system/sample-app.service
install -o root -g root -m 0644 "${GOLDEN_FILES}/systemd/sample-app-drain.service" /etc/systemd/system/sample-app-drain.service
install -o root -g root -m 0755 "${GOLDEN_FILES}/bin/asg-lifecycle-drain.sh" /usr/local/sbin/asg-lifecycle-drain
install -o root -g root -m 0644 "${GOLDEN_FILES}/logrotate/sample-app" /etc/logrotate.d/sample-app

log "ensuring the AWS CLI is available for the lifecycle hook"
if ! command -v aws >/dev/null 2>&1; then
  dnf -y install awscli-2
fi

systemctl daemon-reload
systemctl enable sample-app.service sample-app-drain.service

log "writing release metadata"
cat > /etc/golden-ami-release <<RELEASE
SERVICE=sample-app
GIT_SHA=${GIT_SHA}
BUILD_DATE=${BUILD_DATE:-unknown}
RELEASE
chmod 0644 /etc/golden-ami-release
log "done"
