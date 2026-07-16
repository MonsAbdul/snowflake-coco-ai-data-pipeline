CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
      'COCO_WORKSHOP.PIPELINE_LAB',
      $$
    name: SV_AP_ANALYTICS
    description: >
      Unified Accounts Payable invoice analytics across four ERP systems
      (SAP, Oracle, Baan, Workday). Each row is one invoice. Status is normalized
      to APPROVED/PENDING. Amounts are in original transaction currency — no FX
      conversion applied. Use for spend analysis, vendor concentration, approval
      bottleneck detection, and procurement compliance.
    tables:
      - name: SILVER_AP_INVOICES
        base_table:
          database: COCO_WORKSHOP
          schema: PIPELINE_LAB
          table: SILVER_AP_INVOICES
        description: >
          Fact table of AP invoices unified from SAP, Oracle, Baan, and Workday.
          Grain: one row per invoice per source system. Amounts are in original
          transaction currency. Join back to Bronze tables via SOURCE_INVOICE_ID +
          SOURCE_SYSTEM for audit trail.
        dimensions:
          - name: SOURCE_SYSTEM
            expr: SOURCE_SYSTEM
            data_type: VARCHAR
            description: >
              ERP system that originated the invoice. Values: SAP, ORACLE, BAAN,
              WORKDAY. Use for filtering or grouping by source.
            synonyms:
              - erp system
              - source
              - system
          - name: SOURCE_INVOICE_ID
            expr: SOURCE_INVOICE_ID
            data_type: VARCHAR
            description: >
              Primary key from the source ERP. Format varies by system. Not
              comparable across systems.
          - name: INVOICE_NUMBER
            expr: INVOICE_NUMBER
            data_type: VARCHAR
            description: >
              Business-facing invoice reference number. Unique within each
              SOURCE_SYSTEM.
            synonyms:
              - invoice ref
              - invoice no
          - name: VENDOR_ID
            expr: VENDOR_ID
            data_type: VARCHAR
            description: >
              Vendor/supplier identifier from the source system. IDs are NOT
              cross-referenceable across systems.
            synonyms:
              - supplier id
          - name: VENDOR_NAME
            expr: VENDOR_NAME
            data_type: VARCHAR
            description: >
              Vendor display name. Use for grouping and display. May contain
              non-ASCII characters from European vendor names.
            synonyms:
              - supplier name
              - vendor
              - supplier
          - name: CURRENCY_CODE
            expr: CURRENCY_CODE
            data_type: VARCHAR
            description: >
              ISO 4217 currency code (USD, EUR, GBP). Amounts are in this
              currency. Do NOT sum across currencies without noting the result
              is mixed-currency.
            synonyms:
              - currency
              - ccy
          - name: PAYMENT_TERMS
            expr: PAYMENT_TERMS
            data_type: VARCHAR
            description: >
              Raw payment terms from source. NOT normalized: SAP uses NET30/NET60,
              Oracle/Baan use N30/N60, Workday uses Net 30/Net 60. All represent
              30-day or 60-day terms.
            synonyms:
              - terms
              - pay terms
          - name: PO_NUMBER
            expr: PO_NUMBER
            data_type: VARCHAR
            description: >
              Purchase order reference. NULL means no PO was associated (common
              for service invoices). Use IS NULL check for procurement compliance.
            synonyms:
              - purchase order
              - po
          - name: LINE_DESCRIPTION
            expr: LINE_DESCRIPTION
            data_type: VARCHAR
            description: >
              Free-text description of the invoice line item. May be in Dutch
              (Baan) or English. Useful for keyword search.
            synonyms:
              - description
              - memo
          - name: GL_ACCOUNT
            expr: GL_ACCOUNT
            data_type: VARCHAR
            description: >
              General ledger account code from the source system. Format varies
              by source. NOT cross-mapped between systems.
            synonyms:
              - gl code
              - account
          - name: COST_CENTER
            expr: COST_CENTER
            data_type: VARCHAR
            description: >
              Department or cost center code. Format varies by source. Represents
              the team/function that incurred the cost.
            synonyms:
              - department
              - business unit
              - dept
          - name: APPROVAL_STATUS
            expr: APPROVAL_STATUS
            data_type: VARCHAR
            description: >
              Normalized approval state. Only two values: APPROVED (ready to pay)
              or PENDING (awaiting approval). Mapped from source-specific statuses.
            synonyms:
              - status
              - approval state
        time_dimensions:
          - name: INVOICE_DATE
            expr: INVOICE_DATE
            data_type: DATE
            description: >
              Date the invoice was issued. Primary time dimension for trend
              analysis, aging calculations, and period filtering.
            synonyms:
              - invoice dt
              - date
          - name: DUE_DATE
            expr: DUE_DATE
            data_type: DATE
            description: >
              Payment due date. Compare to CURRENT_DATE for aging/overdue
              analysis. DUE_DATE minus INVOICE_DATE approximates payment terms
              in days.
            synonyms:
              - payment due date
              - due
          - name: CREATED_AT
            expr: CREATED_AT
            data_type: TIMESTAMP_NTZ
            description: >
              Timestamp when the invoice record was created in the source system.
              All values in UTC.
            synonyms:
              - created date
              - creation date
        facts:
          - name: INVOICE_AMOUNT
            expr: INVOICE_AMOUNT
            data_type: NUMBER
            description: >
              Invoice total in the original transaction currency (see
              CURRENCY_CODE). Positive = payable, negative = credit memo.
              Do NOT sum across currencies without stating the result is
              mixed-currency.
            synonyms:
              - amount
              - spend
              - invoice value
        metrics:
          - name: TOTAL_SPEND
            expr: SUM(INVOICE_AMOUNT)
            data_type: NUMBER
            description: >
              Total invoice amount. WARNING: if not filtered by CURRENCY_CODE,
              this is a mixed-currency sum.
            synonyms:
              - total amount
              - total ap
          - name: INVOICE_COUNT
            expr: COUNT(*)
            data_type: NUMBER
            description: Total number of invoices.
            synonyms:
              - number of invoices
              - invoice volume
              - count
          - name: AVERAGE_INVOICE_AMOUNT
            expr: AVG(INVOICE_AMOUNT)
            data_type: NUMBER
            description: Average invoice amount in original transaction currency.
            synonyms:
              - avg invoice
              - average spend
          - name: PENDING_COUNT
            expr: COUNT_IF(APPROVAL_STATUS = 'PENDING')
            data_type: NUMBER
            description: Number of invoices still awaiting approval.
            synonyms:
              - unapproved count
              - pending invoices
          - name: PENDING_AMOUNT
            expr: SUM(IFF(APPROVAL_STATUS = 'PENDING', INVOICE_AMOUNT, 0))
            data_type: NUMBER
            description: >
              Total amount of invoices pending approval (mixed-currency if
              unfiltered).
            synonyms:
              - unpaid amount
              - outstanding amount
          - name: DISTINCT_VENDOR_COUNT
            expr: COUNT(DISTINCT VENDOR_ID)
            data_type: NUMBER
            description: Number of unique vendors with invoices.
            synonyms:
              - vendor count
              - number of vendors
    verified_queries:
      - name: spend_by_vendor_12m
        question: What is total AP spend by vendor over the last 12 months?
        sql: >
          SELECT VENDOR_NAME, SUM(INVOICE_AMOUNT) AS TOTAL_SPEND,
            COUNT(*) AS INVOICE_COUNT
          FROM SILVER_AP_INVOICES
          WHERE INVOICE_DATE >= DATEADD(MONTH, -12, CURRENT_DATE)
          GROUP BY VENDOR_NAME
          ORDER BY TOTAL_SPEND DESC
        verified_at: 1784180473
        verified_by: Cortex Code
      - name: invoices_by_month_cost_center
        question: How many invoices per month by business unit?
        sql: >
          SELECT DATE_TRUNC('MONTH', INVOICE_DATE) AS INVOICE_MONTH,
            COST_CENTER, COUNT(*) AS INVOICE_COUNT
          FROM SILVER_AP_INVOICES
          GROUP BY INVOICE_MONTH, COST_CENTER
          ORDER BY INVOICE_MONTH DESC, INVOICE_COUNT DESC
        verified_at: 1784180473
        verified_by: Cortex Code
      - name: top10_vendors_pending
        question: Which are the top 10 vendors by unpaid invoice amount?
        sql: >
          SELECT VENDOR_NAME, SUM(INVOICE_AMOUNT) AS UNPAID_AMOUNT,
            COUNT(*) AS INVOICE_COUNT
          FROM SILVER_AP_INVOICES
          WHERE APPROVAL_STATUS = 'PENDING'
          GROUP BY VENDOR_NAME
          ORDER BY UNPAID_AMOUNT DESC
          LIMIT 10
        verified_at: 1784180473
        verified_by: Cortex Code
      - name: spend_by_source_currency
        question: What is the spend breakdown by source system and currency?
        sql: >
          SELECT SOURCE_SYSTEM, CURRENCY_CODE, SUM(INVOICE_AMOUNT) AS TOTAL_AMOUNT,
            COUNT(*) AS INVOICE_COUNT
          FROM SILVER_AP_INVOICES
          GROUP BY SOURCE_SYSTEM, CURRENCY_CODE
          ORDER BY TOTAL_AMOUNT DESC
        verified_at: 1784180473
        verified_by: Cortex Code
      - name: invoices_without_po
        question: Which invoices have no purchase order number?
        sql: >
          SELECT VENDOR_NAME, INVOICE_NUMBER, INVOICE_AMOUNT, CURRENCY_CODE,
            INVOICE_DATE
          FROM SILVER_AP_INVOICES
          WHERE PO_NUMBER IS NULL
          ORDER BY INVOICE_AMOUNT DESC
        verified_at: 1784180473
        verified_by: Cortex Code
      $$,
      FALSE
    );