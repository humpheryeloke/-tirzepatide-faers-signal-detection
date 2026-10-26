/* =============================================================================
   13_robustness_and_evidence_tiers.sql
   Purpose : Test whether each hidden subgroup finding survives the checks a safety
             reviewer would ask for, and grade the evidence.

   CHECKS applied to every hidden finding (primary analysis A1)
     1  Enough cases        a >= 5 (three or four cases is too fragile to rank)
     2  Multiplicity        Benjamini-Hochberg q < 0.05 across all subgroup tests
     3  Real difference     subgroup-vs-rest interaction test p < 0.05 (script 09)
     4  Broader exposure    still detected when tirzepatide as SECONDARY suspect is also counted (A2)
     5  Class effect check  in A3 (comparator = other GLP-1 drugs) the subgroup ROR is still > 1
                            with >= 3 cases; if tirzepatide-specific, it should not vanish
     Context shown beside the tier (not used to grade): crude vs Mantel-Haenszel adjusted ROR,
     stability across the four quarters, seriousness, positive dechallenge.

   EVIDENCE TIERS (project-defined; NOT a regulatory classification)
     H3 Robust      checks 1-5 all met
     H2 Supported   checks 1-3 met
     H1 Candidate   detected in the subgroup but fails at least one of checks 1-3
   ============================================================================= */
USE faers_pv;

-- 13.1 Seriousness among tirzepatide cases with each event. FAERS OUTC lists outcomes only for serious reports, so serious share = cases with >=1 outcome record / all cases with the event (NOT / cases with outcome info, which is always 100%).
DROP TABLE IF EXISTS event_outcome_profile;
CREATE TABLE event_outcome_profile (
    pt VARCHAR(255) PRIMARY KEY, target_cases INT, with_outcome_info INT, death INT, life_threatening INT,
    hospitalisation INT, disability_or_intervention INT, any_serious INT, positive_dechallenge INT
) ENGINE = InnoDB;
INSERT INTO event_outcome_profile
SELECT e.pt, COUNT(*), SUM(o.caseid IS NOT NULL), COALESCE(SUM(o.death), 0), COALESCE(SUM(o.life_threatening), 0),
       COALESCE(SUM(o.hospitalisation), 0), COALESCE(SUM(o.disability), 0),
       COALESCE(SUM(o.death OR o.life_threatening OR o.hospitalisation OR o.disability OR o.other_serious), 0),
       SUM(x.tirz_dechal_positive = 1)
FROM analysis_case ac
JOIN case_event e ON e.caseid = ac.caseid
JOIN candidate_pt cp ON cp.pt = e.pt
LEFT JOIN case_outcome o ON o.caseid = ac.caseid
LEFT JOIN case_exposure x ON x.caseid = ac.caseid
WHERE ac.analysis_id = 'A1' AND ac.grp = 'T'
GROUP BY e.pt;

-- 13.2 Stability over time: in how many of the 4 quarters is the event (overall population) disproportionate?
DROP TABLE IF EXISTS event_quarter_stability;
CREATE TABLE event_quarter_stability (
    pt VARCHAR(255) PRIMARY KEY, quarters_evaluable INT, quarters_ror_above_1 INT, p_heterogeneity_quarters DOUBLE
) ENGINE = InnoDB;
INSERT INTO event_quarter_stability
SELECT q.pt, SUM(q.is_evaluable), SUM(q.is_evaluable = 1 AND q.ror > 1), h.p_heterogeneity
FROM signal_stats q
LEFT JOIN heterogeneity h ON h.analysis_id = q.analysis_id AND h.stratum_type = 'quarter' AND h.pt = q.pt
WHERE q.analysis_id = 'A1' AND q.stratum_type = 'quarter'
GROUP BY q.pt, h.p_heterogeneity;

