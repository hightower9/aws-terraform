# ============================================================
# Laravel AWS Terraform — Makefile
# ============================================================
# Usage: make <target> ENV=<environment> [EMULATOR=1] [TF_ARGS='-var k=v']
# Environments: local, dev, uat, prod
#
# One Terraform root (this directory) serves every environment; ENV picks
# environments/<env>/terraform.tfvars + backend.tfbackend.
# EMULATOR=1 runs any environment against Floci (localhost:4566) instead
# of real AWS. `local` always uses the emulator.
# ============================================================

ENV ?= local
ENV_LIST := local dev uat prod
ENVS_DIR := environments
SHELL := /bin/bash

ifeq ($(filter $(ENV),$(ENV_LIST)),)
$(error ENV must be one of: $(ENV_LIST) (got '$(ENV)'))
endif

# Optional: load variables from a local .env file (see .env.example).
-include .env
export

EMULATOR ?= 0
# `local` always targets the emulator. Kept in a separate variable so the
# override never leaks into sub-makes (e.g. `make plan-dev`).
USE_EMULATOR := $(if $(filter local,$(ENV)),1,$(EMULATOR))

ifeq ($(USE_EMULATOR),1)
# Point the AWS provider, the aws CLI and the S3 backend at Floci. Set per
# command, not exported, so nothing leaks into a real-AWS run.
AWS_ENV := env -u AWS_PROFILE \
	AWS_ENDPOINT_URL=http://localhost:4566 \
	AWS_ACCESS_KEY_ID=test \
	AWS_SECRET_ACCESS_KEY=test \
	AWS_DEFAULT_REGION=us-east-1
MODE         := $(ENV)-emulator
BACKEND_ARGS := -backend-config=$(ENVS_DIR)/$(ENV)/backend.tfbackend \
                -backend-config=$(ENVS_DIR)/emulator.s3.tfbackend
PREFLIGHT    := true
# Emulator copies must stay disposable, even for prod.
EMU_VARS     := -var alb_deletion_protection=false
else
AWS_ENV      :=
MODE         := $(ENV)
BACKEND_ARGS := -backend-config=$(ENVS_DIR)/$(ENV)/backend.tfbackend
PREFLIGHT    := bash scripts/preflight.sh $(ENV)
EMU_VARS     :=
endif

# Each env (and emulator/real mode) gets its own Terraform working dir and
# plan file, so switching never needs a re-init and can't mix up state.
DATA_DIR  := .terraform-envs/$(MODE)
PLAN_FILE := $(DATA_DIR)/tfplan
VAR_FILE  := -var-file=$(ENVS_DIR)/$(ENV)/terraform.tfvars
# Optional git-ignored per-env overrides (Terraform only auto-loads
# *.auto.tfvars from the root directory, so pass it explicitly).
VAR_FILE  += $(if $(wildcard $(ENVS_DIR)/$(ENV)/secrets.auto.tfvars),-var-file=$(ENVS_DIR)/$(ENV)/secrets.auto.tfvars)
TF        := $(AWS_ENV) TF_DATA_DIR=$(DATA_DIR) terraform

# The bare `export` above is for .env values; keep Makefile internals out of
# sub-make environments so emulator settings can't bleed into a real run.
unexport AWS_ENV USE_EMULATOR MODE BACKEND_ARGS PREFLIGHT EMU_VARS DATA_DIR PLAN_FILE VAR_FILE TF

.PHONY: help init plan apply destroy output fmt validate lint security clean \
        bootstrap-state start-floci stop-floci floci-ui start-localstack \
        test-app test-env test-all shell

# ---- Default target ----
help: ## Show this help
	@echo "Usage: make <target> ENV=<environment> [EMULATOR=1]"
	@echo ""
	@echo "Environments: $(ENV_LIST)"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_%-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ---- Core targets (per-environment) ----
init: ## Run terraform init for ENV
	$(TF) init -reconfigure -input=false $(BACKEND_ARGS)

plan: ## Run preflight + terraform plan for ENV (writes the plan file)
	@$(PREFLIGHT)
	$(TF) plan -input=false $(VAR_FILE) $(EMU_VARS) -out=$(PLAN_FILE) $(TF_ARGS)

