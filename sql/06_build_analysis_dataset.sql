/* =============================================================================
   06_build_analysis_dataset.sql
   Purpose : Assemble the final analysis dataset from the cleaned pieces:
             events per case, outcomes, indication group, probable cross-source
             duplicates, and the case lists for each analysis.
   Analyses (defined once, used by every later script)
     A1  PRIMARY      target = tirzepatide as PRIMARY SUSPECT (PS)
                      comparator = all cases with NO tirzepatide in any role
     A2  SENSITIVITY  target = tirzepatide as primary OR secondary suspect (PS/SS)
                      comparator = as A1
     A3  ACTIVE COMP. target = tirzepatide PS (no other GLP-1 RA as suspect)
                      comparator = other GLP-1 RA as primary suspect (semaglutide etc.)
                      -> separates "tirzepatide-specific" from "GLP-1 class" effects
   Cases where tirzepatide appears only as a concomitant/interacting drug belong to
   neither group in A1/A2 (they are neither clearly exposed nor clearly unexposed).
   ============================================================================= */
USE faers_pv;
SET SESSION group_concat_max_len = 1000000;

-- 6.1 Events per case: one row per (case, MedDRA preferred term). A term repeated inside
--     a report counts once, because the unit of analysis is "cases with the event".
DROP TABLE IF EXISTS case_event;
CREATE TABLE case_event (
    caseid VARCHAR(20) NOT NULL, pt VARCHAR(255) NOT NULL,
    PRIMARY KEY (caseid, pt), INDEX ix_pt (pt)
) ENGINE = InnoDB;
INSERT INTO case_event
SELECT DISTINCT c.caseid, TRIM(r.pt)
FROM clean_case c JOIN raw_reac r ON r.primaryid = c.primaryid
WHERE TRIM(r.pt) <> '';

-- 6.2 Seriousness outcomes per case (OUTC codes): DE death, LT life-threatening, HO hospitalisation,
--     DS disability, CA congenital anomaly, RI intervention required, OT other serious.
DROP TABLE IF EXISTS case_outcome;
CREATE TABLE case_outcome (
    caseid VARCHAR(20) PRIMARY KEY, death TINYINT, life_threatening TINYINT, hospitalisation TINYINT,
    disability TINYINT, other_serious TINYINT
) ENGINE = InnoDB;
INSERT INTO case_outcome
SELECT c.caseid, MAX(o.outc_cod = 'DE'), MAX(o.outc_cod = 'LT'), MAX(o.outc_cod = 'HO'),
       MAX(o.outc_cod IN ('DS', 'CA', 'RI')), MAX(o.outc_cod = 'OT')
FROM clean_case c JOIN raw_outc o ON o.primaryid = c.primaryid GROUP BY c.caseid;

-- 6.3 Indication group per case (from the INDI file, any drug in the report). Used as a
--     subgroup because tirzepatide is marketed for type 2 diabetes (Mounjaro) and weight
--     management (Zepbound); safety patterns may differ between those populations.
DROP TABLE IF EXISTS case_indication;
CREATE TABLE case_indication (caseid VARCHAR(20) PRIMARY KEY, indication_group VARCHAR(20) NOT NULL) ENGINE = InnoDB;
INSERT INTO case_indication
SELECT caseid,
       CASE WHEN has_dm = 1 AND has_ob = 1 THEN 'Both'
            WHEN has_dm = 1 THEN 'Diabetes'
            WHEN has_ob = 1 THEN 'Obesity/weight' ELSE 'Other/unknown' END
FROM (
    SELECT c.caseid,
           MAX(UPPER(i.indi_pt) REGEXP 'DIABET|GLYCAEMIC CONTROL|BLOOD GLUCOSE|HYPERGLYC') AS has_dm,
           MAX(UPPER(i.indi_pt) REGEXP 'OBES|OVERWEIGHT|WEIGHT (CONTROL|LOSS|MANAGEMENT|REDUCTION|DECREASE)|BODY MASS INDEX|BARIATRIC') AS has_ob
    FROM clean_case c JOIN raw_indi i ON i.primaryid = c.primaryid GROUP BY c.caseid
) x;
INSERT INTO case_indication SELECT c.caseid, 'Other/unknown' FROM clean_case c LEFT JOIN case_indication i ON i.caseid = c.caseid WHERE i.caseid IS NULL;

