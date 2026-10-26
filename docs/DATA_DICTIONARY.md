# Data dictionary (output files in `outputs/`)

## event_overview.csv — one row per adverse-event term (primary analysis A1)
| Column | Meaning |
|---|---|
| pt | MedDRA Preferred Term |
| event_type | Clinical, or Product/administration |
| clinical_area | Keyword grouping built for navigation (not MedDRA SOC) |
| event_class | No signal / Hidden subgroup signal / Consistent signal / Discordant signal / Aggregate signal only |
| tirzepatide_cases | Cases with the event, tirzepatide primary suspect |
| ror, ror_lci | Reporting odds ratio and lower 95% limit, overall |
| ic025 | Lower 95% credibility bound of the Information Component |
| q_bh | Benjamini–Hochberg adjusted p-value |
| overall_detected | 1 if ≥3 cases, ROR lower limit >1 and IC025 >0 |
| n_evaluable_subgroups / n_detected_subgroups | Subgroups with ≥3 cases / in which the rule is met |
| ror_adjusted, ror_adjusted_lci | Mantel–Haenszel ROR adjusted for age × sex × quarter |
| serious_share | Share of tirzepatide cases with the event that have ≥1 serious outcome (event-wide) |
| death_cases, hospitalisation_cases, positive_dechallenge | Event-wide counts among tirzepatide cases |

## hidden_signals.csv — one row per hidden event × subgroup finding
Adds: priority (P1/P2/P3/PU), evidence_tier (H1–H3), stratum_type, stratum_label, stratum_family, subgroup_cases, ror / ror_lci / ror_uci, ratio_of_rors, p_interaction, a2_detected (1 = still detected with secondary-suspect reports), a3_cases / a3_ror (vs other GLP-1 drugs), quarters_ror_above_1 / quarters_evaluable.

## subgroup_results.csv — every evaluable event × subgroup result (A1)
cases, n_target, n_comparator, ror, ror_lci, ror_uci, prr, ic025, q_bh, signal_detected, signal_strong.

## stratum_sizes.csv, cleaning_log.csv, kpi.csv
Subgroup sizes; row counts at every cleaning step; headline KPIs with numerator, denominator and definition.

## KPI definitions
| KPI | Numerator | Denominator | Reading |
|---|---|---|---|
| Events with overall signal % | Events meeting the detection rule overall | Events tested (≥3 cases) | How much the pooled screen finds |
| Hidden event share % | Events detected only in a subgroup | Events tested | How much the pooled screen misses |
| Robust share of hidden findings | H3 findings | All hidden findings | How much survives the checks |
| Serious share | Cases with the event and ≥1 serious outcome | Cases with the event | Clinical weight of an event (event-wide) |
Limitations: all are counts of reports, not rates of occurrence in patients.