# A saved plan already carries its variables and applies without a prompt;
# Terraform rejects -var/-var-file alongside a plan file.
apply: ## Apply the plan file from `make plan` for ENV
	@test -f $(PLAN_FILE) || { echo "No plan for $(MODE) — run 'make plan ENV=$(ENV)$(if $(filter 1,$(EMULATOR)), EMULATOR=1)' first"; exit 1; }
	$(TF) apply -input=false $(PLAN_FILE)
	rm -f $(PLAN_FILE)

destroy: ## Run terraform destroy for ENV (prod requires CONFIRM=prod)
	@if [ "$(ENV)" = "prod" ] && [ "$(USE_EMULATOR)" != "1" ] && [ "$(CONFIRM)" != "prod" ]; then \
		echo "Refusing to destroy prod. Re-run with: make destroy ENV=prod CONFIRM=prod"; exit 1; \
	fi
	$(TF) destroy -input=false -auto-approve $(VAR_FILE) $(EMU_VARS) $(TF_ARGS)

output: ## Show terraform output for ENV
	$(TF) output

# ---- Formatting, validation & security ----
fmt: ## Format all .tf files
	terraform fmt -recursive

validate: ## Validate the configuration (offline, no backend)
	TF_DATA_DIR=.terraform-envs/validate terraform init -backend=false -input=false >/dev/null
	TF_DATA_DIR=.terraform-envs/validate terraform validate

security: ## Run Checkov (same check as CI; needs `pip install checkov`)
	checkov --directory . --framework terraform --config-file .checkov.yml --quiet

# ---- Environment-specific shortcuts: init-dev, plan-prod, apply-uat, ... ----
init-%: ## Shortcut: make init-<env>
	@$(MAKE) --no-print-directory init ENV=$*
plan-%: ## Shortcut: make plan-<env>
	@$(MAKE) --no-print-directory plan ENV=$*
apply-%: ## Shortcut: make apply-<env>
	@$(MAKE) --no-print-directory apply ENV=$*
destroy-%: ## Shortcut: make destroy-<env>
	@$(MAKE) --no-print-directory destroy ENV=$*

# ---- Remote state bootstrap ----
bootstrap-state: ## Create state buckets (ENVS="prod" for one; EMULATOR=1 for Floci)
	$(AWS_ENV) bash scripts/bootstrap-state.sh $(ENVS)

# ---- Local emulator (Floci) ----
start-floci: ## Start Floci (AWS emulator :4566) + Floci UI (:4500)
	bash scripts/start-floci.sh

stop-floci: ## Stop Floci and its console (state kept in .floci/)
	docker compose -f docker-compose.floci.yml down

floci-ui: ## Open the Floci web console (http://localhost:4500)
	@curl -fsS --max-time 3 http://localhost:4500/api/clouds >/dev/null 2>&1 || { echo "Floci UI is not running — run 'make start-floci' first"; exit 1; }
	@echo "Floci UI: http://localhost:4500"
	@{ command -v start >/dev/null && start http://localhost:4500; } || \
	 { command -v xdg-open >/dev/null && xdg-open http://localhost:4500; } || \
	 { command -v open >/dev/null && open http://localhost:4500; } || true

start-localstack: ## Start LocalStack (legacy alternative to Floci)
	bash scripts/start-localstack.sh

# ---- Local testing ----
test-app: ## Run ENV's Docker image locally like cloud-init does and check health
	bash scripts/test-app.sh $(ENV)

test-env: ## Full emulator run for ENV: bootstrap, init, plan, apply, output, test-app
	@$(MAKE) --no-print-directory bootstrap-state ENVS=$(ENV) EMULATOR=1
	@$(MAKE) --no-print-directory init ENV=$(ENV) EMULATOR=1
	@$(MAKE) --no-print-directory plan ENV=$(ENV) EMULATOR=1
	@$(MAKE) --no-print-directory apply ENV=$(ENV) EMULATOR=1
	@$(MAKE) --no-print-directory output ENV=$(ENV) EMULATOR=1
	@$(MAKE) --no-print-directory test-app ENV=$(ENV)

test-all: ## test-env for every environment, stopping at the first failure
	@set -e; for e in $(ENV_LIST); do $(MAKE) --no-print-directory test-env ENV=$$e; done

# ---- Utility ----
shell: ## Open terraform console for ENV
	$(TF) console $(VAR_FILE) $(EMU_VARS)

clean: ## Remove all Terraform working dirs and plan files (state is remote)
	rm -rf .terraform-envs
