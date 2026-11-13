# 0002: AWS Systems Manager Session Manager instead of SSH and bastion hosts

- Status: accepted
- Date: 2026-11-13
- Deciders: Adrian Garcia (SRE / Tech Lead)

## Context and problem statement

Engineers need shell access to instances for incident response and diagnostics. The traditional
options are SSH with key pairs, a bastion host, or a VPN. Each one adds inbound attack surface,
key management and an audit gap. Auditors ask who ran which command on which host and when.

## Decision drivers

- No inbound network path to instances from the internet or from an office network.
- Access decisions and audit logs live in IAM and CloudTrail, not in a separate key system.
- No long-lived secrets on instances or on laptops.
- Works during an incident, even if DNS or the load balancer is down.

## Considered options

1. SSH on port 22 with a restricted source range.
2. A bastion host in a public subnet, with SSH jump hosts.
3. Systems Manager Session Manager, with IAM-controlled access and no inbound ports.

## Decision outcome

Chosen: option 3.

- Security groups have no port 22 rule. `sshd` is installed but disabled at boot, has no host
  keys in the image and rejects password logins.
- Access is granted by IAM policies that match instance tags (for example
  `ssm:resourceTag/Service = sample-app`). Break-glass access uses a separate role that requires
  MFA.
- Session logs and command transcripts are written to CloudWatch Logs and S3 (account-level
  Session Manager preferences, not in this repo).
- The instance role includes `AmazonSSMManagedInstanceCore`. The agent uses an outbound HTTPS
  channel through NAT, so the private subnets need no inbound rules at all.
- The Packer build uses `ssh_interface = "session_manager"` as well, so the build never needs
  an inbound port and the temporary key pair is removed in the finalize step.

## Pros and cons

- Good: no inbound ports, no bastion to patch, no shared keys to rotate.
- Good: every session is attributed to an IAM identity and logged.
- Bad: requires the `session-manager-plugin` on the operator's machine and on the CI runner.
- Bad: if the SSM agent is broken, the only recovery path is to replace the instance. That is
  acceptable for an immutable fleet, and the emergency runbook covers it.
- Bad: sessions run as `ssm-user` by default. Operators either sudo from there or use the
  Session Manager "run as" preference to start sessions as `ec2-user`.

## Links

- [Emergency access runbook](../runbooks/emergency-access-and-cve-patching.md).
