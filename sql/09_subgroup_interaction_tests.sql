/* =============================================================================
   09_subgroup_interaction_tests.sql
   Purpose : Decide whether a subgroup result is genuinely DIFFERENT from the rest, rather
             than just "significant in one subgroup and not in another".
   Why     : "Significant in women, not significant in men" is not evidence that women and
             men differ (the difference between 'significant' and 'not significant' is not
             itself significant; Gelman & Stern 2006). Two formal tests are used instead:

   (1) Heterogeneity across all strata of one type (Cochran's Q on ln ROR):
         Q = sum w_i (lnROR_i - lnROR_pooled)^2, w_i = 1 / SE_i^2, df = k - 1.
       Only strata with >= 3 target cases enter. Needs at least 2 such strata.
   (2) Subgroup versus the rest of the same stratum type (ratio of RORs):
         z = [ln ROR_sub - ln ROR_rest] / sqrt(SE_sub^2 + SE_rest^2); two-sided p.
       "Rest" = all other strata of the same type (e.g. age 65+ versus ages 18-44 and 45-64
       combined). This is the interaction test recommended when looking for effect
       modification in subgroups (EMA 2016 signal-detection guideline, stratified analysis).
   ============================================================================= */
USE faers_pv;

-- 9.1 Heterogeneity (Cochran's Q) per event and stratum type
DROP TABLE IF EXISTS heterogeneity;
CREATE TABLE heterogeneity (
    analysis_id CHAR(2) NOT NULL, stratum_type VARCHAR(12) NOT NULL, pt VARCHAR(255) NOT NULL,
    k_strata INT NOT NULL, q_stat DOUBLE, df INT, p_heterogeneity DOUBLE,
    PRIMARY KEY (analysis_id, stratum_type, pt)
) ENGINE = InnoDB;

INSERT INTO heterogeneity
SELECT analysis_id, stratum_type, pt, k, q, k - 1, chisq_sf(q, k - 1)
FROM (
    SELECT analysis_id, stratum_type, pt, COUNT(*) AS k,
           GREATEST(0e0, SUM(w * x * x) - POW(SUM(w * x), 2) / SUM(w)) AS q
    FROM (SELECT analysis_id, stratum_type, pt, LOG(ror) AS x, 1e0 / (se_ln_ror * se_ln_ror) AS w
          FROM signal_stats WHERE is_evaluable = 1 AND stratum_type <> 'overall') z
    GROUP BY analysis_id, stratum_type, pt HAVING COUNT(*) >= 2
) h;

-- 9.2 Subgroup versus the rest (interaction test), evaluable subgroup rows only
DROP TABLE IF EXISTS subgroup_vs_rest;
CREATE TABLE subgroup_vs_rest (
    stat_id INT PRIMARY KEY, a_rest INT, c_rest INT, ror_rest DOUBLE, se_ln_ror_rest DOUBLE,
    ratio_of_rors DOUBLE, ratio_lci DOUBLE, ratio_uci DOUBLE, z_interaction DOUBLE, p_interaction DOUBLE
) ENGINE = InnoDB;

INSERT INTO subgroup_vs_rest
SELECT stat_id, a_rest, c_rest, ror_rest, se_rest, ror / ror_rest,
       EXP(LOG(ror / ror_rest) - 1.96e0 * se_diff), EXP(LOG(ror / ror_rest) + 1.96e0 * se_diff),
       (LOG(ror) - LOG(ror_rest)) / se_diff, 2e0 * norm_sf(ABS((LOG(ror) - LOG(ror_rest)) / se_diff))
FROM (
    SELECT stat_id, ror, se_ln_ror, a_rest, c_rest, ror_rest, se_rest, SQRT(se_ln_ror * se_ln_ror + se_rest * se_rest) AS se_diff
    FROM (
        -- cells of the "rest" 2x2 table; 0.5 is added to every cell if any cell is zero (z = 1)
        SELECT stat_id, ror, se_ln_ror, a_rest, c_rest,
               ((a_rest + 0.5e0 * z) * (d_rest + 0.5e0 * z)) / ((b_rest + 0.5e0 * z) * (c_rest + 0.5e0 * z)) AS ror_rest,
               SQRT(1e0 / (a_rest + 0.5e0 * z) + 1e0 / (b_rest + 0.5e0 * z) + 1e0 / (c_rest + 0.5e0 * z) + 1e0 / (d_rest + 0.5e0 * z)) AS se_rest
        FROM (
            SELECT s.stat_id, s.ror, s.se_ln_ror,
                   g.a_tot - s.a AS a_rest, g.c_tot - s.c AS c_rest,
                   (g.nt - s.n_target) - (g.a_tot - s.a) AS b_rest, (g.nc - s.n_comparator) - (g.c_tot - s.c) AS d_rest,
                   ((g.a_tot - s.a) = 0 OR (g.c_tot - s.c) = 0 OR (g.nt - s.n_target) - (g.a_tot - s.a) = 0
                    OR (g.nc - s.n_comparator) - (g.c_tot - s.c) = 0) AS z
            FROM signal_stats s
            JOIN (SELECT sc.analysis_id, sc.stratum_type, sc.pt, SUM(sc.a) AS a_tot, SUM(sc.c) AS c_tot,
                         (SELECT SUM(n.n_target) FROM stratum_n n WHERE n.analysis_id = sc.analysis_id AND n.stratum_type = sc.stratum_type) AS nt,
                         (SELECT SUM(n.n_comparator) FROM stratum_n n WHERE n.analysis_id = sc.analysis_id AND n.stratum_type = sc.stratum_type) AS nc
                  FROM signal_counts sc WHERE sc.stratum_type <> 'overall' GROUP BY sc.analysis_id, sc.stratum_type, sc.pt) g
              ON g.analysis_id = s.analysis_id AND g.stratum_type = s.stratum_type AND g.pt = s.pt
            WHERE s.is_evaluable = 1 AND s.stratum_type <> 'overall'
        ) r
    ) x
) y;

INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '09', 'Subgroup tests', 'Heterogeneity tests (event x stratum type x analysis)', COUNT(*), 'Cochran Q' FROM heterogeneity
UNION ALL SELECT '09', 'Subgroup tests', 'Subgroup-vs-rest interaction tests', COUNT(*), 'ratio of RORs' FROM subgroup_vs_rest;

-- 9.3 Overview for the primary analysis
SELECT stratum_type, COUNT(*) AS events_tested, SUM(p_heterogeneity < 0.05) AS heterogeneous_p05, SUM(p_heterogeneity < 0.001) AS heterogeneous_p001
FROM heterogeneity WHERE analysis_id = 'A1' GROUP BY stratum_type ORDER BY stratum_type;
