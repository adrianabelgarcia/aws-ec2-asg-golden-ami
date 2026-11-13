## What and why

<!-- One paragraph. Link the ADR or runbook if the change follows or updates one. -->

## Type of change

- [ ] Golden AMI (packer/, app/)
- [ ] Infrastructure (terraform/)
- [ ] Pipeline (.github/)
- [ ] Documentation only

## Rollout and rollback

<!-- For AMI or launch template changes: which alarms protect the instance refresh, and what is the rollback path? -->

## Checklist

- [ ] `make lint` passes locally (app tests, shellcheck, actionlint, packer validate, terraform fmt/validate, tflint, checkov)
- [ ] No hardcoded account IDs, secrets or personal data
- [ ] Checkov skips (if any) are inline and justified
- [ ] Docs and runbooks updated where behavior changed
