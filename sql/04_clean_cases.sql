/* =============================================================================
   04_clean_cases.sql
   Purpose : Turn 1.6 million raw report rows into ONE clean row per case.
   Why     : FAERS stores every follow-up version of a case as a new report. Counting
             report rows instead of cases would count the same patient several times,
             inflating both the drug and the comparator counts. The unit of analysis
             in this project is the CASE (caseid).
   Steps   : 4.1 remove cases FDA deleted  ->  4.2 keep the latest version of each case
             ->  4.3 standardise age, sex, reporter type, region  ->  4.4 log the result.
   ============================================================================= */
USE faers_pv;

-- 4.1 Cases withdrawn by FDA/manufacturers (DELETE files) are removed completely.
--     The first line of each DELETE file is blank; blanks are ignored.
DROP TABLE IF EXISTS stg_deleted_cases;
CREATE TABLE stg_deleted_cases (caseid VARCHAR(20) PRIMARY KEY) ENGINE = InnoDB
    AS SELECT DISTINCT caseid FROM raw_deleted WHERE TRIM(caseid) <> '';

-- 4.2 Keep only the LATEST version of each case. FDA's recommended rule: sort by
--     FDA receipt date, then case version, then primaryid, and keep the last one.
DROP TABLE IF EXISTS stg_case_latest;
CREATE TABLE stg_case_latest (
    caseid VARCHAR(20) PRIMARY KEY, primaryid VARCHAR(20) NOT NULL, src_quarter CHAR(6) NOT NULL,
    caseversion INT, fda_date DATE, event_dt VARCHAR(10), age_raw VARCHAR(20), age_cod VARCHAR(10),
    sex_raw VARCHAR(5), occp_cod VARCHAR(10), occr_country VARCHAR(60), reporter_country VARCHAR(60),
    mfr_num VARCHAR(100), INDEX ix_pid (primaryid)
) ENGINE = InnoDB;

INSERT INTO stg_case_latest
SELECT caseid, primaryid, src_quarter, caseversion, fda_date, event_dt, age, age_cod, sex, occp_cod,
       occr_country, reporter_country, mfr_num
FROM (
    SELECT d.caseid, d.primaryid, d.src_quarter, CAST(NULLIF(d.caseversion, '') AS UNSIGNED) AS caseversion,
           STR_TO_DATE(d.fda_dt, '%Y%m%d') AS fda_date, d.event_dt, d.age, d.age_cod, d.sex, d.occp_cod,
           d.occr_country, d.reporter_country, d.mfr_num,
           ROW_NUMBER() OVER (PARTITION BY d.caseid
                              ORDER BY STR_TO_DATE(d.fda_dt, '%Y%m%d') DESC,
                                       CAST(NULLIF(d.caseversion, '') AS UNSIGNED) DESC,
                                       d.primaryid DESC) AS rn
    FROM raw_demo d
    LEFT JOIN stg_deleted_cases x ON x.caseid = d.caseid
    WHERE x.caseid IS NULL
) ranked
WHERE rn = 1;

-- 4.3 Standardised case table: one row per case, subgroup variables derived.
DROP TABLE IF EXISTS clean_case;
CREATE TABLE clean_case (
    caseid         VARCHAR(20) PRIMARY KEY,
    primaryid      VARCHAR(20) NOT NULL,        -- the report version whose drugs/reactions are used
    src_quarter    CHAR(6)     NOT NULL,        -- quarter in which that version was received
    age_years      DECIMAL(7,2) NULL,
    age_group      VARCHAR(10) NOT NULL,        -- '<18','18-44','45-64','65+','Unknown'
    sex            VARCHAR(8)  NOT NULL,        -- 'F','M','Unknown'
    reporter_type  VARCHAR(24) NOT NULL,        -- 'Healthcare professional','Consumer','Other','Unknown'
    region         VARCHAR(10) NOT NULL,        -- 'US','Non-US','Unknown'
    event_year     SMALLINT NULL,
    mfr_num        VARCHAR(100) NULL,
    INDEX ix_pid (primaryid), INDEX ix_q (src_quarter)
) ENGINE = InnoDB;

INSERT INTO clean_case
SELECT caseid, primaryid, src_quarter, age_years,
       CASE WHEN age_years IS NULL THEN 'Unknown'
            WHEN age_years < 18 THEN '<18' WHEN age_years < 45 THEN '18-44'
            WHEN age_years < 65 THEN '45-64' ELSE '65+' END AS age_group,
       CASE sex_raw WHEN 'F' THEN 'F' WHEN 'M' THEN 'M' ELSE 'Unknown' END AS sex,
       CASE occp_cod WHEN 'CN' THEN 'Consumer'
                     WHEN 'MD' THEN 'Healthcare professional' WHEN 'PH' THEN 'Healthcare professional'
                     WHEN 'HP' THEN 'Healthcare professional' WHEN 'OT' THEN 'Healthcare professional'
                     WHEN 'LW' THEN 'Other' ELSE 'Unknown' END AS reporter_type,
       CASE WHEN country = '' THEN 'Unknown' WHEN country = 'US' THEN 'US' ELSE 'Non-US' END AS region,
       CASE WHEN event_dt REGEXP '^(19|20)[0-9]{2}' THEN CAST(LEFT(event_dt, 4) AS UNSIGNED) END AS event_year,
       NULLIF(mfr_num, '')
