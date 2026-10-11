# Skills and agents that ship with Cotterpin

Cotterpin ships agent knowledge in two places:

| where | what | rule |
|---|---|---|
| `cotterpin/library/skills/<name>/SKILL.md`, `cotterpin/library/agents/<name>.md` | **product** — how to work safely and verifiably under Cotterpin, in any language | names no language and no customer |
| `cotterpin_pack_java/skills/<name>/SKILL.md`, `cotterpin_pack_java/agents/<name>.md` | **Java pack** — Java, Spring, JPA and Maven knowledge any Java repository needs | names no customer; every name starts with `java-` |
| `cotterpin_pack_angular/skills/<name>/SKILL.md`, `cotterpin_pack_angular/agents/<name>.md` | **Angular pack** — Angular, TypeScript, RxJS, npm and Playwright knowledge any Angular workspace needs | names no customer; every name starts with `angular-` |
| `cotterpin_pack_terraform/skills/<name>/SKILL.md`, `cotterpin_pack_terraform/agents/<name>.md` | **Terraform / AWS pack** — Terraform, AWS provider, EKS and Kubernetes knowledge any infrastructure repository needs | names no customer; every name starts with `terraform-` |
| `cotterpin_pack_dotnet/skills/<name>/SKILL.md`, `cotterpin_pack_dotnet/agents/<name>.md` | **.NET pack** — one skill per .NET task route (when to use, steps, traps) | names no customer; every name starts with `dotnet-` |
| `cotterpin_pack_python/skills/<name>/SKILL.md`, `cotterpin_pack_python/agents/<name>.md` | **Python pack** — uv, typing, framework, migration and release knowledge any Python repository needs | names no customer; every name starts with `python-` |

Every file has YAML frontmatter with `name` (equal to its directory or file name) and `description`; an agent may also
declare `tools` and `model`. Both trees are package data (`pyproject.toml`) and runtime paths in the release descriptor,
so an installed Cotterpin carries them.

`tests/conformance/test_shipped_skills_and_agents.py` enforces, for every shipped file: valid frontmatter; no
customer-identifying text (the identifiers of `tools/ci/customer_neutrality.py` plus customer paths, rule numbers,
session numbers and dated incident history); no language or framework terms in the product tree; every
`cotterpin <command>` and `cotterpin pack java <command>` it tells an agent to run exists (or is an RC1 command being
built by another group, listed in that test); and that this page lists it.

The kernel's own routes (audit, fix, documents, knowledge bundle, route governance, release triage) carry their persona
definitions beside them, in `cotterpin/kernel/agents/cotterpin-*.md`, exactly as a pack's routes carry theirs in the
pack. They are documented by those routes' runbooks and by WORKFLOWS.md, not by this page, and
`tests/kernel/test_kernel_product_routes.py` holds them to the same frontmatter, neutrality and command rules.

## Classification of the first customer's skills and agents

Each input was classified as:

- **PRODUCT** — generic harness knowledge any Cotterpin user needs; rewritten product-neutral into the product library.
- **PACK** — Java-specific knowledge any Java repository needs; rewritten customer-neutral into the Java pack.
- **CONSUMER** — about that customer's codebase, domain, architecture rules or history. It stays in the customer's
  repository and is not shipped. Where an input mixed generic truths with customer rules, the generic part was folded
  into the shipped file named in the "shipped as" column and the rest stays with the customer.

The customer's skill names carry a repository prefix, omitted below. Commands were rewritten to Cotterpin verbs
(`cotterpin commit`, `cotterpin check`, `cotterpin pack java ...`); customer script paths, rule ids, session numbers,
incident dates and names were removed.

### Skills (34)

