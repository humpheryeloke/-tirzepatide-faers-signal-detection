/* =============================================================================
   07_build_contingency_tables.sql
   Purpose : For every event (MedDRA PT), every subgroup and every analysis, count the
             four cells of the 2x2 table used by all disproportionality methods:

                                  event reported   event NOT reported
        target drug (tirzepatide)       a                 b
        comparator                      c                 d

   Cells are counts of CASES (not reports, not reaction rows). Only 'a' and 'c' are
   counted here; b and d follow from the group sizes: b = N_target - a, d = N_comp - c.
   Subgroups (strata) analysed, each as its own set of 2x2 tables:
        overall | age | sex | age x sex | reporter type | region | receipt quarter | indication
   Within one stratum TYPE the strata are disjoint (a case is in exactly one age group);
   across types they overlap (the same case is in an age group AND a sex group).
   ============================================================================= */
USE faers_pv;

-- 7.1 Candidate events: terms reported in at least 3 tirzepatide cases (broadest definition, A2).
--     A term with fewer than 3 target cases cannot meet the signal rule in any subgroup either,
--     because a subgroup count can never exceed the overall count.
DROP TABLE IF EXISTS candidate_pt;
CREATE TABLE candidate_pt (pt VARCHAR(255) PRIMARY KEY) ENGINE = InnoDB;
INSERT INTO candidate_pt
SELECT e.pt FROM case_event e JOIN analysis_case ac ON ac.caseid = e.caseid AND ac.analysis_id = 'A2' AND ac.grp = 'T'
GROUP BY e.pt HAVING COUNT(*) >= 3;

-- 7.2 Group sizes per analysis and stratum (the N behind b and d)
DROP TABLE IF EXISTS stratum_n;
CREATE TABLE stratum_n (
    analysis_id CHAR(2) NOT NULL, stratum_type VARCHAR(12) NOT NULL, stratum_label VARCHAR(40) NOT NULL,
    n_target INT NOT NULL, n_comparator INT NOT NULL,
    PRIMARY KEY (analysis_id, stratum_type, stratum_label)
) ENGINE = InnoDB;

-- 7.3 Event counts per analysis, stratum type, stratum and event
DROP TABLE IF EXISTS signal_counts;
CREATE TABLE signal_counts (
    analysis_id CHAR(2) NOT NULL, stratum_type VARCHAR(12) NOT NULL, stratum_label VARCHAR(40) NOT NULL,
    pt VARCHAR(255) NOT NULL, a INT NOT NULL, c INT NOT NULL,
    PRIMARY KEY (analysis_id, stratum_type, stratum_label, pt)
) ENGINE = InnoDB;

/* The same two queries are needed for 8 stratum types x 3 analyses, so they live in one
   procedure. For each stratum type, "label_expr" says how to name the stratum and
   "filter_expr" excludes cases whose subgroup variable is unknown. */
DROP PROCEDURE IF EXISTS sp_count_stratum;
DELIMITER $$
CREATE PROCEDURE sp_count_stratum(IN p_type VARCHAR(12), IN label_expr VARCHAR(200), IN filter_expr VARCHAR(300))
BEGIN
    SET @sql_n = CONCAT(
        'INSERT INTO stratum_n SELECT ac.analysis_id, ''', p_type, ''', ', label_expr, ', SUM(ac.grp = ''T''), SUM(ac.grp = ''C'') ',
        'FROM analysis_case ac JOIN analysis_dataset ad ON ad.caseid = ac.caseid WHERE ', filter_expr, ' GROUP BY ac.analysis_id, ', label_expr);
    PREPARE s FROM @sql_n; EXECUTE s; DEALLOCATE PREPARE s;

    SET @sql_c = CONCAT(
        'INSERT INTO signal_counts SELECT ac.analysis_id, ''', p_type, ''', ', label_expr, ', e.pt, SUM(ac.grp = ''T''), SUM(ac.grp = ''C'') ',
        'FROM analysis_case ac JOIN analysis_dataset ad ON ad.caseid = ac.caseid ',
        'JOIN case_event e ON e.caseid = ac.caseid JOIN candidate_pt cp ON cp.pt = e.pt ',
        'WHERE ', filter_expr, ' GROUP BY ac.analysis_id, ', label_expr, ', e.pt HAVING SUM(ac.grp = ''T'') >= 1');
    PREPARE s FROM @sql_c; EXECUTE s; DEALLOCATE PREPARE s;
END$$
DELIMITER ;

TRUNCATE stratum_n; TRUNCATE signal_counts;
CALL sp_count_stratum('overall',   '''All''',                                  '1 = 1');
CALL sp_count_stratum('age',       'ad.age_group',                             'ad.age_group <> ''Unknown''');
CALL sp_count_stratum('sex',       'ad.sex',                                   'ad.sex <> ''Unknown''');
CALL sp_count_stratum('age_sex',   'CONCAT(ad.age_group, '' '', ad.sex)',      'ad.age_group <> ''Unknown'' AND ad.sex <> ''Unknown''');
CALL sp_count_stratum('reporter',  'ad.reporter_type',                         'ad.reporter_type <> ''Unknown''');
CALL sp_count_stratum('region',    'ad.region',                                'ad.region <> ''Unknown''');
CALL sp_count_stratum('quarter',   'ad.src_quarter',                           '1 = 1');
CALL sp_count_stratum('indication','ad.indication_group',                      'ad.indication_group <> ''Other/unknown''');

INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '07', 'Contingency tables', 'Candidate events (>= 3 target cases)', COUNT(*), 'candidate_pt' FROM candidate_pt
UNION ALL SELECT '07', 'Contingency tables', 'Event x stratum x analysis count rows', COUNT(*), 'signal_counts' FROM signal_counts
UNION ALL SELECT '07', 'Contingency tables', 'Strata defined (analysis x type x label)', COUNT(*), 'stratum_n' FROM stratum_n;

-- 7.4 Checks. (1) Within a stratum TYPE the strata are disjoint, so group sizes may be added within a type only.
SELECT analysis_id, stratum_type, SUM(n_target) AS target_cases_in_type, SUM(n_comparator) AS comparator_cases_in_type
FROM stratum_n WHERE analysis_id = 'A1' GROUP BY analysis_id, stratum_type ORDER BY stratum_type;
-- (2) The 'overall' counts must reproduce the case numbers from script 06
SELECT analysis_id, n_target, n_comparator FROM stratum_n WHERE stratum_type = 'overall' ORDER BY analysis_id;
-- (3) No cell can exceed its group size
SELECT COUNT(*) AS impossible_cells FROM signal_counts s JOIN stratum_n n
  ON n.analysis_id = s.analysis_id AND n.stratum_type = s.stratum_type AND n.stratum_label = s.stratum_label
WHERE s.a > n.n_target OR s.c > n.n_comparator;
