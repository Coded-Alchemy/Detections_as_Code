# Detection-as-Code Pipeline

## Overview

This repository implements a Detection-as-Code (DaC) pipeline that treats security detection rules as version-controlled software. Sigma rules authored by detection engineers are automatically validated, converted to Splunk SPL, and deployed to a live Splunk instance through a fully automated CI/CD pipeline built on GitHub Actions and Terraform.

The pipeline enforces a strict separation between authoring, validation, and deployment. No detection rule reaches production without passing schema validation, SPL conversion, Terraform planning, and a mandatory human approval gate. Every deployment is traceable to a commit, a branch, and a named actor.

---

## Architecture

### Repository Structure

```
.
├── .github/
│   ├── actions/
│   │   ├── splunk-health-check/   # Composite: verify Splunk API reachability
│   │   ├── terraform-cache/       # Composite: restore provider plugin cache
│   │   ├── terraform-env/         # Composite: inject TF_VAR_* secrets
│   │   ├── terraform-init/        # Composite: init, fmt, commit formatted files
│   │   └── secure-tmpdir/         # Composite: job-scoped temp directory
│   └── workflows/
│       └── detection-pipeline.yml # Main CI/CD workflow
├── sigma_rules/                   # Source of truth: Sigma detection rules
│   └── windows/
│       └── *.yml
├── generated/
│   └── splunk/                    # Auto-generated SPL files (not committed)
│       └── *.spl
├── terraform/
│   ├── locals.tf                  # Auto-generated from Sigma rules
│   ├── saved_searches.tf          # Splunk saved search resource definitions
│   ├── providers.tf               # Splunk provider configuration
│   ├── variables.tf               # Input variable declarations
│   └── backend.tf                 # Terraform backend configuration
└── scripts/
    ├── generate_locals.py         # Sigma → locals.tf code generation
    ├── validate_sigma_rules.py    # Sigma schema linter
    ├── diff_detections.py         # PR detection change summary
    ├── convert_sigma_to_spl.sh    # Sigma → SPL conversion runner
    ├── import_existing_searches.py # locals.tf parser for import matching
    ├── import_splunk_searches.sh  # Terraform state import orchestrator
    ├── pre_cleanup_state.sh       # Stale state removal before planning
    ├── cleanup_stale_state.sh     # Post-import stale state removal
    └── validate_splunk_resources.sh # State-to-Splunk resource validation
```

### Pipeline Job Graph

```
[1] preflight        Splunk health check + detection diff summary
     │
    [2] validate      Sigma schema lint — hard fail on any invalid rule
     │
    [3] build         Generate locals.tf artifact from Sigma metadata
     │
  ┌──┴──┐
 [4]   [5]           Parallel execution
convert tf-init      Sigma→SPL + upload  |  provider cache + fmt + init + commit
  └──┬──┘
     │
    [6] tf-state-sync   pre-cleanup → import → stale cleanup
     │
    [7] tf-validate     API-level validation of every state resource
     │
    [8] tf-plan         terraform plan + upload plan artifact
     │
    [9] tf-apply        main branch only · manual approval gate
                        terraform apply + deployment summary
```

Jobs 4 and 5 run in parallel after build completes, converging at job 8 (`tf-plan`), which only executes when both branches have passed. This means a SPL conversion failure and a Terraform state failure are independent — either will block the plan without requiring the other to complete first.

---

## Triggers

| Event | Branch | Jobs Executed |
|-------|--------|---------------|
| `pull_request` | `main`, `dev` | Jobs 1–8 (plan only, no apply) |
| `push` | `dev` | Jobs 1–8 (plan only, no apply) |
| `push` | `main` | Jobs 1–9 (full deploy, approval required) |

Pull requests never trigger apply. The pipeline acts as a validation and preview gate on PRs, giving reviewers a complete picture of what will change before merge.

---

## Detection Authoring

### Sigma Rule Format

