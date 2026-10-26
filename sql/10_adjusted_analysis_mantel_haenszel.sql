/* =============================================================================
   10_adjusted_analysis_mantel_haenszel.sql
   Purpose : Re-estimate each event's ROR AFTER adjusting for age, sex and reporting
             quarter, the three stratification variables recommended by the EMA for
             spontaneous-report signal detection (EMA/106464/2006 rev.1).
   Why     : A crude (overall) ROR can be distorted by who reports. If tirzepatide reports
             come mostly from women aged 45-64 and the comparator mostly from men over 65, an
             event that is simply more common in women will look "disproportionate".
             Adjustment compares like with like: tirzepatide vs comparator WITHIN each
             age x sex x quarter cell, then pools the cells.
   Method  : Mantel-Haenszel pooled odds ratio (Mantel & Haenszel 1959) with the
             Robins-Breslow-Greenland variance (Robins et al. 1986), valid for sparse data:
                 OR_MH = sum(a_i d_i / n_i) / sum(b_i c_i / n_i)
   Missing age/sex: kept as their own 'Unknown' category so that no case is dropped.
   Reading  : If the crude and adjusted ROR differ a lot, the crude signal is partly
              explained by reporter/demographic composition (confounding), not by the drug.
   ============================================================================= */
USE faers_pv;

-- 10.1 Counts per fine adjustment cell (age group x sex x quarter)
DROP TABLE IF EXISTS mh_cell_n;
CREATE TABLE mh_cell_n (
    analysis_id CHAR(2), age_group VARCHAR(10), sex VARCHAR(8), src_quarter CHAR(6),
    n_target INT NOT NULL, n_comparator INT NOT NULL,
    PRIMARY KEY (analysis_id, age_group, sex, src_quarter)
) ENGINE = InnoDB;
INSERT INTO mh_cell_n
SELECT ac.analysis_id, ad.age_group, ad.sex, ad.src_quarter, SUM(ac.grp = 'T'), SUM(ac.grp = 'C')
FROM analysis_case ac JOIN analysis_dataset ad ON ad.caseid = ac.caseid
GROUP BY ac.analysis_id, ad.age_group, ad.sex, ad.src_quarter;

DROP TABLE IF EXISTS mh_cell_counts;
CREATE TABLE mh_cell_counts (
    analysis_id CHAR(2), age_group VARCHAR(10), sex VARCHAR(8), src_quarter CHAR(6), pt VARCHAR(255),
    a INT NOT NULL, c INT NOT NULL,
    PRIMARY KEY (analysis_id, age_group, sex, src_quarter, pt)
) ENGINE = InnoDB;
INSERT INTO mh_cell_counts
SELECT ac.analysis_id, ad.age_group, ad.sex, ad.src_quarter, e.pt, SUM(ac.grp = 'T'), SUM(ac.grp = 'C')
FROM analysis_case ac
JOIN analysis_dataset ad ON ad.caseid = ac.caseid
JOIN case_event e ON e.caseid = ac.caseid
JOIN candidate_pt cp ON cp.pt = e.pt
GROUP BY ac.analysis_id, ad.age_group, ad.sex, ad.src_quarter, e.pt;

-- 10.2 Mantel-Haenszel adjusted ROR with 95% CI (events with at least 3 target cases overall)
DROP TABLE IF EXISTS signal_adjusted;
CREATE TABLE signal_adjusted (
    analysis_id CHAR(2) NOT NULL, pt VARCHAR(255) NOT NULL, a_total INT, cells_used INT,
    ror_mh DOUBLE, ror_mh_lci DOUBLE, ror_mh_uci DOUBLE,
    PRIMARY KEY (analysis_id, pt)
) ENGINE = InnoDB;

INSERT INTO signal_adjusted
SELECT analysis_id, pt, a_total, cells, EXP(LOG(r / s)), EXP(LOG(r / s) - 1.96e0 * SQRT(var_ln)), EXP(LOG(r / s) + 1.96e0 * SQRT(var_ln))
FROM (
    SELECT analysis_id, pt, SUM(a) AS a_total, COUNT(*) AS cells, SUM(ri) AS r, SUM(si) AS s,
           SUM(pi * ri) / (2e0 * POW(SUM(ri), 2))
           + SUM(pi * si + qi * ri) / (2e0 * SUM(ri) * SUM(si))
           + SUM(qi * si) / (2e0 * POW(SUM(si), 2)) AS var_ln
    FROM (
        SELECT m.analysis_id, m.pt, m.a, n.n_target + n.n_comparator AS n,
               m.a * (n.n_comparator - m.c) / (n.n_target + n.n_comparator) AS ri,       -- a*d/n
               (n.n_target - m.a) * m.c / (n.n_target + n.n_comparator) AS si,           -- b*c/n
               (m.a + n.n_comparator - m.c) / (n.n_target + n.n_comparator) AS pi,       -- (a+d)/n
               ((n.n_target - m.a) + m.c) / (n.n_target + n.n_comparator) AS qi          -- (b+c)/n
        FROM mh_cell_counts m
        JOIN mh_cell_n n ON n.analysis_id = m.analysis_id AND n.age_group = m.age_group AND n.sex = m.sex AND n.src_quarter = m.src_quarter
    ) t
    GROUP BY analysis_id, pt HAVING SUM(ri) > 0 AND SUM(si) > 0
) u;

-- 10.3 Crude versus adjusted for the primary analysis: where does adjustment change the picture?
DROP VIEW IF EXISTS v_crude_vs_adjusted;
CREATE VIEW v_crude_vs_adjusted AS
SELECT o.analysis_id, o.pt, o.a AS target_cases, o.ror AS ror_crude, o.ror_lci AS lci_crude,
       j.ror_mh AS ror_adjusted, j.ror_mh_lci AS lci_adjusted, j.ror_mh_uci AS uci_adjusted,
       j.ror_mh / o.ror AS adjusted_to_crude_ratio,
       (o.signal_detected = 1) AS crude_signal, (j.ror_mh_lci > 1 AND o.a >= 3) AS adjusted_signal
FROM signal_stats o JOIN signal_adjusted j ON j.analysis_id = o.analysis_id AND j.pt = o.pt
WHERE o.stratum_type = 'overall';

INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '10', 'Mantel-Haenszel', CONCAT('Events with adjusted ROR, ', analysis_id), COUNT(*), 'adjusted for age x sex x quarter' FROM signal_adjusted GROUP BY analysis_id;

SELECT SUM(crude_signal = 1 AND adjusted_signal = 1) AS signal_both,
       SUM(crude_signal = 1 AND adjusted_signal = 0) AS signal_lost_after_adjustment,
       SUM(crude_signal = 0 AND adjusted_signal = 1) AS signal_appears_after_adjustment,
       SUM(adjusted_to_crude_ratio < 0.8 OR adjusted_to_crude_ratio > 1.25) AS ror_changes_over_20pct
FROM v_crude_vs_adjusted WHERE analysis_id = 'A1';
