# Technical Requirements Mapping

The hackathon challenge document lists, under "Technical Requirements &
Snowflake Features to Implement" for **every one of its six use cases**
(Automotive, Retail, Clinical Trial, Pharmaceutical Manufacturing,
Insurance, and this one — Unified Enterprise AI Agents Platform), the
identical block of text:

> Cortex Agents: Product matching agent with multi-strategy approach, Price
> optimization agent for competitive analysis, Market intelligence agent
> for trend detection
> Snowflake Intelligence: Competitive pricing dashboard, Market trend
> analysis, Matching accuracy metrics

This is a copy-paste artifact — it's the Retail Intelligence Platform's
requirements (product catalogs, competitor pricing) pasted under every
other use case's heading too. Our actual problem statement is: *"Build a
unified AI-powered enterprise enablement platform ... allows business users
to interact with structured and unstructured enterprise data using natural
language ... democratize analytics, accelerate document intelligence, and
provide conversational root-cause analysis for data quality issues."*
There is no product catalog, no competitor pricing feed, and no matching
task anywhere in that statement or in the dataset we were given
(`INSURANCE_AI_HUB`: customers, policies, claims, billing, agents,
at-risk policies, policy documents, DQ rules/results).

Building a literal "product matching agent" would mean inventing a problem
that doesn't exist in the data just to match boilerplate text. Instead, we
treated the four **category headings** — AI/SQL, Cortex Agents, Snowflake
Intelligence, MCP Integration — as the real requirement, and implemented
each one against what this use case actually needs:

| Category (from doc) | Retail-boilerplate example (doesn't apply here) | What we built instead |
|---|---|---|
| AI/SQL | — | Cortex Analyst semantic views (`ANALYTICS_SEMANTIC_VIEW`, `DQ_SEMANTIC_VIEW`) generate governed SQL from natural language |
| Cortex Agents | Product matching / price optimization / market intelligence agents | Three tools unified in one `AGENT` object: **AnalyticsAgent** (structured data), **DocumentQA** (RAG over policy documents), **DataQualityAgent** (conversational DQ root cause) — directly matching the three capabilities named in our actual problem statement |
| Snowflake Intelligence | Competitive pricing dashboard / market trend analysis / matching accuracy metrics | **Portfolio & risk dashboard** (premium, loss ratio, revenue at risk by segment) / **Claims & churn trend analysis** (month-over-month) / **Agent accuracy & usage metrics** (query volume by tool, 👍/👎 helpful rate, latency) — the same three dashboard *shapes*, translated to data that exists in this project |
| MCP Integration ("as applicable") | — | `CREATE MCP SERVER` exposing the semantic views and search service as MCP tools, so any MCP client (Claude, Cursor, etc.) can query the platform directly — genuinely applicable since these are already Cortex objects |

This mapping is deliberate, not an oversight — happy to walk a judge through
why each substitution was made if asked during Q&A.
