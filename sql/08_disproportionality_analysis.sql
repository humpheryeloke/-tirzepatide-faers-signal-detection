/* =============================================================================
   08_disproportionality_analysis.sql
   Purpose : Calculate the three standard disproportionality statistics for every
             event x stratum x analysis, and flag signals.

   METHODS (all computed from the 2x2 table a, b, c, d; a = target cases with the event)
   1. ROR  Reporting Odds Ratio (Rothman; van Puijenbroek 2002)
           ROR = (a*d)/(b*c), SE(ln ROR) = sqrt(1/a + 1/b + 1/c + 1/d), 95% CI = exp(ln ROR +/- 1.96 SE)
   2. PRR  Proportional Reporting Ratio (Evans 2001; the EMA/MHRA screening criteria)
           PRR = [a/(a+b)] / [c/(c+d)]; signal if PRR >= 2, chi-square >= 4 and a >= 3
   3. IC   Information Component of the BCPNN (WHO-UMC, Bate 1998; Noren 2006)
           IC = log2[(a+0.5)/(E+0.5)], E = (a+b)(a+c)/N, with Noren's lower limit
           IC025 = IC - 3.3(a+0.5)^-1/2 - 2(a+0.5)^-3/2. Signal if IC025 > 0.
           The +0.5 makes the IC a shrinkage estimator: it is cautious with small counts.

   SIGNAL RULE used in this project ("detected"): a >= 3 AND lower 95% limit of ROR > 1
   AND IC025 > 0  (a frequentist and a Bayesian criterion must agree).
   PRR (Evans) criteria are reported alongside; "strong" = all three criteria met.

   ZERO CELLS: if any of a, b, c, d is 0 the Haldane-Anscombe correction (+0.5 to every
   cell) is used for ROR/PRR in that row, and the row is marked.

   MULTIPLE TESTING: thousands of event x subgroup rows are tested, so some will pass by
   chance. p-values (one-sided, H1: ROR > 1) are adjusted with the Benjamini-Hochberg false
   discovery rate (Benjamini & Hochberg 1995), separately for the 'overall' family and the
   'subgroup' family within each analysis. The adjusted value is q_bh; q_bh < 0.05 is the
   threshold used to call a subgroup finding "supported".
   ============================================================================= */
USE faers_pv;

DROP TABLE IF EXISTS signal_stats;
CREATE TABLE signal_stats (
    stat_id INT AUTO_INCREMENT PRIMARY KEY,
    analysis_id CHAR(2) NOT NULL, stratum_type VARCHAR(12) NOT NULL, stratum_label VARCHAR(40) NOT NULL,
    family VARCHAR(10) NOT NULL, pt VARCHAR(255) NOT NULL,
    a INT NOT NULL, b INT NOT NULL, c INT NOT NULL, d INT NOT NULL, n_target INT NOT NULL, n_comparator INT NOT NULL,
    zero_cell_corrected TINYINT NOT NULL,
    ror DOUBLE, se_ln_ror DOUBLE, ror_lci DOUBLE, ror_uci DOUBLE,
    prr DOUBLE, chi_square DOUBLE,
    expected_a DOUBLE, ic DOUBLE, ic025 DOUBLE, ic975 DOUBLE,
    p_one_sided DOUBLE, q_bh DOUBLE NULL,
    is_evaluable TINYINT NOT NULL,
    sig_ror TINYINT NOT NULL, sig_prr TINYINT NOT NULL, sig_ic TINYINT NOT NULL,
    signal_detected TINYINT NOT NULL, signal_strong TINYINT NOT NULL,
    UNIQUE KEY uq (analysis_id, stratum_type, stratum_label, pt), INDEX ix_pt (analysis_id, pt)
) ENGINE = InnoDB;

