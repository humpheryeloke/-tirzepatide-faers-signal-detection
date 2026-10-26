/* =============================================================================
   12_event_classification_and_subgroup_findings.sql
   Purpose : Compare each event's OVERALL (aggregate) result with its SUBGROUP results and
             classify it. This is the core of the "hidden subgroup signal" question.

   Population subgroups examined: age, sex, age x sex, reporter type, region, indication.
   (Receipt quarter is a time check, not a patient subgroup; it is used in script 13.)
   A subgroup row "signals" when it meets the same rule as the overall analysis
   (a >= 3, ROR lower 95% limit > 1 and IC025 > 0).

   EVENT CLASSES (primary analysis A1; only events with >= 3 target cases overall)
     Hidden subgroup signal  overall NOT detected, >= 1 subgroup detected  <- the project question
     Consistent signal       overall detected and >= 50% of evaluable subgroups detected
     Discordant signal       overall detected but < 50% of evaluable subgroups detected
     Aggregate signal only   overall detected, no subgroup detected (subgroups too small to confirm)
     No signal               nothing detected overall or in any subgroup
   Absence of a signal is NOT evidence of safety: it can simply mean too few reports.

   SUBGROUP FINDING TYPES (one row per evaluable subgroup, a >= 3)
     Hidden       subgroup detected while the overall result is not
     Amplified    overall detected AND subgroup detected AND subgroup ROR >= 2x the rest
                  with a significant interaction (p < 0.05): the signal concentrates there
     Attenuated   overall detected but the subgroup is clearly weaker than the rest
                  (ratio of RORs <= 0.5, interaction p < 0.05, subgroup not detected)
     Other        evaluable but none of the above
   ============================================================================= */
USE faers_pv;

DROP TABLE IF EXISTS event_class;
CREATE TABLE event_class (
    analysis_id CHAR(2) NOT NULL, pt VARCHAR(255) NOT NULL,
    overall_cases INT, overall_comparator INT, overall_ror DOUBLE, overall_lci DOUBLE, overall_ic025 DOUBLE, overall_q_bh DOUBLE,
    overall_detected TINYINT, n_evaluable_subgroups INT, n_detected_subgroups INT, share_detected DOUBLE,
    event_class VARCHAR(30) NOT NULL,
    PRIMARY KEY (analysis_id, pt)
) ENGINE = InnoDB;

INSERT INTO event_class
SELECT o.analysis_id, o.pt, o.a, o.c, o.ror, o.ror_lci, o.ic025, o.q_bh, o.signal_detected,
       COALESCE(g.n_eval, 0), COALESCE(g.n_det, 0), g.n_det / NULLIF(g.n_eval, 0),
       CASE WHEN o.signal_detected = 0 AND COALESCE(g.n_det, 0) >= 1 THEN 'Hidden subgroup signal'
            WHEN o.signal_detected = 0 THEN 'No signal'
            WHEN COALESCE(g.n_det, 0) = 0 THEN 'Aggregate signal only'
            WHEN g.n_det / g.n_eval >= 0.5 THEN 'Consistent signal'
            ELSE 'Discordant signal' END
FROM signal_stats o
LEFT JOIN (SELECT analysis_id, pt, SUM(is_evaluable) AS n_eval, SUM(signal_detected) AS n_det
           FROM signal_stats
           WHERE stratum_type IN ('age', 'sex', 'age_sex', 'reporter', 'region', 'indication')
           GROUP BY analysis_id, pt) g ON g.analysis_id = o.analysis_id AND g.pt = o.pt
WHERE o.stratum_type = 'overall' AND o.is_evaluable = 1;

-- Subgroup findings: every evaluable subgroup row with its tests next to the overall result
DROP TABLE IF EXISTS subgroup_findings;
CREATE TABLE subgroup_findings (
    stat_id INT PRIMARY KEY, analysis_id CHAR(2) NOT NULL, pt VARCHAR(255) NOT NULL,
    stratum_type VARCHAR(12) NOT NULL, stratum_label VARCHAR(40) NOT NULL,
    a INT, c INT, n_target INT, n_comparator INT, ror DOUBLE, ror_lci DOUBLE, ror_uci DOUBLE, prr DOUBLE, ic025 DOUBLE,
    signal_detected TINYINT, q_bh DOUBLE,
    ratio_of_rors DOUBLE, ratio_lci DOUBLE, ratio_uci DOUBLE, p_interaction DOUBLE, p_heterogeneity DOUBLE,
    overall_detected TINYINT, overall_ror DOUBLE, overall_lci DOUBLE, event_class VARCHAR(30),
    finding_type VARCHAR(12) NOT NULL,
    INDEX ix_a_pt (analysis_id, pt), INDEX ix_type (finding_type)
) ENGINE = InnoDB;

INSERT INTO subgroup_findings
SELECT s.stat_id, s.analysis_id, s.pt, s.stratum_type, s.stratum_label, s.a, s.c, s.n_target, s.n_comparator,
       s.ror, s.ror_lci, s.ror_uci, s.prr, s.ic025, s.signal_detected, s.q_bh,
       v.ratio_of_rors, v.ratio_lci, v.ratio_uci, v.p_interaction, h.p_heterogeneity,
       e.overall_detected, e.overall_ror, e.overall_lci, e.event_class,
       CASE WHEN e.overall_detected = 0 AND s.signal_detected = 1 THEN 'Hidden'
            WHEN e.overall_detected = 1 AND s.signal_detected = 1 AND v.ratio_of_rors >= 2 AND v.p_interaction < 0.05 THEN 'Amplified'
            WHEN e.overall_detected = 1 AND s.signal_detected = 0 AND v.ratio_of_rors <= 0.5 AND v.p_interaction < 0.05 THEN 'Attenuated'
            ELSE 'Other' END
FROM signal_stats s
JOIN event_class e ON e.analysis_id = s.analysis_id AND e.pt = s.pt
LEFT JOIN subgroup_vs_rest v ON v.stat_id = s.stat_id
LEFT JOIN heterogeneity h ON h.analysis_id = s.analysis_id AND h.stratum_type = s.stratum_type AND h.pt = s.pt
WHERE s.is_evaluable = 1 AND s.stratum_type IN ('age', 'sex', 'age_sex', 'reporter', 'region', 'indication');

INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '12', 'Event classification', CONCAT(event_class, ' (events, ', analysis_id, ')'), COUNT(*), '' FROM event_class GROUP BY analysis_id, event_class;

-- 12.1 Event classification, primary analysis
SELECT event_class, COUNT(*) AS events, ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM event_class WHERE analysis_id = 'A1' GROUP BY event_class ORDER BY events DESC;

-- 12.2 Subgroup finding types (rows)
SELECT finding_type, COUNT(*) AS evaluable_subgroup_rows, COUNT(DISTINCT pt) AS events
FROM subgroup_findings WHERE analysis_id = 'A1' GROUP BY finding_type ORDER BY FIELD(finding_type, 'Hidden', 'Amplified', 'Attenuated', 'Other');

-- 12.3 Where do hidden signals come from? (rows by subgroup type)
SELECT stratum_type, COUNT(*) AS hidden_rows, COUNT(DISTINCT pt) AS events, SUM(a < 5) AS rows_with_3_or_4_cases
FROM subgroup_findings WHERE analysis_id = 'A1' AND finding_type = 'Hidden' GROUP BY stratum_type ORDER BY hidden_rows DESC;