-- 6.4 Probable cross-source duplicates. The same patient event can reach FDA through the
--     manufacturer, a doctor AND the patient under DIFFERENT case IDs; script 04 cannot see
--     that. Conservative rule: two cases are probable duplicates only if ALL of these match:
--     full event date, age, sex, event country, the exact set of reaction terms, and the
--     exact set of primary-suspect drug names. Only the lowest case ID in each group is kept.
DROP TABLE IF EXISTS stg_case_signature;
CREATE TABLE stg_case_signature (caseid VARCHAR(20) PRIMARY KEY, sig CHAR(32) NOT NULL, INDEX ix_sig (sig)) ENGINE = InnoDB;
INSERT INTO stg_case_signature
SELECT c.caseid, MD5(CONCAT_WS('#', l.event_dt, c.age_years, c.sex, COALESCE(NULLIF(l.occr_country, ''), l.reporter_country), p.pt_set, d.ps_set))
FROM clean_case c
JOIN stg_case_latest l ON l.caseid = c.caseid
JOIN (SELECT caseid, GROUP_CONCAT(pt ORDER BY pt SEPARATOR '|') AS pt_set FROM case_event GROUP BY caseid) p ON p.caseid = c.caseid
JOIN (SELECT c2.caseid, GROUP_CONCAT(DISTINCT UPPER(TRIM(rd.drugname)) ORDER BY UPPER(TRIM(rd.drugname)) SEPARATOR '|') AS ps_set
      FROM clean_case c2 JOIN raw_drug rd ON rd.primaryid = c2.primaryid AND rd.role_cod = 'PS' GROUP BY c2.caseid) d ON d.caseid = c.caseid
WHERE CHAR_LENGTH(l.event_dt) = 8 AND c.age_years IS NOT NULL AND c.sex <> 'Unknown';

DROP TABLE IF EXISTS probable_duplicate;
CREATE TABLE probable_duplicate (caseid VARCHAR(20) PRIMARY KEY, kept_caseid VARCHAR(20) NOT NULL) ENGINE = InnoDB;
INSERT INTO probable_duplicate
SELECT s.caseid, k.keep_id
FROM stg_case_signature s
JOIN (SELECT sig, MIN(CAST(caseid AS UNSIGNED)) AS keep_id, COUNT(*) AS n FROM stg_case_signature GROUP BY sig HAVING COUNT(*) > 1) k ON k.sig = s.sig
WHERE CAST(s.caseid AS UNSIGNED) <> k.keep_id;

-- 6.5 Analysis membership: which case is in which analysis, as target (T) or comparator (C)
DROP TABLE IF EXISTS analysis_case;
CREATE TABLE analysis_case (
    analysis_id CHAR(2) NOT NULL, caseid VARCHAR(20) NOT NULL, grp CHAR(1) NOT NULL,
    PRIMARY KEY (analysis_id, caseid), INDEX ix_case (caseid)
) ENGINE = InnoDB;

CREATE OR REPLACE VIEW v_case_flags AS
SELECT c.caseid, COALESCE(e.tirz_ps, 0) AS tirz_ps, COALESCE(e.tirz_suspect, 0) AS tirz_suspect, COALESCE(e.tirz_any, 0) AS tirz_any,
       COALESCE(e.other_glp1_ps, 0) AS other_glp1_ps, COALESCE(e.other_glp1_suspect, 0) AS other_glp1_suspect
FROM clean_case c
LEFT JOIN case_exposure e ON e.caseid = c.caseid
LEFT JOIN probable_duplicate pd ON pd.caseid = c.caseid
WHERE pd.caseid IS NULL;