| input | decision | shipped as | reason |
|---|---|---|---|
| api | CONSUMER | — | the customer's API spec regeneration and three specific front-end clients |
| autonomous-shell-safety | PRODUCT | `unattended-shell-safety` | every unattended run is halted by an approval prompt or a hung command, in any repository |
| caching | CONSUMER | `java-spring-runtime-traps` (generic part) | the customer's cache registry and rule numbers; the Spring proxy and cache-error truths are generic |
| claim-verification | PRODUCT | `claim-verification` | re-deriving claims and spotting vacuous passes applies to every audit and agent |
| column-rename | PACK | `java-schema-migrations` | the compiler-blind places a renamed column hides are Java/JPA/Flyway truths; the batch history is the customer's |
| commit-and-push | PRODUCT | `commit-route` | one commit door, ownership first, proving HEAD moved and never self-serving approvals are product behaviour |
| controller-api-dto | CONSUMER | — | the customer's controller and DTO architecture rules |
| dao-pattern | CONSUMER | `java-persistence-pitfalls` (generic part) | the customer's data-access base class and conventions; the JPQL, result-type and bulk-update pitfalls are generic |
| defaults-and-resilience | CONSUMER | `java-spring-runtime-traps` (generic part) | the customer's domain defaults; the rollback-only mechanism is a Spring truth |
| delivery-audit | PRODUCT | `delivery-audit` | the census, audit, refute, reconcile, crystallise loop and behaviour-based staleness are product doctrine |
| deployment-ops | CONSUMER | `java-maven-build-truth` (generic part) | the customer's cloud deployment and health checks; the build-cache truths are Maven truths |
| destub-campaign | PACK | `java-test-destub` | converting mocked Java tests on the de-stub route is the Java pack's first manifest |
| entity-persistence | CONSUMER | `java-persistence-pitfalls` (generic part) | the customer's entity rules; rename completeness and save-by-id are generic |
| events-async-audit | CONSUMER | `java-spring-runtime-traps` (generic part) | the customer's event and audit-log rules; listener and async safety are generic |
| explanation-contract | CONSUMER | — | the customer's user-facing message contract and domain boundary |
| flyway-migrations | PACK | `java-schema-migrations` | idempotence, type matching and two-step destructive change apply to any Flyway codebase; the naming scheme and deploy steps are the customer's |
| gate-authoring | PRODUCT | `gate-authoring` | promote-at-zero, the scanner contract and self-verifying generators apply to every check |
| llm-bedrock | CONSUMER | — | the customer's model gateway and prompt patterns |
| (new) building the Lambda packages | PRODUCT | `lambda-build` | building the approval broker and licensing Lambda packages from a committed tree and locked wheels, and reading each refusal, is product operations (7 October 2026) |
| (new) Founding Developers applications | PRODUCT | `founding-developers` | the programme's application routes, capacity and refusals live in the product's licence service (7 October 2026) |
| (new) keeping the knowledge bundle | PRODUCT | `knowledge-bundle` | one home per fact (the bundle for how a repository is built and run, its product documents for how it is used), a concept naming every asset it covers, and closing coverage gaps are the same in every repository (10 October 2026) |
| (new) agent memory folders | PRODUCT | `memory` | searching, showing and noting facts through `cotterpin memory` (docs/product/MEMORY.md), never writing a store by hand, is how every agent uses durable memory |
| n-plus-one | PACK | `java-persistence-pitfalls` | pre-fetch, batch-save and unnest patterns apply to any JPA codebase |
| naming-and-file-manifest | CONSUMER | — | the customer's naming conventions and feature file manifest |
| okf-version-migration | PRODUCT | `okf-version-migration` | the OKF library ships in the product; version migration is the same in every repository |
| pg-cortex | CONSUMER | — | the customer's product domain |
| quality-gate | PRODUCT | `gate-integrity` | never weaken a check, shrink-only baselines and asking before architectural decisions are product rules |
| refactor-integration | PACK | `java-refactor-integration` | multi-module contract manifests and reactor test-compile apply to any Maven repository |
| rules-in-code | CONSUMER | — | about the customer's rule store and rule engine |
| safety-fix | CONSUMER | — | the customer's safety domain and its policy documents |
| security | PACK | `java-security-basics` | SecureRandom, password hashing and bound SQL are Java security basics |
| service-layer | CONSUMER | — | the customer's service-layer architecture rules |
| session-protocol | PRODUCT | `session-start` | inheriting proof and running only the delta is how every Cotterpin session starts |
| shell-and-output-safety | PRODUCT | `unattended-shell-safety` | never filtering live output and never editing source through the shell apply everywhere |
| svc6-drain | CONSUMER | — | drains one of the customer's own architecture rules |
| testing | PACK | `java-integration-testing` | delta test runs and the Spring/JPA full-suite traps apply to any Java repository |
| webhook-verification | PACK | `java-security-basics` | raw-body signature verification and failing closed apply to any Java webhook |
| workflow-authoring | PRODUCT | `route-authoring` | keeping a route's declaration, contract, workflow, runbook and personas in agreement is product behaviour |

### Agents (13)

