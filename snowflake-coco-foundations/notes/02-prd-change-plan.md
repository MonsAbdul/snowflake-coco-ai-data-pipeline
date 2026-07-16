I have everything needed. Here's the full plan:

  ────────────────────────────────────────

  1. Summary of Requested Changes

  The column mapping PRD specifies onboarding Baan IV and Workday into the existing COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES Dynamic Table (currently SAP + Oracle, 30 rows). It also requires:

  • Dropping SOURCE_ENTITY_CODE and SOURCE_METADATA from the current DT (per BR-008: system-specific columns not carried to Silver).
  • Renaming INVOICE_STATUS → APPROVAL_STATUS (the column mapping uses APPROVAL_STATUS as the canonical Silver name).
  • Adding status normalization logic (BR-001) as a CASE statement across all branches.
  • Adding Baan deduplication (BR-003) via QUALIFY ROW_NUMBER().
  • Changing TARGET_LAG from '1 hour' to DOWNSTREAM (BR-009).

  ────────────────────────────────────────

  2. Source-to-Silver Mapping Summary

  ┌────────────────────┬─────────────────────────┬──────────────────┬────────────────────┬────────────────────────────┬───────────────────────────────────────────┐
  │ Silver Column      │ SAP                     │ Oracle           │ Baan               │ Workday                    │ Transform                                 │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ SOURCE_SYSTEM      │ 'SAP'                   │ 'ORACLE'         │ 'BAAN'             │ 'WORKDAY'                  │ Hard-coded literal                        │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ SOURCE_INVOICE_ID  │ INVOICE_ID              │ INV_ID           │ BAN_INVOICE_ID     │ WD_INVOICE_ID              │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ INVOICE_NUMBER     │ INVOICE_NUMBER          │ INV_NUM          │ BAN_INVOICE_REF    │ WD_INVOICE_NUM             │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ VENDOR_ID          │ VENDOR_ID               │ SUPPLIER_ID      │ BAN_VENDOR_CODE    │ WD_SUPPLIER_ID             │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ VENDOR_NAME        │ VENDOR_NAME             │ SUPPLIER_NAME    │ BAN_VENDOR_DESC    │ WD_SUPPLIER_NAME           │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ INVOICE_DATE       │ INVOICE_DATE            │ INV_DATE         │ BAN_INV_DATE       │ WD_INVOICE_DATE            │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ DUE_DATE           │ DUE_DATE                │ PAYMENT_DUE_DATE │ BAN_PAY_DATE       │ WD_DUE_DATE                │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ INVOICE_AMOUNT     │ INVOICE_AMOUNT          │ TOTAL_AMOUNT     │ BAN_AMOUNT         │ WD_AMOUNT                  │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ CURRENCY_CODE      │ CURRENCY_CODE           │ CURRENCY         │ BAN_CURR           │ WD_CURRENCY                │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ PAYMENT_TERMS      │ PAYMENT_TERMS           │ TERMS_CODE       │ BAN_PAY_TERMS      │ WD_PAY_TERMS               │ Pass-through (no normalization at Silver) │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ PO_NUMBER          │ PO_NUMBER               │ PURCHASE_ORDER   │ BAN_PO_REF         │ WD_PO_NUMBER               │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ LINE_DESCRIPTION   │ LINE_DESCRIPTION        │ DESCRIPTION      │ BAN_LINE_DESC      │ WD_MEMO                    │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ GL_ACCOUNT         │ GL_ACCOUNT              │ ACCOUNT_CODE     │ BAN_GL_CODE        │ WD_LEDGER_ACCOUNT          │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ COST_CENTER        │ COST_CENTER             │ DEPT_CODE        │ BAN_COST_CTR       │ WD_COST_CENTER             │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ APPROVAL_STATUS    │ CASE on APPROVAL_STATUS │ CASE on STATUS   │ CASE on BAN_STATUS │ CASE on WD_APPROVAL_STATUS │ BR-001 normalization                      │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ CREATED_AT         │ CREATED_AT              │ CREATION_DATE    │ BAN_CREATED        │ WD_CREATED_DATE            │ Direct                                    │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ SOURCE_ENTITY_CODE │ —                       │ —                │ —                  │ —                          │ [REMOVED] per BR-008                      │
  ├────────────────────┼─────────────────────────┼──────────────────┼────────────────────┼────────────────────────────┼───────────────────────────────────────────┤
  │ SOURCE_METADATA    │ —                       │ —                │ —                  │ —                          │ [REMOVED] per BR-008                      │
  └────────────────────┴─────────────────────────┴──────────────────┴────────────────────┴────────────────────────────┴───────────────────────────────────────────┘

  Columns dropped from source: BAN_COMPANY (Baan), WD_TENANT_ID (Workday), SAP_COMPANY_CODE, SAP_DOCUMENT_TYPE (SAP), ORACLE_ORG_ID, ORACLE_SOURCE (Oracle).

  ────────────────────────────────────────

  3. Open Questions and Assumptions

  Row 1
  #: 1
  Question: Payment terms normalization — Should Silver standardize N30/NET30/Net 30 into one format?
  Owner: Sarah Chen / David Kim (due 2025-06-20)
  Current Assumption: Pass through raw values; normalize in Gold.
  Risk if Wrong: Downstream reports show inconsistent groupings until Gold is built.
  ────────────────────────────────────────────────────────────
  Row 2
  #: 2
  Question: Column rename: INVOICE_STATUS → APPROVAL_STATUS — The current DT uses INVOICE_STATUS. The mapping CSV uses APPROVAL_STATUS. Which is canonical?
  Owner: Needs confirmation
  Current Assumption: Plan uses APPROVAL_STATUS (matches mapping CSV).
  Risk if Wrong: Breaking change for any query referencing INVOICE_STATUS.
  ────────────────────────────────────────────────────────────
  Row 3
  #: 3
  Question: Baan cost center dual format (BC-XX vs BC-XXX) — Pass through both or pad old format?
  Owner: Karen van der Berg
  Current Assumption: Pass through as-is (both formats coexist).
  Risk if Wrong: Aggregation by cost center may split what should be one group.
  ────────────────────────────────────────────────────────────
  Row 4
  #: 4
  Question: Baan dedup: scope — BR-003 applies QUALIFY dedup to Baan only. Should SAP/Oracle/Workday get the same safety net?
  Owner: Engineering
  Current Assumption: Baan-only (as specified).
  Risk if Wrong: If another source develops dupes, they pass through silently.
  ────────────────────────────────────────────────────────────
  Row 5
  #: 5
  Question: Workday legal blocker — DPA-2025-0041 is pending. Should the DDL include the Workday branch now (producing NULLs/empty until data flows), or add it post-signoff?
  Owner: Jennifer Okafor / Legal
  Current Assumption: Include the branch now; it will simply return 0 rows until data lands.
  Risk if Wrong: If legal objects to the schema existing before signoff, remove and re-add later.
  ────────────────────────────────────────────────────────────
  Row 6
  #: 6
  Question: SOURCE_ENTITY_CODE / SOURCE_METADATA removal — These exist in the current DT. Any downstream consumer using them?
  Owner: David Kim (confirmed drop in BR-008)
  Current Assumption: Safe to drop.
  Risk if Wrong: If a dashboard or Gold DT references them, it breaks on next refresh.

  ────────────────────────────────────────

  4. DDL Delta Plan

  Type: CREATE OR REPLACE (full replacement — adds 2 branches, removes 2 columns, adds CASE logic, adds QUALIFY).

    CREATE OR REPLACE DYNAMIC TABLE COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
      TARGET_LAG = DOWNSTREAM
      WAREHOUSE = COCO_WORKSHOP_WH
    AS

    -- SAP branch
    SELECT
        'SAP'                   AS SOURCE_SYSTEM,
        INVOICE_ID              AS SOURCE_INVOICE_ID,
        INVOICE_NUMBER,
        VENDOR_ID,
        VENDOR_NAME,
        INVOICE_DATE,
        DUE_DATE,
        INVOICE_AMOUNT,
        CURRENCY_CODE,
        PAYMENT_TERMS,
        PO_NUMBER,
        LINE_DESCRIPTION,
        GL_ACCOUNT,
        COST_CENTER,
        CASE APPROVAL_STATUS
            WHEN 'APPROVED' THEN 'APPROVED'
            WHEN 'PENDING'  THEN 'PENDING'
            ELSE APPROVAL_STATUS
        END                     AS APPROVAL_STATUS,
        CREATED_AT
    FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_SAP_AP_INVOICES

    UNION ALL

    -- Oracle branch
    SELECT
        'ORACLE'                AS SOURCE_SYSTEM,
        INV_ID                  AS SOURCE_INVOICE_ID,
        INV_NUM                 AS INVOICE_NUMBER,
        SUPPLIER_ID             AS VENDOR_ID,
        SUPPLIER_NAME           AS VENDOR_NAME,
        INV_DATE                AS INVOICE_DATE,
        PAYMENT_DUE_DATE        AS DUE_DATE,
        TOTAL_AMOUNT            AS INVOICE_AMOUNT,
        CURRENCY                AS CURRENCY_CODE,
        TERMS_CODE              AS PAYMENT_TERMS,
        PURCHASE_ORDER          AS PO_NUMBER,
        DESCRIPTION             AS LINE_DESCRIPTION,
        ACCOUNT_CODE            AS GL_ACCOUNT,
        DEPT_CODE               AS COST_CENTER,
        CASE STATUS
            WHEN 'VALIDATED' THEN 'APPROVED'
            WHEN 'APPROVED'  THEN 'APPROVED'
            WHEN 'PENDING'   THEN 'PENDING'
            ELSE STATUS
        END                     AS APPROVAL_STATUS,
        CREATION_DATE           AS CREATED_AT
    FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_ORACLE_AP_INVOICES

    UNION ALL

    -- Baan branch (with dedup per BR-003)
    SELECT
        'BAAN'                  AS SOURCE_SYSTEM,
        BAN_INVOICE_ID          AS SOURCE_INVOICE_ID,
        BAN_INVOICE_REF         AS INVOICE_NUMBER,
        BAN_VENDOR_CODE         AS VENDOR_ID,
        BAN_VENDOR_DESC         AS VENDOR_NAME,
        BAN_INV_DATE            AS INVOICE_DATE,
        BAN_PAY_DATE            AS DUE_DATE,
        BAN_AMOUNT              AS INVOICE_AMOUNT,
        BAN_CURR                AS CURRENCY_CODE,
        BAN_PAY_TERMS           AS PAYMENT_TERMS,
        BAN_PO_REF              AS PO_NUMBER,
        BAN_LINE_DESC           AS LINE_DESCRIPTION,
        BAN_GL_CODE             AS GL_ACCOUNT,
        BAN_COST_CTR            AS COST_CENTER,
        CASE BAN_STATUS
            WHEN 'POSTED'   THEN 'APPROVED'
            WHEN 'APPROVED' THEN 'APPROVED'
            WHEN 'PENDING'  THEN 'PENDING'
            ELSE BAN_STATUS
        END                     AS APPROVAL_STATUS,
        BAN_CREATED             AS CREATED_AT
    FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_BAAN_AP_INVOICES
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY BAN_INVOICE_REF
        ORDER BY BAN_CREATED DESC
    ) = 1

    UNION ALL

    -- Workday branch
    SELECT
        'WORKDAY'               AS SOURCE_SYSTEM,
        WD_INVOICE_ID           AS SOURCE_INVOICE_ID,
        WD_INVOICE_NUM          AS INVOICE_NUMBER,
        WD_SUPPLIER_ID          AS VENDOR_ID,
        WD_SUPPLIER_NAME        AS VENDOR_NAME,
        WD_INVOICE_DATE         AS INVOICE_DATE,
        WD_DUE_DATE             AS DUE_DATE,
        WD_AMOUNT               AS INVOICE_AMOUNT,
        WD_CURRENCY             AS CURRENCY_CODE,
        WD_PAY_TERMS            AS PAYMENT_TERMS,
        WD_PO_NUMBER            AS PO_NUMBER,
        WD_MEMO                 AS LINE_DESCRIPTION,
        WD_LEDGER_ACCOUNT       AS GL_ACCOUNT,
        WD_COST_CENTER          AS COST_CENTER,
        CASE WD_APPROVAL_STATUS
            WHEN 'Approved'  THEN 'APPROVED'
            WHEN 'In Review' THEN 'PENDING'
            ELSE WD_APPROVAL_STATUS
        END                     AS APPROVAL_STATUS,
        WD_CREATED_DATE         AS CREATED_AT
    FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_WORKDAY_AP_INVOICES

  Key changes from current DT:

  ┌───────────────────────────────────────────┬──────────────────────────┐
  │ Change                                    │ Type                     │
  ├───────────────────────────────────────────┼──────────────────────────┤
  │ SOURCE_ENTITY_CODE removed                │ Breaking — column drop   │
  ├───────────────────────────────────────────┼──────────────────────────┤
  │ SOURCE_METADATA removed                   │ Breaking — column drop   │
  ├───────────────────────────────────────────┼──────────────────────────┤
  │ INVOICE_STATUS renamed to APPROVAL_STATUS │ Breaking — column rename │
  ├───────────────────────────────────────────┼──────────────────────────┤
  │ Status values now normalized via CASE     │ Semantic change          │
  ├───────────────────────────────────────────┼──────────────────────────┤
  │ Baan UNION ALL branch added               │ Additive                 │
  ├───────────────────────────────────────────┼──────────────────────────┤
  │ Workday UNION ALL branch added            │ Additive                 │
  ├───────────────────────────────────────────┼──────────────────────────┤
  │ TARGET_LAG → DOWNSTREAM                   │ Behavioral change        │
  ├───────────────────────────────────────────┼──────────────────────────┤
  │ Baan branch has QUALIFY dedup             │ New logic                │
  └───────────────────────────────────────────┴──────────────────────────┘

  ────────────────────────────────────────

  5. Validation Queries (Post-Implementation)

    -- Row counts by source (expect: SAP=15, Oracle=15, Baan≤10, Workday=10)
    SELECT SOURCE_SYSTEM, COUNT(*) AS ROW_COUNT
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    GROUP BY SOURCE_SYSTEM
    ORDER BY SOURCE_SYSTEM;

    -- Confirm status normalization: only APPROVED or PENDING should appear
    SELECT APPROVAL_STATUS, COUNT(*) AS CNT
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    GROUP BY APPROVAL_STATUS
    ORDER BY APPROVAL_STATUS;

    -- Confirm Baan dedup worked: no duplicate INVOICE_NUMBERs in Baan
    SELECT INVOICE_NUMBER, COUNT(*) AS DUPES
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    WHERE SOURCE_SYSTEM = 'BAAN'
    GROUP BY INVOICE_NUMBER
    HAVING COUNT(*) > 1;

    -- NULL check on required fields
    SELECT SOURCE_SYSTEM,
           COUNT_IF(SOURCE_INVOICE_ID IS NULL) AS NULL_ID,
           COUNT_IF(INVOICE_NUMBER IS NULL)    AS NULL_INV_NUM,
           COUNT_IF(VENDOR_ID IS NULL)         AS NULL_VENDOR,
           COUNT_IF(INVOICE_AMOUNT IS NULL)    AS NULL_AMOUNT,
           COUNT_IF(APPROVAL_STATUS IS NULL)   AS NULL_STATUS
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    GROUP BY SOURCE_SYSTEM;

    -- Date range sanity check
    SELECT SOURCE_SYSTEM,
           MIN(INVOICE_DATE) AS EARLIEST,
           MAX(INVOICE_DATE) AS LATEST
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    GROUP BY SOURCE_SYSTEM
    ORDER BY SOURCE_SYSTEM;

    -- Confirm dropped columns don't exist
    DESCRIBE TABLE COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES;
    -- Should NOT show SOURCE_ENTITY_CODE or SOURCE_METADATA

  ────────────────────────────────────────

  Next step: Resolve open questions (especially #2 — column name INVOICE_STATUS vs APPROVAL_STATUS) and confirm you're comfortable with the breaking changes before I execute the DDL.