# The Terraform / AWS pack

`cotterpin-pack-terraform` (package `cotterpin_pack_terraform`, pack id `terraform`) teaches Cotterpin infrastructure
as code: an exact reader of HCL, gates that stop the classic Terraform and AWS defects at commit, hook guards that stop
the toolchain's destructive commands before they run, and ten task routes that change real Terraform modules and land
only after an OFFLINE PLAN proves the change does what the task promises. Nothing in the pack ever reaches an AWS
account.

| | |
|---|---|
| install | `pip install cotterpin-pack-terraform` (its own distribution, PACK-1; [LOCK-AND-PACKS.md](LOCK-AND-PACKS.md)) |
| recognised by `cotterpin init` | a root `.terraform.lock.hcl`, `main.tf`, `versions.tf`, `providers.tf`, `terraform.tf`, `backend.tf`, `.terraform-version` or `.tflint.hcl` (names only, never contents) |
| `cotterpin doctor` probes (each only after you agree) | Terraform 1.7 or newer (`terraform version`; mock providers in `terraform test` need 1.7), TFLint 0.50 or newer (`tflint --version`) |
| tools | `cotterpin pack terraform task-list \| task-plan \| task-start \| task-drive \| task-status \| task-apply \| task-check \| task-verify \| task-revert` |
| gates | 19 (12 blocking from install, 7 advisory) — [Gates](#gates) |
| hook guards | 8 — [Hook guards](#hook-guards) |
| routes | 10 task routes, one shared workflow `terraform-task.js` — [Task routes](#task-routes) |
| skills / agents | 11 skills (`terraform-*`), 3 route personas — [SKILLS-AND-AGENTS.md](SKILLS-AND-AGENTS.md) |

## Never a real account

Every Terraform call the pack makes runs with a SCRUBBED environment: every `AWS_*` and `TF_*` variable of your shell
is removed (a profile, keys, a session token, an assumed role, `TF_CLI_ARGS` that could add `-auto-approve`), the shared
AWS config and credentials files point at nothing, the instance metadata service is off, and placeholder keys are set.
Checks run in private copies of your repository under the run's scratch (`.cotterpin/scratch/<run id>/`, hidden from
`git status`), in which each `provider "aws"` block is rewritten to skip every account check (its `alias`, `region`,
`default_tags` and `ignore_tags` kept) and every state backend is removed.

Fenced runs (validate, test, the offline plan) send every HTTP(S) request to a closed local port: if a provider tried
to call AWS — an API data source, an import, a credential check — the call fails on your machine. Measured while
building it: the same plan whose import block needs the account contacted S3 with the placeholder keys when unfenced,
and failed locally when fenced. The pack never runs `apply`, and its hook guards refuse an agent that tries.

## Never a prompt

No pack command and no pack test raises an OS credential, Keychain, password, Touch ID or browser dialog on your
machine. Every path that could is closed in the one environment every Terraform call gets: the AWS credential chain
(`credential_process` helpers such as aws-vault, granted or SSO live in the config files, which point at nothing; the
metadata service is off), Terraform's CLI configuration (`TF_CLI_CONFIG_FILE` is empty: no `credentials_helper` from
`~/.terraformrc` runs and no stored token is read), git's credential helpers for module sources (system and global git
configuration skipped, so macOS's `osxkeychain` helper is never called; `GIT_TERMINAL_PROMPT=0` makes a fetch that
needs a credential FAIL instead of asking) and ssh (`BatchMode=yes`; a running ssh agent is still used). The pack opens
no browser. The `cloud-login-prompt` hook guard refuses an agent that tries to start a sign-in that would raise one
(`terraform login`, `aws sso login` without `--no-browser`, `aws-vault` on the Keychain backend). Pinned with real
calls and a static scan of the pack and its tests by `tests/packs/terraform/test_terraform_no_prompt.py`.

Provider downloads are the one thing that needs the network. `terraform init` asks first — consent
`toolchain.terraform.providers` says what is downloaded (the providers your configuration requires, hashicorp/aws is
about 650 MB unpacked, and the registry modules it calls), from where, where it is kept (one cache per machine,
`$COTTERPIN_TERRAFORM_PLUGIN_CACHE` else `<Cotterpin cache>/terraform/plugins`) and why. Declined, or not asked in a
non-interactive shell, `init` runs from the cache only (`-plugin-dir`, nothing downloaded) and a missing provider stops
the check with `PROVIDERS_MISSING` and the exact consent to give: `cotterpin consent grant toolchain.terraform.providers`
or `--consent toolchain.terraform.providers` on the command.

