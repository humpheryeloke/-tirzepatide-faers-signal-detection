/* =============================================================================
   02_load_raw_data.sql
   Purpose : Load the four quarterly FAERS ASCII extracts into the raw_* tables.
   Before running
     1. Download the quarterly ASCII zips from the FDA FAERS Quarterly Data Extract page.
     2. Unzip each into  data/raw/2025Q1 ... data/raw/2025Q4  (the zip's ASCII/ and Deleted/
        folders must sit directly inside).
     3. Start the client from the repository root with local_infile enabled:
            mysql --local-infile=1 -u <user> -p
        and on the server:  SET GLOBAL local_infile = 1;
     (MySQL Workbench: Edit Connection > Advanced > add OPT_LOCAL_INFILE=1)
   File format : '$'-delimited, one header row (DELETE files: none).
   Line endings differ by file: DRUG files use CRLF (\r\n); DEMO, REAC, OUTC, INDI and DELETE files use LF (\n).
   Using the wrong terminator loads zero rows without an error, so row counts are verified in script 03.
   ============================================================================= */
USE faers_pv;
SET SESSION sql_mode = 'NO_ENGINE_SUBSTITUTION';   -- do not abort on over-long free text; row counts are checked in script 03
TRUNCATE raw_demo; TRUNCATE raw_drug; TRUNCATE raw_reac; TRUNCATE raw_outc; TRUNCATE raw_indi; TRUNCATE raw_deleted;


-- ---------------------------------------------------------------- 2025Q1
LOAD DATA LOCAL INFILE 'data/raw/2025Q1/ASCII/DEMO25Q1.txt' INTO TABLE raw_demo
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, caseversion, i_f_code, event_dt, mfr_dt, init_fda_dt, fda_dt, rept_cod, auth_num, mfr_num, mfr_sndr,
   lit_ref, age, age_cod, age_grp, sex, e_sub, wt, wt_cod, rept_dt, to_mfr, occp_cod, reporter_country, occr_country)
  SET src_quarter = '2025Q1';
LOAD DATA LOCAL INFILE 'data/raw/2025Q1/ASCII/DRUG25Q1.txt' INTO TABLE raw_drug
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\r\n' IGNORE 1 LINES
  (primaryid, caseid, drug_seq, role_cod, drugname, prod_ai, @val_vbm, route, @dose_vbm, @cum_dose_chr, @cum_dose_unit,
   dechal, rechal, @lot_num, @exp_dt, nda_num, @dose_amt, @dose_unit, @dose_form, @dose_freq)
  SET src_quarter = '2025Q1';
LOAD DATA LOCAL INFILE 'data/raw/2025Q1/ASCII/REAC25Q1.txt' INTO TABLE raw_reac
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, pt, drug_rec_act) SET src_quarter = '2025Q1';
LOAD DATA LOCAL INFILE 'data/raw/2025Q1/ASCII/OUTC25Q1.txt' INTO TABLE raw_outc
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, outc_cod) SET src_quarter = '2025Q1';
LOAD DATA LOCAL INFILE 'data/raw/2025Q1/ASCII/INDI25Q1.txt' INTO TABLE raw_indi
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, indi_drug_seq, indi_pt) SET src_quarter = '2025Q1';
LOAD DATA LOCAL INFILE 'data/raw/2025Q1/Deleted/DELETE25Q1.txt' INTO TABLE raw_deleted
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n'
  (caseid) SET src_quarter = '2025Q1';

-- ---------------------------------------------------------------- 2025Q2
LOAD DATA LOCAL INFILE 'data/raw/2025Q2/ASCII/DEMO25Q2.txt' INTO TABLE raw_demo
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, caseversion, i_f_code, event_dt, mfr_dt, init_fda_dt, fda_dt, rept_cod, auth_num, mfr_num, mfr_sndr,
   lit_ref, age, age_cod, age_grp, sex, e_sub, wt, wt_cod, rept_dt, to_mfr, occp_cod, reporter_country, occr_country)
  SET src_quarter = '2025Q2';
LOAD DATA LOCAL INFILE 'data/raw/2025Q2/ASCII/DRUG25Q2.txt' INTO TABLE raw_drug
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\r\n' IGNORE 1 LINES
  (primaryid, caseid, drug_seq, role_cod, drugname, prod_ai, @val_vbm, route, @dose_vbm, @cum_dose_chr, @cum_dose_unit,
   dechal, rechal, @lot_num, @exp_dt, nda_num, @dose_amt, @dose_unit, @dose_form, @dose_freq)
  SET src_quarter = '2025Q2';
LOAD DATA LOCAL INFILE 'data/raw/2025Q2/ASCII/REAC25Q2.txt' INTO TABLE raw_reac
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, pt, drug_rec_act) SET src_quarter = '2025Q2';
LOAD DATA LOCAL INFILE 'data/raw/2025Q2/ASCII/OUTC25Q2.txt' INTO TABLE raw_outc
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, outc_cod) SET src_quarter = '2025Q2';
LOAD DATA LOCAL INFILE 'data/raw/2025Q2/ASCII/INDI25Q2.txt' INTO TABLE raw_indi
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, indi_drug_seq, indi_pt) SET src_quarter = '2025Q2';
LOAD DATA LOCAL INFILE 'data/raw/2025Q2/Deleted/DELETE25Q2.txt' INTO TABLE raw_deleted
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n'
  (caseid) SET src_quarter = '2025Q2';

