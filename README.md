# Financial Data Platform

A production-ready **Modern Data Stack** built on Azure, Snowflake, Apache Airflow, and dbt.
All infrastructure is provisioned as code, all secrets are vault-managed, and all deployments flow through a CI/CD pipeline with automated quality gates.

---

## Architecture Overview

Data flows through a strict four-layer **Medallion Architecture**. No layer may be skipped.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SOURCE SYSTEMS                                   │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ file drop (CSV, JSON, Parquet)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  LANDING LAYER — Azure Blob Storage (ADLS Gen2)                         │
│  Immutable raw files, one container per source/domain                   │
│  inbound-files-cc / client_a / client_c / ...                           │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ COPY INTO via External Stage (Airflow)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  RAW LAYER — Snowflake RAW schema                                       │
│  Exact source copy, no business logic, append-only or full-replace      │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ dbt staging models
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  SILVER LAYER — Snowflake SILVER schema                                 │
│  Cleaned, typed (TRY_CAST), deduplicated, conformed data                │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ dbt mart/fact/dimension models
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  GOLD LAYER — Snowflake GOLD schema                                     │
│  Business-ready aggregates and dimensional models for BI & analytics    │
└─────────────────────────────────────────────────────────────────────────┘
```

Blob Storage → Snowflake ingestion uses a **Snowflake Storage Integration** (Managed Identity — no shared-access keys). Airflow DAGs trigger `COPY INTO <RAW_TABLE> FROM @<external_stage>`. Direct credential-based access is prohibited.

---

## Technology Stack

| Concern | Technology |
|---|---|
| Cloud | Azure (East US) |
| Data Warehouse | Snowflake |
| Orchestration | Apache Airflow (Azure Container Apps) |
| Transformation | dbt (data build tool) |
| Infrastructure as Code | Terraform |
| CI/CD | GitHub Actions |
| Secrets Management | Azure Key Vault |
| Monitoring | Azure Monitor + Log Analytics |
| Code Quality | Ruff, SQLFluff, pre-commit |
| Testing | pytest, dbt-expectations |

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── pr-checks.yml           # Lint, dbt compile/test on isolated dev schema
│       ├── deploy-staging.yml      # Triggered on merge to dev
│       └── deploy-production.yml   # Triggered on merge to main; requires manual approval
├── airflow/
│   ├── dags/
│   │   ├── ingestion/              # COPY INTO DAGs — External Stage → RAW
│   │   └── transformation/         # dbt run/test DAGs — RAW → SILVER → GOLD
│   └── plugins/                    # Custom operators and hooks
├── dbt/
│   ├── models/
│   │   ├── staging/                # Silver layer — cleaning, typing, deduplication
│   │   └── marts/                  # Gold layer — business aggregates and dimensional models
│   ├── seeds/                      # Static reference/lookup data
│   ├── macros/                     # Reusable SQL macros (DRY)
│   ├── tests/                      # Custom singular and generic tests
│   └── dbt_project.yml
├── terraform/
│   ├── bootstrap/                  # One-time remote state backend provisioning
│   ├── modules/
│   │   ├── azure/
│   │   │   ├── resource_group/
│   │   │   ├── networking/         # VNet, subnets, NSGs, private endpoints, DNS zones
│   │   │   ├── key_vault/          # Key Vault with RBAC + private endpoint
│   │   │   ├── blob_storage/       # ADLS Gen2 storage account + containers
│   │   │   ├── monitoring/         # Log Analytics Workspace + Monitor Action Group
│   │   │   └── airflow/            # Managed Identity + Container App Environment
│   │   └── snowflake/
│   │       ├── database/           # Databases and RAW / SILVER / GOLD schemas
│   │       ├── rbac/               # Roles, grants, service users (LOADER, TRANSFORMER)
│   │       ├── warehouses/         # Ingestion, transformation, and reporting warehouses
│   │       └── storage_integration/ # Azure Storage Integration + named External Stages
│   └── environments/
│       ├── dev/
│       └── prod/
├── src/                            # Python utilities — schema inference, file validation
├── tests/                          # pytest test suite (mirrors src/ structure)
├── .gitignore
├── .mcp.json                       # Snowflake MCP server for Claude Code
├── .pre-commit-config.yaml
├── pyproject.toml
└── CLAUDE.md                       # Governing architecture and code-generation rules
```

---

## Security Model

### Zero Hardcoded Credentials
All secrets are stored in **Azure Key Vault** and injected at runtime via environment variables. No passwords, tokens, or private keys appear in source code.

### Snowflake Authentication
Service accounts use **RSA key pair authentication** (JWT). Password-based auth is disabled for all platform accounts.

| Account | Role | Warehouse |
|---|---|---|
| `AIRFLOW_LOADER` | `LOADER` | `DEV_INGESTION_WH` |
| `DBT_TRANSFORMER` | `TRANSFORMER` | `DEV_TRANSFORMATION_WH` |

### RBAC (Least Privilege)
| Role | Access |
|---|---|
| `LOADER` | Write to RAW schema only |
| `TRANSFORMER` | Read RAW, write SILVER and GOLD |
| `REPORTER` | Read-only on GOLD schema |

