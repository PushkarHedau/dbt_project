# Airflow DAGs

Keep DAG definitions thin: orchestration belongs here; transformation logic belongs in dbt.

Before deploying, configure the Airflow executor/runtime, connection IDs and secret backend, dbt project path, retries, timeouts, alerting, and schedule to match the workload SLA. Validate DAG imports in the same environment used by Airflow.