TRUNCATE analysis_case;
INSERT INTO analysis_case SELECT 'A1', caseid, 'T' FROM v_case_flags WHERE tirz_ps = 1;
INSERT INTO analysis_case SELECT 'A1', caseid, 'C' FROM v_case_flags WHERE tirz_any = 0;
INSERT INTO analysis_case SELECT 'A2', caseid, 'T' FROM v_case_flags WHERE tirz_suspect = 1;
INSERT INTO analysis_case SELECT 'A2', caseid, 'C' FROM v_case_flags WHERE tirz_any = 0;
INSERT INTO analysis_case SELECT 'A3', caseid, 'T' FROM v_case_flags WHERE tirz_ps = 1 AND other_glp1_suspect = 0;
INSERT INTO analysis_case SELECT 'A3', caseid, 'C' FROM v_case_flags WHERE other_glp1_ps = 1 AND tirz_any = 0;

-- 6.6 One wide case table used by every analysis query (strata variables beside each case)
DROP TABLE IF EXISTS analysis_dataset;
CREATE TABLE analysis_dataset (
    caseid VARCHAR(20) PRIMARY KEY, src_quarter CHAR(6), age_group VARCHAR(10), sex VARCHAR(8),
    reporter_type VARCHAR(24), region VARCHAR(10), indication_group VARCHAR(20),
    tirz_ps TINYINT, tirz_suspect TINYINT, tirz_any TINYINT, other_glp1_ps TINYINT
) ENGINE = InnoDB;
INSERT INTO analysis_dataset
SELECT c.caseid, c.src_quarter, c.age_group, c.sex, c.reporter_type, c.region, i.indication_group,
       f.tirz_ps, f.tirz_suspect, f.tirz_any, f.other_glp1_ps
FROM clean_case c JOIN v_case_flags f ON f.caseid = c.caseid JOIN case_indication i ON i.caseid = c.caseid;

-- 6.7 Cleaning log and sanity checks
INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '06', 'Analysis dataset', 'Case-event pairs (case x MedDRA PT)', COUNT(*), 'case_event' FROM case_event
UNION ALL SELECT '06', 'Analysis dataset', 'Probable cross-source duplicates removed', COUNT(*), 'same date, age, sex, country, PT set and suspect drugs' FROM probable_duplicate
UNION ALL SELECT '06', 'Analysis dataset', 'Cases in analysis dataset after duplicate removal', COUNT(*), 'analysis_dataset' FROM analysis_dataset
UNION ALL SELECT '06', 'Analysis A1 (primary)', 'Target cases: tirzepatide primary suspect', SUM(grp = 'T'), '' FROM analysis_case WHERE analysis_id = 'A1'
UNION ALL SELECT '06', 'Analysis A1 (primary)', 'Comparator cases: no tirzepatide in any role', SUM(grp = 'C'), '' FROM analysis_case WHERE analysis_id = 'A1'
UNION ALL SELECT '06', 'Analysis A2 (sensitivity)', 'Target cases: tirzepatide PS or SS', SUM(grp = 'T'), '' FROM analysis_case WHERE analysis_id = 'A2'
UNION ALL SELECT '06', 'Analysis A2 (sensitivity)', 'Comparator cases', SUM(grp = 'C'), '' FROM analysis_case WHERE analysis_id = 'A2'
UNION ALL SELECT '06', 'Analysis A3 (active comparator)', 'Target cases: tirzepatide PS, no other GLP-1 RA suspect', SUM(grp = 'T'), '' FROM analysis_case WHERE analysis_id = 'A3'
UNION ALL SELECT '06', 'Analysis A3 (active comparator)', 'Comparator cases: other GLP-1 RA primary suspect', SUM(grp = 'C'), '' FROM analysis_case WHERE analysis_id = 'A3';

SELECT analysis_id, grp, COUNT(*) AS cases FROM analysis_case GROUP BY analysis_id, grp ORDER BY analysis_id, grp;
SELECT COUNT(*) AS probable_duplicates_removed FROM probable_duplicate;
-- A case must never be in both groups of the same analysis
SELECT COUNT(*) AS cases_in_both_groups FROM (SELECT analysis_id, caseid FROM analysis_case GROUP BY analysis_id, caseid HAVING COUNT(*) > 1) x;
