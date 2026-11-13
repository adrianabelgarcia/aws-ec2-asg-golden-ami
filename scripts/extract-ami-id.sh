#!/usr/bin/env bash
# Reads the AMI ID produced by the Packer manifest post-processor.
#
# Usage: extract-ami-id.sh <path-to-manifest.json>
# The manifest stores artifact_id as "<region>:<ami-id>", for example "us-east-1:ami-0abc...".
set -euo pipefail

MANIFEST="${1:-}"
[[ -n "${MANIFEST}" && -r "${MANIFEST}" ]] || { echo "usage: $0 <manifest.json>" >&2; exit 2; }

artifact_id="$(python3 -c '
import json, sys
builds = json.load(open(sys.argv[1])).get("builds", [])
if not builds:
    sys.exit("manifest contains no builds")
print(builds[-1]["artifact_id"])
' "${MANIFEST}")"

ami_id="${artifact_id##*:}"
if [[ ! "${ami_id}" =~ ^ami-[0-9a-f]{8,17}$ ]]; then
  echo "::error::could not parse an AMI ID from artifact_id '${artifact_id}'" >&2
  exit 1
fi
echo "${ami_id}"
