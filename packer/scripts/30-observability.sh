#!/usr/bin/env bash
# Installs the CloudWatch agent and bakes in its configuration. The agent is enabled, not
# started: it starts on boot and reads instance identity from IMDS at that time.
set -euo pipefail

log() { printf '[30-observability] %s\n' "$*"; }

readonly AGENT_DIR="/opt/aws/amazon-cloudwatch-agent"
readonly AGENT_RPM="https://amazoncloudwatch-agent-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"

log "installing the CloudWatch agent from the regional AWS distribution bucket"
dnf -y install "${AGENT_RPM}"

log "installing the agent configuration"
install -d -m 0755 "${AGENT_DIR}/etc"
install -o root -g root -m 0644 "${GOLDEN_FILES}/cloudwatch/amazon-cloudwatch-agent.json" \
  "${AGENT_DIR}/etc/amazon-cloudwatch-agent.json"

# Store the configuration in the agent state without starting it. This runs during the build,
# so there is no instance identity to bind to yet.
"${AGENT_DIR}/bin/amazon-cloudwatch-agent-ctl" -a fetch-config -m ec2 \
  -c "file:${AGENT_DIR}/etc/amazon-cloudwatch-agent.json"

systemctl enable amazon-cloudwatch-agent.service
log "done"
