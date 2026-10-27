# Hidden Adverse-Event Signals in Tirzepatide Reports (FDA FAERS 2025)

A stratified disproportionality analysis that looks for adverse events that are **not** over-reported in the whole population but **are** over-reported inside a subgroup (sex, age, region, reporter type, indication). Built in MySQL from the raw FAERS quarterly files.

**[Open the interactive dashboard](dashboard/index.html)** (download the repo and open the file in a browser) · [Full report](docs/Tirzepatide_FAERS_Signal_Report.docx) · [Excel results](excel/Tirzepatide_FAERS_Subgroup_Signals.xlsx)

> **Interpretation note:** this is an exploratory analysis of spontaneous reports. Observed patterns are statistical associations and do not show that tirzepatide caused any event. Findings are leads for case review, not medical advice or individual clinical guidance.

## Question
Pooled signal screening can miss events concentrated in one group. Which tirzepatide events show that pattern, and how strong is the evidence for each?

## Data
FDA FAERS public quarterly ASCII files, 2025 Q1–Q4 (DEMO, DRUG, REAC, OUTC, INDI and deleted-case lists). 1,617,444 report rows → 1,465,808 unique cases → 1,440,079 after duplicate removal; 58,877 had tirzepatide as primary suspect. Raw files are not stored here (size). Download them from the [FDA FAERS page](https://www.fda.gov/drugs/fdas-adverse-event-reporting-system-faers/fda-adverse-event-reporting-system-faers-latest-quarterly-data-files) and place each quarter under `data/raw/2025Q1` … `2025Q4`.

## Method (standard pharmacovigilance practice)
* **Case-level cleaning:** FDA deleted cases removed, latest version kept, conservative cross-source duplicate rule.
* **Disproportionality:** ROR, PRR (Evans 2001) and Bayesian IC / IC025 (Bate 1998; Norén 2006). Detected = ≥3 cases, ROR lower 95% CI > 1 and IC025 > 0. Consistent with EMA GVP Module IX and CIOMS VIII.
* **Subgroups:** same test inside every stratum; Cochran Q heterogeneity; subgroup-vs-rest ratio-of-RORs test; Benjamini–Hochberg FDR; Mantel–Haenszel adjusted ROR (age × sex × quarter).
* **Sensitivity:** A2 (primary + secondary suspect), A3 (active comparator: other GLP-1 drugs).
* **Evidence tiers H1–H3** and **priority P1–P3/PU** are my own ranking conventions, defined in `sql/13` and `sql/14`.

## Key results
| | |
|---|---|
| Events tested | 1,406 |
| Detected in the pooled analysis | 168 (11.9%) |
| **Hidden subgroup signals** | **160 events, 250 event × subgroup findings** |
| Passing all five robustness checks (H3) | 101 findings |
| Highest-priority (robust, patient-characteristic subgroup) | 7 findings: liver function tests (age 18–44), vitreous detachment (men), cholangitis (men), dysgeusia (men), colitis (diabetes indication), micturition urgency (men 18–44) |

Region and reporter-type findings are the majority but mainly reflect how cases are reported (tirzepatide reports are 95% consumer-reported), so they are ranked lower.

## Dashboard pages
The interactive dashboard (`dashboard/index.html`) has four pages:
1. **Overview:** headline KPIs, what the pooled screen finds versus misses, hidden findings by subgroup and evidence tier, priority leads, and the case-flow funnel.
2. **Hidden-signal explorer:** filter findings by priority, evidence tier, subgroup type, clinical area and minimum cases; ranked forest plot of subgroup ROR with 95% CI.
3. **Event drill-through:** pick any event to see its ROR in every subgroup, its adjusted ROR, seriousness and which subgroups meet the detection rule.
4. **Method & caveats:** data flow, statistical methods, evidence tiers, limitations and references.

## Run it yourself
1. Install MySQL 8 and enable `local_infile` (`SET GLOBAL local_infile=1;`).
2. Place the raw files as described above.
3. From the repo root: `mysql --local-infile=1 -u root -p < sql/99_run_all.sql` (about 40–60 minutes; script 07 is the slow step).
4. `sh sql/export_csv.sh` writes the CSVs in `outputs/`.

## Structure
```
sql/        00 setup · 01–02 load · 03 audit · 04–06 clean & build · 07–10 statistics · 11–14 classify, grade, prioritise · 15 exports · 99 run all
outputs/    result CSVs (feed the dashboard and Excel workbook)
dashboard/  index.html (interactive, self-contained)
excel/      results workbook
docs/       report, data dictionary, executive summary
```

## Limitations
Spontaneous reports have no denominator, so findings are not incidence and not causation. Under-reporting and stimulated reporting vary. Adjustment covers age, sex and quarter only. About 40% of cases lack usable age. Events are MedDRA preferred terms, not grouped. Absence of a signal is not evidence of safety. Findings are leads for case review, not clinical conclusions.

## Tools
* **MySQL 8:** all cleaning, statistics and classification
* **Excel:** results workbook with formula-driven summary
* **HTML / JavaScript:** interactive dashboard

## References
Evans 2001; van Puijenbroek 2002; Bate 1998; Norén 2006; Mantel & Haenszel 1959; Robins, Breslow & Greenland 1986; Benjamini & Hochberg 1995; Gelman & Stern 2006; EMA GVP IX; CIOMS VIII. Full list in the report.

## Author
Humphery Chinedu Eloke · Pharmacology · pharmacovigilance data analysis
