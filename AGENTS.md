# AGENTS.md - Laravel AWS Terraform

## What this repo does
Deploys a Dockerized Laravel app on AWS: ALB (HTTPS via ACM) → Auto Scaling Group across 2 AZs → EC2 running the container (image from ECR, env from SSM Parameter Store), plus S3 storage, CloudWatch logs/alarms (SNS), VPC flow logs. Four environments: local, dev, uat, prod.

User docs: `docs/GUIDE.md` (daily use, Floci), `docs/PRODUCTION.md` (go-live). Keep them in sync with behaviour changes.

## Layout: ONE root config
- Root `main.tf` / `variables.tf` / `resources.tf` / `outputs.tf` serve every environment. Do not re-create per-env copies of `.tf` files.
- An environment = `environments/<env>/terraform.tfvars` + `environments/<env>/backend.tfbackend`.
- `environments/emulator.s3.tfbackend` is layered on top for Floci runs.
- Per-env/mode working dirs: `.terraform-envs/<env>` and `.terraform-envs/<env>-emulator` (TF_DATA_DIR). Plan file: `<dir>/tfplan`.

## Command order
```bash
make init ENV=<env> [EMULATOR=1]     # first
make plan ENV=<env> [EMULATOR=1]     # runs scripts/preflight.sh for real AWS; writes the plan
make apply ENV=<env> [EMULATOR=1]    # applies exactly that plan (no -var allowed with a plan file)
make output ENV=<env> [EMULATOR=1]
```
- One-off variable overrides: `TF_ARGS='-var k=v'` on plan. `TF_VAR_*` does NOT override tfvars.
- `local` is always the emulator. `EMULATOR=1` injects the Floci endpoint + test creds per command and is never exported. Emulator plans also pass `-var alb_deletion_protection=false`.
- `make test-env ENV=<env>` = bootstrap + init + plan + apply + output + test-app on Floci. `make test-all` runs it for all four.

## Placeholders and preflight
- Dummy values that must change for real use carry a trailing `# PLACEHOLDER: ...` comment in tfvars/backend files.
- `scripts/preflight.sh <env>`: in prod any marker (or nginx image, empty cert/email/ami_id, `latest` tag) is an error that blocks `make plan`; in dev/uat they are warnings. Emulator runs skip it.
- When adding a new must-change value, add a working dummy + `# PLACEHOLDER` marker, and a prod semantic check if it's critical.

## Zero-downtime (read before changing ec2/alb)
- `aws_autoscaling_group.instance_refresh` (native, no local-exec): `min_healthy_percentage=100`, `max_healthy_percentage=200`, `auto_rollback=true`.
- It triggers because `launch_template.version = aws_launch_template.this.latest_version` (never `$Latest`).
- `health_check_type = "ELB"` + target group health check on `health_check_url`: an instance is healthy only when the app answers.
- A precondition enforces `asg_max_size >= 2 * asg_desired_capacity`.
- `desired_capacity` is in `ignore_changes`.
- Don't put module-level `depends_on` on `module.ec2`: it defers the AMI data source and makes the launch template change on every plan (=> needless refreshes). Express ordering through outputs instead (`iam.instance_profile_name` and `app_config.path` carry `depends_on`).

## Modules
| Module | Key resources |
|---|---|
| `vpc` | VPC, ≥2 public subnets (one per AZ), IGW, default SG locked, flow logs |
| `security_group` | ALB SG (80/443 from `allowed_ingress_cidrs`), instance SG (app_port from ALB SG only, no SSH) |
| `alb` | ALB (drop invalid headers, deletion protection var), TG (`name_prefix`, health check), HTTP forward-or-redirect, HTTPS when `certificate_arn` set |
| `ec2` | Launch template (IMDSv2, encrypted gp3, pinned `ami_id` optional), ASG + instance refresh, app & cloud-init log groups |
| `ecr` | Repo per env, IMMUTABLE tags, scan on push, KMS, lifecycle |
| `app_config` | SSM `/<project>/<env>/app/*`: `settings` (String), `secret_placeholders` (SecureString, `ignore_changes = [value]`) |
| `iam` | Instance role: app bucket, own log groups, own SSM path, own ECR repo, `AmazonSSMManagedInstanceCore` |
| `s3` | App + logs buckets: KMS, versioning, public block, TLS-only policy, access logging, lifecycle, `force_destroy` var |
| `monitoring` | SNS topic (+ optional email), alarms: no healthy hosts, unhealthy hosts, target/ELB 5xx, CPU |

## Cloud-init (`cloud-init/user_data.sh.tpl`)
- Installs docker + CloudWatch agent (no `dnf update`: the AMI defines the OS).
- Sets the Docker `shutdown-timeout` to 30.
- Writes `/etc/<app>/app.env` from SSM `get-parameters-by-path`.
- Does an ECR login when the image is ECR, then `docker run --env-file` with the awslogs driver (stream = real instance ID via IMDSv2).
- Terraform `${...}` = template inputs. Bash variables use plain `$VAR`; if you need braces in bash, escape them as `$${VAR}`.

## Local testing (Floci)
- `make start-floci` starts the emulator on :4566 and Floci UI on :4500 (`make floci-ui`), both bound to 127.0.0.1 (no auth).
- On Floci, EC2 instances are containers, so cloud-init can't run Docker and ALB targets stay unhealthy. That's expected; `make test-app` covers the container.
- Known Floci-only perpetual diffs: tags on `aws_iam_instance_profile` and `aws_flow_log`.
- Git Bash on Windows rewrites `/laravel/...` CLI args. Use `MSYS_NO_PATHCONV=1` for SSM paths.

## Validation
```bash
make fmt        # terraform fmt -recursive
make validate   # init -backend=false + validate (single root)
make security   # Checkov with .checkov.yml (every skip has a reason; new findings fail)
```
CI (`.github/workflows/terraform.yml`) is **manual only** (`workflow_dispatch`): fmt, validate, preflight, Checkov, and optionally a real plan via OIDC (`AWS_ROLE_ARN`). Do not add automatic triggers unless asked.

## Gotchas
- Environment CIDRs must not overlap: local=10.10, dev=10.20, uat=10.30, prod=10.40.
- `force_destroy` is rejected in prod by a variable validation.
- Account ID comes from `data.aws_caller_identity`. There is no `aws_account_id` variable.
- State locking is S3 `use_lockfile` (Terraform ≥ 1.10). There is no DynamoDB table.
- `.terraform.lock.hcl` is committed with hashes for windows_amd64, linux_amd64, darwin_amd64 and darwin_arm64. Regenerate with `terraform providers lock -platform=...` when bumping the provider.
- No database is created. DB settings go in `app_settings`, `DB_PASSWORD` in SSM.