FROM (
    -- middle layer: keep an age only if it is a plausible human age (0-120 years)
    SELECT m.*, CASE WHEN m.age_years_raw BETWEEN 0 AND 120 THEN ROUND(m.age_years_raw, 2) END AS age_years
    FROM (
        -- inner layer: convert the reported age to years using its unit code (YR, DEC, MON, WK, DY, HR).
        SELECT l.*,
               COALESCE(NULLIF(TRIM(l.occr_country), ''), NULLIF(TRIM(l.reporter_country), ''), '') AS country,
               CASE WHEN l.age_raw = '' OR l.age_raw NOT REGEXP '^[0-9.]+$' THEN NULL
                    ELSE CASE l.age_cod
                            WHEN 'YR'  THEN CAST(l.age_raw AS DECIMAL(14,2))
                            WHEN 'DEC' THEN CAST(l.age_raw AS DECIMAL(14,2)) * 10
                            WHEN 'MON' THEN CAST(l.age_raw AS DECIMAL(14,2)) / 12
                            WHEN 'WK'  THEN CAST(l.age_raw AS DECIMAL(14,2)) / 52.18
                            WHEN 'DY'  THEN CAST(l.age_raw AS DECIMAL(14,2)) / 365.25
                            WHEN 'HR'  THEN CAST(l.age_raw AS DECIMAL(14,2)) / 8766
                         END
               END AS age_years_raw
        FROM stg_case_latest l
    ) m
) t;

-- 4.4 Cleaning log: what was removed and why
INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '04', 'Case de-duplication', 'Report rows loaded (all versions, 4 quarters)', COUNT(*), 'raw_demo' FROM raw_demo
UNION ALL SELECT '04', 'Case de-duplication', 'Distinct case IDs in raw data', COUNT(DISTINCT caseid), 'one case can have several versions'
FROM raw_demo
UNION ALL SELECT '04', 'Case de-duplication', 'Case IDs on FDA DELETE lists', COUNT(*), 'stg_deleted_cases' FROM stg_deleted_cases
UNION ALL SELECT '04', 'Case de-duplication', 'Cases removed because FDA deleted them', COUNT(DISTINCT d.caseid), 'present in demo and on DELETE lists'
FROM raw_demo d JOIN stg_deleted_cases x ON x.caseid = d.caseid
UNION ALL SELECT '04', 'Case de-duplication', 'Older versions discarded (kept latest per case)',
       (SELECT COUNT(*) FROM raw_demo d LEFT JOIN stg_deleted_cases x ON x.caseid = d.caseid WHERE x.caseid IS NULL) - COUNT(*),
       'follow-up versions replaced by the latest' FROM clean_case
UNION ALL SELECT '04', 'Case de-duplication', 'Clean cases (one row per case)', COUNT(*), 'clean_case' FROM clean_case
UNION ALL SELECT '04', 'Standardisation', 'Cases with age missing or implausible (set to Unknown)', SUM(age_group = 'Unknown'), 'age_years NULL' FROM clean_case
UNION ALL SELECT '04', 'Standardisation', 'Cases with sex missing/unknown', SUM(sex = 'Unknown'), 'blank or UNK' FROM clean_case
UNION ALL SELECT '04', 'Standardisation', 'Cases with reporter type unknown', SUM(reporter_type = 'Unknown'), 'blank occp_cod' FROM clean_case
UNION ALL SELECT '04', 'Standardisation', 'Cases with region unknown', SUM(region = 'Unknown'), 'no country' FROM clean_case;

-- 4.5 Check: exactly one row per case and nothing deleted survives
SELECT COUNT(*) AS clean_cases, COUNT(DISTINCT caseid) AS distinct_cases,
       (SELECT COUNT(*) FROM clean_case c JOIN stg_deleted_cases x ON x.caseid = c.caseid) AS deleted_cases_remaining
FROM clean_case;
SELECT age_group, COUNT(*) AS cases FROM clean_case GROUP BY age_group ORDER BY FIELD(age_group, '<18', '18-44', '45-64', '65+', 'Unknown');
SELECT src_quarter, COUNT(*) AS cases FROM clean_case GROUP BY src_quarter ORDER BY src_quarter;
