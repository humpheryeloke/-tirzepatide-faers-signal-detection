/* =============================================================================
   05_standardise_drugs.sql
   Purpose : Recognise tirzepatide (and the comparator GLP-1 drugs) however the
             reporter wrote the name, then summarise exposure per case.
   Why     : drugname is free text typed by reporters ("MOUNJARO", "Mounjaro 7.5mg",
             "MOUNJARNO", "tirzepatide 1mg/ml"...). Matching only the exact word
             "TIRZEPATIDE" would silently miss most tirzepatide cases. prod_ai (the
             active ingredient FDA derives from the product) is more reliable than
             drugname but is blank for 1.7% of rows, so both are used.
   Method  : (1) build one row per DISTINCT name pair (66k spellings, not 7.8M rows),
             (2) classify each with transparent pattern rules, (3) join back.
   ============================================================================= */
USE faers_pv;

-- 5.1 Distinct drug-name spellings
DROP TABLE IF EXISTS drug_name_map;
CREATE TABLE drug_name_map (
    name_norm VARCHAR(500) NOT NULL, ai_norm VARCHAR(500) NOT NULL,
    substance VARCHAR(20) NULL,           -- standardised substance, NULL = not a drug of interest
    match_rule VARCHAR(60) NULL,          -- which rule matched (for audit)
    PRIMARY KEY (name_norm(200), ai_norm(200))
) ENGINE = InnoDB;

INSERT INTO drug_name_map (name_norm, ai_norm)
SELECT DISTINCT UPPER(TRIM(drugname)), UPPER(TRIM(prod_ai)) FROM raw_drug;

-- 5.2 Classification rules. Order matters: the first rule that matches wins.
--     Active ingredient (prod_ai) rules come first because they are the most reliable.
UPDATE drug_name_map SET substance = 'TIRZEPATIDE', match_rule = 'ai: tirzepatide'
 WHERE substance IS NULL AND ai_norm LIKE '%TIRZEPATIDE%';
UPDATE drug_name_map SET substance = 'TIRZEPATIDE', match_rule = 'name: brand/generic/misspelling'
 WHERE substance IS NULL AND (name_norm LIKE '%MOUNJARO%' OR name_norm LIKE '%ZEPBOUND%' OR name_norm LIKE '%TIRZEPATID%'
       OR name_norm LIKE '%MOUNJANO%' OR name_norm LIKE '%MOUNJARNO%' OR name_norm IN ('TIRZEP', 'TIRZ'));

-- Comparator class: other GLP-1 receptor agonists (used only for the active-comparator sensitivity analysis)
UPDATE drug_name_map SET substance = 'SEMAGLUTIDE', match_rule = 'ai/name: semaglutide'
 WHERE substance IS NULL AND (ai_norm LIKE '%SEMAGLUTIDE%' OR name_norm REGEXP 'SEMAGLUTIDE|OZEMPIC|WEGOVY|RYBELSUS');
UPDATE drug_name_map SET substance = 'LIRAGLUTIDE', match_rule = 'ai/name: liraglutide'
 WHERE substance IS NULL AND (ai_norm LIKE '%LIRAGLUTIDE%' OR name_norm REGEXP 'LIRAGLUTIDE|VICTOZA|SAXENDA|XULTOPHY');
UPDATE drug_name_map SET substance = 'DULAGLUTIDE', match_rule = 'ai/name: dulaglutide'
 WHERE substance IS NULL AND (ai_norm LIKE '%DULAGLUTIDE%' OR name_norm REGEXP 'DULAGLUTIDE|TRULICITY');
UPDATE drug_name_map SET substance = 'EXENATIDE', match_rule = 'ai/name: exenatide'
 WHERE substance IS NULL AND (ai_norm LIKE '%EXENATIDE%' OR name_norm REGEXP 'EXENATIDE|BYETTA|BYDUREON');
UPDATE drug_name_map SET substance = 'LIXISENATIDE', match_rule = 'ai/name: lixisenatide'
 WHERE substance IS NULL AND (ai_norm LIKE '%LIXISENATIDE%' OR name_norm REGEXP 'LIXISENATIDE|ADLYXIN|LYXUMIA|SOLIQUA');

-- 5.3 Audit the rules: which spellings were captured, and nothing unexpected
SELECT substance, match_rule, COUNT(*) AS spellings FROM drug_name_map WHERE substance IS NOT NULL GROUP BY 1, 2 ORDER BY 1, 2;

-- False-positive check: spellings classed as tirzepatide whose name does NOT contain an obvious tirzepatide word
SELECT name_norm, ai_norm FROM drug_name_map
WHERE substance = 'TIRZEPATIDE' AND name_norm NOT REGEXP 'MOUNJARO|ZEPBOUND|TIRZEPATID' LIMIT 20;

