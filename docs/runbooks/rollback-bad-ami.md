# Runbook: roll back a bad AMI

**Use when:** a rollback alarm fired, a release is failing its smoke test, or users report errors
or slowness that started with a deployment.

**Goal:** the fleet runs the last good AMI within 15 minutes. The bad AMI is marked and kept for
investigation.

## 0. Set variables

```bash
export AWS_PROFILE=acme-prod            # or acme-staging
export ENV=prod                          # staging or prod
export SERVICE=sample-app
export ASG="${SERVICE}-${ENV}"
export LT_ID="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].MixedInstancesPolicy.LaunchTemplate.LaunchTemplateSpecification.LaunchTemplateId' --output text)"
export PARAM="/acme-demo/${SERVICE}/${ENV}/ami-id"
```

## 1. Find out what the refresh is doing

```bash
aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --max-records 3 \
  --query 'InstanceRefreshes[].{Id:InstanceRefreshId,Status:Status,Reason:StatusReason,Progress:PercentageComplete,Start:StartTime}' \
  --output table
```

| Status | Meaning | Go to |
| --- | --- | --- |
| `RollbackInProgress` | The ASG is already reverting. Let it finish. | Step 4 |
| `RollbackSuccessful` | The previous launch template version is running again. | Step 3 |
| `RollbackFailed` | The rollback itself failed. Treat as an incident. | Step 2 |
| `InProgress` with an alarm in ALARM | Auto rollback is disabled or the refresh is in a checkpoint. | Step 2 |
| `Successful` | The bad AMI is fully deployed and nothing rolled it back. | Step 3 |

## 2. Stop the bad rollout (if it is still running)

```bash
aws autoscaling rollback-instance-refresh --auto-scaling-group-name "$ASG"
```

`rollback-instance-refresh` cancels the current refresh and starts the rollback to the previous
launch template version. Use `cancel-instance-refresh` only if you want to stop without
reverting, which leaves a mixed fleet.

Check the alarm state while you wait:

```bash
aws cloudwatch describe-alarms --alarm-name-prefix "${SERVICE}-${ENV}-rollback" \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}' --output table
```

## 3. Point the fleet back at the last good AMI

Find the previous promoted AMI from the SSM parameter history:

```bash
aws ssm get-parameter-history --name "$PARAM" --query 'Parameters[].{Value:Value,Modified:LastModifiedDate}' --output table
```

The entry before the current value is the last good AMI. Confirm it in the AMI metadata (`Release`
tag is the commit SHA):

```bash
export GOOD_AMI=ami-xxxxxxxxxxxxxxxxx
aws ec2 describe-images --image-ids "$GOOD_AMI" --query 'Images[0].{State:State,Tags:Tags[?Key==`Release`||Key==`BuildDate`]}'
```

Then run the rollback through Terraform so state stays truthful:

1. Set the SSM parameter back, so that future Terraform runs agree with the fleet:
   ```bash
   aws ssm put-parameter --name "$PARAM" --type String --overwrite --value "$GOOD_AMI"
   ```
2. Apply the environment with the good AMI from a workstation or from `terraform.yml`:
   ```bash
   cd terraform/envs/$ENV
   terraform init -backend-config=backend.hcl
   terraform apply -var "ami_id=$GOOD_AMI"
   ```
3. Start a refresh to the good AMI if the apply did not change the launch template (for example
   when the bad version is still the default version):
   ```bash
   aws autoscaling start-instance-refresh --auto-scaling-group-name "$ASG" \
     --preferences '{"MinHealthyPercentage":90,"SkipMatching":true,"AutoRollback":false}'
   ```

Launch-template-only emergency (no Terraform available): point the group at the previous version
and refresh. Terraform must be reconciled within the same working day.

```bash
aws ec2 describe-launch-template-versions --launch-template-id "$LT_ID" --versions '$Latest' '$Default' \
  --query 'LaunchTemplateVersions[].{Version:VersionNumber,Ami:LaunchTemplateData.ImageId}' --output table
export GOOD_VERSION=7   # the version whose ImageId is $GOOD_AMI
aws ec2 modify-launch-template --launch-template-id "$LT_ID" --default-version "$GOOD_VERSION"
```

## 4. Verify

```bash
ALB_DNS="$(cd terraform/envs/$ENV && terraform output -raw alb_dns_name)"
DOMAIN="staging.acme-demo.dev"          # or the prod domain
./scripts/smoke-test.sh "$DOMAIN" "$ALB_DNS" "<git sha of the good release>"
TG_ARN="$(aws elbv2 describe-target-groups --names "${SERVICE}-${ENV}-tg" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)"
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
```

Watch the 5xx and latency graphs for at least 30 minutes after the last instance is replaced.

## 5. Preserve evidence and close

- Tag the bad AMI so nobody promotes it by accident. Do not deregister it yet.
  ```bash
  aws ec2 create-tags --resources "$BAD_AMI" --tags Key=Status,Value=bad Key=Incident,Value=<ticket>
  ```
- Save the Trivy report and the refresh event history for the incident record:
  ```bash
  aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" --max-records 50 > activities.json
  ```
- Open a follow-up to add the failing case to the tests or to the smoke test.
- Decide if the rollback alarm thresholds were right. Too late a rollback is an alarm problem.
  Too early is a false positive that should be documented in [ADR-0003](../adr/0003-instance-refresh-over-blue-green-asg.md).

## Notes

- Never fix a bad release by editing a running instance. Instances are replaceable, and an
  edited instance hides the real cause.
- If the alarms are already in ALARM before a new refresh starts, the refresh can roll back at
  once. Clear the cause first, or the rollback will repeat.
