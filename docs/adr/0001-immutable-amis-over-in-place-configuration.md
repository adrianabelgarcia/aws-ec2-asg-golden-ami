# 0001: Immutable golden AMIs instead of in-place configuration management

- Status: accepted
- Date: 2026-11-13
- Deciders: Adrian Garcia (SRE / Tech Lead)

## Context and problem statement

The service is a legacy workload that cannot run in containers yet. Today it is configured by
installing packages and files on long-lived VMs. Configuration drift, unclear provenance of
packages and slow, risky patching are the main operational problems. We need a way to ship OS
patches, application releases and configuration changes that is repeatable and easy to roll back.

## Decision drivers

- Every running instance must match a reviewed, scanned artifact.
- Rollback must be a deployment, not a repair job on a live machine.
- Patching a CVE across the fleet must not depend on the state of each machine.
- The team is small. The mechanism has to be understood by one person at 3 a.m.

## Considered options

1. Configuration management in place (Ansible or Chef run against running instances on a schedule).
2. Immutable golden AMIs built by Packer, deployed through an Auto Scaling group.
3. Containers on ECS or EKS.

## Decision outcome

Chosen: option 2. Every change produces a new AMI. The AMI contains the OS, hardening, the
CloudWatch agent, the application binary and its systemd units. Instances receive only a
per-instance environment file through user data. Instances are replaced, not modified.

Option 3 is the long-term direction for services that can be containerized. It is not feasible
for this workload now and the AMI pipeline keeps the operational model the same when it changes.

## Pros and cons

- Good: the image is the unit of audit. Each AMI carries its git SHA, base AMI, build date and a
  Trivy report.
- Good: rollback is `terraform apply` of the previous AMI ID, or an automatic refresh rollback.
- Good: there is no drift to detect. A replaced instance is the same as the one that passed tests.
- Good: patches are measured by an SSM patch scan, and remediated by a rebuild.
- Bad: a rebuild takes 20 to 30 minutes instead of a 2-minute package install. Acceptable for
  the current release cadence. Emergency fixes still go through the pipeline.
- Bad: a small amount of runtime state (logs, caches) is lost on replacement. Logs are shipped to
  CloudWatch as they are written, so nothing of value lives only on the instance.
- Bad: AMIs are account-scoped, so the image must be copied across accounts for production (see
  `release.yml`).

## Links

- [architecture.md](../architecture.md), release flow.
- [0003](0003-instance-refresh-over-blue-green-asg.md), how new AMIs reach the fleet.
