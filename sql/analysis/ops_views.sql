USE CATALOG IDENTIFIER(:catalog);

-- event_log resolves TABLE arguments in the reader's session; persist the catalog.
EXECUTE IMMEDIATE 'CREATE OR REPLACE VIEW ops.expectations AS
WITH records AS (
  SELECT origin.update_id AS update_id,timestamp,
    explode(from_json(details:flow_progress.data_quality.expectations,
      \'ARRAY<STRUCT<name:STRING,dataset:STRING,passed_records:BIGINT,failed_records:BIGINT>>\')) AS rule
  FROM event_log(TABLE(' || :catalog || '.bronze.orders_raw)) WHERE event_type=\'flow_progress\'
)
SELECT update_id,rule.dataset AS dataset,rule.name AS expectation,
  min(timestamp) AS recorded_at,sum(rule.passed_records) AS passed_records,
  sum(rule.failed_records) AS failed_records
FROM records GROUP BY update_id,rule.dataset,rule.name';

CREATE OR REPLACE VIEW ops.job_runs AS
SELECT job_id,run_id,IF(job_id='747628238433531','dev','prod') AS environment,
  min(period_start_time) AS started_at,max(period_end_time) AS ended_at,
  max_by(result_state,period_end_time) AS result_state,
  timestampdiff(SECOND,min(period_start_time),max(period_end_time)) AS duration_seconds
FROM system.lakeflow.job_run_timeline
WHERE workspace_id='7474654791620994' AND job_id IN ('747628238433531','118635285146392')
  AND period_start_time>=date_sub(current_date(),30)
GROUP BY job_id,run_id;

CREATE OR REPLACE VIEW ops.task_runs AS
SELECT job_id,job_run_id,run_id,task_key,min(period_start_time) AS started_at,
  max_by(result_state,period_end_time) AS result_state,
  sum(timestampdiff(SECOND,period_start_time,period_end_time)) AS duration_seconds
FROM system.lakeflow.job_task_run_timeline
WHERE workspace_id='7474654791620994' AND job_id IN ('747628238433531','118635285146392')
  AND period_start_time>=date_sub(current_date(),30)
GROUP BY job_id,job_run_id,run_id,task_key;

CREATE OR REPLACE VIEW ops.pipeline_updates AS
SELECT pipeline_id,update_id,min(period_start_time) AS started_at,
  max_by(result_state,period_end_time) AS result_state,
  sum(timestampdiff(SECOND,period_start_time,period_end_time)) AS duration_seconds
FROM system.lakeflow.pipeline_update_timeline
WHERE workspace_id='7474654791620994'
  AND trigger_details.job_task.job_id IN ('747628238433531','118635285146392')
  AND period_start_time>=date_sub(current_date(),30)
GROUP BY pipeline_id,update_id;

CREATE OR REPLACE VIEW ops.compute_usage AS
SELECT usage_date,sku_name,usage_unit,sum(usage_quantity) AS usage_quantity
FROM system.billing.usage
WHERE workspace_id='7474654791620994' AND usage_date>=date_sub(current_date(),30)
GROUP BY usage_date,sku_name,usage_unit;

CREATE OR REPLACE VIEW ops.query_performance AS
SELECT statement_id,start_time,execution_status,total_duration_ms,read_rows,produced_rows
FROM system.query.history
WHERE workspace_id='7474654791620994' AND start_time>=date_sub(current_date(),30)
  AND compute.warehouse_id='7c433c4d75a98ff6';

CREATE OR REPLACE VIEW ops.gold_lineage AS
SELECT DISTINCT source_table_full_name,target_table_full_name,entity_type,event_date
FROM system.access.table_lineage
WHERE workspace_id='7474654791620994' AND event_date>=date_sub(current_date(),30)
  AND target_table_catalog IN ('meridian_t02_prod','meridian_t02_dev')
  AND target_table_schema='gold'
  AND target_table_name IN ('fct_order_headers','fct_order_items','dim_customer_history','vdp_top_customers');