## Task routes

One run changes ONE unit — a module directory of your repository — from a plan sealed by its content digest. The
route's workflow (terraform-task.js, shared by all ten)
runs the deterministic recipe through a relay, fans each judgement item the recipe could not decide out to a writer and
a DIFFERENT reviewer, and hands the result to one deterministic verify lane. The kernel commits the frontier; the
workflow never runs `git add`, `git commit`, `git push` or `terraform apply`.

```text
cotterpin pack terraform task-list
cotterpin pack terraform task-plan  --task <task> --module <dir> [--param name=value ...]
cotterpin pack terraform task-start --task <task> --module <dir> [--param name=value ...]
cotterpin pack terraform task-drive  --tree <tree> --run-id <id>
```

| task (`--task`) | route / manifest | mechanical (the recipe) | judgement (writer + reviewer) | the offline plan must show |
|---|---|---|---|---|
| `eks-upgrade` | `terraform_eks_upgrade` / TERRAFORM-EKS-UPGRADE | the cluster's version (or the variable default it names) +1 minor; node groups at the old version follow | a node group with no version or a string cluster name; an AMI `release_version`; an add-on version chosen for the old version; a `kubernetes_manifest` on an API the new version removed | cluster and node groups UPDATE in place; nothing replaced, created or destroyed |
| `ec2-patch` | `terraform_ec2_patch` / TERRAFORM-EC2-PATCH | ami: every literal AMI of launch templates and instances, `latest_version` for groups pinned to a numbered version, a rolling `instance_refresh`; ssm: `ssm_patching.tf` (baseline, patch group, window, target, `AWS-RunPatchBaseline`) | a group on the template's `$Default` version | ami: no destroy, an instance replaced only with `--param allowReplace=true`; ssm: only the patching resources created |
| `redis-create` | `terraform_redis_create` / TERRAFORM-ELASTICACHE-REDIS | `redis_<name>.tf`: replication group with encryption at rest and in transit, IAM authentication through a user group (no static password; the default user off), Multi-AZ failover, a dedicated security group open to the named groups only | — | exactly those resources CREATED, nothing that exists changes, both encryption settings on |
| `rds-postgres-create` | `terraform_rds_postgres_create` / TERRAFORM-RDS-POSTGRES | `rds_<name>.tf`: never public, encrypted, `manage_master_user_password`, TLS forced by a parameter group, IAM auth, deletion protection, final snapshot, backups, Performance Insights, storage autoscaling | — | exactly those resources CREATED; the planned instance private, encrypted, protected, password managed |
| `aws-provider-upgrade` | `terraform_aws_provider_upgrade` / TERRAFORM-AWS-PROVIDER-UPGRADE | hashicorp/aws one major (`~> N.0`; local child modules widened to a minimum), that major's renames, the lock file moved with `init -upgrade` (consent) | every removed resource or argument, named with its replacement | validate against the NEW provider; the old state upgraded by it; no destroy, no replacement |
| `s3-secure-bucket` | `terraform_s3_secure_bucket` / TERRAFORM-S3-SECURE-BUCKET | `s3_<name>.tf`: public access blocks on, ACLs disabled, default encryption (SSE-KMS with a bucket key, or SSE-S3), versioning, TLS-only policy, lifecycle clean-up, optional logging | — | exactly those resources CREATED |
| `vpc-create` | `terraform_vpc_create` / TERRAFORM-VPC | `vpc_<name>.tf`: public and private subnets per zone by `cidrsubnet` (no overlap by construction), no public IPs by default, NAT per zone / single / none, flow logs, the default security group emptied | — | exactly those resources CREATED; every PLANNED subnet range inside the VPC range, none overlapping |
| `iam-oidc-role` | `terraform_iam_oidc_role` / TERRAFORM-IAM-OIDC-ROLE | `iam_role_<name>.tf`: trust with `aud` AND `sub` conditions naming exactly the subjects (never `*` or `repo:*`), an inline policy of exactly the actions and resources (never a wildcard), the provider when none is named | — | exactly those resources CREATED |
| `import` | `terraform_import` / TERRAFORM-IMPORT | `imports.tf` import blocks (never `terraform import`), `imported.tf` resource blocks with the identifying argument from the id | every other argument the real resource has (marked `cotterpin:fill`) | an import reads the account, so instead: a mocked `terraform test` (mock provider + an override per address) plans every import |
| `moved-refactor` | `terraform_moved_refactor` / TERRAFORM-MOVED-REFACTOR | the block renamed, every reference rewritten (attributes, interpolations, `depends_on`; never a longer name that starts the same), `moved` blocks in `moved.tf`, an earlier move's `to` carried forward | moving a resource's text into a child module | every requested MOVE, and no create, destroy, replacement or update |

