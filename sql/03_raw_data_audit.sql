/* =============================================================================
   03_raw_data_audit.sql
   Purpose : Audit the raw tables BEFORE any cleaning. Every result here is a
             finding that drives a cleaning decision in scripts 04-06.
   Nothing in this script changes the raw tables (only etl_log is written to).
   ============================================================================= */
USE faers_pv;

-- 3.1 Row counts per table and quarter. Compare with the line counts of the source
--     files (header excluded): e.g. DEMO25Q1.txt has 400,515 lines = 400,514 rows.
--     If a table shows 0 rows the line terminator in script 02 was wrong for that file.
SELECT 'raw_demo' AS tbl, src_quarter, COUNT(*) AS row_count FROM raw_demo GROUP BY src_quarter
UNION ALL SELECT 'raw_drug', src_quarter, COUNT(*) FROM raw_drug GROUP BY src_quarter
UNION ALL SELECT 'raw_reac', src_quarter, COUNT(*) FROM raw_reac GROUP BY src_quarter
UNION ALL SELECT 'raw_outc', src_quarter, COUNT(*) FROM raw_outc GROUP BY src_quarter
UNION ALL SELECT 'raw_indi', src_quarter, COUNT(*) FROM raw_indi GROUP BY src_quarter
UNION ALL SELECT 'raw_deleted', src_quarter, COUNT(*) FROM raw_deleted GROUP BY src_quarter
ORDER BY tbl, src_quarter;

INSERT INTO etl_log (step_no, step_name, metric, row_count)
SELECT '03', 'Raw audit', CONCAT(tbl, ' rows loaded'), n FROM (
    SELECT 'raw_demo' tbl, COUNT(*) n FROM raw_demo UNION ALL SELECT 'raw_drug', COUNT(*) FROM raw_drug
    UNION ALL SELECT 'raw_reac', COUNT(*) FROM raw_reac UNION ALL SELECT 'raw_outc', COUNT(*) FROM raw_outc
    UNION ALL SELECT 'raw_indi', COUNT(*) FROM raw_indi UNION ALL SELECT 'raw_deleted', COUNT(*) FROM raw_deleted) t;

-- 3.2 Identifiers. primaryid = one report version; caseid = one case across its versions.
--     Expect primaryid to be unique within a quarter but cases to repeat (follow-ups).
SELECT src_quarter, COUNT(*) AS report_rows, COUNT(DISTINCT primaryid) AS distinct_primaryid,
       COUNT(DISTINCT caseid) AS distinct_caseid
FROM raw_demo GROUP BY src_quarter;

SELECT COUNT(*) AS report_rows, COUNT(DISTINCT primaryid) AS distinct_primaryid,
       COUNT(DISTINCT caseid) AS distinct_cases_all_quarters,
       COUNT(*) - COUNT(DISTINCT primaryid) AS primaryid_repeated_across_quarters,
       COUNT(*) - COUNT(DISTINCT caseid)    AS rows_that_are_extra_versions_of_a_case
FROM raw_demo;

-- 3.3 How many cases have more than one version, and how many cases sit in more than one quarter?
SELECT versions_in_data, COUNT(*) AS cases FROM (
    SELECT caseid, COUNT(*) AS versions_in_data FROM raw_demo GROUP BY caseid) v
GROUP BY versions_in_data ORDER BY versions_in_data;

-- 3.4 Completeness of the fields used as subgroups
SELECT 'sex' AS field, COALESCE(NULLIF(sex, ''), '(blank)') AS value, COUNT(*) AS n,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM raw_demo), 2) AS pct FROM raw_demo GROUP BY 2
UNION ALL
SELECT 'age_cod', COALESCE(NULLIF(age_cod, ''), '(blank)'), COUNT(*), ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM raw_demo), 2)
FROM raw_demo GROUP BY 2
UNION ALL
SELECT 'occp_cod (reporter type)', COALESCE(NULLIF(occp_cod, ''), '(blank)'), COUNT(*), ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM raw_demo), 2)
FROM raw_demo GROUP BY 2
ORDER BY field, n DESC;

-- 3.5 Age: units differ (YR, MON, DEC, WK, DY, HR) so the raw number is not comparable.
--     Check for impossible values after converting to years.
SELECT age_cod, COUNT(*) AS n,
       MIN(CAST(age AS DECIMAL(12,2))) AS min_value, MAX(CAST(age AS DECIMAL(12,2))) AS max_value,
       SUM(CASE age_cod WHEN 'YR' THEN CAST(age AS DECIMAL(12,2)) > 120
                        WHEN 'DEC' THEN CAST(age AS DECIMAL(12,2)) > 12
                        ELSE 0 END) AS implausible_over_120_years
