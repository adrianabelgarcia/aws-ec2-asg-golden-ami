#!/usr/bin/env bash
# Copies a shared golden AMI into the current AWS account, encrypted with that account's key.
# Run with credentials for the destination account. Prints the new AMI ID on stdout.
#
# Usage: copy-ami.sh <source-ami-id> <source-region> <kms-key-alias> <name>
set -euo pipefail

usage() { echo "usage: $0 <source-ami-id> <source-region> <kms-key-alias> <name>" >&2; exit 2; }

SOURCE_AMI="${1:-}"
SOURCE_REGION="${2:-}"
KMS_ALIAS="${3:-}"
NAME="${4:-}"
[[ -n "${SOURCE_AMI}" && -n "${SOURCE_REGION}" && -n "${KMS_ALIAS}" && -n "${NAME}" ]] || usage
[[ "${SOURCE_AMI}" =~ ^ami-[0-9a-f]{8,17}$ ]] || { echo "::error::invalid source AMI ${SOURCE_AMI}" >&2; exit 1; }

# Passing the key ARN explicitly avoids depending on alias support in every EC2 API path.
kms_arn="$(aws kms describe-key --key-id "${KMS_ALIAS}" --query 'KeyMetadata.Arn' --output text)"

new_ami="$(aws ec2 copy-image \
  --source-region "${SOURCE_REGION}" \
  --source-image-id "${SOURCE_AMI}" \
  --name "${NAME}" \
  --description "Copy of ${SOURCE_AMI} encrypted with ${KMS_ALIAS}" \
  --encrypted \
  --kms-key-id "${kms_arn}" \
  --query 'ImageId' --output text)"

echo "copy started: ${new_ami}" >&2
aws ec2 wait image-available --image-ids "${new_ami}"
echo "${new_ami}"