-- False-negative check: names that look like tirzepatide but were not matched
SELECT name_norm, ai_norm FROM drug_name_map
WHERE substance IS NULL AND (name_norm REGEXP 'TIRZ|MOUNJ|ZEPBO|ZEPPB' OR ai_norm REGEXP 'TIRZ|MOUNJ|ZEPBO') LIMIT 20;

-- 5.4 Drug rows of interest, attached to the selected report version of each clean case
DROP TABLE IF EXISTS clean_drug_focus;
CREATE TABLE clean_drug_focus (
    caseid VARCHAR(20) NOT NULL, drug_seq INT NOT NULL, role_cod VARCHAR(5) NOT NULL,
    substance VARCHAR(20) NOT NULL, drugname_reported VARCHAR(255), dechal VARCHAR(5), rechal VARCHAR(5),
    INDEX ix_case (caseid), INDEX ix_sub (substance, role_cod)
) ENGINE = InnoDB;

INSERT INTO clean_drug_focus
SELECT c.caseid, CAST(NULLIF(d.drug_seq, '') AS UNSIGNED), d.role_cod, m.substance, LEFT(d.drugname, 255), d.dechal, d.rechal
FROM clean_case c
JOIN raw_drug d ON d.primaryid = c.primaryid
JOIN drug_name_map m ON m.name_norm = UPPER(TRIM(d.drugname)) AND m.ai_norm = UPPER(TRIM(d.prod_ai))
WHERE m.substance IS NOT NULL;

-- 5.5 One row per case: which drugs of interest, in which role
--     Role codes: PS primary suspect, SS secondary suspect, C concomitant, I interacting.
DROP TABLE IF EXISTS case_exposure;
CREATE TABLE case_exposure (
    caseid VARCHAR(20) PRIMARY KEY,
    tirz_ps TINYINT NOT NULL, tirz_suspect TINYINT NOT NULL, tirz_any TINYINT NOT NULL,
    other_glp1_ps TINYINT NOT NULL, other_glp1_suspect TINYINT NOT NULL,
    tirz_dechal_positive TINYINT NOT NULL            -- tirzepatide stopped and event improved (dechallenge = 'Y')
) ENGINE = InnoDB;

INSERT INTO case_exposure
SELECT caseid,
       MAX(substance = 'TIRZEPATIDE' AND role_cod = 'PS'),
       MAX(substance = 'TIRZEPATIDE' AND role_cod IN ('PS', 'SS')),
       MAX(substance = 'TIRZEPATIDE'),
       MAX(substance <> 'TIRZEPATIDE' AND role_cod = 'PS'),
       MAX(substance <> 'TIRZEPATIDE' AND role_cod IN ('PS', 'SS')),
       MAX(substance = 'TIRZEPATIDE' AND dechal = 'Y')
FROM clean_drug_focus GROUP BY caseid;

INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '05', 'Drug standardisation', 'Distinct drugname/active-ingredient spellings', COUNT(*), 'drug_name_map' FROM drug_name_map
UNION ALL SELECT '05', 'Drug standardisation', 'Spellings classified as tirzepatide', COUNT(*), 'prod_ai + brand/misspelling rules' FROM drug_name_map WHERE substance = 'TIRZEPATIDE'
UNION ALL SELECT '05', 'Drug standardisation', 'Spellings classified as other GLP-1 RA', COUNT(*), 'semaglutide, liraglutide, dulaglutide, exenatide, lixisenatide' FROM drug_name_map WHERE substance IS NOT NULL AND substance <> 'TIRZEPATIDE'
UNION ALL SELECT '05', 'Drug standardisation', 'Clean cases with tirzepatide as primary suspect (PS)', SUM(tirz_ps), 'target group, primary analysis' FROM case_exposure
UNION ALL SELECT '05', 'Drug standardisation', 'Clean cases with tirzepatide as PS or secondary suspect', SUM(tirz_suspect), 'target group, sensitivity analysis' FROM case_exposure
UNION ALL SELECT '05', 'Drug standardisation', 'Clean cases with tirzepatide in any role', SUM(tirz_any), '' FROM case_exposure
UNION ALL SELECT '05', 'Drug standardisation', 'Clean cases with another GLP-1 RA as primary suspect', SUM(other_glp1_ps), 'active comparator group' FROM case_exposure;

SELECT SUM(tirz_ps) AS tirz_primary_suspect, SUM(tirz_suspect) AS tirz_any_suspect, SUM(tirz_any) AS tirz_any_role,
       SUM(other_glp1_ps) AS other_glp1_ps, SUM(tirz_ps AND other_glp1_suspect) AS tirz_ps_with_other_glp1_suspect FROM case_exposure;
