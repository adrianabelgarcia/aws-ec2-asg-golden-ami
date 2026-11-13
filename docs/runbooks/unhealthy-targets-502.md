# Runbook: unhealthy targets, 502s and 503s

**Use when:** the `unhealthy-targets` alarm fires, users see HTTP 502 Bad Gateway or 503 Service
Unavailable, or `HTTPCode_ELB_502_Count` / `HTTPCode_ELB_503_Count` rise.

**What the codes mean from the ALB side**

| Code | Issued by | Meaning | Usual causes |
| --- | --- | --- | --- |
| 502 | ALB | The target closed the connection, sent an invalid response, or the connection was reset | App crash mid-request, keep-alive mismatch, app exceeds `WriteTimeout`, malformed response headers |
| 503 | ALB | No healthy targets to send the request to | Every target failed health checks, the fleet is draining, or the group is empty |
| 504 | ALB | The target did not respond within the idle timeout (60 s) | Slow dependency, deadlock, thread exhaustion |
| 5xx from target | App | The app itself returned an error | Application bug, dependency failure. See the logs. |

## 0. Set variables

```bash
export AWS_PROFILE=acme-prod
export ENV=prod
export SERVICE=sample-app
export TG_ARN="$(aws elbv2 describe-target-groups --names "${SERVICE}-${ENV}-tg" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)"
```

## 1. Which targets are unhealthy, and why

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason,Detail:TargetHealth.Description}' \
  --output table
```

| `Reason` | Meaning | Next step |
| --- | --- | --- |
| `Target.ResponseCodeMismatch` | `/health` returned something other than 200 | Step 3. A 503 during drain is expected. |
| `Target.Timeout` | No response within 5 s | Step 3, check whether the process is hung |
| `Target.FailedHealthChecks` | Connection refused or reset | Step 3, check that the app is listening on 8080 |
| `Target.DeregistrationInProgress` | Normal drain | No action |
| `Elb.InternalError` | ALB-side problem | Check AWS Health, open a support case if it persists |

## 2. Check the fleet from the load balancer's point of view

Count 5xx by origin over the last hour (the `ELB` variant means the ALB produced it):

```bash
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name HTTPCode_ELB_502_Count \
  --dimensions Name=LoadBalancer,Value="$(aws elbv2 describe-load-balancers --names "${SERVICE}-${ENV}-alb" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text | sed 's#.*:loadbalancer/##')" \
  --start-time "$(date -u -d '-1 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" --period 300 --statistics Sum
```

Logs Insights is faster for the question "which path, which instance":

```text
fields @timestamp, @message
| filter @logStream like /app$/
| parse @message '"method":"*","path":"*","status":*,' as method, path, status
| filter status >= 500
| stats count() by path, status, bin(5m)
```

Run it against `/acme-demo/sample-app/app`.

## 3. Inspect one unhealthy instance

Use Session Manager. Do not edit the instance; capture evidence and replace it.

```bash
aws ssm start-session --target i-0123456789abcdef0
sudo systemctl status sample-app --no-pager
sudo ss -ltnp | grep 8080                       # is the app listening?
curl -si http://127.0.0.1:8080/health; echo      # what does the health check see?
sudo journalctl -u sample-app --no-pager -n 200
sudo tail -n 200 /var/log/sample-app/app.log
sudo dmesg -T | tail -n 50                        # OOM kills show up here
```

Typical findings:

- `ss` shows nothing on 8080: the process is down. `systemctl` shows why (`Restart=on-failure`
  restarts it; repeated restarts mean a crash loop).
- `curl` returns 503 with `"status":"draining"`: the instance is draining (shutting down). That is
  correct behavior.
- Health is fine locally but the ALB marks it unhealthy: check the security group rule from the
  ALB security group to the instance security group on the app port.

## 4. Fix

| Cause | Fix |
| --- | --- |
| Single instance crash loop | Terminate the instance: `aws autoscaling terminate-instance-in-auto-scaling-group --instance-id i-... --should-decrement-desired-capacity false`. The ASG replaces it. |
| All instances failing after a release | Rollback. See the rollback runbook. |
| Dependency outage (502 or 504 from the app) | Follow the dependency's runbook. Scaling out does not help. |
| Keep-alive 502s (short bursts, no crashes) | Confirm the app `IdleTimeout` (75 s) is larger than the ALB idle timeout (60 s). |
| Capacity: 503 with few targets left | Raise `min_size` temporarily, then find why scale-out did not happen (see the CPU and request policies). |
| WAF blocks legitimate traffic (403, not 5xx) | Check WAF sampled requests, add a scoped exception rule. Do not disable the managed group. |

## 5. Verify and close

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
```

All targets should be `healthy` and the 5xx rate should be back under the SLO threshold for 30
minutes. Record the cause in the incident ticket and link the SLO section that was affected.
