# Runbook: instance refresh is stuck

**Use when:** a refresh has been `Pending` or `InProgress` for longer than expected, the release
job is waiting, or the progress percentage has not moved for 20 minutes.

**Goal:** find which of the usual blockers is active, then unblock it or stop the refresh
cleanly. Do not start a second refresh on top of a stuck one.

## 0. Set variables

```bash
export AWS_PROFILE=acme-prod
export ENV=prod
export ASG="sample-app-${ENV}"
```

## 1. Read the refresh and the group

```bash
aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --max-records 1 --output json
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[].{Id:InstanceId,State:LifecycleState,Health:HealthStatus,Version:LaunchTemplate.Version}}' \
  --output json
```

The refresh record has `StatusReason` and `PercentageComplete`. Read `StatusReason` first.

## 2. Match the symptom to the cause

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Status `InProgress`, `StatusReason` mentions a checkpoint | Intentional pause at 50% for `checkpoint_delay` (10 min) | Wait out the delay. It resumes on its own. |
| New instances stay `Pending`, then get terminated | Instances fail ELB health. The new AMI is broken or the app does not start. | Step 3 |
| Instances `InService` but `Unhealthy` on the target group | Health check path or port mismatch, or the app returns non-200 | Runbook: unhealthy targets and 502s |
| Scaling activity says `InsufficientInstanceCapacity` | Spot pools and on-demand capacity cannot satisfy the group in this AZ set | Step 4 |
| Terminating instances stay in `Terminating:Wait` | The drain hook waits for `complete-lifecycle-action` (heartbeat 300 s) | Step 5 |
| Refresh is `Pending` with no instances being touched | `min_healthy_percentage` cannot be met with current unhealthy instances | Fix the unhealthy ones first |

## 3. Failing new instances

Find the cause on a new instance without changing it. Use Session Manager (see
[emergency access](emergency-access-and-cve-patching.md)):

```bash
aws ssm start-session --target i-0123456789abcdef0
# inside the session:
sudo systemctl status sample-app --no-pager
sudo journalctl -u sample-app --no-pager -n 100
sudo tail -n 100 /var/log/sample-app/app.log
cat /etc/golden-ami-release
```

If the app does not start at all, the AMI is bad: stop the refresh and go to the rollback runbook.

```bash
aws autoscaling rollback-instance-refresh --auto-scaling-group-name "$ASG"
```

## 4. Capacity shortage

```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" --max-records 10 \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Message:StatusMessage}' --output table
```

Spot shortage is expected for some instance types. The mixed instances policy already lists four
types. If all four are constrained, the group runs below desired capacity while the refresh
waits. Options, in order:

1. Wait. Spot capacity usually returns within minutes.
2. Temporarily raise `on_demand_base_capacity` through Terraform for the duration of the refresh,
   so on-demand capacity covers the gap. Revert afterwards.
3. Cancel the refresh if the fleet is below its minimum and users are affected:
   `aws autoscaling cancel-instance-refresh --auto-scaling-group-name "$ASG"`.

## 5. Drain hook not completing

The hook is completed by `asg-lifecycle-drain` on the terminating instance. If it cannot complete,
the ASG waits for the heartbeat (300 s) and then continues anyway (`default_result = CONTINUE`).
So a stuck hook costs at most five minutes per instance.

If many instances are waiting, check the drain service on one of them:

```bash
aws ssm start-session --target i-0123456789abcdef0
sudo systemctl status sample-app-drain --no-pager
sudo journalctl -u sample-app-drain --no-pager -n 50
```

Look for `lifecycle hook completed` or for a credentials or permission error. A permission error
means the instance role lost `autoscaling:CompleteLifecycleAction`, which is a Terraform drift
problem to fix in the module.

To release the waiting instances manually (only when the app has been stopped already):

```bash
aws autoscaling complete-lifecycle-action --auto-scaling-group-name "$ASG" \
  --lifecycle-hook-name "sample-app-${ENV}-terminate-drain" \
  --instance-id i-0123456789abcdef0 --lifecycle-action-result CONTINUE
```

## 6. After the refresh ends

- `Successful`: run the smoke test and confirm target health (see the rollback runbook, step 4).
- `Cancelled`: the fleet is mixed. Decide the target AMI, then run a new refresh to it. Do not
  leave the group in a mixed state overnight.
- `RollbackSuccessful`: the rollback alarm was right. Follow the rollback runbook, step 5.

## Prevention

- Keep `checkpoint_delay` and `heartbeat_timeout` at values that match the real drain time.
- Keep the smoke test in the release job. A broken app that passes launch but not traffic is the
  most common cause of a long stuck refresh.
