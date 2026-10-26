/* =============================================================================
   99_run_all.sql  -  runs the whole pipeline in order.
   From the repo root:  mysql --local-infile=1 -u root -p < sql/99_run_all.sql
   Expected total run time: about 40-60 minutes (script 07 is the slow step).
   Raw FAERS files must first be placed in data/raw/2025Q1 ... 2025Q4 (see README).
   ============================================================================= */
SOURCE sql/00_setup_database.sql;
SOURCE sql/01_create_raw_tables.sql;
SOURCE sql/02_load_raw_data.sql;
SOURCE sql/03_raw_data_audit.sql;
SOURCE sql/04_clean_cases.sql;
SOURCE sql/05_standardise_drugs.sql;
SOURCE sql/06_build_analysis_dataset.sql;
SOURCE sql/07_build_contingency_tables.sql;
SOURCE sql/08_disproportionality_analysis.sql;
SOURCE sql/09_subgroup_interaction_tests.sql;
SOURCE sql/10_adjusted_analysis_mantel_haenszel.sql;
SOURCE sql/11_event_catalogue.sql;
SOURCE sql/12_event_classification_and_subgroup_findings.sql;
SOURCE sql/13_robustness_and_evidence_tiers.sql;
SOURCE sql/14_prioritisation_and_kpis.sql;
SOURCE sql/15_export_outputs.sql;
