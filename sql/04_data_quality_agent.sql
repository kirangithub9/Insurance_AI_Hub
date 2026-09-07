-- ============================================================================
-- AGENT 3: DATA QUALITY ROOT CAUSE
-- Cortex Analyst Semantic View over the DATA_QUALITY schema
-- (DQ_RULES, DQ_RESULTS, DQ_COLUMN_HEALTH, DQ_SCORES)
--
-- Columns confirmed directly against the live tables in
-- INSURANCE_AI_HUB.DATA_QUALITY. Notable value formats:
--   DQ_RESULTS.STATUS        -> 'PASS' | 'FAIL'
--   DQ_RULES.SEVERITY        -> 'Critical' | 'High' | 'Medium' | 'Low'
--   DQ_RULES.RULE_TYPE       -> 'Completeness' | 'Accuracy' | 'Format' |
--                                'Validity' | 'Timeliness' | 'Uniqueness' |
--                                'Range' | 'Consistency' | 'Referential'
--   DQ_COLUMN_HEALTH.HEALTH_STATUS -> 'Healthy' | 'Warning' | 'Critical'
--   DQ_SCORES.TREND          -> 'UP' | 'DOWN' | 'STABLE'
--
-- DEPENDS ON sql/08_dq_agent_enhancements.sql having been run first: this
-- view now also includes column_trends (VW_DQ_COLUMN_HEALTH_TRENDS) and
-- downstream_impact (DQ_DOWNSTREAM_IMPACT), added to answer two example
-- questions from the requirement doc that DQ_COLUMN_HEALTH/DQ_RULES/
-- DQ_RESULTS alone couldn't: "which column caused the biggest score drop"
-- and "is any downstream reporting impacted".
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA DATA_QUALITY;