Each route ships its manifest (`manifests/`), route declaration (`routes/`), runbook (`runbooks/`) and skill
(`skills/terraform-*`); the parameters of each task are in its runbook and in `task-list`.

### The verify lane

`cotterpin pack terraform task-verify` runs the whole verification in one detached process (a first provider download
can outlive one agent shell call: exit 3 means "still running, run the same command again", and the same command never
starts a second lane). In order, stopping at the first failure:

| step | refuses with |
|---|---|
| changed paths inside the manifest's write set and the unit's directories | `NOTHING_CHANGED`, `OUTSIDE_SCOPE` |
| the recipe's residue check (what a finished unit must no longer contain) | `RESIDUE` |
| the pack's gates on the changed files (blocking findings only) | `GATES_BLOCKING` |
| `terraform fmt -check` on your own files | `FORMAT` |
| `terraform init -backend=false` (consent for downloads) | `PROVIDERS_MISSING`, `INIT_FAILED` |
| `terraform validate -json` (errors go to one repair round) | `VALIDATE_FAILED` |
| `tflint` (errors refuse; warnings are reported) | `TFLINT_FAILED` |
| the unit's `terraform test` files (and, for an import, the generated mocked test) | `TEST_FAILED` |
| the offline plan and the task's plan policy | `OFFLINE_PLAN_UNAVAILABLE`, `PLAN_FAILED`, `PLAN_REFUSED` |
| the frontier: paths, byte states, digest | `COMMIT_READY` |

### The offline plan

1. The BASE commit is planned against an empty state; its planned values are the infrastructure the base describes.
2. They become a version-4 state, each resource with its provider schema version. What the plan left unknown (computed
   by the account at apply time) gets a KNOWN placeholder of the schema's type — an id in AWS's shape (`lt-…`,
   `sg-…`, `subnet-…`), an ARN in AWS's shape, empty collections — because a null would make the provider plan the
   attribute again, and for one that forces replacement that is a replacement the real plan would never show. When the
   change writes that very argument as a literal (`vpc = true` becoming `domain = "vpc"`), the literal is used.
