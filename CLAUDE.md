# CLAUDE.md — System Instructions for Financial Data Platform

This document governs all development, code generation, and technical decisions in this project.
Every implementation must be justified by and compliant with the guidelines below.

---

## Project Overview

Production-ready **Modern Data Stack** built on:

- **Cloud**: Azure (primary infrastructure)
- **Data Warehouse**: Snowflake
- **Orchestration**: Apache Airflow (Azure Managed Airflow / MWAA)
- **Transformation**: dbt (data build tool)
- **IaC**: Terraform
- **CI/CD**: GitHub Actions

---

## Pillar 1 — Security

### RBAC (Role-Based Access Control)

- All Snowflake access must be governed by roles. Never grant privileges directly to users.
- Define roles following the principle of least privilege:
  - `LOADER` — raw ingestion only
  - `TRANSFORMER` — dbt transformations
  - `REPORTER` — read-only access to Gold layer
  - `SYSADMIN` / `SECURITYADMIN` — strictly for administrative tasks
- Airflow connections and service principals must be scoped to the minimum required permissions.

### Zero Hardcoded Credentials

- **No secrets, passwords, tokens, or keys may appear in source code or version-controlled files.**
- All secrets must be stored in:
  - **Azure Key Vault** for runtime secrets (Airflow connections, Snowflake credentials)
  - **GitHub Actions Secrets** for CI/CD pipeline variables
- Reference secrets via environment variables or secret references only.

### Authentication

- Prefer **private key authentication** (RSA key pairs) for Snowflake service accounts over password-based auth.
- Rotate keys on a defined schedule; never commit private keys to the repository.
- Use **Azure Managed Identity** for service-to-service authentication where applicable.

### PII Protection

- Apply **Snowflake Dynamic Data Masking** policies to all columns tagged as PII.
- Tag PII columns using Snowflake Object Tagging (`TAG` objects) before applying masking.
- Masking policies must restrict plain-text PII to privileged roles only.
- Document all PII columns in dbt schema files using `meta.pii: true`.

---

## Pillar 2 — Data Management

### Data Quality as Code

- Every dbt model must have a corresponding `schema.yml` file with:
  - Column-level `not_null` and `unique` tests for primary keys.
  - Referential integrity tests (`relationships`) for foreign keys.
  - Custom business-rule tests using **dbt-expectations** (e.g., `expect_column_values_to_be_between`).
- No model may be merged without at least one dbt test covering its primary key.
- Run `dbt test` as a mandatory step in all CI/CD pipelines.

### Defensive Typing

- Use `TRY_CAST` instead of `CAST` whenever parsing raw/external data to avoid silent failures.
- Use `NULLIF` to replace known sentinel values (e.g., `'N/A'`, `''`, `0`) with `NULL`.
- Validate data types explicitly at the Silver layer before promoting to Gold.

### Lineage and Documentation

- All dbt models must include a `description` field in `schema.yml`.
- Use `dbt docs generate` and publish the docs site as an artifact in CI.
- Source declarations (`sources:`) must define freshness checks with `warn_after` and `error_after`.

---

## Pillar 3 — Data Ops

### Infrastructure as Code (IaC)

- All Azure and Snowflake resources must be provisioned via **Terraform**.
  - No manual resource creation in the portal or Snowflake UI for production.
- Terraform state must be stored remotely in **Azure Blob Storage** with state locking enabled.
- Organize Terraform code into modules:
  - `modules/azure/blob_storage` — storage accounts, containers, ADLS Gen2 config
  - `modules/azure/networking` — VNet, private endpoints, firewall rules
  - `modules/snowflake/storage_integration` — Azure Storage Integration and named External Stages
  - `modules/snowflake/warehouses` — Virtual Warehouse definitions and sizing
  - `modules/snowflake/rbac` — roles, grants, and user assignments
  - `modules/snowflake/database` — databases and schema objects
- Apply `terraform fmt` and `terraform validate` as pre-commit hooks and CI checks.

### CI/CD with GitHub Actions

- Define separate workflows for:
  - `pr-checks.yml` — linting, unit tests, `dbt compile`, `dbt test` on dev schema
  - `deploy-staging.yml` — triggered on merge to `dev`
  - `deploy-production.yml` — triggered on merge to `main`, requires manual approval
- Use **environments** in GitHub Actions to enforce protection rules on production deployments.
- dbt runs in CI must target an **isolated dev schema** using `--target ci` with schema suffix `_pr_<PR_NUMBER>`.

### Strict Branching Strategy