-- ---------------------------------------------------------------- 2025Q3
LOAD DATA LOCAL INFILE 'data/raw/2025Q3/ASCII/DEMO25Q3.txt' INTO TABLE raw_demo
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, caseversion, i_f_code, event_dt, mfr_dt, init_fda_dt, fda_dt, rept_cod, auth_num, mfr_num, mfr_sndr,
   lit_ref, age, age_cod, age_grp, sex, e_sub, wt, wt_cod, rept_dt, to_mfr, occp_cod, reporter_country, occr_country)
  SET src_quarter = '2025Q3';
LOAD DATA LOCAL INFILE 'data/raw/2025Q3/ASCII/DRUG25Q3.txt' INTO TABLE raw_drug
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\r\n' IGNORE 1 LINES
  (primaryid, caseid, drug_seq, role_cod, drugname, prod_ai, @val_vbm, route, @dose_vbm, @cum_dose_chr, @cum_dose_unit,
   dechal, rechal, @lot_num, @exp_dt, nda_num, @dose_amt, @dose_unit, @dose_form, @dose_freq)
  SET src_quarter = '2025Q3';
LOAD DATA LOCAL INFILE 'data/raw/2025Q3/ASCII/REAC25Q3.txt' INTO TABLE raw_reac
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, pt, drug_rec_act) SET src_quarter = '2025Q3';
LOAD DATA LOCAL INFILE 'data/raw/2025Q3/ASCII/OUTC25Q3.txt' INTO TABLE raw_outc
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, outc_cod) SET src_quarter = '2025Q3';
LOAD DATA LOCAL INFILE 'data/raw/2025Q3/ASCII/INDI25Q3.txt' INTO TABLE raw_indi
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, indi_drug_seq, indi_pt) SET src_quarter = '2025Q3';
LOAD DATA LOCAL INFILE 'data/raw/2025Q3/Deleted/DELETE25Q3.txt' INTO TABLE raw_deleted
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n'
  (caseid) SET src_quarter = '2025Q3';

-- ---------------------------------------------------------------- 2025Q4
LOAD DATA LOCAL INFILE 'data/raw/2025Q4/ASCII/DEMO25Q4.txt' INTO TABLE raw_demo
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, caseversion, i_f_code, event_dt, mfr_dt, init_fda_dt, fda_dt, rept_cod, auth_num, mfr_num, mfr_sndr,
   lit_ref, age, age_cod, age_grp, sex, e_sub, wt, wt_cod, rept_dt, to_mfr, occp_cod, reporter_country, occr_country)
  SET src_quarter = '2025Q4';
LOAD DATA LOCAL INFILE 'data/raw/2025Q4/ASCII/DRUG25Q4.txt' INTO TABLE raw_drug
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\r\n' IGNORE 1 LINES
  (primaryid, caseid, drug_seq, role_cod, drugname, prod_ai, @val_vbm, route, @dose_vbm, @cum_dose_chr, @cum_dose_unit,
   dechal, rechal, @lot_num, @exp_dt, nda_num, @dose_amt, @dose_unit, @dose_form, @dose_freq)
  SET src_quarter = '2025Q4';
LOAD DATA LOCAL INFILE 'data/raw/2025Q4/ASCII/REAC25Q4.txt' INTO TABLE raw_reac
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, pt, drug_rec_act) SET src_quarter = '2025Q4';
LOAD DATA LOCAL INFILE 'data/raw/2025Q4/ASCII/OUTC25Q4.txt' INTO TABLE raw_outc
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, outc_cod) SET src_quarter = '2025Q4';
LOAD DATA LOCAL INFILE 'data/raw/2025Q4/ASCII/INDI25Q4.txt' INTO TABLE raw_indi
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (primaryid, caseid, indi_drug_seq, indi_pt) SET src_quarter = '2025Q4';
LOAD DATA LOCAL INFILE 'data/raw/2025Q4/Deleted/DELETE25Q4.txt' INTO TABLE raw_deleted
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY '$' ESCAPED BY '' LINES TERMINATED BY '\n'
  (caseid) SET src_quarter = '2025Q4';

-- Indexes are created after loading (much faster than loading into indexed tables)
ALTER TABLE raw_demo   ADD INDEX ix_demo_case (caseid), ADD INDEX ix_demo_pid (primaryid);
ALTER TABLE raw_drug   ADD INDEX ix_drug_pid (primaryid), ADD INDEX ix_drug_case (caseid);
ALTER TABLE raw_reac   ADD INDEX ix_reac_pid (primaryid);
ALTER TABLE raw_outc   ADD INDEX ix_outc_pid (primaryid);
ALTER TABLE raw_indi   ADD INDEX ix_indi_pid (primaryid);
ALTER TABLE raw_deleted ADD INDEX ix_del_case (caseid);
