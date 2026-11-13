# Service level objectives: sample-app

These objectives describe what users experience. They decide when a release is bad, when we
stop shipping features and when we page someone. They are reviewed quarterly.

## Service level indicators

| SLI | Good event | Measured from | Valid events |
| --- | --- | --- | --- |
| Availability | Request answered with a non-5xx status | ALB `RequestCount` minus `HTTPCode_Target_5XX_Count` and `HTTPCode_ELB_5XX_Count` | All requests except 4xx caused by the client |
| Latency | One-minute period where p95 `TargetResponseTime` is under 500 ms | ALB `TargetResponseTime` with statistic `p95` | Every one-minute period with traffic |

Measuring availability at the ALB reflects what the load balancer and the fleet return to clients.
Measuring at the instance would miss errors the ALB generates (no healthy targets, 502s).

Latency is a time-slice indicator. ALB does not publish request-level latency histograms, so the
SLI counts the share of minutes whose p95 is under the target. This is coarser than a request
ratio, and it is still a reliable signal for regressions that a release can cause.

## Service level objectives

| Environment | SLO | Window | Error budget |
| --- | --- | --- | --- |
| prod, availability | 99.9% of valid requests are non-5xx | rolling 30 days | 0.1%, about 43 minutes of full outage |
| prod, latency | 99% of one-minute periods have p95 under 500 ms | rolling 30 days | 1% of periods, about 7 hours |
| staging | Informational only, no error budget | none | none |

Staging exists to catch problems before production, so its numbers do not commit anyone to
anything. The smoke test and the rollback alarms still run there.

## Error budget policy

| Budget remaining (30 days) | Policy |
| --- | --- |
| more than 50% | Normal delivery. Releases proceed with the standard pipeline. |
| 25% to 50% | Releases need a reviewed risk note in the PR. Non-urgent infrastructure changes wait for a second review. |
| below 25% | Feature releases pause. Only reliability fixes and security patches ship. A review of the incidents that consumed the budget is scheduled within a week. |
| exhausted | Feature freeze until the rolling window recovers above 25%. The team reviews the top three contributors and commits to actions with owners. |

Security patches (including critical CVE fixes through the emergency path in the runbook) are
exempt from the freeze.

## Burn-rate alerts

A burn rate is how fast the error budget is spent compared with the rate that would exactly use
up the budget over the SLO window. A burn rate of 1 means the budget lasts the whole window.

Multi-window burn-rate alerts (as described in the Google SRE workbook) avoid paging on short
spikes and still catch fast outages:

| Severity | Burn rate | Long window | Short window | Budget consumed when it fires | Response |
| --- | --- | --- | --- | --- | --- |
| Page | 14.4 | 1 hour | 5 minutes | 2% of the monthly budget | Page on-call now |
| Page | 6 | 6 hours | 30 minutes | 5% of the monthly budget | Page on-call within the hour |
| Ticket | 3 | 1 day | 2 hours | 10% of the monthly budget | Next working day |
| Ticket | 1 | 3 days | 6 hours | 10% of the monthly budget | Review in the weekly SLO meeting |

For the availability SLO (error ratio target 0.1%), the page threshold at burn rate 14.4 is an
error ratio of 1.44% sustained over the long window and the short window together.

### How the alarms are expressed

The module ships threshold alarms today. They are the first layer:

- `rollback-5xx-rate` (5% over 2 of 3 minutes). It is also an instance refresh rollback alarm.
- `rollback-p95-latency` (1 second over 3 of 5 minutes). It is also an instance refresh rollback alarm.
- `unhealthy-targets`, `capacity-below-minimum` and `fleet-cpu-high` page or notify.

The burn-rate alerts above are the target configuration. They are not in the module yet. They
need metric math that combines two periods (for example `RequestCount` at 60 s and at 3600 s), which
is more involved than the threshold alarms. Implementing them is the first SLO item in the README
"what's next" section.

## Measurement notes

- The SLO is reported from ALB metrics in CloudWatch. Access logs in S3 are the audit source when
  a number is disputed.
- Planned maintenance does not count against the budget only when it is announced and runs
  inside the agreed window. Otherwise it counts.
- A release that rolls back automatically still counts its bad minutes against the budget. The
  rollback is a protection, not an exemption.