| input | decision | shipped as | reason |
|---|---|---|---|
| capability-census | PRODUCT | `capability-census` | the first phase of the product's delivery audit |
| delivery-auditor | PRODUCT | `delivery-auditor` | the audit's adversarial judge; the customer's domain boundary became a generic "scope policy" check |
| delivery-reconciler | PRODUCT | `delivery-reconciler` | merges verdicts and downgrades overstated markers in any repository |
| delivery-refuter | PRODUCT | `delivery-refuter` | the opposite-prior check against every non-delivered verdict |
| gate-crystalliser | PRODUCT | `gate-crystalliser` | turns confirmed finding classes into checks in any repository |
| general-reviewer | PRODUCT | `general-reviewer` | default reviewer persona for a route role with no specialist |
| general-worker | PRODUCT | `general-worker` | default worker persona for a route role with no specialist |
| guard-adversary | PRODUCT | `guard-adversary` | refutes changes to guards and enforcement claims in any repository |
| okf-cartographer | PRODUCT | `okf-cartographer` | records proven structure in the repository's OKF bundle |
| refactor-integration-verifier | PACK | `java-refactor-integration-verifier` | contract manifests and reactor commands for Java modules |
| safety-boundary-verifier | CONSUMER | — | the customer's safety domain and medical-boundary policy |
| svc6-drain | CONSUMER | — | drains one of the customer's own architecture rules |
| workflow-governance-curator | PRODUCT | `route-governance-curator` | audits any repository's routes for completeness and agreement |

### Shipped files with no single input

Every shipped skill and agent traces to at least one input above, except the agents a pack route names as its personas
(`routes/<task>.json` → `personas`): those are documented by their route's runbook. They still obey every other rule on
this page.

### Written for the product (no customer input)

