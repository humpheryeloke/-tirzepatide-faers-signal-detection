# Executive summary

**Question.** Does the standard pooled screen of tirzepatide adverse-event reports miss events that are concentrated in a subgroup?

**What I did.** Cleaned the raw FDA FAERS 2025 files (1.6 million report rows to 1.44 million unique cases, 58,877 with tirzepatide as primary suspect) and tested 1,406 adverse-event terms overall and within sex, age, region, reporter and indication subgroups, using ROR, PRR and Bayesian IC with false-discovery control and Mantel–Haenszel adjustment.

**What I found.**
* 168 events (11.9%) are flagged in the pooled analysis; a further 160 (11.4%) are flagged **only** inside a subgroup.
* 101 of 250 hidden findings pass all five robustness checks. Most are in non-US or reporter-type subgroups and mainly reflect reporting context.
* Seven robust findings are in patient-characteristic subgroups and are the first candidates for case review: liver function tests in adults 18–44 (most consistent), vitreous detachment, cholangitis and dysgeusia in men, colitis in the diabetes indication, and micturition urgency in men 18–44.

**What to do.** Case-level medical review of the seven priority findings; compare with the current product labels; repeat the analysis on healthcare-professional reports only and on later quarters. Success = findings confirmed, matched to labelled events, or closed as reporting artefacts.

**Caution.** FAERS has no denominator and cannot show causation. These are leads, not risks.