All detection rules are authored in [Sigma](https://github.com/SigmaHQ/sigma) format and stored under `sigma_rules/`. Sigma is a vendor-neutral detection rule standard that the pipeline converts to Splunk SPL at build time.

Each rule must conform to the following schema:

```yaml
title: "Human readable rule name"
status: stable          # stable | test | experimental | deprecated | unsupported
description: "What this rule detects and why it matters"
level: high             # critical | high | medium | low | informational
logsource:
  product: windows
  service: security
detection:
  selection:
    EventID:
      - 4625
  condition: selection
falsepositives:
  - Legitimate administrative activity
tags:
  - attack.credential_access
  - attack.t1110
```

The `validate` job enforces the following schema requirements before any conversion is attempted:

- `title`, `status`, `description`, `logsource`, `detection` are all present
- `status` is one of the recognised values
- `level` is one of the recognised values
- `detection` contains a `condition` field
- `logsource` is a non-empty mapping

A rule that fails any of these checks fails the pipeline at job 2, before any Terraform or SPL work begins.

### Adding a New Detection Rule

1. Create a new `.yml` file under `sigma_rules/` following the schema above
2. Open a pull request against `main` or push to `dev`
3. The pipeline validates the rule, converts it to SPL, and posts a plan to the PR summary showing exactly what will be created in Splunk
4. A SOC lead reviews and approves the PR
5. On merge to `main`, the pipeline deploys the detection automatically after a second manual approval at the environment gate

### Sigma Rule Severity Mapping

The `generate_locals.py` script maps Sigma severity levels to Splunk scheduling and alerting configuration:

| Sigma Level | Splunk Schedule | Alert Threshold | Schedule Priority |
|-------------|----------------|-----------------|-------------------|
| `critical` | Every 5 minutes | 0 (any match) | highest |
| `high` | Every 15 minutes | 0 (any match) | highest |
| `medium` | Every hour | 1 | default |
| `low` | Every 6 hours | 5 | default |

---

## Pipeline Jobs — Detailed Reference

### Job 1: Preflight

**Purpose:** Fail fast before any compute-intensive work begins.

**Steps:**

1. **Splunk Health Check** — calls `/services/server/info` on the configured Splunk instance. If Splunk returns anything other than HTTP 200, the entire pipeline aborts immediately. This prevents all downstream jobs from spending time on work that cannot be deployed.

2. **Detection Change Summary** — `diff_detections.py` compares the Sigma rules changed in this push or PR against the base branch using `git diff`. It posts a formatted table to the GitHub step summary showing which rules were added, modified, or removed, with level changes highlighted. This gives reviewers an immediate human-readable view of what changed without reading raw Terraform plan output.

**Failure behaviour:** Hard fail. All downstream jobs are blocked.

---

### Job 2: Validate

**Purpose:** Enforce Sigma rule schema correctness before any conversion or infrastructure work.

**Steps:**

1. **Validate Sigma Rules** — `validate_sigma_rules.py` iterates every `.yml` file under `sigma_rules/` and checks each against the required schema. Failures are reported per-file with specific field-level error messages. The script exits non-zero if any rule fails, blocking all downstream jobs.

**Why this matters:** A rule that is structurally invalid but still produces valid SPL during conversion is a silent detection gap. The converted SPL may be syntactically correct but semantically wrong — matching nothing, or matching everything. Catching schema errors here ensures that only intentionally authored, structurally sound rules reach Splunk.

**Failure behaviour:** Hard fail. All downstream jobs are blocked.

---

### Job 3: Build

**Purpose:** Generate the Terraform configuration from the validated Sigma rule set.

**Steps:**

1. **Clean Workspace** — removes any previously generated `locals.tf` and `generated/` directory to ensure the build is fully reproducible from source.

2. **Generate Terraform Locals** — `generate_locals.py` reads every Sigma rule, extracts metadata (title, description, severity, level), applies the severity-to-schedule mapping, and writes `terraform/locals.tf`. This file is the bridge between the Sigma rule authoring layer and the Terraform deployment layer. It is never edited manually.

3. **Upload Generated Locals** — `locals.tf` is uploaded as a GitHub Actions artifact named `terraform-locals`. Every downstream job that needs Terraform downloads this artifact rather than regenerating it, ensuring all jobs work from an identical configuration.

**Failure behaviour:** Hard fail on missing or zero-rule output.

---

### Job 4: Convert (parallel)

**Purpose:** Convert every Sigma rule to Splunk SPL.

**Steps:**

1. **Convert Sigma Rules to SPL** — `convert_sigma_to_spl.sh` iterates every `.yml` file under `sigma_rules/` and calls `sigma convert --target splunk --pipeline splunk_windows` for each. Output files are written to `generated/splunk/`. The script fails if any individual rule fails to convert or produces an empty output file.

2. **Upload SPL Detections** — the `generated/splunk/` directory is uploaded as the `spl-detections` artifact. Every downstream Terraform job downloads this artifact because `saved_searches.tf` uses `file()` to read SPL content at plan time. Without the artifact present, `terraform plan` fails.

**Failure behaviour:** Hard fail. `tf-plan` cannot proceed without this artifact.

---

### Job 5: Terraform Init (parallel)

**Purpose:** Initialise Terraform, apply formatting, and commit any formatting changes back to the branch.

**Steps:**

1. **Restore Provider Cache** — restores the `.terraform/` provider plugin directory from cache, keyed to the hash of `.terraform.lock.hcl`. Avoids downloading the Splunk provider on every pipeline run.

2. **Terraform Init** — runs `terraform init -reconfigure` to initialise the backend and download any uncached providers.

3. **Terraform Format** — runs `terraform fmt -recursive` to apply canonical HCL formatting to all files under `terraform/`. This runs as a fix, not a check — files are reformatted in place rather than failing on unformatted input.

4. **Commit Formatted Files** — if any files were modified by `fmt`, commits them back to the triggering branch with the message `style: terraform fmt auto-format [skip ci]`. The `[skip ci]` tag prevents the commit from triggering a new pipeline run. This step is skipped on pull requests because you cannot push to a PR merge ref.

**Failure behaviour:** Hard fail on init failure. Format and commit steps are best-effort on PRs.

---

### Job 6: Terraform State Sync

**Purpose:** Align the Terraform state file with the actual state of Splunk before planning. This is the most operationally complex job in the pipeline.

**Background:** Terraform maintains a state file that maps resource definitions to real infrastructure. If Splunk is modified outside of Terraform (manual edits, prior pipeline runs, deletions), the state file becomes out of sync. Planning against stale state produces errors ranging from duplicate resource creation to 404s on refresh.

**Steps:**

1. **Pre-Cleanup Broken State Entries** — `pre_cleanup_state.sh` iterates every `splunk_saved_searches.detections` resource in state and performs two checks for each:
   - Can `terraform state show` read it without errors?
   - Does the Splunk API return HTTP 200 when queried by the resource's saved search name?
   
   Any resource that fails either check is removed from state with `terraform state rm`. This catches the case where a saved search was deleted from Splunk directly — the state entry would pass a local read but fail the API check, which is exactly what causes 404 errors during plan.

2. **Import Existing Splunk Saved Searches** — `import_splunk_searches.sh` performs the reverse: it fetches all saved searches currently in Splunk, parses `locals.tf` to extract the expected rule names using `import_existing_searches.py`, and imports any Splunk search that matches a rule definition but is absent from state. This handles the case where a detection was created by a previous pipeline run but the state file was lost or reset.

   `import_existing_searches.py` uses brace-depth tracking rather than regex pattern matching to parse `locals.tf`. This is necessary because the rule blocks contain heredoc strings and nested maps that break `[^}]`-style regex approaches.

3. **Clean Up Stale State Entries** — `cleanup_stale_state.sh` performs a final pass, removing any state entries whose corresponding saved search no longer exists in Splunk. This catches deletions that occurred between the pre-cleanup step and the end of the import step.

**Failure behaviour:** Hard fail on any step. All three must pass before planning proceeds. `continue-on-error` is explicitly not used — silent state corruption is worse than a failed pipeline run.

---

### Job 7: Terraform Validate Resources

**Purpose:** Confirm that every resource remaining in state after sync actually exists and is readable in Splunk.

**Steps:**

1. **Validate Resources Against Splunk** — `validate_splunk_resources.sh` iterates every resource in state, extracts the saved search name, URL-encodes it, and calls the Splunk saved searches API directly. Any resource returning a non-200 response fails the validation. The script reports pass/fail per resource and exits non-zero if any resource fails.

This is a redundant check by design. State sync in job 6 should have removed all stale entries, but this job provides an independent verification that the state is clean before a plan is generated. A plan generated against a dirty state will fail at apply time — catching it here avoids wasting the approval gate.

**Failure behaviour:** Hard fail.

---

### Job 8: Terraform Plan

**Purpose:** Generate a Terraform execution plan and make it available for review.

**Steps:**

1. **Download Artifacts** — downloads both `terraform-locals` and `spl-detections`. The SPL files are required because `saved_searches.tf` uses `file()` to embed SPL content directly into the resource definition at plan time.

2. **Terraform Plan** — runs `terraform plan -out=tfplan`. The plan output is written to the GitHub step summary so reviewers can see exactly what Terraform intends to create, update, or destroy without leaving the PR interface.

3. **Upload Plan Artifact** — the binary plan file is uploaded as `terraform-plan` with a 7-day retention period. The apply job downloads and applies this exact plan binary, guaranteeing that what was reviewed is what gets deployed. Plan artifacts are only retained on `main` branch runs.

**Failure behaviour:** Hard fail.

---

### Job 9: Terraform Apply

**Purpose:** Deploy the approved plan to Splunk.

**Conditions:** Only executes on `push` events to `main`. Never executes on pull requests or pushes to `dev`.

**Approval gate:** The job targets the `production` GitHub environment. GitHub pauses execution and sends approval notifications to all configured reviewers before the job runs. The job does not proceed until a reviewer explicitly approves it. Reviewers cannot approve their own deployments if "Prevent self-review" is enabled on the environment.

**One-time environment setup:**
```
GitHub → Settings → Environments → New environment → "production"
  → Required reviewers: [SOC lead, detection team lead]
  → Prevent self-review: enabled
  → Deployment branches: main only
```

**Steps:**

1. **Download Artifacts** — downloads `terraform-locals`, `spl-detections`, and the `terraform-plan` binary from the plan job.

2. **Terraform Apply** — runs `terraform apply -auto-approve tfplan` against the saved plan binary. Using the saved plan guarantees that the apply executes exactly what was reviewed — Terraform will refuse to apply if the plan is no longer valid against the current state.

3. **Deployment Summary** — writes a summary table to the GitHub step summary recording the commit SHA, branch, actor, and UTC timestamp of the deployment. This provides a lightweight audit trail directly in the GitHub Actions interface.

**Failure behaviour:** Hard fail. A failed apply leaves state partially updated — the state sync job on the next run will reconcile the discrepancy.

---

## Composite Actions Reference

### `splunk-health-check`

Calls the Splunk `/services/server/info` endpoint and asserts HTTP 200. Used in `preflight` to abort the pipeline before any work begins if Splunk is unreachable.

### `terraform-env`

Exports `TF_VAR_splunk_url`, `TF_VAR_splunk_username`, `TF_VAR_splunk_password`, `TF_VAR_alert_email`, and `TF_VAR_insecure_skip_verify` into `$GITHUB_ENV`. Centralises secret injection — secrets are never referenced inline in job steps.

### `terraform-cache`

Wraps `actions/cache@v4` to restore and save the `.terraform/` provider plugin directory, keyed to `${{ runner.os }}-${{ hashFiles('terraform/.terraform.lock.hcl') }}`. Eliminates provider downloads on every job.

### `terraform-init`

Runs `terraform init -reconfigure`, then `terraform fmt -recursive`, then commits and pushes any formatting changes back to the triggering branch. Skips the commit step on pull requests.

### `secure-tmpdir`

Creates a job-scoped temporary directory at `/tmp/dac-{run_id}-{job}`, exports it as `$SECURE_TMPDIR`, and registers a guaranteed cleanup step that runs on job exit regardless of success or failure. Prevents temp files containing sensitive data (search names, API responses) from persisting between runs on the self-hosted runner.

---

## Security Considerations

### Secret Management

All secrets are stored in GitHub Actions repository secrets and referenced only through the `terraform-env` composite action. They are never echoed, logged, or interpolated directly into shell commands. The Splunk password is passed to `curl` via the `-u` flag using an environment variable, not as a command-line argument, to prevent exposure in process listings.

### TLS Verification

TLS verification on Splunk API calls is controlled by the `SPLUNK_TLS_SKIP` environment variable, which defaults to `false`. It is set to `true` in this lab configuration because the Splunk instance uses a self-signed certificate. In a production environment with a valid certificate, remove the `SPLUNK_TLS_SKIP: "true"` lines from the `tf-state-sync` and `tf-validate` jobs.

### Temp File Isolation

The self-hosted runner executes all jobs on the same host. Without isolation, temp files written by one job could be read or overwritten by a concurrent job from a different workflow run. The `secure-tmpdir` action addresses this by namespacing temp directories under the run ID and job name, and by registering a cleanup handler that runs even if the job fails.

### Apply Gate

The `environment: production` declaration on the apply job is the primary deployment control. It ensures that no detection reaches Splunk without explicit human sign-off from a named reviewer. The plan binary uploaded in job 8 and applied in job 9 is the same file — there is no opportunity for the plan to change between review and execution.

### Workflow Permissions

The workflow declares `permissions: contents: write` to allow the format commit step to push back to the repository. All other GitHub token permissions remain at their defaults. The token is scoped to the repository and expires at the end of the workflow run.

---

## Terraform State Management

### State Sync Design

Terraform state is stored locally on the self-hosted runner. The state sync job runs three scripts in sequence on every pipeline execution to keep state aligned with Splunk:

```
pre_cleanup_state.sh      Remove entries that fail Splunk API check
       ↓
import_splunk_searches.sh Import Splunk searches missing from state
       ↓
cleanup_stale_state.sh    Remove entries whose searches were deleted
```

This sequence handles all known drift scenarios:

| Scenario | Script that handles it |
|----------|----------------------|
| State entry exists, search deleted from Splunk | `pre_cleanup_state.sh` |
| Search exists in Splunk, no state entry | `import_splunk_searches.sh` |
| State entry exists, search never in Splunk | `pre_cleanup_state.sh` |
| State entry valid, search deleted after import | `cleanup_stale_state.sh` |

### Known Limitation: Local State

Using local Terraform state on a self-hosted runner is appropriate for a single-operator lab environment. For a multi-operator or production environment, state should be migrated to a remote backend with locking:

```hcl
# terraform/backend.tf (production configuration)
terraform {
  backend "s3" {
    bucket         = "your-tfstate-bucket"
    key            = "detections/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

Remote state eliminates the risk of state corruption from concurrent runs and makes the state accessible to multiple operators without requiring access to the runner host.

---

## Adding a New Detection Rule — End-to-End Walkthrough

1. **Create the rule file**
   ```bash
   touch sigma_rules/windows/my_new_detection.yml
   ```

2. **Author the rule** following the Sigma schema documented above. Ensure `title`, `status`, `description`, `logsource`, `detection`, and `level` are all present.

3. **Open a pull request** against `dev`.

4. **Pipeline runs jobs 1–8:**
   - Job 1 confirms Splunk is reachable and posts a change summary showing your new rule as "Added"
   - Job 2 validates the rule schema
   - Job 3 generates `locals.tf` including your new rule
   - Job 4 converts your rule to SPL
   - Jobs 6–7 sync and validate state
   - Job 8 generates a plan showing `1 to add` and posts it to the PR summary

5. **Review the PR** — a SOC lead examines the detection diff in job 1's summary and the Terraform plan in job 8's summary. Both are visible directly in the GitHub Actions tab without leaving the browser.

6. **Merge dev** to `main`.

7. **Pipeline runs jobs 1–9** on the merge commit. Jobs 1–8 repeat. Job 9 pauses and sends an approval notification to configured reviewers.

8. **Reviewer approves** the deployment in the GitHub UI.

9. **Job 9 applies** — `terraform apply` creates the saved search in Splunk. The deployment summary records the commit, actor, and timestamp.

10. **The detection is live.** It will begin running on its configured schedule immediately after creation.

---

## Troubleshooting

### Pipeline fails at preflight with HTTP connection error
Splunk is unreachable from the runner. Check that the runner host has network access to `SPLUNK_URL` and that the Splunk service is running.

### Pipeline fails at validate with schema errors
One or more Sigma rules is missing a required field. The validate job output lists the specific file and field. Fix the rule and push again.

### Pipeline fails at tf-state-sync with import errors
A saved search exists in Splunk under a name that doesn't exactly match the `name` field in `locals.tf`. This typically happens when a search was created manually in Splunk with a slightly different name. Check the import job output for the mismatch, then either rename the search in Splunk or adjust the rule title in the Sigma file.

### Terraform plan shows unexpected deletions
A rule was removed from `sigma_rules/` or its title was changed, causing `generate_locals.py` to produce a different key or name. The plan will show the old search as a deletion and the new one as a creation. This is expected — verify the plan output before approving the apply.

### Apply job never appears
The apply job only runs on `push` to `main`. If you are on `dev` or on a PR, the apply job is intentionally absent from the pipeline.

### Apply job runs but approval notification was not received
Check the `production` environment configuration in GitHub Settings → Environments. Ensure the correct reviewers are listed and that their GitHub notification settings allow environment approval notifications.