CREATE OR REPLACE SEMANTIC VIEW DQ_SEMANTIC_VIEW
  TABLES (
    rules AS DQ_RULES PRIMARY KEY (RULE_ID)
      WITH SYNONYMS ('data quality rules', 'validation rules') COMMENT = 'Defined data quality rules',
    results AS DQ_RESULTS PRIMARY KEY (RESULT_ID)
      WITH SYNONYMS ('validation results', 'rule failures', 'check results') COMMENT = 'Historical results of running each DQ rule',
    column_health AS DQ_COLUMN_HEALTH PRIMARY KEY (HEALTH_ID)
      WITH SYNONYMS ('column health') COMMENT = 'Per-column health metrics (nulls, duplicates, outliers, format violations) as of each check date -- this table holds MULTIPLE historical snapshots per column (one row per column per CHECK_DATE), so aggregates over it span all checks ever run, not just the current state. Filter to MAX(CHECK_DATE) for "current" questions, or prefer the column_trends table below, which is pre-collapsed to one row per column at its latest snapshot.',
    scores AS DQ_SCORES PRIMARY KEY (SCORE_ID)
      WITH SYNONYMS ('data quality scores', 'DQ scores') COMMENT = 'Aggregated weekly data quality scores per table',
    column_trends AS VW_DQ_COLUMN_HEALTH_TRENDS PRIMARY KEY (TREND_ID)
      WITH SYNONYMS ('column score trend', 'column health history', 'score drop') COMMENT = 'Per-column data quality score trend derived from DQ_COLUMN_HEALTH history: latest score vs. previous and earliest snapshot, so root-cause questions like "which column had the biggest score drop" can be answered',
    downstream_impact AS DQ_DOWNSTREAM_IMPACT PRIMARY KEY (DOWNSTREAM_ID)
      WITH SYNONYMS ('downstream reports', 'impacted dashboards', 'report lineage', 'affected reporting') COMMENT = 'Maps a source table/column to the downstream reports, dashboards, or models that depend on it, for data-quality impact analysis'
  )

  RELATIONSHIPS (
    results (RULE_ID) REFERENCES rules (RULE_ID)
  )

  FACTS (
    results.total_records AS results.TOTAL_RECORDS,
    results.passed_records AS results.PASSED_RECORDS,
    results.failed_records AS results.FAILED_RECORDS,
    results.pass_rate AS results.PASS_RATE,
    rules.threshold_pct AS rules.THRESHOLD_PCT,
    column_health.null_pct AS column_health.NULL_PCT,
    column_health.distinct_count AS column_health.DISTINCT_COUNT,
    column_health.duplicate_pct AS column_health.DUPLICATE_PCT,
    column_health.outlier_count AS column_health.OUTLIER_COUNT,
    column_health.format_violation_count AS column_health.FORMAT_VIOLATION_COUNT,
    column_health.score AS column_health.SCORE,
    scores.overall_score AS scores.OVERALL_SCORE,
    scores.completeness_score AS scores.COMPLETENESS_SCORE,
    scores.accuracy_score AS scores.ACCURACY_SCORE,
    scores.consistency_score AS scores.CONSISTENCY_SCORE,
    scores.timeliness_score AS scores.TIMELINESS_SCORE,
    scores.rules_passed AS scores.RULES_PASSED,
    scores.rules_failed AS scores.RULES_FAILED,
    scores.total_rules AS scores.TOTAL_RULES,

    column_trends.latest_score AS column_trends.LATEST_SCORE,
    column_trends.previous_score AS column_trends.PREVIOUS_SCORE,
    column_trends.score_change AS column_trends.SCORE_CHANGE,
    column_trends.earliest_score AS column_trends.EARLIEST_SCORE,
    column_trends.score_change_since_first AS column_trends.SCORE_CHANGE_SINCE_FIRST
  )

  DIMENSIONS (
    rules.rule_name AS rules.RULE_NAME,
    rules.rule_description AS rules.RULE_DESCRIPTION,
    rules.rule_type AS rules.RULE_TYPE
      WITH SYNONYMS ('type of check', 'DQ dimension'),
    rules.rule_expression AS rules.RULE_EXPRESSION,
    rules.severity AS rules.SEVERITY
      WITH SYNONYMS ('rule severity', 'criticality'),
    rules.is_critical AS rules.IS_CRITICAL,
    rules.active_flag AS rules.ACTIVE_FLAG,
    rules.target_table AS rules.TARGET_TABLE
      WITH SYNONYMS ('rule table'),
    rules.target_column AS rules.TARGET_COLUMN
      WITH SYNONYMS ('rule column'),

    results.execution_date AS results.EXECUTION_DATE
      WITH SYNONYMS ('check date', 'run date'),
    results.status AS results.STATUS
      WITH SYNONYMS ('pass fail status', 'check outcome'),
    results.error_sample AS results.ERROR_SAMPLE
      WITH SYNONYMS ('failure reason', 'sample bad values'),
    results.target_table AS results.TARGET_TABLE,
    results.target_column AS results.TARGET_COLUMN,

    column_health.table_name AS column_health.TABLE_NAME,
    column_health.column_name AS column_health.COLUMN_NAME,
    column_health.check_date AS column_health.CHECK_DATE,
    column_health.health_status AS column_health.HEALTH_STATUS
      WITH SYNONYMS ('column status', 'health rating'),
    column_health.is_critical AS column_health.IS_CRITICAL,

    scores.table_name AS scores.TABLE_NAME,
    scores.schema_name AS scores.SCHEMA_NAME,
    scores.score_date AS scores.SCORE_DATE,
    scores.trend AS scores.TREND
      WITH SYNONYMS ('score direction', 'improving or declining'),

    column_trends.table_name AS column_trends.TABLE_NAME,
    column_trends.column_name AS column_trends.COLUMN_NAME,
    column_trends.latest_check_date AS column_trends.LATEST_CHECK_DATE,
    column_trends.latest_health_status AS column_trends.LATEST_HEALTH_STATUS
      WITH SYNONYMS ('current column health status'),
    column_trends.earliest_check_date AS column_trends.EARLIEST_CHECK_DATE,

    downstream_impact.target_table AS downstream_impact.TARGET_TABLE,
    downstream_impact.target_column AS downstream_impact.TARGET_COLUMN,
    downstream_impact.report_name AS downstream_impact.REPORT_NAME
      WITH SYNONYMS ('downstream report', 'dashboard name', 'affected report', 'impacted report'),
    downstream_impact.report_type AS downstream_impact.REPORT_TYPE,
    downstream_impact.owner_team AS downstream_impact.OWNER_TEAM,
    downstream_impact.impact_level AS downstream_impact.IMPACT_LEVEL
      WITH SYNONYMS ('severity of downstream impact')
  )

  METRICS (
    results.total_checks AS COUNT(DISTINCT results.RESULT_ID)
      WITH SYNONYMS ('number of checks run'),
    results.total_failures AS SUM(IFF(results.STATUS = 'FAIL', 1, 0))
      WITH SYNONYMS ('number of failed checks', 'rule failures'),
    results.failure_rate AS AVG(IFF(results.STATUS = 'FAIL', 1.0, 0.0))
      WITH SYNONYMS ('data quality failure rate'),
    results.avg_pass_rate AS AVG(results.pass_rate)
      WITH SYNONYMS ('average pass rate'),

    column_health.avg_null_pct AS AVG(column_health.null_pct)
      WITH SYNONYMS ('average null percentage'),
    column_health.avg_duplicate_pct AS AVG(column_health.duplicate_pct)
      WITH SYNONYMS ('average duplicate percentage'),
    column_health.total_outliers AS SUM(column_health.outlier_count)
      WITH SYNONYMS ('number of outliers'),
    column_health.total_format_violations AS SUM(column_health.format_violation_count)
      WITH SYNONYMS ('number of format violations'),
    column_health.unhealthy_column_count AS SUM(IFF(column_health.HEALTH_STATUS != 'Healthy', 1, 0))
      WITH SYNONYMS ('number of unhealthy columns'),

    scores.avg_overall_score AS AVG(scores.overall_score)
      WITH SYNONYMS ('average data quality score'),
    scores.avg_completeness_score AS AVG(scores.completeness_score),
    scores.avg_accuracy_score AS AVG(scores.accuracy_score),
    scores.declining_table_count AS SUM(IFF(scores.TREND = 'DOWN', 1, 0))
      WITH SYNONYMS ('number of tables trending down', 'declining data quality'),

    column_trends.biggest_score_drop AS MIN(column_trends.score_change_since_first)
      WITH SYNONYMS ('largest score decline', 'worst column trend', 'biggest score drop'),
    column_trends.declining_column_count AS SUM(IFF(column_trends.score_change_since_first < 0, 1, 0))
      WITH SYNONYMS ('number of columns trending down'),

    downstream_impact.impacted_report_count AS COUNT(DISTINCT downstream_impact.DOWNSTREAM_ID)
      WITH SYNONYMS ('number of affected reports', 'number of impacted dashboards'),
    downstream_impact.high_impact_report_count AS SUM(IFF(downstream_impact.IMPACT_LEVEL = 'High', 1, 0))
      WITH SYNONYMS ('number of high-impact reports')
  )

  COMMENT = 'Semantic view for Agent 3 (Data Quality Root Cause): lets business users ask why a DQ check failed, which columns are unhealthy, and how DQ scores trend over time.';

GRANT SELECT ON SEMANTIC VIEW DQ_SEMANTIC_VIEW TO ROLE PUBLIC;
SHOW SEMANTIC VIEWS IN SCHEMA INSURANCE_AI_HUB.DATA_QUALITY;
DESCRIBE SEMANTIC VIEW DQ_SEMANTIC_VIEW;

-- Sanity check: query it directly before wiring into the agent
SELECT * FROM SEMANTIC_VIEW(
  DQ_SEMANTIC_VIEW
  METRICS results.total_failures, results.avg_pass_rate
  DIMENSIONS rules.rule_type
);

-- ----------------------------------------------------------------------------
-- Once this view is verified working, add it to the unified agent by
-- uncommenting the DataQualityAgent block in 03_create_unified_agent.sql
-- and re-running that script (CREATE OR REPLACE AGENT is idempotent).
-- ----------------------------------------------------------------------------