| input | decision | shipped as | reason |
|---|---|---|---|
| (none: the policy layer, RC1) | PRODUCT | `approvals-and-questions` | risk tiers, pending approvals a person gives with `cotterpin approve`, and asking the developer a question (which never grants anything) are the harness's protocol in every repository ([APPROVALS.md](APPROVALS.md)) |
| (none: the Python pack, RC1) | PACK | `python-version-upgrade`, `python-uv-migration`, `python-add-mypy`, `python-framework-upgrade`, `python-fastapi-endpoint`, `python-pydantic-v2`, `python-vuln-fix`, `python-alembic-migration`, `python-raise-coverage`, `python-wheel-release` | one skill per Python work route (when to use it, its steps, its traps), written for the pack; any Python repository needs them, none names a repository ([PACK-PYTHON.md](PACK-PYTHON.md)) |
| (none: the Angular pack's upgrade route) | PACK | `angular-upgrade` | one major per run with ng update and its migrations is how every Angular workspace upgrades ([PACK-ANGULAR.md](PACK-ANGULAR.md)) |
| (none: the Angular pack's toolchain route) | PACK | `angular-node-ts-upgrade` | TypeScript and Node.js read from the installed Angular's own manifests |
| (none: the Angular pack's standalone route) | PACK | `angular-standalone-migration` | Angular's own schematic, one mode per run, applies to every NgModule-based application |
| (none: the Angular pack's feature route) | PACK | `angular-add-feature` | a generated component with its own lazy route, proven lazy by the build |
| (none: the Angular pack's API route) | PACK | `angular-api-service` | a typed HttpClient service, a registered functional interceptor and HttpTestingController specs |
| (none: the Angular pack's RxJS route) | PACK | `angular-rxjs-upgrade` | RxJS inside Angular's peer range and off its deprecated APIs, toPromise() decided by a reviewed writer |
| (none: the Angular pack's strict route) | PACK | `angular-strict-mode` | strict TypeScript and template checks on, errors fixed with types, never suppressed |
| (none: the Angular pack's lazy route) | PACK | `angular-lazy-loading` | eager routes made lazy, proven by a smaller measured initial bundle |
| (none: the Angular pack's end-to-end route) | PACK | `angular-e2e-playwright` | Playwright against the running application, every action and assertion awaited |
| (none: the Angular pack's vulnerability route) | PACK | `angular-npm-audit` | npm audit fix within each declared major, never --force, proven by a fresh advisory report |

### Written for the Terraform / AWS pack (no customer input)

Each task route of the pack ([PACK-TERRAFORM.md](PACK-TERRAFORM.md)) ships the skill an agent reads before doing that
task by hand or reviewing it; the route's personas (`terraform-task-relay`, `terraform-task-writer`,
`terraform-task-reviewer`) are documented by the routes' runbooks.

| input | decision | shipped as | reason |
|---|---|---|---|
| (none: the Terraform pack, RC1) | PACK | `terraform-plan-safety` | saved and reviewed plans, declarative state changes and the pack's hook guards apply to every Terraform repository |
| (none: the Terraform pack, RC1) | PACK | `terraform-eks-upgrade` | the EKS upgrade order, node group skew and removed Kubernetes APIs are Amazon EKS truths |
| (none: the Terraform pack, RC1) | PACK | `terraform-ec2-patching` | AMI rolls through launch templates and SSM patch baselines apply to any EC2 fleet |
| (none: the Terraform pack, RC1) | PACK | `terraform-elasticache-redis` | ElastiCache encryption, AUTH and failover defaults apply to any Redis or Valkey cluster |
| (none: the Terraform pack, RC1) | PACK | `terraform-rds-postgres` | private, encrypted, managed-password RDS defaults apply to any PostgreSQL database |
| (none: the Terraform pack, RC1) | PACK | `terraform-aws-provider-upgrade` | the hashicorp/aws major upgrade steps apply to any configuration using that provider |
| (none: the Terraform pack, RC1) | PACK | `terraform-s3-secure-bucket` | the private, encrypted, TLS-only bucket resources apply to any S3 bucket |
| (none: the Terraform pack, RC1) | PACK | `terraform-vpc-design` | non-overlapping cidrsubnet layouts, NAT and flow logs apply to any VPC |
| (none: the Terraform pack, RC1) | PACK | `terraform-iam-oidc-role` | aud and sub trust conditions and least privilege apply to any OIDC-assumed role |
| (none: the Terraform pack, RC1) | PACK | `terraform-import` | import blocks instead of the import command apply to any Terraform adoption of existing resources |
| (none: the Terraform pack, RC1) | PACK | `terraform-moved-refactor` | moved blocks and a plan with no destroy apply to any Terraform refactor |

### Written for the .NET pack (no customer input)

Each .NET task route ([PACK-DOTNET.md](PACK-DOTNET.md)) ships one skill: when to use the route, its steps, and the
traps of that task. Their personas (`dotnet-task-relay`, `dotnet-task-writer`, `dotnet-task-reviewer`) are route
personas, documented by the routes' runbooks.

| input | decision | shipped as | reason |
|---|---|---|---|
| (none: route `dotnet_upgrade`) | PACK | `dotnet-upgrade` | raising a project's target framework, its framework packages and its removed APIs |
| (none: route `dotnet_ef_migration`) | PACK | `dotnet-ef-core-migrations` | EF Core versions, the local `dotnet-ef` tool and migrations that keep data |
| (none: route `dotnet_webapi_endpoint`) | PACK | `dotnet-web-api-endpoints` | a minimal-API resource with integration tests through the real pipeline |
| (none: route `dotnet_nullable`) | PACK | `dotnet-nullable-reference-types` | enabling the analysis with its ratchet and closing warnings honestly |
| (none: route `dotnet_nuget_vulnerable`) | PACK | `dotnet-vulnerable-packages` | direct and transitive advisory fixes and central package management |
| (none: route `dotnet_health_otel`) | PACK | `dotnet-health-and-telemetry` | liveness versus readiness probes and an exporter for OpenTelemetry |
| (none: route `dotnet_stj_migration`) | PACK | `dotnet-system-text-json` | moving off Newtonsoft.Json without changing the JSON on the wire |
| (none: route `dotnet_hosted_worker`) | PACK | `dotnet-hosted-services` | background workers with scopes, timers, cancellation and failure handling |
| (none: route `dotnet_jwt_auth`) | PACK | `dotnet-jwt-authentication` | bearer token validation, secrets and a secure-by-default policy |
| (none: route `dotnet_containerise`) | PACK | `dotnet-containers` | multi-stage, non-root images whose entry point is the built assembly |

## Consumer skills and agents (the extensions list)

The CONSUMER inputs stay in the first customer's repository. They are listed here so the extensions mechanism
(`.cotterpin/extensions.json`, pinned in the repository's lock — see the product-contract-and-extensions decision record
in `docs/adr/`) can declare them once it accepts skills and agents:
api, caching, controller-api-dto, dao-pattern, defaults-and-resilience, deployment-ops, entity-persistence,
events-async-audit, explanation-contract, llm-bedrock, naming-and-file-manifest, pg-cortex, rules-in-code, safety-fix,
service-layer, svc6-drain (skills); safety-boundary-verifier, svc6-drain (agents).

Until then a repository keeps its own skills and agents in its agent host's own settings directory, beside the shipped
ones. A repository file never replaces a shipped file of the same name; give it a different name.

## Adding a shipped skill or agent

1. Decide PRODUCT or PACK by the rule above; anything about one repository is not shipped.
2. Write it under the matching tree with frontmatter `name` and `description`.
3. Add its path, sorted, to `runtimePackagePaths` in `cotterpin/release/manifests/release-descriptor-v1.json`.
4. Add a row to this page.
5. Run `tests/conformance/test_shipped_skills_and_agents.py`.
