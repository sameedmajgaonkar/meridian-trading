-- Operations telemetry queries over system tables and ops monitoring tables.
-- dev catalog

-- 7.1 Pipeline health: latest update per project pipeline.
SELECT * FROM system.lakeflow.pipeline_update_timeline
WHERE pipeline_name = 'meridian_t02_pipeline'
  AND start_time >= current_timestamp() - INTERVAL 7 DAYS
ORDER BY start_time DESC;

-- 7.2 Job runs of the project job.
SELECT * FROM system.lakeflow.job_run_timeline
WHERE name = 'meridian_t02_job'
  AND period_start_time >= current_timestamp() - INTERVAL 7 DAYS
ORDER BY period_start_time DESC;

-- 7.3 Latest quality-gate results (our own ops table, known schema).
SELECT check_name, check_value, status, batch, evaluated_at
FROM meridian_t02.ops.quality_gate
WHERE evaluated_at >= current_timestamp() - INTERVAL 7 DAYS
ORDER BY evaluated_at DESC, check_name;

-- 7.4 Quarantine pressure over time (rows rejected per batch).
SELECT _batch_id, entity, count(*) AS invalid_rows
FROM meridian_t02.ops.quarantine_invalid
GROUP BY _batch_id, entity
ORDER BY _batch_id, entity;

-- 7.5 Serverless spend last 7 days (Free Edition quota guard).
SELECT usage_date, sku_name, sum(usage_quantity) AS usage_quantity
FROM system.billing.usage
WHERE usage_date >= current_date() - INTERVAL 7 DAYS
GROUP BY usage_date, sku_name
ORDER BY usage_date DESC;

-- 7.6 Who ran what: recent project-related audit events.
SELECT event_time, user_identity.email AS user_email, action_name,
       request_params['job_name'] AS job_name
FROM system.access.audit
WHERE event_time >= current_timestamp() - INTERVAL 7 DAYS
  AND (request_params['job_name'] LIKE 'meridian%'
       OR request_params['pipeline_name'] LIKE 'meridian%')
ORDER BY event_time DESC
LIMIT 50;
