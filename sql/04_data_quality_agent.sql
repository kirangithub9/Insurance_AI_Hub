-- ============================================================================
-- AGENT 3: DATA QUALITY ROOT CAUSE (DRAFT — CONFIRM COLUMNS BEFORE RUNNING)
--
-- ⚠️ This file is a TEMPLATE. I don't yet have the real CREATE TABLE
-- statements for DQ_RULES, DQ_RESULTS, DQ_COLUMN_HEALTH, and DQ_SCORES —
-- only the table names are confirmed. The columns below are my best guess
-- from naming convention and should be checked against your actual DDL
-- (run the GET_DDL query from earlier, or paste the CREATE TABLE statements)
-- before you execute this script. Replace any column name that doesn't
-- match and re-run.
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA DATA_QUALITY;

-- Uncomment once verified against real column names:
-- DESCRIBE TABLE DQ_RULES;
-- DESCRIBE TABLE DQ_RESULTS;
-- DESCRIBE TABLE DQ_COLUMN_HEALTH;
-- DESCRIBE TABLE DQ_SCORES;

CREATE OR REPLACE SEMANTIC VIEW DQ_SEMANTIC_VIEW
  TABLES (
    rules AS DQ_RULES PRIMARY KEY (RULE_ID)
      WITH SYNONYMS ('data quality rules', 'validation rules') COMMENT = 'Defined data quality rules',
    results AS DQ_RESULTS PRIMARY KEY (RESULT_ID)
      WITH SYNONYMS ('validation results', 'rule failures') COMMENT = 'Historical results of running each DQ rule',
    column_health AS DQ_COLUMN_HEALTH PRIMARY KEY (HEALTH_ID)
      WITH SYNONYMS ('column health') COMMENT = 'Per-column health metrics (nulls, distinctness, etc.)',
    scores AS DQ_SCORES PRIMARY KEY (SCORE_ID)
      WITH SYNONYMS ('data quality scores', 'DQ scores') COMMENT = 'Aggregated data quality scores per table'
  )

  RELATIONSHIPS (
    results (RULE_ID) REFERENCES rules (RULE_ID)
  )

  FACTS (
    results.records_checked AS results.RECORDS_CHECKED,
    results.records_failed AS results.RECORDS_FAILED,
    column_health.null_percentage AS column_health.NULL_PERCENTAGE,
    column_health.distinct_count AS column_health.DISTINCT_COUNT,
    scores.overall_score AS scores.OVERALL_SCORE
  )

  DIMENSIONS (
    rules.rule_name AS rules.RULE_NAME,
    rules.rule_type AS rules.RULE_TYPE,
    rules.severity AS rules.SEVERITY,
    rules.table_name AS rules.TABLE_NAME,
    rules.column_name AS rules.COLUMN_NAME,

    results.check_date AS results.CHECK_DATE,
    results.pass_flag AS results.PASS_FLAG,
    results.failure_reason AS results.FAILURE_REASON,

    column_health.table_name AS column_health.TABLE_NAME,
    column_health.column_name AS column_health.COLUMN_NAME,
    column_health.check_date AS column_health.CHECK_DATE,

    scores.table_name AS scores.TABLE_NAME,
    scores.score_date AS scores.SCORE_DATE
  )

  METRICS (
    results.total_checks AS COUNT(DISTINCT results.RESULT_ID),
    results.total_failures AS SUM(IFF(results.PASS_FLAG = FALSE, 1, 0))
      WITH SYNONYMS ('number of failed checks', 'rule failures'),
    results.failure_rate AS AVG(IFF(results.PASS_FLAG = FALSE, 1.0, 0.0))
      WITH SYNONYMS ('data quality failure rate'),
    column_health.avg_null_percentage AS AVG(column_health.null_percentage),
    scores.avg_overall_score AS AVG(scores.overall_score)
      WITH SYNONYMS ('average data quality score')
  )

  COMMENT = 'Semantic view for Agent 3 (Data Quality Root Cause): lets business users ask why a DQ check failed, which columns are unhealthy, and how DQ scores trend over time.';

GRANT SELECT ON SEMANTIC VIEW DQ_SEMANTIC_VIEW TO ROLE PUBLIC;
SHOW SEMANTIC VIEWS IN SCHEMA INSURANCE_AI_HUB.DATA_QUALITY;

-- ----------------------------------------------------------------------------
-- Once this view is verified working, add it to the unified agent by
-- uncommenting the DataQualityAgent block in 03_create_unified_agent.sql
-- and re-running that script (CREATE OR REPLACE AGENT is idempotent).
-- ----------------------------------------------------------------------------
