#!/usr/bin/env bash
# Runs on every instance. Watches IMDS for an Auto Scaling termination lifecycle hook (or a
# Spot interruption notice). When one arrives it stops sample-app, which drains in-flight
# requests, and only then completes the hook so the ASG proceeds with termination.
set -euo pipefail

readonly ENV_FILE="/etc/sample-app/instance.env"
readonly IMDS="http://169.254.169.254/latest"
readonly POLL_SECONDS=5

log() { printf '%s asg-lifecycle-drain: %s\n' "$(date -u +%FT%TZ)" "$*"; }

imds_get() {
  local token
  token="$(curl -sf -m 2 -X PUT "${IMDS}/api/token" \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" || return 1
  curl -sf -m 2 -H "X-aws-ec2-metadata-token: ${token}" "${IMDS}/$1"
}

# Wait for cloud-init to write the per-instance settings (ASG name, hook name, region).
until [[ -r "${ENV_FILE}" ]]; do
  sleep "${POLL_SECONDS}"
done
set -a
# shellcheck source=/dev/null
. "${ENV_FILE}"
set +a

instance_id="$(imds_get meta-data/instance-id)"
log "watching for termination lifecycle hook on ${instance_id} (asg=${ASG_NAME})"

while true; do
  lifecycle_state="$(imds_get meta-data/autoscaling/target-lifecycle-state || true)"
  spot_action="$(imds_get meta-data/spot/instance-action || true)"

  if [[ "${spot_action}" != "" ]]; then
    log "spot interruption notice received, draining"
    systemctl stop sample-app.service
    # A Spot reclaim is not an ASG lifecycle event, so there is no hook to complete.
    exit 0
  fi

  if [[ "${lifecycle_state}" == "Terminated:Wait" ]]; then
    log "termination hook received, draining"
    systemctl stop sample-app.service
    aws autoscaling complete-lifecycle-action \
      --region "${AWS_REGION}" \
      --auto-scaling-group-name "${ASG_NAME}" \
      --lifecycle-hook-name "${LIFECYCLE_HOOK_NAME}" \
      --instance-id "${instance_id}" \
      --lifecycle-action-result CONTINUE
    log "lifecycle hook completed"
    exit 0
  fi

  sleep "${POLL_SECONDS}"
done
