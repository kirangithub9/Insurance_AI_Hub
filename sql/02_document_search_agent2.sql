-- ============================================================================
-- AGENT 2: DOCUMENT Q&A (RAG over unstructured data)
-- Cortex Search Service over DOCUMENTS.DOCUMENT_CHUNKS
--
-- Cortex Search computes and manages its own embeddings internally, so the
-- EMBEDDING VECTOR(FLOAT,768) column on DOCUMENT_CHUNKS is NOT required by
-- this service (Cortex Search re-embeds CHUNK_TEXT itself using the model
-- you choose below). Keep that column only if you want to do your own
-- manual vector similarity queries separately.
--
-- Prereqs: POLICY_DOCUMENTS.CONTENT_TEXT must already hold the extracted
-- text of each policy/contract document (e.g. via Cortex PARSE_DOCUMENT if
-- you loaded raw PDFs/DOCX into a stage — not covered here since your table
-- already has a CONTENT_TEXT column, implying text extraction is done).
-- ============================================================================

USE DATABASE INSURANCE_AI_HUB;
USE SCHEMA DOCUMENTS;

-- ----------------------------------------------------------------------------
-- STEP 1: Populate DOCUMENT_CHUNKS from POLICY_DOCUMENTS.CONTENT_TEXT
-- Run this once to (re)chunk every document. Safe to re-run (idempotent
-- delete+insert per document) if you reload/edit source documents later.
-- ----------------------------------------------------------------------------

DELETE FROM DOCUMENT_CHUNKS
WHERE DOCUMENT_ID IN (SELECT DOCUMENT_ID FROM POLICY_DOCUMENTS);

INSERT INTO DOCUMENT_CHUNKS (
  CHUNK_ID, DOCUMENT_ID, CHUNK_INDEX, CHUNK_TEXT, SECTION_TITLE, TOKEN_COUNT
)
SELECT
  pd.DOCUMENT_ID || '-CHK-' || LPAD(c.index::STRING, 4, '0')            AS CHUNK_ID,
  pd.DOCUMENT_ID                                                        AS DOCUMENT_ID,
  c.index                                                                AS CHUNK_INDEX,
  c.value::STRING                                                        AS CHUNK_TEXT,
  pd.DOCUMENT_TITLE                                                      AS SECTION_TITLE,
  -- rough token estimate (~4 chars/token); good enough for display purposes
  CEIL(LENGTH(c.value::STRING) / 4.0)::NUMBER                            AS TOKEN_COUNT
FROM POLICY_DOCUMENTS pd,
     LATERAL FLATTEN(
       input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
         pd.CONTENT_TEXT,
         'none',   -- use 'markdown' instead if CONTENT_TEXT is markdown-formatted
         1200,     -- chunk_size (characters)
         200       -- overlap (characters)
       )
     ) c
WHERE pd.CONTENT_TEXT IS NOT NULL
  AND c.value IS NOT NULL;

-- Sanity check
SELECT DOCUMENT_ID, COUNT(*) AS num_chunks
FROM DOCUMENT_CHUNKS
GROUP BY DOCUMENT_ID
ORDER BY DOCUMENT_ID;

-- ----------------------------------------------------------------------------
-- STEP 2: Create the Cortex Search service
-- Adjust WAREHOUSE to whichever warehouse you're using (COMPUTE_WH shown in
-- your worksheet toolbar) and TARGET_LAG to how fresh you need search results
-- (shorter lag = more frequent re-indexing = more credit usage).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE CORTEX SEARCH SERVICE POLICY_DOCUMENT_SEARCH_SVC
  ON CHUNK_TEXT
  ATTRIBUTES DOCUMENT_ID, POLICY_ID, DOCUMENT_TYPE, DOCUMENT_TITLE, SECTION_TITLE, DOCUMENT_STATUS
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS (
  SELECT
    dc.CHUNK_ID,
    dc.CHUNK_TEXT,
    dc.SECTION_TITLE,
    dc.CHUNK_INDEX,
    pd.DOCUMENT_ID,
    pd.POLICY_ID,
    pd.DOCUMENT_TYPE,
    pd.DOCUMENT_TITLE,
    pd.DOCUMENT_STATUS
  FROM DOCUMENT_CHUNKS dc
  JOIN POLICY_DOCUMENTS pd
    ON dc.DOCUMENT_ID = pd.DOCUMENT_ID
);

-- Confirm it's live
SHOW CORTEX SEARCH SERVICES IN SCHEMA INSURANCE_AI_HUB.DOCUMENTS;

-- ----------------------------------------------------------------------------
-- STEP 3: Test the search service directly (before wiring it into an agent)
-- ----------------------------------------------------------------------------

SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'INSURANCE_AI_HUB.DOCUMENTS.POLICY_DOCUMENT_SEARCH_SVC',
    '{
       "query": "what are the exclusion clauses for water damage",
       "columns": ["CHUNK_TEXT", "DOCUMENT_TITLE", "POLICY_ID", "DOCUMENT_TYPE"],
       "limit": 5
     }'
  )
) AS search_results;
