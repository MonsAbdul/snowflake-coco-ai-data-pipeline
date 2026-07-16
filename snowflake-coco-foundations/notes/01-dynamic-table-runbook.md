 1. Recommended TARGET_LAG

  Current setting: 1 hour — this is reasonable for a workshop, but here's how to think about it in production:

  ┌──────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ Option           │ When to Use                                                                                                                                                  │
  ├──────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ DOWNSTREAM       │ If a Gold-layer DT will sit on top of this Silver table. Let the downstream DT's lag drive refresh timing — avoids paying for refreshes nobody consumes yet. │
  ├──────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 1 hour (current) │ Good default if analysts query Silver directly and can tolerate hour-old data.                                                                               │
  ├──────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 5–15 minutes     │ If this feeds near-real-time dashboards or operational reporting.                                                                                            │
  └──────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Recommendation for this pipeline: If you plan to build a Gold DT on top, switch to TARGET_LAG = DOWNSTREAM. If Silver is the final consumption layer, 1 hour is fine for AP invoice workflows (invoices don't change sub-minute).

  ────────────────────────────────────────

  2. Inspection SQL

    -- Current state and scheduling health
    SHOW DYNAMIC TABLES LIKE 'SILVER_AP_INVOICES' IN SCHEMA COCO_WORKSHOP.PIPELINE_LAB;
    -- Key columns: scheduling_state, refresh_mode, refresh_mode_reason, data_timestamp, target_lag

    -- Refresh history (successes and failures)
    SELECT name, state, state_message, refresh_action, refresh_trigger,
           refresh_start_time, refresh_end_time,
           DATEDIFF('second', refresh_start_time, refresh_end_time) AS duration_sec
    FROM TABLE(COCO_WORKSHOP.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
      NAME => 'COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES'
    ))
    ORDER BY refresh_start_time DESC
    LIMIT 20;

    -- Current data freshness (lag from now)
    SELECT DATEDIFF('minute', data_timestamp, CURRENT_TIMESTAMP()) AS staleness_minutes
    FROM TABLE(COCO_WORKSHOP.INFORMATION_SCHEMA.DYNAMIC_TABLES(
      NAME => 'COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES'
    ));

  ────────────────────────────────────────

  3. Failure and Staleness Patterns to Watch

  ┌───────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────────────┐
  │ Pattern               │ Cause                                                                                                                  │ Signal                                                            │
  ├───────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ SUSPENDED state       │ Repeated refresh failures or manual suspension                                                                         │ scheduling_state = 'SUSPENDED' in SHOW output                     │
  ├───────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ UPSTREAM_FAILED       │ A source table's change tracking was disabled or the table was dropped/recreated                                       │ state = 'FAILED', state_message mentions upstream                 │
  ├───────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ Full refresh fallback │ Snowflake can't maintain incremental state (e.g., source replaced with CTAS)                                           │ refresh_action = 'FULL' in history; refresh_mode_reason shows why │
  ├───────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ Warehouse contention  │ COCO_WORKSHOP_WH is XS and shared — long queues delay refresh                                                          │ duration_sec grows or refresh skipped                             │
  ├───────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ Schema drift          │ Someone adds a column to a bronze table — won't break this DT (explicit columns used), but new data won't flow through │ Silent data gap — no error, just missing columns                  │
  └───────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────────────┘

  Your current DT is healthy: scheduling_state = ACTIVE, refresh_mode = INCREMENTAL, initial refresh succeeded in 1 second.

  ────────────────────────────────────────

  4. Best-Practices Checklist

  • Explicit column lists — already done. Never use SELECT * in DTs.
  • Dedicated or right-sized warehouse — consider a dedicated XS warehouse for DT refreshes to avoid contention with ad-hoc queries on COCO_WORKSHOP_WH.
  • Change tracking stays enabled — do not run ALTER TABLE ... SET CHANGE_TRACKING = FALSE on the bronze source tables.
  • Don't CTAS-replace sources — replacing a bronze table with CREATE OR REPLACE TABLE breaks change tracking lineage. Use INSERT/MERGE to load new data.
  • Monitor scheduling_state — set up an alert (or periodic check) for SUSPENDED state so you catch failures early rather than discovering stale data later.
  • Use DOWNSTREAM lag for mid-pipeline DTs — if you add a Gold layer, switch Silver to DOWNSTREAM so refreshes are demand-driven.
  • Tag with comments — COMMENT = 'Silver AP invoices unified from SAP + Oracle bronze' makes the DT self-documenting in SHOW DYNAMIC TABLES.