### Network Isolation
All Azure resources communicate over **private endpoints** within a dedicated VNet. Public network access is disabled on Key Vault and Storage. Private DNS zones resolve `*.blob.core.windows.net` and `*.vaultcore.azure.net` to private IPs.

### PII Protection
PII columns are tagged in dbt schema files (`meta: {pii: true}`) and protected by **Snowflake Dynamic Data Masking** policies. Plain-text PII is only visible to privileged roles.

---

## CI/CD Pipeline

```
feature/* or bugfix/*
        │
        │  PR opened
        ▼
┌───────────────────┐
│   pr-checks.yml   │  terraform fmt + validate
│                   │  ruff lint + pytest
│                   │  dbt compile + slim CI build
│                   │  (state:modified+ on isolated schema)
└────────┬──────────┘
         │  PR merged to dev
         ▼
┌───────────────────┐
│ deploy-staging.yml│  terraform plan → apply (staging env)
│                   │  dbt run + test + docs
└────────┬──────────┘
         │  PR merged to main
         ▼
┌───────────────────┐
│deploy-production  │  terraform plan
│     .yml          │  ── manual approval gate ──
│                   │  terraform apply (production env)
│                   │  dbt run + test + docs
│                   │  upload dbt manifest to Azure Blob
└───────────────────┘
```

dbt runs in CI target an **isolated schema per PR** (`_pr_<PR_NUMBER>`) to prevent cross-contamination. Slim CI (`dbt build --select state:modified+`) uses the production manifest stored in Azure Blob to run only affected models.

---

## Infrastructure

All Azure and Snowflake resources are provisioned via Terraform. No manual resource creation is permitted in production.

**Terraform remote state** is stored in Azure Blob Storage (`rg-findata-tfstate / stfindatatfstate / tfstate`) with state locking enabled. The bootstrap module provisions this backend as a one-time local apply.

### Azure Resources (61 planned)
- Resource Group
- Virtual Network + 2 Subnets + NSGs
- Private DNS Zones (`blob`, `vaultcore`)
- Azure Key Vault (RBAC mode, private endpoint)
- Storage Account — ADLS Gen2 (private endpoint, versioning, soft delete)
- Log Analytics Workspace
- Azure Monitor Action Group
- User-Assigned Managed Identity
- Container App Environment (VNet-injected, for Airflow)

### Snowflake Resources
- Database + RAW / SILVER / GOLD schemas
- 3 Roles (LOADER, TRANSFORMER, REPORTER) + grants
- 2 Service users with RSA key authentication
- 3 Virtual Warehouses (auto-suspend ≤ 5 min)
- Storage Integration (Managed Identity — no SAS keys)
- External Stage per Blob container

---

## Getting Started

### Prerequisites
- Azure CLI authenticated (`az login`)
- Terraform ≥ 1.6
- Snowflake account with `SYSADMIN` and `SECURITYADMIN` access
- GitHub CLI (`gh`) authenticated

### 1. Generate RSA key pairs
```bash
# Airflow service account
openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out airflow_rsa_key.p8
openssl rsa -in airflow_rsa_key.p8 -pubout -out airflow_rsa_key.pub

# dbt service account
openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out dbt_rsa_key.p8
openssl rsa -in dbt_rsa_key.p8 -pubout -out dbt_rsa_key.pub
```

### 2. Bootstrap remote state
```bash
cd terraform/bootstrap
terraform init
terraform apply
```

### 3. Set required environment variables
```bash
export ARM_SUBSCRIPTION_ID=<your-azure-subscription-id>
export ARM_TENANT_ID=<your-azure-tenant-id>
export SNOWFLAKE_ORGANIZATION_NAME=<your-org>
export SNOWFLAKE_ACCOUNT_NAME=<your-account>
export SNOWFLAKE_USER=TERRAFORM_SVC
export SNOWFLAKE_PRIVATE_KEY_PATH=/path/to/terraform_svc_private_key.p8
```

### 4. Inject RSA public keys and plan
```bash
cd terraform
# Paste public key bodies into environments/dev/terraform.tfvars
terraform init
terraform plan -var-file=environments/dev/terraform.tfvars
```

### 5. Push and open a pull request
All changes go through a feature branch → PR → dev → main flow. Direct commits to `dev` or `main` are blocked.

```bash
git checkout -b feature/<description>
git push origin feature/<description>
gh pr create --base dev
```

---

## Data Quality

Every dbt model ships with a `schema.yml` file containing:
- `not_null` + `unique` tests on all primary keys
- `relationships` tests for foreign keys
- `dbt-expectations` tests for business rules (value ranges, accepted values, etc.)

`dbt test` is a mandatory step in all CI/CD pipelines. No model may be merged without at least one test on its primary key.

---

## Local Development

Each developer works in an isolated Snowflake schema (`DEV_<username>`) to prevent cross-contamination.

```bash
# Install pre-commit hooks
pip install pre-commit
pre-commit install

# Run dbt against your personal schema
cd dbt
dbt run --target dev

# Run the test suite
pytest tests/
```

---

## Contributing

- Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification for all commit messages (`feat:`, `fix:`, `refactor:`, `ci:`, etc.)
- All PRs into `dev` require at least one peer review approval
- All PRs into `main` require peer review + passing CI + manual deployment approval
- Pre-commit hooks (Ruff, SQLFluff, Terraform fmt/validate) must pass before any commit is accepted
