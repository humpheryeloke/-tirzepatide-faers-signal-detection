/* =============================================================================
   14_prioritisation_and_kpis.sql
   Purpose : Turn graded findings into a review list a safety physician could use,
             and compute the headline KPIs.

   WHY region and reporter strata are treated differently from sex/age/indication:
   A "Non-US" or "Consumer" subgroup differs from its comparison group in HOW cases are
   reported (reporting culture, regulatory rules, product use patterns), not only in biology.
   A hidden finding in those strata is a reporting-composition signal until shown otherwise.
   Sex, age and indication are patient characteristics, so a finding there is a stronger lead
   for pharmacological or population explanations. This is a triage rule, not proof either way.

   PRIORITY (project-defined triage, not a regulatory classification)
     P1  Clinical event, H3, patient-characteristic stratum (sex / age / age x sex / indication)
     P2  Clinical event, H3 in region or reporter stratum, OR H2 in a patient-characteristic stratum
     P3  Any other clinical finding (H2 reporting-type strata, or H1)
     PU  Product-use / administration events (device, dosing, storage) - handled as quality
         and usability questions, not safety signals
   ============================================================================= */
USE faers_pv;

DROP TABLE IF EXISTS hidden_signals_prioritised;
CREATE TABLE hidden_signals_prioritised AS
SELECT h.*,
       CASE WHEN h.stratum_type IN ('sex','age','age_sex','indication') THEN 'Patient characteristic' ELSE 'Reporting context' END AS stratum_family,
       CASE WHEN h.event_type <> 'Clinical' THEN 'PU'
            WHEN h.evidence_tier = 'H3 Robust' AND h.stratum_type IN ('sex','age','age_sex','indication') THEN 'P1'
            WHEN h.evidence_tier = 'H3 Robust' THEN 'P2'
            WHEN h.evidence_tier = 'H2 Supported' AND h.stratum_type IN ('sex','age','age_sex','indication') THEN 'P2'
            ELSE 'P3' END AS priority,
       CASE WHEN h.overall_lci > 1 THEN 'Also disproportionate overall' ELSE 'Not disproportionate overall' END AS overall_status
FROM hidden_signals h;
ALTER TABLE hidden_signals_prioritised ADD PRIMARY KEY (stat_id);

-- 14.1 Counts by priority
SELECT priority, stratum_family, COUNT(*) AS findings, COUNT(DISTINCT pt) AS events
FROM hidden_signals_prioritised GROUP BY priority, stratum_family ORDER BY priority, stratum_family;

-- 14.2 KPI table (one row per KPI, definition kept beside the value)
DROP TABLE IF EXISTS kpi_summary;
CREATE TABLE kpi_summary (kpi_no INT PRIMARY KEY, kpi VARCHAR(80), value_num DOUBLE, value_text VARCHAR(40), numerator VARCHAR(120), denominator VARCHAR(120), definition VARCHAR(300));

INSERT INTO kpi_summary VALUES
(1, 'Clean unique cases (2025)', (SELECT COUNT(*) FROM clean_case), NULL, 'Cases after deletion, version and duplicate rules', NULL, 'Unique FAERS cases remaining after cleaning'),
(2, 'Tirzepatide cases (primary suspect)', (SELECT COUNT(DISTINCT caseid) FROM analysis_case WHERE analysis_id='A1' AND grp='T'), NULL, 'Unique cases with tirzepatide as primary suspect', NULL, 'Exposure group for the primary analysis (A1)'),
(3, 'Events tested', (SELECT COUNT(*) FROM event_class WHERE analysis_id='A1'), NULL, 'Preferred terms meeting the minimum-count rule', NULL, 'Events carried into disproportionality testing'),
(4, 'Events with overall signal (%)', (SELECT 100*SUM(event_class IN ('Consistent signal','Discordant signal','Aggregate signal only'))/COUNT(*) FROM event_class WHERE analysis_id='A1'), NULL, 'Events detected overall', 'Events tested', 'Share of tested events meeting the detection rule in the whole population'),
(5, 'Events with a hidden subgroup signal', (SELECT COUNT(*) FROM event_class WHERE analysis_id='A1' AND event_class='Hidden subgroup signal'), NULL, 'Events not detected overall but detected in a subgroup', NULL, 'Events whose signal appears only inside a subgroup'),
(6, 'Robust hidden findings (H3)', (SELECT COUNT(*) FROM hidden_signals WHERE evidence_tier='H3 Robust'), NULL, 'Event x subgroup findings passing all five checks', NULL, 'Strongest evidence tier'),
(7, 'Priority P1 findings', (SELECT COUNT(*) FROM hidden_signals_prioritised WHERE priority='P1'), NULL, 'H3, clinical event, patient-characteristic stratum', NULL, 'Highest-priority leads for medical review');