- All changes must originate from a `feature/<description>` or `bugfix/<description>` branch.
- **No direct commits to `dev` or `main` are allowed.** All changes must arrive via a Pull Request.
- Branch flow: `feature/*` or `bugfix/*` → `dev` → `staging` → `main`.
- PRs into `dev` require at least one peer review approval before merging.
- PRs into `main` require peer review approval and a passing CI pipeline; production deployments also require manual approval via GitHub Actions environments.
- Branch protection rules must be enforced in GitHub for both `dev` and `main`.

### DAG Observability and Branch Isolation

- Every Airflow DAG must emit structured logs and be observable via Azure Monitor.
- Use **dbt slim CI** (`dbt build --select state:modified+`) in pull requests to run only affected models.
- Each developer works in an isolated Snowflake schema (`DEV_<username>`) to prevent cross-contamination.

---

## Pillar 4 — Data Architecture

### Medallion Architecture

All data flows through a strict four-layer architecture. No layer may be skipped.

| Layer       | Location / Schema           | Purpose                                                                                        |
|-------------|----------------------------|------------------------------------------------------------------------------------------------|
| **Landing** | Azure Blob Storage          | Files as-landed from source systems. External to Snowflake. Immutable after landing.           |
| **Raw**     | Snowflake `RAW` schema      | Exact source copy loaded into Snowflake via `COPY INTO`. No business logic. Append or full-replace only. |
| **Silver**  | Snowflake `SILVER` schema   | Cleaned, typed, deduplicated, and conformed data. Defensive typing applied here.               |
| **Gold**    | Snowflake `GOLD` schema     | Business-ready aggregates, metrics, and dimensional models for BI and analytics.               |

#### Azure Blob → Snowflake Ingestion Pattern

The **Landing layer resides entirely in Azure Blob Storage** — there is no `LANDING` schema in Snowflake. Data is promoted to `RAW` via the following mechanism:

1. Files arrive in Azure Blob Storage containers (one container per source/domain).
2. A Snowflake **Storage Integration** (provisioned via Terraform) grants Snowflake read access to the storage account using a managed identity — no shared-access keys.
3. Named **External Stages** (one per container/path pattern) map Snowflake stage objects to Blob Storage paths.
4. Airflow DAGs trigger `COPY INTO <RAW_TABLE> FROM @<stage>` statements to load files into `RAW` tables on a scheduled basis.

- dbt `sources:` declarations point to `RAW`.
- dbt staging models live in `SILVER`.
- dbt mart/fact/dimension models live in `GOLD`.

### Idempotency

- All dbt models must be idempotent: running them multiple times must produce the same result.
- Use `incremental` materializations only when justified by volume; always define a reliable `unique_key`.
- Prefer `table` or `incremental` over `view` for Gold-layer models used in BI tools.

### Decoupling Storage and Compute

- Raw data persists in **Azure Blob Storage (ADLS Gen2)** before loading into Snowflake. Snowflake never pulls directly from a source system — files must first land in Blob Storage.
- The Snowflake **Storage Integration** is the sole authorized path between Blob Storage and Snowflake; direct credential-based access is prohibited.
- Snowflake **Virtual Warehouses** must be sized per workload and set to auto-suspend (≤ 5 minutes).
- Use separate warehouses for ingestion (`COPY INTO`), transformation (dbt), and reporting to prevent resource contention.

---

## Pillar 5 — Orchestration

### Airflow Best Practices

- Use **Azure Managed Airflow** (via Azure Managed Workflows or equivalent managed service).
- Each DAG must represent a single, cohesive pipeline. No monolithic DAGs.
- All tasks must be **atomic**: a task either fully succeeds or fails cleanly without partial side effects.
- Separate DAGs by concern:
  - `ingestion/` DAGs execute `COPY INTO <RAW_TABLE> FROM @<external_stage>` to load data from Azure Blob Storage into the `RAW` schema.
  - `transformation/` DAGs invoke `dbt run` / `dbt test` to promote data through `SILVER` and `GOLD`.
- Ingestion DAGs must never invoke dbt directly; transformation DAGs must never issue `COPY INTO`.

### DAG Configuration Defaults

```python
default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": True,
}

dag = DAG(
    dag_id="...",
    default_args=default_args,
    schedule_interval="@daily",
    catchup=False,          # MANDATORY: always False unless explicitly justified
    max_active_runs=1,
    tags=["layer", "domain"],
)
```

- `catchup=False` is **mandatory** unless a backfill is explicitly planned and documented.
- Use `max_active_runs=1` to prevent concurrent DAG runs from racing on shared resources.

### Time-Context Variables

- Use Airflow macros (`{{ ds }}`, `{{ data_interval_start }}`, `{{ data_interval_end }}`) for all time-partitioned logic.
- Never use `datetime.now()` or hardcoded dates inside DAG or task logic.
- Pass execution dates as parameters to dbt runs: `dbt run --vars '{"run_date": "{{ ds }}"}'`.

