#!/usr/bin/env bash
# Waits for the most recent instance refresh of an Auto Scaling group to finish.
#
# Usage: wait-instance-refresh.sh <asg-name> [timeout-seconds] [started-after-iso8601]
#
# Exits 0 when the refresh is Successful. Exits 1 when AWS reports Failed, Cancelled or any
# rollback state, which means the new AMI was judged unhealthy by the alarms and reverted.
set -euo pipefail

usage() { echo "usage: $0 <asg-name> [timeout-seconds] [started-after-iso8601]" >&2; exit 2; }

ASG_NAME="${1:-}"
TIMEOUT_SECONDS="${2:-2700}"
STARTED_AFTER="${3:-}"
[[ -n "${ASG_NAME}" ]] || usage
[[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || usage

readonly POLL_SECONDS=30
readonly START_GRACE_SECONDS=300
deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
start_deadline=$(( $(date +%s) + START_GRACE_SECONDS ))

# Prints "<status> <start-time>" for the newest refresh, or "None -" when there is none.
latest_refresh() {
  aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name "${ASG_NAME}" \
    --max-records 1 \
    --output json \
  | python3 -c '
import json, sys
refreshes = json.load(sys.stdin).get("InstanceRefreshes", [])
if not refreshes:
    print("None -")
else:
    r = refreshes[0]
    print(r["Status"], r.get("StartTime", "-"))
'
}

started_after_epoch=0
if [[ -n "${STARTED_AFTER}" ]]; then
  started_after_epoch="$(date -u -d "${STARTED_AFTER}" +%s)"
fi

while true; do
  if ! refresh_info="$(latest_refresh)"; then
    echo "::error::could not describe instance refreshes for ${ASG_NAME}"
    exit 1
  fi
  read -r status start_time <<< "${refresh_info}"

  # A refresh that started before this deployment belongs to an earlier release.
  if [[ "${start_time}" != "-" && "${started_after_epoch}" -gt 0 ]]; then
    start_epoch="$(date -u -d "${start_time}" +%s)"
    if (( start_epoch < started_after_epoch )); then
      status="NotStartedYet"
    fi
  fi

  # The release changed the launch template, so a refresh must start shortly. If it does not,
  # something is wrong with the ASG and the pipeline should fail instead of waiting for the timeout.
  if [[ "${status}" == "NotStartedYet" ]] && (( $(date +%s) > start_deadline )); then
    echo "::error::no new instance refresh started for ${ASG_NAME} within ${START_GRACE_SECONDS}s"
    exit 1
  fi

  case "${status}" in
    None)
      echo "no instance refresh exists for ${ASG_NAME}; the AMI did not change"
      exit 0
      ;;
    NotStartedYet | Pending | InProgress | Cancelling)
      echo "$(date -u +%FT%TZ) instance refresh status: ${status}"
      ;;
    Successful)
      echo "instance refresh for ${ASG_NAME} succeeded"
      exit 0
      ;;
    Failed | Cancelled | RollbackInProgress | RollbackSuccessful | RollbackFailed)
      echo "::error::instance refresh for ${ASG_NAME} ended with ${status}"
      exit 1
      ;;
    *)
      echo "unexpected instance refresh status: ${status}" >&2
      ;;
  esac

  if (( $(date +%s) > deadline )); then
    echo "::error::timed out after ${TIMEOUT_SECONDS}s waiting for instance refresh (last status ${status})"
    exit 1
  fi
  sleep "${POLL_SECONDS}"
done