-- 8.1 Build b and d, then all statistics. Corrected cells (a2..d2) are used only when a cell is zero.
INSERT INTO signal_stats
    (analysis_id, stratum_type, stratum_label, family, pt, a, b, c, d, n_target, n_comparator, zero_cell_corrected,
     ror, se_ln_ror, ror_lci, ror_uci, prr, chi_square, expected_a, ic, ic025, ic975, p_one_sided, is_evaluable,
     sig_ror, sig_prr, sig_ic, signal_detected, signal_strong)
SELECT analysis_id, stratum_type, stratum_label, family, pt, a, b, c, d, n_target, n_comparator, zc,
       ror, se, EXP(LOG(ror) - 1.96e0 * se), EXP(LOG(ror) + 1.96e0 * se), prr,
       n_tot * POW(a * d - b * c, 2) / ((a + b) * 1e0 * (c + d) * (a + c) * (b + d)),
       e, ic, ic - 3.3e0 / SQRT(a + 0.5e0) - 2e0 / POW(a + 0.5e0, 1.5e0), ic + 2.4e0 / SQRT(a + 0.5e0) - 0.5e0 / POW(a + 0.5e0, 1.5e0),
       norm_sf(LOG(ror) / se),
       a >= 3,
       a >= 3 AND EXP(LOG(ror) - 1.96e0 * se) > 1,
       a >= 3 AND prr >= 2 AND n_tot * POW(a * d - b * c, 2) / ((a + b) * 1e0 * (c + d) * (a + c) * (b + d)) >= 4,
       a >= 3 AND ic - 3.3e0 / SQRT(a + 0.5e0) - 2e0 / POW(a + 0.5e0, 1.5e0) > 0,
       (a >= 3 AND EXP(LOG(ror) - 1.96e0 * se) > 1 AND ic - 3.3e0 / SQRT(a + 0.5e0) - 2e0 / POW(a + 0.5e0, 1.5e0) > 0),
       (a >= 3 AND EXP(LOG(ror) - 1.96e0 * se) > 1 AND ic - 3.3e0 / SQRT(a + 0.5e0) - 2e0 / POW(a + 0.5e0, 1.5e0) > 0
        AND prr >= 2 AND n_tot * POW(a * d - b * c, 2) / ((a + b) * 1e0 * (c + d) * (a + c) * (b + d)) >= 4)
FROM (
    SELECT s.*, (a + b + c + d) AS n_tot, (a + b) * (a + c) / (a + b + c + d) AS e,
           (a2 * d2) / (b2 * c2) AS ror, SQRT(1e0 / a2 + 1e0 / b2 + 1e0 / c2 + 1e0 / d2) AS se,
           (a2 / (a2 + b2)) / (c2 / (c2 + d2)) AS prr,
           LOG(2e0, (a + 0.5e0) / ((a + b) * (a + c) / (a + b + c + d) + 0.5e0)) AS ic
    FROM (
        SELECT sc.analysis_id, sc.stratum_type, sc.stratum_label,
               IF(sc.stratum_type = 'overall', 'overall', 'subgroup') AS family, sc.pt,
               sc.a, (n.n_target - sc.a) AS b, sc.c, (n.n_comparator - sc.c) AS d, n.n_target, n.n_comparator,
               (sc.a = 0 OR n.n_target - sc.a = 0 OR sc.c = 0 OR n.n_comparator - sc.c = 0) AS zc,
               sc.a + 0.5e0 * (sc.a = 0 OR n.n_target - sc.a = 0 OR sc.c = 0 OR n.n_comparator - sc.c = 0) AS a2,
               (n.n_target - sc.a) + 0.5e0 * (sc.a = 0 OR n.n_target - sc.a = 0 OR sc.c = 0 OR n.n_comparator - sc.c = 0) AS b2,
               sc.c + 0.5e0 * (sc.a = 0 OR n.n_target - sc.a = 0 OR sc.c = 0 OR n.n_comparator - sc.c = 0) AS c2,
               (n.n_comparator - sc.c) + 0.5e0 * (sc.a = 0 OR n.n_target - sc.a = 0 OR sc.c = 0 OR n.n_comparator - sc.c = 0) AS d2
        FROM signal_counts sc
        JOIN stratum_n n ON n.analysis_id = sc.analysis_id AND n.stratum_type = sc.stratum_type AND n.stratum_label = sc.stratum_label
    ) s
) t;

