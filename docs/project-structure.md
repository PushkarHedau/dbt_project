# Project structure

- `dbt/models/staging/`: source-aligned, lightly transformed models.
- `dbt/models/intermediate/`: reusable joins and business logic.
- `dbt/models/marts/`: curated, business-facing models.
- `dbt/macros/`: reusable Jinja/SQL macros.
- `dbt/tests/`: singular data-quality SQL tests; schema tests can live beside model YAML.
- `dbt/seeds/`: small, version-controlled reference data only.
- `dbt/snapshots/`: dbt snapshots for supported change-history use cases.
- `dbt/analyses/`: exploratory SQL not built as a model.
- `dags/`: Airflow orchestration; no credentials or transformation logic.
- `.github/workflows/`: CI checks.

Warehouse databases, schemas, source tables, and deployment settings are placeholders until confirmed for each environment.
