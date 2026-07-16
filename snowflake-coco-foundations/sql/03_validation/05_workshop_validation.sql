--!jinja
use role accountadmin;

create or replace api integration dora_api_integration 
api_provider = aws_api_gateway 
api_aws_role_arn = 'arn:aws:iam::321463406630:role/snowflakeLearnerAssumedRole' 
enabled = true 
api_allowed_prefixes = ('https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora');

create database if not exists util_db;
use database util_db;
use schema public;

create or replace external function util_db.public.grader(        
 step varchar     
 , passed boolean     
 , actual integer     
 , expected integer    
 , description varchar) 
 returns variant 
 api_integration = dora_api_integration 
 context_headers = (current_timestamp,current_account, current_statement, current_account_name) 
 as 'https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora/grader'  
;  

select grader(step, (actual = expected), actual, expected, description) as graded_results from (SELECT
 'AUTO_GRADER_IS_WORKING' as step
 ,(select 123) as actual
 ,123 as expected
 ,'The Snowflake auto-grader has been successfully set up in your account!' as description
);

create or replace external function util_db.public.greeting(
      email varchar
    , firstname varchar
    , middlename varchar
    , lastname varchar)
returns variant
api_integration = dora_api_integration
context_headers = (current_timestamp, current_account, current_statement, current_account_name) 
as 'https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora/greeting'
; 


-- Be sure to follow the rules your session leader presents
-- If you do not have a middle name, use an empty string '' ; do not use "null" in place of any values
-- Double-check your email. You must use the same email for the greeting as you used to register
select util_db.public.greeting('monawarabdul@gmail.com', 'Monawar', '', 'Abdulrazaq');

-- ============================================
-- Answer Key: CoCo Foundations: Getting Started with CoCo
-- ============================================

USE ROLE accountadmin;
USE WAREHOUSE compute_wh;
USE DATABASE coco_workshop;

select util_db.public.grader(step, (actual = expected), actual, expected,
description) as graded_results from (SELECT
 'BWCC01' as step
 ,(SELECT COUNT(*) FROM INFORMATION_SCHEMA.DATABASES WHERE DATABASE_NAME = 'COCO_WORKSHOP') as actual
 , 1 as expected
 ,'COCO_WORKSHOP database successfully created!' as description
);

select util_db.public.grader(step, (actual = expected), actual, expected,
description) as graded_results from (SELECT
  'BWCC02' as step
  ,(SELECT COUNT(*) FROM coco_workshop.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME IN ('PIPELINE_LAB', 'SOURCE_DATA')) as actual
  , 2 as expected
  ,'PIPELINE_LAB and SOURCE_DATA schemas successfully created!' as description
);

select util_db.public.grader(step, (actual = expected), actual, expected,
description) as graded_results from (SELECT
  'BWCC03' as step
  ,(SELECT COUNT(*) FROM coco_workshop.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'SOURCE_DATA' AND TABLE_TYPE = 'BASE TABLE') as actual
  , 5 as expected
  ,'All 5 source data tables successfully created!' as description
);

select util_db.public.grader(step, (actual = expected), actual, expected,
description) as graded_results from (SELECT
  'BWCC04' as step
  ,(SELECT COUNT(*) FROM coco_workshop.INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'SILVER_AP_INVOICES' AND TABLE_SCHEMA = 'PIPELINE_LAB') as actual
  , 1 as expected
  ,'SILVER_AP_INVOICES dynamic table successfully created!' as description
);

select util_db.public.grader(step, (actual = expected), actual, expected,
description) as graded_results from (SELECT
  'BWCC05' as step
  ,(SELECT COUNT(*) FROM coco_workshop.pipeline_lab.silver_ap_invoices) as actual
  , 50 as expected
  ,'SILVER_AP_INVOICES contains all 50 rows from all source systems!' as description
);

WITH check_results AS (
  SELECT 'BWCC01' AS step, 'Database (COCO_WORKSHOP)' AS description,
    IFF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.DATABASES WHERE DATABASE_NAME = 'COCO_WORKSHOP') = 1, TRUE, FALSE) AS passed
  UNION ALL
  SELECT 'BWCC02', 'Schemas (PIPELINE_LAB, SOURCE_DATA)',
    IFF((SELECT COUNT(*) FROM coco_workshop.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME IN ('PIPELINE_LAB', 'SOURCE_DATA')) = 2, TRUE, FALSE)
  UNION ALL
  SELECT 'BWCC03', 'Source Data Tables (expected 5)',
    IFF((SELECT COUNT(*) FROM coco_workshop.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'SOURCE_DATA' AND TABLE_TYPE = 'BASE TABLE') = 5, TRUE, FALSE)
  UNION ALL
  SELECT 'BWCC04', 'Dynamic Table (SILVER_AP_INVOICES)',
    IFF((SELECT COUNT(*) FROM coco_workshop.INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'SILVER_AP_INVOICES' AND TABLE_SCHEMA = 'PIPELINE_LAB') = 1, TRUE, FALSE)
  UNION ALL
  SELECT 'BWCC05', 'SILVER_AP_INVOICES Row Count (expected 50)',
    IFF(
      CASE
        WHEN (SELECT COUNT(*) FROM coco_workshop.INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'SILVER_AP_INVOICES' AND TABLE_SCHEMA = 'PIPELINE_LAB') = 1
        THEN (SELECT COUNT(*) FROM coco_workshop.pipeline_lab.silver_ap_invoices)
        ELSE 0
      END = 50, TRUE, FALSE)
)
SELECT
  CASE
    WHEN SUM(IFF(passed, 0, 1)) = 0
    THEN 'Congratulations! You have successfully completed the Cortex Code Foundations workshop!'
    ELSE 'Not all steps passed. Failed: ' ||
         LISTAGG(CASE WHEN NOT passed THEN step || ' - ' || description END, ' | ')
           WITHIN GROUP (ORDER BY step)
  END AS STATUS
FROM check_results;