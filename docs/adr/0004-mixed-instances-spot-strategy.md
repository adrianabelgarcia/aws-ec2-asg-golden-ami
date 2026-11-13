# 0004: Mixed on-demand and Spot capacity with capacity-optimized allocation

- Status: accepted
- Date: 2026-11-13
- Deciders: Adrian Garcia (SRE / Tech Lead)

## Context and problem statement

Compute is the largest line item of the fleet. Spot capacity is typically 60 to 70% cheaper than
on-demand, but interruptions happen. Production needs predictable capacity for the base load and
can take cost savings above it. Staging can tolerate interruptions and should be cheap.

## Decision drivers

- Production availability must not depend on the Spot market for the base load.
- Spot interruptions must be survivable without user-visible errors.
- Cost per environment should match the environment's purpose.
- Instance family diversity should be high enough to avoid one capacity pool drying up.

## Considered options

1. On-demand only.
2. Spot only, with one instance type.
3. Mixed instances policy: an on-demand base plus Spot above it, several instance types, and
   `capacity-optimized` Spot allocation.

## Decision outcome

Chosen: option 3, with different ratios per environment:

| Environment | On-demand base | Above base | Spot share at steady state |
| --- | --- | --- | --- |
| prod | 2 instances | 50% on-demand | about 25% of a 4-instance fleet, about 60% at the maximum of 12 |
| staging | 0 | 20% on-demand | about 80% |

Instance types are `m7i.large`, `m6i.large`, `m7a.large` and `m6a.large`. They share the same
size and memory profile, so the app behaves the same on any of them while the Spot pools differ.

Allocation strategy is `capacity-optimized`, which picks the pools least likely to be reclaimed
rather than the cheapest pool. That trades a few cents for fewer interruptions.

Interruption handling is in the image: `asg-lifecycle-drain` polls IMDS for the two-minute Spot
interruption notice, stops `sample-app` (which fails its health check and drains in-flight
requests), and lets the ASG replace the instance. `capacity_rebalance = true` lets the ASG launch
a replacement early when AWS signals elevated risk.

## Pros and cons

- Good: prod keeps its base capacity on-demand. An interruption event reduces capacity, but not
  below the base.
- Good: staging costs a fraction of prod and still exercises the Spot code path, so Spot issues
  show up before production.
- Bad: mixed instance types make performance comparisons slightly harder. Dashboards aggregate
  per group, not per type.
- Bad: when Spot capacity is scarce for all listed types, the group scales below desired. The
  `capacity-below-minimum` alarm pages for this.

## Links

- [Stuck refresh runbook](../runbooks/instance-refresh-stuck.md), which covers capacity shortages.
- [README cost estimate](../../README.md#cost-estimate).