-- 13.3 Hidden findings with all checks
DROP TABLE IF EXISTS hidden_signals;
CREATE TABLE hidden_signals (
    stat_id INT PRIMARY KEY, pt VARCHAR(255) NOT NULL, event_type VARCHAR(24), clinical_area VARCHAR(40),
    stratum_type VARCHAR(12), stratum_label VARCHAR(40),
    subgroup_cases INT, subgroup_comparator_cases INT, ror DOUBLE, ror_lci DOUBLE, ror_uci DOUBLE, ic025 DOUBLE, prr DOUBLE,
    overall_cases INT, overall_ror DOUBLE, overall_lci DOUBLE, ror_adjusted_overall DOUBLE, lci_adjusted_overall DOUBLE,
    q_bh DOUBLE, ratio_of_rors DOUBLE, ratio_lci DOUBLE, p_interaction DOUBLE, p_heterogeneity_type DOUBLE,
    a2_detected TINYINT, a3_cases INT, a3_ror DOUBLE, a3_lci DOUBLE,
    check_cases_ge5 TINYINT, check_q_lt_005 TINYINT, check_interaction_lt_005 TINYINT, check_a2 TINYINT, check_a3 TINYINT,
    evidence_tier VARCHAR(14) NOT NULL,
    quarters_evaluable INT, quarters_ror_above_1 INT,
    serious_share DOUBLE, death_cases INT, hospitalisation_cases INT
) ENGINE = InnoDB;

INSERT INTO hidden_signals
SELECT f.stat_id, f.pt, ec.event_type, ec.clinical_area, f.stratum_type, f.stratum_label,
       f.a, f.c, f.ror, f.ror_lci, f.ror_uci, f.ic025, f.prr,
       e.overall_cases, e.overall_ror, e.overall_lci, adj.ror_mh, adj.ror_mh_lci,
       f.q_bh, f.ratio_of_rors, f.ratio_lci, f.p_interaction, f.p_heterogeneity,
       COALESCE(s2.signal_detected, 0), s3.a, s3.ror, s3.ror_lci,
       f.a >= 5, f.q_bh < 0.05, f.p_interaction < 0.05, COALESCE(s2.signal_detected, 0) = 1,
       (s3.a >= 3 AND s3.ror > 1),
       CASE WHEN f.a >= 5 AND f.q_bh < 0.05 AND f.p_interaction < 0.05 AND COALESCE(s2.signal_detected, 0) = 1 AND s3.a >= 3 AND s3.ror > 1 THEN 'H3 Robust'
            WHEN f.a >= 5 AND f.q_bh < 0.05 AND f.p_interaction < 0.05 THEN 'H2 Supported'
            ELSE 'H1 Candidate' END,
       qs.quarters_evaluable, qs.quarters_ror_above_1,
       op.any_serious / NULLIF(op.target_cases, 0), op.death, op.hospitalisation
FROM subgroup_findings f
JOIN event_class e ON e.analysis_id = f.analysis_id AND e.pt = f.pt
JOIN event_catalogue ec ON ec.pt = f.pt
LEFT JOIN signal_adjusted adj ON adj.analysis_id = 'A1' AND adj.pt = f.pt
LEFT JOIN signal_stats s2 ON s2.analysis_id = 'A2' AND s2.stratum_type = f.stratum_type AND s2.stratum_label = f.stratum_label AND s2.pt = f.pt
LEFT JOIN signal_stats s3 ON s3.analysis_id = 'A3' AND s3.stratum_type = f.stratum_type AND s3.stratum_label = f.stratum_label AND s3.pt = f.pt
LEFT JOIN event_quarter_stability qs ON qs.pt = f.pt
LEFT JOIN event_outcome_profile op ON op.pt = f.pt
WHERE f.analysis_id = 'A1' AND f.finding_type = 'Hidden';

INSERT INTO etl_log (step_no, step_name, metric, row_count, note)
SELECT '13', 'Evidence tiers', CONCAT('Hidden subgroup findings: ', evidence_tier), COUNT(*), 'rows (event x subgroup)' FROM hidden_signals GROUP BY evidence_tier;

-- 13.4 Results
SELECT evidence_tier, event_type, COUNT(*) AS findings, COUNT(DISTINCT pt) AS events
FROM hidden_signals GROUP BY evidence_tier, event_type ORDER BY evidence_tier, event_type;

SELECT pt, stratum_type, stratum_label, subgroup_cases AS cases, ROUND(ror, 1) AS ror, ROUND(ror_lci, 1) AS lci,
       ROUND(overall_ror, 2) AS overall_ror, ROUND(q_bh, 4) AS q, ROUND(p_interaction, 4) AS p_int, a3_cases, ROUND(a3_ror, 1) AS a3_ror, evidence_tier
FROM hidden_signals WHERE evidence_tier IN ('H3 Robust', 'H2 Supported') ORDER BY evidence_tier DESC, event_type, ror_lci DESC LIMIT 60;
