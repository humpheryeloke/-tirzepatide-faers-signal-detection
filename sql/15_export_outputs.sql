/* =============================================================================
   15_export_outputs.sql
   Purpose : Define the final result sets that feed the dashboard, Excel workbook and report.
   Each view below is exported to outputs/*.csv by sql/export_csv.sh (mysql client, tab -> comma).
   Power BI imports the same CSVs, so every number in the dashboard traces back to this script.
   ============================================================================= */
USE faers_pv;

CREATE OR REPLACE VIEW out_event_overview AS
SELECT e.pt, c.event_type, c.clinical_area, e.event_class, e.overall_cases AS tirzepatide_cases,
       ROUND(e.overall_ror, 2) AS ror, ROUND(e.overall_lci, 2) AS ror_lci, ROUND(e.overall_ic025, 2) AS ic025,
       ROUND(e.overall_q_bh, 4) AS q_bh, e.overall_detected, e.n_evaluable_subgroups, e.n_detected_subgroups,
       ROUND(a.ror_mh, 2) AS ror_adjusted, ROUND(a.ror_mh_lci, 2) AS ror_adjusted_lci,
       ROUND(o.any_serious / NULLIF(o.target_cases, 0), 3) AS serious_share, o.death AS death_cases,
       o.hospitalisation AS hospitalisation_cases, o.positive_dechallenge
FROM event_class e
JOIN event_catalogue c ON c.pt = e.pt
LEFT JOIN signal_adjusted a ON a.analysis_id = e.analysis_id AND a.pt = e.pt
LEFT JOIN event_outcome_profile o ON o.pt = e.pt
WHERE e.analysis_id = 'A1';

CREATE OR REPLACE VIEW out_hidden_signals AS
SELECT priority, evidence_tier, pt, event_type, clinical_area, stratum_type, stratum_family, stratum_label,
       subgroup_cases, ROUND(ror, 2) AS ror, ROUND(ror_lci, 2) AS ror_lci, ROUND(ror_uci, 2) AS ror_uci, ROUND(ic025, 2) AS ic025,
       ROUND(overall_ror, 2) AS overall_ror, ROUND(overall_lci, 2) AS overall_lci, ROUND(q_bh, 5) AS q_bh,
       ROUND(ratio_of_rors, 2) AS ratio_of_rors, ROUND(p_interaction, 5) AS p_interaction,
       a2_detected, a3_cases, ROUND(a3_ror, 2) AS a3_ror, quarters_evaluable, quarters_ror_above_1,
       ROUND(serious_share, 3) AS serious_share, death_cases, hospitalisation_cases
FROM hidden_signals_prioritised;

CREATE OR REPLACE VIEW out_subgroup_results AS
SELECT s.stratum_type, s.stratum_label, s.pt, c.event_type, c.clinical_area, s.a AS cases, s.n_target, s.n_comparator,
       ROUND(s.ror, 2) AS ror, ROUND(s.ror_lci, 2) AS ror_lci, ROUND(s.ror_uci, 2) AS ror_uci, ROUND(s.prr, 2) AS prr,
       ROUND(s.ic025, 2) AS ic025, ROUND(s.q_bh, 5) AS q_bh, s.signal_detected, s.signal_strong
FROM signal_stats s JOIN event_catalogue c ON c.pt = s.pt
WHERE s.analysis_id = 'A1' AND s.stratum_type <> 'overall' AND s.is_evaluable = 1;

CREATE OR REPLACE VIEW out_stratum_sizes AS
SELECT analysis_id, stratum_type, stratum_label, n_target, n_comparator FROM stratum_n;

CREATE OR REPLACE VIEW out_cleaning_log AS
SELECT log_id, step_no, step_name, metric, row_count, note FROM etl_log ORDER BY log_id;

CREATE OR REPLACE VIEW out_kpi AS SELECT kpi_no, kpi, ROUND(value_num, 2) AS value, numerator, denominator, definition FROM kpi_summary;
