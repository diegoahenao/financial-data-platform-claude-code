---
name: security-review
description: Run a full security vulnerability audit of this repository covering secrets, Terraform RBAC, GitHub Actions, Airflow, dbt, and Python code.
argument-hint: [area] — optionally scope to: terraform | workflows | dbt | airflow | python | all (default)
context: fork
agent: security-review
---

Run a security vulnerability review of the financial-data-platform repository.

Scope: $ARGUMENTS (if empty, review all areas)

Instructions:
1. Start by listing all files in the repo using Glob to understand the surface area
2. Systematically work through each security domain in your system prompt
3. For each area, grep for known-bad patterns before reading files in detail
4. Read files that contain potential issues to confirm or rule out the finding
5. Produce the full structured report — CRITICAL through LOW, plus PASSED CHECKS

Grep patterns to start with:
- Secrets: `password|secret|token|key|credential|sas_token|client_secret` (case-insensitive) in non-test files
- Hardcoded IPs/accounts: specific account names or IPs in source files
- Dangerous functions: `eval\(|exec\(|os\.system\(|subprocess.*shell=True|pickle\.loads`
- GitHub Actions injection: `\$\{\{ github\.event\.(issue|pull_request|comment)`
- Terraform over-grants: `ACCOUNTADMIN|SYSADMIN|SECURITYADMIN` assigned to service accounts, `ALL PRIVILEGES`
- Unencrypted outputs: `sensitive\s*=\s*false` in Terraform outputs containing credentials

Be thorough. Missing a real vulnerability is worse than a false positive.
