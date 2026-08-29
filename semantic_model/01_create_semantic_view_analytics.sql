-- ============================================================================
-- AGENT 1: SELF-SERVICE ANALYTICS
-- Cortex Analyst Semantic View over the ANALYTICS schema
-- (CUSTOMERS, POLICIES, CLAIMS, BILLING, AGENTS, AT_RISK_POLICIES)
--
-- This uses the native CREATE SEMANTIC VIEW object (SQL-first, no YAML/stage
-- needed) so Cortex Analyst can answer natural-language questions like:
--   "What is our loss ratio by policy type this year?"
--   "Which agents have the highest average performance rating?"
--   "How much revenue is at risk from customers with 2+ complaints?"
--
-- Run this after the tables in INSURANCE_AI_HUB.ANALYTICS are created and
-- loaded. Snowflake semantic views are a newer object type — if any clause
-- errors on your account, check `CREATE SEMANTIC VIEW` in the SQL reference
-- for the exact syntax version your account has, then adjust.
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE SEMANTIC VIEW ANALYTICS_SEMANTIC_VIEW
  TABLES (
    customers AS CUSTOMERS PRIMARY KEY (CUSTOMER_ID)
      WITH SYNONYMS ('clients', 'policyholders') COMMENT = 'Insurance customers / policyholders',
    agents AS AGENTS PRIMARY KEY (AGENT_ID)
      WITH SYNONYMS ('insurance agents', 'reps') COMMENT = 'Insurance agents who sell and service policies',
    policies AS POLICIES PRIMARY KEY (POLICY_ID)
      WITH SYNONYMS ('insurance policies', 'contracts') COMMENT = 'Active and historical insurance policies',
    claims AS CLAIMS PRIMARY KEY (CLAIM_ID)
      WITH SYNONYMS ('insurance claims') COMMENT = 'Claims filed against policies',
    billing AS BILLING PRIMARY KEY (BILLING_ID)
      WITH SYNONYMS ('invoices', 'payments') COMMENT = 'Billing/invoice records for policies',
    at_risk AS AT_RISK_POLICIES PRIMARY KEY (RISK_ID)
      WITH SYNONYMS ('churn risk', 'at-risk policies') COMMENT = 'Policies flagged as at risk of churn or revenue loss'
  )

  RELATIONSHIPS (
    policies (CUSTOMER_ID) REFERENCES customers (CUSTOMER_ID),
    policies (AGENT_ID) REFERENCES agents (AGENT_ID),
    claims (POLICY_ID) REFERENCES policies (POLICY_ID),
    billing (POLICY_ID) REFERENCES policies (POLICY_ID),
    at_risk (POLICY_ID) REFERENCES policies (POLICY_ID)
  )

  FACTS (
    policies.premium_amount AS policies.PREMIUM_AMOUNT,
    policies.coverage_amount AS policies.COVERAGE_AMOUNT,
    policies.deductible AS policies.DEDUCTIBLE,
    policies.loss_ratio AS policies.LOSS_RATIO,
    claims.claim_amount AS claims.CLAIM_AMOUNT,
    claims.approved_amount AS claims.APPROVED_AMOUNT,
    claims.fraud_score AS claims.FRAUD_SCORE,
    claims.days_to_resolve AS claims.DAYS_TO_RESOLVE,
    billing.amount_due AS billing.AMOUNT_DUE,
    billing.amount_paid AS billing.AMOUNT_PAID,
    billing.outstanding_balance AS billing.OUTSTANDING_BALANCE,
    billing.late_fee AS billing.LATE_FEE,
    agents.performance_rating AS agents.PERFORMANCE_RATING,
    at_risk.risk_score AS at_risk.RISK_SCORE,
    at_risk.revenue_at_risk AS at_risk.REVENUE_AT_RISK,
    at_risk.churn_probability AS at_risk.CHURN_PROBABILITY,
    customers.credit_score AS customers.CREDIT_SCORE
  )

  DIMENSIONS (
    customers.customer_name AS CONCAT(customers.FIRST_NAME, ' ', customers.LAST_NAME)
      WITH SYNONYMS ('client name', 'policyholder name'),
    customers.state AS customers.STATE,
    customers.city AS customers.CITY,
    customers.risk_tier AS customers.RISK_TIER,
    customers.segment AS customers.SEGMENT,
    customers.gender AS customers.GENDER,
    customers.customer_since AS customers.CUSTOMER_SINCE,

    agents.agent_name AS agents.AGENT_NAME,
    agents.agent_type AS agents.AGENT_TYPE,
    agents.region AS agents.REGION,
    agents.branch AS agents.BRANCH,
    agents.specialization AS agents.SPECIALIZATION,
    agents.active_flag AS agents.ACTIVE_FLAG,
    agents.hire_date AS agents.HIRE_DATE,

    policies.policy_type AS policies.POLICY_TYPE
      WITH SYNONYMS ('line of business', 'insurance type'),
    policies.policy_status AS policies.POLICY_STATUS,
    policies.plan_tier AS policies.PLAN_TIER,
    policies.payment_frequency AS policies.PAYMENT_FREQUENCY,
    policies.auto_renew AS policies.AUTO_RENEW,
    policies.start_date AS policies.START_DATE,
    policies.end_date AS policies.END_DATE,

    claims.claim_type AS claims.CLAIM_TYPE,
    claims.claim_status AS claims.CLAIM_STATUS,
    claims.fraud_flag AS claims.FRAUD_FLAG
      WITH SYNONYMS ('suspected fraud', 'flagged as fraud'),
    claims.priority AS claims.PRIORITY,
    claims.friction_point AS claims.FRICTION_POINT,
    claims.assigned_adjuster AS claims.ASSIGNED_ADJUSTER,
    claims.claim_date AS claims.CLAIM_DATE,
    claims.resolution_date AS claims.RESOLUTION_DATE,

    billing.payment_status AS billing.PAYMENT_STATUS,
    billing.payment_method AS billing.PAYMENT_METHOD,
    billing.invoice_date AS billing.INVOICE_DATE,
    billing.due_date AS billing.DUE_DATE,
    billing.payment_date AS billing.PAYMENT_DATE,

    at_risk.risk_category AS at_risk.RISK_CATEGORY
      WITH SYNONYMS ('churn category', 'risk type'),
    at_risk.recommended_action AS at_risk.RECOMMENDED_ACTION,
    at_risk.identified_date AS at_risk.IDENTIFIED_DATE,
    at_risk.last_interaction_date AS at_risk.LAST_INTERACTION_DATE
  )

  METRICS (
    customers.customer_count AS COUNT(DISTINCT customers.CUSTOMER_ID)
      WITH SYNONYMS ('number of customers', 'total customers'),

    policies.policy_count AS COUNT(DISTINCT policies.POLICY_ID)
      WITH SYNONYMS ('number of policies', 'total policies'),
    policies.total_premium AS SUM(policies.premium_amount)
      WITH SYNONYMS ('total premium revenue', 'written premium'),
    policies.avg_loss_ratio AS AVG(policies.loss_ratio)
      WITH SYNONYMS ('average loss ratio'),
    policies.total_coverage AS SUM(policies.coverage_amount),

    claims.claim_count AS COUNT(DISTINCT claims.CLAIM_ID)
      WITH SYNONYMS ('number of claims', 'total claims'),
    claims.total_claim_amount AS SUM(claims.claim_amount)
      WITH SYNONYMS ('total claims paid', 'total claim value'),
    claims.total_approved_amount AS SUM(claims.approved_amount),
    claims.avg_days_to_resolve AS AVG(claims.days_to_resolve)
      WITH SYNONYMS ('average claim resolution time'),
    claims.avg_fraud_score AS AVG(claims.fraud_score),
    claims.fraud_claim_count AS SUM(IFF(claims.FRAUD_FLAG, 1, 0))
      WITH SYNONYMS ('number of fraudulent claims', 'flagged fraud claims'),

    billing.total_outstanding_balance AS SUM(billing.outstanding_balance)
      WITH SYNONYMS ('total amount overdue', 'total unpaid balance'),
    billing.total_amount_paid AS SUM(billing.amount_paid),
    billing.total_late_fees AS SUM(billing.late_fee),

    at_risk.total_revenue_at_risk AS SUM(at_risk.revenue_at_risk)
      WITH SYNONYMS ('revenue at risk', 'churn revenue exposure'),
    at_risk.avg_churn_probability AS AVG(at_risk.churn_probability),
    at_risk.at_risk_policy_count AS COUNT(DISTINCT at_risk.RISK_ID),

    agents.avg_performance_rating AS AVG(agents.performance_rating)
      WITH SYNONYMS ('average agent rating')
  )

  COMMENT = 'Semantic view for Agent 1 (Self-Service Analytics): lets business users ask natural-language questions across customers, policies, claims, billing, agents, and at-risk policies without writing SQL.';

-- Grant usage so Cortex Analyst / Snowflake Intelligence and end users can query it
GRANT SELECT ON SEMANTIC VIEW ANALYTICS_SEMANTIC_VIEW TO ROLE PUBLIC;

-- Sanity check: list the semantic view and preview its metadata
SHOW SEMANTIC VIEWS IN SCHEMA INSURANCE_AI_HUB.ANALYTICS;
DESCRIBE SEMANTIC VIEW ANALYTICS_SEMANTIC_VIEW;

-- Example of querying it directly with SEMANTIC_VIEW() before wiring up an agent
-- SELECT * FROM SEMANTIC_VIEW(
--   ANALYTICS_SEMANTIC_VIEW
--   METRICS policies.total_premium, claims.claim_count
--   DIMENSIONS policies.policy_type
-- );