---

## Pillar 6 — Software Engineering

### Test-Driven Development (TDD)

- **Write tests before writing implementation code.** No exceptions.
- Use **pytest** for all Python unit and integration tests.
- Test coverage must be ≥ 80% for any new Python module.
- Tests live in `tests/` mirroring the source structure (e.g., `src/utils/parser.py` → `tests/utils/test_parser.py`).

### Code Quality and Formatting

- Python code must comply with **PEP-8**.
- Mandatory toolchain enforced via **pre-commit hooks**:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.4.4
    hooks:
      - id: ruff           # linter
      - id: ruff-format    # formatter (replaces black)

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: detect-private-key

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.92.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate

  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 3.0.7
    hooks:
      - id: sqlfluff-lint
        args: ["--dialect", "snowflake"]
      - id: sqlfluff-fix
        args: ["--dialect", "snowflake"]
```

- Pre-commit hooks must pass before any commit is accepted locally and in CI.

### DRY Principle and dbt Macros

- Repeated SQL logic must be abstracted into **dbt macros** in the `macros/` directory.
- Common patterns to macro-ize: date spine generation, PII masking, data type casting, surrogate key generation.
- Use the `dbt_utils` and `dbt_expectations` packages; do not reinvent existing functionality.

### Modularity and Project Structure

```
.
├── .github/
│   └── workflows/
│       ├── pr-checks.yml           # Linting, dbt compile/test on dev schema
│       ├── deploy-staging.yml      # Triggered on merge to dev
│       └── deploy-production.yml   # Triggered on merge to main; requires manual approval
├── airflow/
│   ├── dags/
│   │   ├── ingestion/              # COPY INTO DAGs — load External Stage → RAW
│   │   └── transformation/         # dbt run/test DAGs — RAW → SILVER → GOLD
│   └── plugins/                    # Custom operators and hooks
├── dbt/
│   ├── models/
│   │   ├── staging/                # Silver layer — cleaning, typing, deduplication
│   │   └── marts/                  # Gold layer — business aggregates and dimensional models
│   ├── seeds/                      # Static reference/lookup data (CSV files)
│   ├── macros/                     # Reusable SQL macros
│   ├── tests/                      # Custom singular and generic tests
│   └── dbt_project.yml
├── terraform/
│   ├── modules/
│   │   ├── azure/
│   │   │   ├── blob_storage/       # Storage accounts, containers, ADLS Gen2 config
│   │   │   └── networking/         # VNet, private endpoints, firewall rules
│   │   └── snowflake/
│   │       ├── storage_integration/ # Azure Storage Integration + named External Stages
│   │       ├── warehouses/          # Virtual Warehouse definitions and sizing
│   │       ├── rbac/                # Roles, grants, and user assignments
│   │       └── database/            # Databases and schema objects
│   └── environments/
│       ├── dev/
│       └── prod/
├── src/                            # Python utilities (schema inference, file validation, helpers)
├── tests/                          # Pytest test suite
├── .pre-commit-config.yaml
├── pyproject.toml                  # Ruff, pytest, and project config
├── CLAUDE.md                       # This file
└── README.md
```

### Language and Communication

- All code **comments**, **docstrings**, **documentation**, **commit messages**, and **console outputs** must be written in **English**.
- Commit messages must follow the **Conventional Commits** specification:
  - `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `ci:`

---

## Code Generation Rules for Claude

When generating or suggesting any code in this project, Claude must:

1. **Always reference this document** as the governing authority for technical decisions.
2. **Never hardcode secrets**, credentials, or environment-specific values.
3. **Always include dbt tests** when generating dbt models.
4. **Always write pytest tests** before or alongside any new Python function.
5. **Apply Medallion layer labels** when creating or modifying dbt models.
6. **Default `catchup=False`** in all new Airflow DAGs.
7. **Use `TRY_CAST` and `NULLIF`** when handling raw or external data in SQL.
8. **Tag PII columns** in dbt schema files with `meta: {pii: true}`.
9. **Propose Terraform resources** for any new infrastructure component instead of manual steps.
10. **Enforce pre-commit compliance** — generated code must pass all configured hooks.
11. **Route all Blob → Snowflake ingestion through External Stages** — never use direct credential-based access or Python-based file downloads into Snowflake. `COPY INTO` via a named External Stage is the only permitted ingestion mechanism.
12. **Place ingestion DAGs under `airflow/dags/ingestion/`** and transformation DAGs under `airflow/dags/transformation/`. Never mix `COPY INTO` and `dbt` logic in the same DAG.
