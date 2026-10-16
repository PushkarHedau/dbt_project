# dbt + Airflow Data Platform

Starter repository for a dbt transformation project and Airflow orchestration.

## Repository layout

- `dbt/` — dbt project: layered models, macros, tests, seeds, snapshots and documentation.
- `dags/` — Airflow DAGs and shared DAG configuration.
- `docs/` — architecture, development workflow and operational guidance.
- `.github/workflows/` — CI checks for dbt project structure and DAG Python files.

## Environments

Keep credentials out of Git. Configure Snowflake/dbt credentials and Airflow connections through the approved secret backend or environment-specific secret manager. `dbt/profiles.yml.example` is a template only.

## Branching strategy (MST)

- `master`: production-ready baseline; protect it and merge only reviewed, validated changes.
- `develop`: integration branch for unreleased work.
- `feature`: starter working branch; for ongoing work, prefer short-lived branches named `feature/<ticket-or-purpose>`.

Flow:
1. Create feature work from the latest `master` baseline as per the team's MST convention.
2. Before integration, sync/rebase the feature branch with the latest `develop`.
3. Open a PR from feature to `develop`; run CI and validate in DEV.
4. Promote validated changes from `develop` to `master` through a separate PR and production checks.
5. Never commit secrets or environment-specific credentials.

## Getting started

1. Review `dbt/dbt_project.yml` and `dbt/profiles.yml.example`.
2. Install dbt Core and the Snowflake adapter in your development environment.
3. Configure your local dbt profile outside version control.
4. Add source definitions and models only after confirming the actual Snowflake databases, schemas and source tables.
5. Deploy Airflow DAGs only after configuring the executor, connection IDs, secret backend and runtime image for your environment.

This repository is a scaffold, not a configured deployment.