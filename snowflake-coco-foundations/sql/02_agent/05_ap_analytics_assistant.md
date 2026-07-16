Agent is live. Here's the full configuration you can save alongside your project files:

  ────────────────────────────────────────

  Agent: COCO_WORKSHOP.PIPELINE_LAB.AP_ANALYTICS_ASSISTANT

  DDL (copy-pasteable)

    CREATE OR REPLACE AGENT COCO_WORKSHOP.PIPELINE_LAB.AP_ANALYTICS_ASSISTANT
    FROM SPECIFICATION $$
    {
      "models": {
        "orchestration": "auto"
      },
      "orchestration": {
        "budget": {
          "seconds": 900,
          "tokens": 400000
        }
      },
      "instructions": {
        "orchestration": "You are an Accounts Payable analytics assistant. Your primary data source is the SV_AP_ANALYTICS semantic view, which contains unified AP invoice data from four ERP systems (SAP, Oracle, Baan, Workday).\n\nIMPORTANT RULES:\n1. Always use the
  query_ap_invoices tool to answer data questions.\n2. If the user's question is ambiguous about time grain (month vs quarter vs year), currency scope (single vs mixed), or metric definition (total spend vs pending only), ask a clarifying question BEFORE running a query.\n3.
  Amounts are in original transaction currency (USD, EUR, GBP). If a query sums across currencies without a filter, explicitly warn that the result is a mixed-currency total.\n4. VENDOR_ID values are NOT comparable across source systems. Do not attempt cross-system vendor
  deduplication.\n5. PAYMENT_TERMS are not normalized (NET30, N30, Net 30 all mean the same thing but appear differently). Warn the user if grouping by payment terms.\n6. Only two APPROVAL_STATUS values exist: APPROVED and PENDING.",
        "response": "Always structure your response in three parts:\n\n**Answer:** Provide the direct answer to the user's question with key numbers and insights.\n\n**SQL Used:**\n```sql\n<the exact SQL query executed>\n```\n\n**Assumptions:**\n- List any assumptions made about
   grain, filters, time range, or currency scope.\n- If results span multiple currencies, note that amounts are not FX-converted.\n- If a filter was applied that wasn't explicitly requested, explain why."
      },
      "tools": [
        {
          "tool_spec": {
            "type": "cortex_analyst_text_to_sql",
            "name": "query_ap_invoices",
            "description": "Query unified AP invoice data across SAP, Oracle, Baan, and Workday. Use for spend analysis, vendor concentration, approval status, invoice aging, and procurement compliance questions. Data includes invoice amounts in original currency, vendor
  details, cost centers, GL accounts, PO numbers, and approval status."
          }
        }
      ],
      "tool_resources": {
        "query_ap_invoices": {
          "execution_environment": {
            "query_timeout": 299,
            "type": "warehouse",
            "warehouse": ""
          },
          "semantic_view": "COCO_WORKSHOP.PIPELINE_LAB.SV_AP_ANALYTICS"
        }
      }
    }
    $$;

  Design Decisions

  ┌──────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ Decision                     │ Rationale                                                                                                                                      │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Orchestration instructions   │ Encode the guardrails (mixed-currency warning, no cross-system vendor matching, payment terms caveat) so the agent enforces them automatically │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Response instructions        │ Force the 3-part structure (Answer / SQL Used / Assumptions) so users always see what was executed and what was assumed                        │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Clarification-first behavior │ Agent asks before querying when time grain, currency scope, or metric is ambiguous — prevents silent wrong answers                             │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Single tool                  │ One cortex_analyst_text_to_sql tool pointing at SV_AP_ANALYTICS — keeps the agent scoped to curated Silver data only                           │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Empty warehouse string       │ Lets Snowflake use the session warehouse at runtime                                                                                            │
  └──────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  You can test it in Snowsight via the Agent UI, or chat with it using $cortex-agent → CHAT intent.