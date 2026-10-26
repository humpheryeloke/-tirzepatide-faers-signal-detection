/* =============================================================================
   01_create_raw_tables.sql
   Purpose : Landing ("raw") tables that mirror the FAERS ASCII quarterly files.
   Rule    : Nothing is cleaned here. Every column is loaded as text exactly as FDA
             published it, plus src_quarter so each row can be traced to its file.
   Files   : DEMO (case demographics/administrative), DRUG, REAC (reactions, MedDRA PT),
             OUTC (outcomes), INDI (indications) and the quarterly DELETE list.
             THER (therapy dates) and RPSR (report sources) are not used in this
             project and are not loaded.
   ============================================================================= */
USE faers_pv;

DROP TABLE IF EXISTS raw_demo, raw_drug, raw_reac, raw_outc, raw_indi, raw_deleted;

CREATE TABLE raw_demo (
    primaryid VARCHAR(20), caseid VARCHAR(20), caseversion VARCHAR(10), i_f_code VARCHAR(5),
    event_dt VARCHAR(10), mfr_dt VARCHAR(10), init_fda_dt VARCHAR(10), fda_dt VARCHAR(10),
    rept_cod VARCHAR(10), auth_num VARCHAR(100), mfr_num VARCHAR(100), mfr_sndr VARCHAR(100),
    lit_ref TEXT, age VARCHAR(20), age_cod VARCHAR(10), age_grp VARCHAR(5), sex VARCHAR(5),
    e_sub VARCHAR(5), wt VARCHAR(20), wt_cod VARCHAR(10), rept_dt VARCHAR(10), to_mfr VARCHAR(5),
    occp_cod VARCHAR(10), reporter_country VARCHAR(60), occr_country VARCHAR(60),
    src_quarter CHAR(6) NOT NULL
) ENGINE = InnoDB;

-- DRUG: only the columns used downstream are kept (the dose/lot/expiry columns are skipped on load)
CREATE TABLE raw_drug (
    primaryid VARCHAR(20), caseid VARCHAR(20), drug_seq VARCHAR(10), role_cod VARCHAR(5),
    drugname VARCHAR(500), prod_ai VARCHAR(500), route VARCHAR(60),
    dechal VARCHAR(5), rechal VARCHAR(5), nda_num VARCHAR(30),
    src_quarter CHAR(6) NOT NULL
) ENGINE = InnoDB;

CREATE TABLE raw_reac (
    primaryid VARCHAR(20), caseid VARCHAR(20), pt VARCHAR(255), drug_rec_act VARCHAR(255),
    src_quarter CHAR(6) NOT NULL
) ENGINE = InnoDB;

CREATE TABLE raw_outc (
    primaryid VARCHAR(20), caseid VARCHAR(20), outc_cod VARCHAR(5),
    src_quarter CHAR(6) NOT NULL
) ENGINE = InnoDB;

CREATE TABLE raw_indi (
    primaryid VARCHAR(20), caseid VARCHAR(20), indi_drug_seq VARCHAR(10), indi_pt VARCHAR(255),
    src_quarter CHAR(6) NOT NULL
) ENGINE = InnoDB;

CREATE TABLE raw_deleted (
    caseid VARCHAR(20), src_quarter CHAR(6) NOT NULL
) ENGINE = InnoDB;