FROM raw_demo WHERE age <> '' AND age REGEXP '^[0-9.]+$'
GROUP BY age_cod ORDER BY n DESC;

SELECT COUNT(*) AS age_not_numeric FROM raw_demo WHERE age <> '' AND age NOT REGEXP '^[0-9.]+$';

-- 3.6 Date formats (FAERS dates are YYYYMMDD but may be truncated to YYYYMM or YYYY)
SELECT CHAR_LENGTH(event_dt) AS event_dt_length, COUNT(*) AS n FROM raw_demo GROUP BY 1 ORDER BY 1;
SELECT CHAR_LENGTH(fda_dt) AS fda_dt_length, COUNT(*) AS n FROM raw_demo GROUP BY 1 ORDER BY 1;

-- 3.7 Referential integrity: child rows without a parent report, and reports without drugs/reactions
SELECT 'drug rows without a DEMO parent' AS check_name, COUNT(*) AS n
FROM raw_drug d LEFT JOIN raw_demo m ON m.primaryid = d.primaryid WHERE m.primaryid IS NULL
UNION ALL SELECT 'reaction rows without a DEMO parent', COUNT(*)
FROM raw_reac r LEFT JOIN raw_demo m ON m.primaryid = r.primaryid WHERE m.primaryid IS NULL
UNION ALL SELECT 'reports with no drug row', COUNT(*)
FROM raw_demo m WHERE NOT EXISTS (SELECT 1 FROM raw_drug d WHERE d.primaryid = m.primaryid)
UNION ALL SELECT 'reports with no reaction row', COUNT(*)
FROM raw_demo m WHERE NOT EXISTS (SELECT 1 FROM raw_reac r WHERE r.primaryid = m.primaryid);

-- 3.8 Drug records: role codes and name quality
SELECT role_cod, COUNT(*) AS drug_rows,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM raw_drug), 2) AS pct
FROM raw_drug GROUP BY role_cod ORDER BY drug_rows DESC;     -- PS primary suspect, SS secondary suspect, C concomitant, I interacting

SELECT SUM(prod_ai = '') AS drugs_without_active_ingredient,
       ROUND(100 * SUM(prod_ai = '') / COUNT(*), 2) AS pct_without_active_ingredient,
       COUNT(DISTINCT UPPER(TRIM(drugname))) AS distinct_drugname_spellings,
       COUNT(DISTINCT UPPER(TRIM(prod_ai)))  AS distinct_prod_ai_values
FROM raw_drug;

-- 3.9 Tirzepatide: how many different spellings exist? (this is why names must be standardised)
SELECT UPPER(TRIM(drugname)) AS drugname_as_reported, COUNT(*) AS drug_rows, SUM(role_cod = 'PS') AS as_primary_suspect
FROM raw_drug
WHERE UPPER(drugname) REGEXP 'MOUNJ|ZEPBOUND|TIRZEPAT' OR UPPER(prod_ai) LIKE '%TIRZEPATIDE%'
GROUP BY 1 ORDER BY drug_rows DESC LIMIT 15;

-- 3.10 Reaction terms (MedDRA preferred terms): blanks and spelling variants of the same term
SELECT SUM(TRIM(pt) = '') AS blank_pt,
       COUNT(DISTINCT pt) AS distinct_pt_exact,
       COUNT(DISTINCT UPPER(TRIM(pt))) AS distinct_pt_case_insensitive
FROM raw_reac;

-- 3.11 Duplicate (case, term) pairs: one PT repeated within a report counts once in analysis
SELECT COUNT(*) AS reaction_rows, COUNT(DISTINCT primaryid, UPPER(TRIM(pt))) AS distinct_report_pt_pairs FROM raw_reac;

-- 3.12 Cases FDA later deleted (must be removed even if they appear in a data file)
SELECT COUNT(DISTINCT caseid) AS deleted_caseids_listed,
       (SELECT COUNT(DISTINCT m.caseid) FROM raw_demo m JOIN raw_deleted x ON x.caseid = m.caseid) AS of_which_present_in_demo
FROM raw_deleted WHERE caseid <> '';

-- 3.13 Duplicate (primaryid, drug_seq) pairs: the pair is NOT a safe primary key for raw_drug
SELECT COUNT(*) AS duplicated_pairs, SUM(n) AS rows_involved
FROM (SELECT primaryid, drug_seq, COUNT(*) AS n FROM raw_drug GROUP BY primaryid, drug_seq HAVING COUNT(*) > 1) x;
