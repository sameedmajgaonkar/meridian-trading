-- SQL Alert query: counts failed runs of meridian_t02_job in the last 24 hours.

SELECT count(*) AS failed_runs_last_24h
FROM system.lakeflow.job_run_timeline r
JOIN system.lakeflow.jobs j ON r.job_id = j.job_id
WHERE j.name LIKE '%meridian_t02_job%'
  AND r.result_state = 'FAILED'
  AND r.period_start_time >= current_timestamp() - INTERVAL 24 HOURS;
