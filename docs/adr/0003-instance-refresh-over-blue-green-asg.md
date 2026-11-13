# 0003: Rolling instance refresh with alarm-based rollback instead of blue/green ASG swap

- Status: accepted
- Date: 2026-11-13
- Deciders: Adrian Garcia (SRE / Tech Lead)

## Context and problem statement

A new AMI must reach every instance without dropping traffic, and a bad AMI must be reverted
without a human racing the clock. Two patterns are common on AWS:

- Blue/green ASG swap: create a second ASG with the new AMI, shift the ALB target group (or
  weights), then destroy the old ASG.
- Rolling instance refresh: the same ASG replaces instances in batches while preserving a
  minimum healthy percentage.

## Decision drivers

- Zero-downtime rollouts with a controlled blast radius.
- Automatic rollback that does not depend on someone noticing a dashboard.
- Low cost at the steady state (blue/green doubles capacity during a rollout).
- Fewer moving parts in Terraform state.

## Considered options

1. Blue/green with two ASGs and a target group switch.
2. Rolling instance refresh with checkpoints and alarm-based auto rollback.
3. Rolling refresh with no alarms, and rollback by human decision.

## Decision outcome

Chosen: option 2. The module sets:

- `min_healthy_percentage = 90`, so at most one instance of a 10-instance group is replaced at a
  time.
- `checkpoint_percentages = [50]` with a 600 second delay, so the new version runs at half
  capacity under real load before the rollout completes.
- `auto_rollback = true` with two alarms in `alarm_specification`: the target 5xx rate above 5%
  (2 of 3 one-minute periods) and p95 target response time above 1 second (3 of 5 periods).

Option 3 was rejected because a rollback that waits for a human at 3 a.m. is the failure mode
we are trying to remove.

Option 1 remains a valid tool for risky schema or architecture changes that cannot be served by
two versions of the app at once. It is not the default because it doubles cost during a release
and makes Terraform state harder to reason about.

## Why only error-rate and latency alarms roll back

`UnHealthyHostCount` is not in the rollback set. During a refresh, the ALB briefly reports
replaced instances as unhealthy, so the alarm would fire on a healthy rollout. It pages a human
instead. The rollback alarms use `treat_missing_data = notBreaching` for the same reason: a quiet
period is not a failure.

## Pros and cons

- Good: no double capacity during rollouts, and a single state object per environment.
- Good: rollback happens within minutes, bounded by the alarm evaluation periods.
- Bad: the two versions run side by side during the rollout, so the app must tolerate mixed
  versions. This is a real constraint and is documented for the service owners.
- Bad: alarms must reflect user impact. A bad release that fails silently (wrong data, no 5xx)
  will not roll back. That is the job of the smoke test and the SLO review, not of the refresh.
- Bad: an alarm that is already in ALARM when a refresh starts can roll the refresh back at once.
  The runbook covers how to clear that state.

## Links

- [architecture.md](../architecture.md), rollout sequence.
- [Rollback runbook](../runbooks/rollback-bad-ami.md).
- [SLOs](../slo.md), which define what "bad" means.
