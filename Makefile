SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

GIT_SHA ?= $(shell git rev-parse HEAD 2>/dev/null || echo dev)
CHECKOV ?= checkov
ENVS := staging prod
SHELL_SCRIPTS := $(shell find packer/scripts packer/files/bin scripts -name '*.sh' 2>/dev/null)

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-20s %s\n", $$1, $$2}'

.PHONY: app-test
app-test: ## gofmt check, vet, race-enabled tests with coverage
	cd app && test -z "$$(gofmt -l .)" || { gofmt -l .; exit 1; }
	cd app && go vet ./...
	cd app && go test -race -count=1 -cover ./...

.PHONY: app-build
app-build: ## Static linux/amd64 binary baked into the AMI
	cd app && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
		-ldflags "-s -w -X main.buildVersion=$(GIT_SHA)" -o bin/sample-app ./cmd/sample-app

.PHONY: shellcheck
shellcheck: ## shellcheck all shell scripts
	shellcheck $(SHELL_SCRIPTS)

.PHONY: actionlint
actionlint: ## lint GitHub workflow files
	actionlint .github/workflows/*.yml

.PHONY: packer-validate
packer-validate: ## Packer fmt check, init and syntax-only validation (no AWS calls)
	cd packer && packer fmt -check -diff .
	cd packer && packer init .
	cd packer && packer validate -syntax-only .

.PHONY: terraform-fmt
terraform-fmt: ## terraform fmt check, recursive
	terraform fmt -check -recursive terraform

.PHONY: terraform-validate
terraform-validate: ## init without a backend and validate the module and both roots
	@for d in terraform/modules/asg-service $(addprefix terraform/envs/,$(ENVS)); do \
		echo "== validate $$d"; \
		(cd $$d && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; \
	done

.PHONY: tflint
tflint: ## TFLint with the terraform and aws rulesets, recursive
	tflint --init --config=$(CURDIR)/.tflint.hcl
	cd terraform && tflint --recursive --config=$(CURDIR)/.tflint.hcl

.PHONY: checkov
checkov: ## Checkov policy scan, hard fail on any finding
	$(CHECKOV) -d terraform --framework terraform --config-file .checkov.yaml

.PHONY: lint
lint: app-test shellcheck actionlint packer-validate terraform-fmt terraform-validate tflint checkov ## Everything that runs without AWS access

.PHONY: clean
clean: ## Remove build output and local Terraform working directories
	rm -rf app/bin packer/manifest.json packer/reports packer/packer_cache
	find terraform -type d -name .terraform -prune -exec rm -rf {} +
