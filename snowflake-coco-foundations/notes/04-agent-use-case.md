Here's the full agent design:

  ────────────────────────────────────────

  Primary Audience

  AP / Finance Operations teams — controllers, AP managers, and procurement analysts who need to:

  • Track invoice volumes and spend across ERP systems
  • Monitor approval pipeline bottlenecks
  • Identify vendor concentration risk
  • Answer month-end close questions without writing SQL

  Secondary audience: VP Finance / CFO for ad-hoc "how much did we spend on X?" questions.

  ────────────────────────────────────────

  Top Five Business Questions

  ┌───┬──────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────┐
  │ # │ Question                                                                     │ Why It Matters                                                             │
  ├───┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
  │ 1 │ What is our total outstanding AP by source system and approval status?       │ Core month-end close metric — how much is approved vs. still pending.      │
  ├───┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
  │ 2 │ Which vendors have the highest invoice volume or total spend this quarter?   │ Vendor concentration risk; informs negotiation and payment prioritization. │
  ├───┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
  │ 3 │ How many invoices are pending approval, and how long have they been waiting? │ Approval bottleneck detection — compares INVOICE_DATE to today for aging.  │
  ├───┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
  │ 4 │ What is our spend breakdown by currency and cost center?                     │ FX exposure visibility and departmental budget tracking.                   │
  ├───┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
  │ 5 │ Are there invoices without a PO number, and which vendors do they come from? │ Procurement compliance — non-PO invoices bypass controls.                  │
  └───┴──────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────┘

  ────────────────────────────────────────

  Guardrails

  Scope Guardrails

  • Single-table only — The agent queries COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES and nothing else. No joins to Bronze, no cross-schema access.
  • No DDL or DML — Agent is read-only. SELECT statements only.
  • No currency conversion — The agent must never apply FX rates. If asked about USD-equivalent totals, it should state that currency conversion is handled in the Gold layer and is not available here.

  Answer Quality Guardrails

  • Payment terms are not normalized — If asked to group by payment terms, the agent must warn that NET30, N30, and Net 30 are the same concept stored differently across sources. It should group on raw values and note the inconsistency.
  • No cross-system vendor matching — Vendor IDs are source-specific. The agent must not assume V-1001 (SAP) and BV-301 (Baan) are the same vendor even if names are similar.
  • Amounts are in original transaction currency — Any sum across currencies is a mixed-currency total; the agent must label it as such.
  • Status values are normalized — Only APPROVED and PENDING exist. The agent can reliably filter/group on these.

  Safety Guardrails

  • No PII exposure — Vendor names are company names (not individuals), but the agent should not speculate about contacts, bank details, or payment information not in the table.
  • Row-count sanity — If a query returns 0 rows, the agent should confirm the filter rather than saying "no data exists."

  ────────────────────────────────────────

  Semantic Descriptions for Answer Quality

  These column-level descriptions should be included in the semantic model YAML:

    columns:
      - name: SOURCE_SYSTEM
        description: "ERP system that originated the invoice. Values: SAP, ORACLE, BAAN, WORKDAY. Use for filtering or grouping by source."

      - name: SOURCE_INVOICE_ID
        description: "Primary key from the source ERP. Format varies by system (SAP-001, ORA-001, BAN-001, WD-001). Not comparable across systems."

      - name: INVOICE_NUMBER
        description: "Business-facing invoice reference number. Unique within each SOURCE_SYSTEM. Used for deduplication in Baan."

      - name: VENDOR_ID
        description: "Vendor/supplier identifier from the source system. IDs are NOT cross-referenceable across systems — each source has its own vendor master."

      - name: VENDOR_NAME
        description: "Vendor display name. May contain non-ASCII characters (European names from Baan). Use for display, not for matching across systems."

      - name: INVOICE_DATE
        description: "Date the invoice was issued. Use for time-series analysis, aging calculations, and period filtering."

      - name: DUE_DATE
        description: "Payment due date. Compare to CURRENT_DATE for aging/overdue analysis. DUE_DATE - INVOICE_DATE approximates payment terms in days."

      - name: INVOICE_AMOUNT
        description: "Invoice total in the original transaction currency (see CURRENCY_CODE). Positive = payable; negative = credit memo. Do NOT sum across currencies without stating the result is mixed-currency."

      - name: CURRENCY_CODE
        description: "ISO 4217 currency code (USD, EUR, GBP). No conversion applied — amounts are in original currency. ~56% USD, 30% EUR, 14% GBP."

      - name: PAYMENT_TERMS
        description: "Raw payment terms from source. NOT normalized: SAP uses NET30/NET60, Oracle/Baan use N30/N60, Workday uses 'Net 30'/'Net 60'. All represent 30-day or 60-day terms."

      - name: PO_NUMBER
        description: "Purchase order reference. NULL means no PO (common for service invoices). Format varies by source system."

      - name: LINE_DESCRIPTION
        description: "Free-text description of what the invoice is for. May be in Dutch (Baan) or English. Useful for keyword search."

      - name: GL_ACCOUNT
        description: "General ledger account code from the source system. Format varies (SAP: 5100-10, Oracle: A5100-40, Baan: GL-510, Workday: LA-NNNN). NOT cross-mapped — each source uses its own chart of accounts."

      - name: COST_CENTER
        description: "Department or cost center code. Format varies by source (CC-ENG-01, D-ENG, BC-MFG, WCC-XXXX). Represents the team/function that incurred the cost."

      - name: APPROVAL_STATUS
        description: "Normalized approval state. Only two values: APPROVED (ready to pay) or PENDING (awaiting approval). Mapped from source-specific statuses at ingestion."

      - name: CREATED_AT
        description: "Timestamp when the invoice record was created in the source system. All values in UTC."

  Table-Level Description

    tables:
      - name: SILVER_AP_INVOICES
        description: >
          Unified Accounts Payable invoice records from four ERP systems
          (SAP, Oracle, Baan, Workday). Each row is one invoice. Status is
          normalized to APPROVED/PENDING. Amounts are in original transaction
          currency — no FX conversion. Baan records are deduplicated on
          invoice number. System-specific metadata is not carried forward;
          join back to Bronze tables using SOURCE_INVOICE_ID + SOURCE_SYSTEM
          if audit trail is needed.

  ────────────────────────────────────────

  Next Steps

  To make this a live Cortex Agent, you'd need to:

  1. Create a semantic model YAML using the descriptions above
  2. Register it with CREATE CORTEX AGENT referencing the semantic model
  3. Add the AGENT_EVAL_SET table (already in your schema) as a test harness

  Want me to build out the semantic model YAML or the agent DDL?