-- 8.2 Benjamini-Hochberg adjusted p-values (q) for evaluable rows (a >= 3), one family per analysis.
--     q_i = min over j >= i of ( p_j * m / rank_j ), computed with window functions.
UPDATE signal_stats s
JOIN (
    SELECT stat_id,
           MIN(q_raw) OVER (PARTITION BY analysis_id, family ORDER BY p_one_sided DESC, stat_id DESC
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS q
    FROM (
        SELECT stat_id, analysis_id, family, p_one_sided,
               LEAST(1e0, p_one_sided * COUNT(*) OVER (PARTITION BY analysis_id, family)
                          / ROW_NUMBER() OVER (PARTITION BY analysis_id, family ORDER BY p_one_sided, stat_id)) AS q_raw
        FROM signal_stats WHERE is_evaluable = 1
    ) r
) x ON x.stat_id = s.stat_id
SET s.q_bh = x.q;

INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '08', 'Disproportionality', CONCAT('Rows analysed, ', analysis_id), COUNT(*), 'event x stratum' FROM signal_stats GROUP BY analysis_id
UNION ALL SELECT '08', 'Disproportionality', CONCAT('Evaluable rows (a>=3), ', analysis_id), SUM(is_evaluable), 'tests entering BH correction' FROM signal_stats GROUP BY analysis_id
UNION ALL SELECT '08', 'Disproportionality', CONCAT('Overall signals detected, ', analysis_id), SUM(signal_detected), 'ROR LCI>1 and IC025>0 and a>=3' FROM signal_stats WHERE stratum_type = 'overall' GROUP BY analysis_id;

-- 8.3 Summary of the primary analysis (A1): signals by criterion at the overall level
SELECT 'events assessed (>= 3 target cases)' AS metric, COUNT(*) AS n FROM signal_stats WHERE analysis_id = 'A1' AND stratum_type = 'overall' AND is_evaluable = 1
UNION ALL SELECT 'ROR criterion met', SUM(sig_ror) FROM signal_stats WHERE analysis_id = 'A1' AND stratum_type = 'overall'
UNION ALL SELECT 'PRR (Evans) criteria met', SUM(sig_prr) FROM signal_stats WHERE analysis_id = 'A1' AND stratum_type = 'overall'
UNION ALL SELECT 'IC025 > 0 (BCPNN) met', SUM(sig_ic) FROM signal_stats WHERE analysis_id = 'A1' AND stratum_type = 'overall'
UNION ALL SELECT 'DETECTED (ROR and IC025)', SUM(signal_detected) FROM signal_stats WHERE analysis_id = 'A1' AND stratum_type = 'overall'
UNION ALL SELECT 'STRONG (all three)', SUM(signal_strong) FROM signal_stats WHERE analysis_id = 'A1' AND stratum_type = 'overall'
UNION ALL SELECT 'detected AND q_bh < 0.05', SUM(signal_detected AND q_bh < 0.05) FROM signal_stats WHERE analysis_id = 'A1' AND stratum_type = 'overall';

-- 8.4 Top ten overall signals in A1 ranked by the lower confidence limit (not by the point estimate)
SELECT pt, a AS target_cases, c AS comparator_cases, ROUND(ror, 2) AS ror, ROUND(ror_lci, 2) AS ror_lci,
       ROUND(prr, 2) AS prr, ROUND(ic025, 2) AS ic025, ROUND(q_bh, 6) AS q_bh
FROM signal_stats WHERE analysis_id = 'A1' AND stratum_type = 'overall' AND signal_detected = 1
ORDER BY ror_lci DESC LIMIT 10;