3. The state is CONVERGED: the base configuration is planned against it, every value the plan now knows is taken back
   into it (a bucket's id flows into the versioning that names the bucket), and an attribute the provider rewrites on
   every plan (a hashed `user_data`) is reset to null. It must settle to an all-no-op plan — exactly what a real apply
   leaves — or the lane reports `OFFLINE_PLAN_UNAVAILABLE` and never claims a pass.
4. The change is planned against that state with `-refresh=false`, behind the fence, and the task's policy judges the
   plan's own `resource_changes`.

Stated limits: a unit that reads the account at plan time (an API data source such as `aws_ami` or
`aws_caller_identity`, an `import` block) cannot be planned offline and is reported, never passed; a value the base
left to the account that the change now writes is taken as matching (an account holding something else would show a
replacement in the real plan). The real plan before any apply remains a person's decision — the hook guards make sure.

## Gates

A gate reads `*.tf` files (never `.terraform/` downloads) through the pack's HCL reader and judges LITERAL values only:
a reference, a call or an interpolation is never guessed at. Each has red and green fixtures under
`cotterpin_pack_terraform/gates/fixtures/<ID>/`, proven by `cotterpin gate fixtures <ID>`; allow one deliberate
exception with `# cotterpin:allow <ID> <reason>` on the line or the line above. Enforcement follows the readiness bar
of GATE-PACK-V1.md: zero false positives on the calibration corpus, or a finding that is a certain
failure at apply time, blocks from install; everything whose intent the code cannot show is advisory.

| gate | enforcement | catches |
|---|---|---|
| TF-SG-WORLD-ADMIN-1 | blocking | SSH, RDP, WinRM, container or cluster APIs, databases or caches open to `0.0.0.0/0` / `::/0` |
| TF-IAM-OIDC-TRUST-1 | blocking | a role trusting an OIDC provider with no `sub` condition (or `*` / `repo:*`) |
| TF-IAM-ADMIN-WILDCARD-1 | blocking | an identity policy allowing `*` on `*` with no condition |
| TF-PROVIDER-UNPINNED-1 | blocking | a `required_providers` entry with no version constraint |
| TF-MODULE-UNPINNED-1 | blocking | a registry module with no `version`, a Git module with no `ref` or a branch `ref` |
| TF-HARDCODED-SECRET-1 | blocking | a literal password, token, key, secret string or sensitive variable default |
| TF-EKS-VERSION-SKIP-1 | blocking | a change moving an EKS cluster more than one minor, or backwards |
| TF-EKS-NODE-SKEW-1 | blocking | a managed node group newer than its cluster |
| TF-SUBNET-CIDR-1 | blocking | overlapping subnets of one VPC, or a subnet outside its VPC's range |
| TF-RDS-PUBLIC-1 | blocking | `publicly_accessible = true` on a database instance |
| TF-STORAGE-UNENCRYPTED-1 | blocking | an RDS instance or Aurora cluster without encryption, an explicitly unencrypted volume or cache |
| TF-S3-PUBLIC-WRITE-1 | blocking | a bucket anyone can write to or delete from (ACL, grant or policy) |
| TF-S3-PUBLIC-READ-1 | advisory | a public-read ACL or grant, a public access block switched off, a public read policy |
| TF-ELASTICACHE-TRANSIT-1 | advisory | a replication group without encryption in transit |
| TF-IMDSV1-1 | advisory | `http_tokens = "optional"` (IMDSv1) |
| TF-RDS-FINAL-SNAPSHOT-1 | advisory | `skip_final_snapshot = true` without deletion protection |
| TF-KMS-ROTATION-1 | advisory | a symmetric key without automatic rotation |
| TF-EKS-PUBLIC-ENDPOINT-1 | advisory | an EKS API endpoint open to the whole internet |
| TF-RENAME-WITHOUT-MOVED-1 | advisory | a change renaming a resource or module call with no `moved` block (destroy + create) |

### Gate calibration

Corpus, measured 2026-10-05: 1,559 `.tf` files — two private infrastructure repositories (211 files) and 14 public
`terraform-aws-modules` releases (VPC, EKS, RDS, RDS Aurora, S3, IAM, security group, ElastiCache, EC2, Auto Scaling,
KMS, Lambda, ALB, ECS) with their examples and sub-modules (1,348 files); every file parsed (0 failures). The two
change gates were replayed over the 955 commits of the two private repositories' history that touched a `.tf` file.
Every hit was read by hand.

| gate | record |
|---|---|
| **KMS-IMMUTABLE-POLICY-READS-1** | wave nine (w9-e), not replayed over this corpus: zero false positives on the operator's key module; an immutable key policy without the provider's read actions makes every later plan of that key fail |
| **TF-ACCOUNT-BOUNDARY-1** | wave nine (w9-e), not replayed over this corpus: judged only against the accounts the repository declares (`accountBoundary` in `.cotterpin/gates.yaml`) |
| **TF-SG-WORLD-ADMIN-1** | 29 literal ingress rules, 0 hits |
| **TF-IAM-OIDC-TRUST-1** | 2 web-identity trust statements, 0 hits (both pin their `sub`) |
| **TF-IAM-ADMIN-WILDCARD-1** | 279 policy statements, 1 hit, true: a hand-written super-admin policy |
| **TF-PROVIDER-UNPINNED-1** | 398 `required_providers` entries, 0 hits |
| **TF-MODULE-UNPINNED-1** | 143 remote module calls, 5 hits, all true (public examples with unpinned registry modules) |
| **TF-HARDCODED-SECRET-1** | 40 secret-bearing arguments and 8 sensitive variables, 0 hits |
| **TF-EKS-VERSION-SKIP-1** | 955 commits replayed, 0 hits; a hit is a certain apply failure |
| **TF-EKS-NODE-SKEW-1** | 1 node group (follows its cluster), 0 hits; a hit is a certain apply failure |
| **TF-SUBNET-CIDR-1** | 11 subnets, all ranges computed, 0 judged; a hit is a certain apply failure (arithmetic) |
| **TF-RDS-PUBLIC-1** | 4 database resources plus the public RDS modules, 0 hits |
| **TF-STORAGE-UNENCRYPTED-1** | 4 databases, 14 volumes/instances/templates, 3 replication groups, 0 hits |
| **TF-S3-PUBLIC-WRITE-1** | 23 ACL, access-block and policy resources, 0 hits |
| **TF-S3-PUBLIC-READ-1** | 11 hits, accurate, on two buckets public on purpose |
| **TF-ELASTICACHE-TRANSIT-1** | 3 replication groups, 1 hit, accurate |
| **TF-IMDSV1-1** | 2 `metadata_options` blocks, 0 hits |
| **TF-RDS-FINAL-SNAPSHOT-1** | 0 hits |
| **TF-KMS-ROTATION-1** | 17 keys, 10 hits, accurate (one switched off explicitly, nine in public examples) |
| **TF-EKS-PUBLIC-ENDPOINT-1** | 1 cluster (private endpoint), 0 hits |
| **TF-RENAME-WITHOUT-MOVED-1** | 955 commits replayed, 152 hits, each an accurate destroy + create, many deliberate redesigns |

The corpus is thin for the EKS and literal-subnet gates; they block because a hit is a certain failure at apply time
(the type-error kind), and a false positive found on any further corpus demotes a gate to advisory in its table row.

## Hook guards

Through `cotterpin hook <event>` ([HOOKS.md](HOOKS.md)); a guard names its risk tier, and the kernel's policy decides
what happens. Each check starts with a substring test, so a command that names none of these programs costs
microseconds: measured median under 0.1 ms and 99th percentile under 1 ms per guard (`test_terraform_hooks.py`).

| guard | refuses | tier | instead |
|---|---|---|---|
| `terraform-apply-unreviewed` | `terraform apply` without a saved plan, or with `-auto-approve` (any apply by an agent is refused first by `terraform-operator-only`) | destructive (saved plan: sensitive write) | change the code, `terraform validate` (and `terraform plan -out=tfplan` without a remote backend), commit and push; the operator applies |
| `terraform-destroy` | `terraform destroy`, `apply -destroy` | destructive | remove the resources and plan, or a `removed` block |
| `terraform-state-surgery` | `state rm/mv/push/replace-provider`, `import`, `taint`/`untaint`, `force-unlock` | destructive | `removed`, `moved`, `import` blocks, `plan -replace` |
| `terraform-lock-disabled` | `-lock=false` | sensitive write | find the run that holds the lock |
| `terraform-state-file-edit` | an editor tool writing `*.tfstate` | destructive | moved/removed/import blocks |
| `kubectl-destructive` | `kubectl delete` of a namespace or `--all`/`-A` (pods excepted), `replace --force`, `helm uninstall` | destructive | delete the named objects, or change the manifests and diff |
| `aws-cli-destructive` | AWS CLI deletes/terminations (`s3 rb --force`, `s3 rm --recursive`, `ec2 terminate-instances`, `rds delete-db-*`, `eks delete-*`, ...); `eks update-cluster-version` (sensitive write) | destructive | change the Terraform configuration and review the plan |
| `cloud-login-prompt` | `terraform login`; `aws sso login`, `aws configure sso`, `aws login` without `--no-browser`; `aws-vault` on the macOS Keychain backend — each raises a browser window or an OS credential dialog | destructive | none needed: the pack plans offline with placeholder keys; the person signs in themselves when they choose |

Refusal codes `hook-terraform-*`, `hook-kubectl-destructive`, `hook-aws-cli-destructive`, `hook-cloud-login-prompt` and the task codes
`terraform-task-*`, `terraform-toolchain` are explained by `cotterpin explain <code>` ([REFUSALS.md](REFUSALS.md)).

## Tests

`tests/packs/terraform/`: the HCL reader, the gates (the kernel's own fixture harness, calibration records, a per-file
speed budget), the hook guards through the real `cotterpin hook` entrypoint, the recipes as pure functions, the shared
workflow under real node (the agent is the one simulated boundary), and `test_terraform_tasks_real.py` — every task
route GREEN and RED against real Terraform projects made with the real CLI (`terraform init` installs the real
hashicorp/aws provider and writes the real lock file), with real `fmt`, `validate`, `tflint`, `terraform test` and the
offline plan. The real-tool tests are in the deferred tier ([TEST-TIERS.md](TEST-TIERS.md)); with
`COTTERPIN_REAL_TOOLS=require` a missing tool fails them. Providers are downloaded once into
`~/.cache/cotterpin-tests/terraform-plugins`.
