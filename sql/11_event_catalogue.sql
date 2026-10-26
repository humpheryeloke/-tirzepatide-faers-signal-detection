/* =============================================================================
   11_event_catalogue.sql
   Purpose : Give every event (MedDRA preferred term) two labels used for prioritisation
             and filtering:
               event_type    'Clinical'  vs  'Product/administration'
               clinical_area a broad body-system group
   Why     : Terms such as "Injection site pain", "Extra dose administered" or "Wrong
             technique in product usage" are expected with an injectable pen and need a
             different review route (quality / human factors) than a clinical safety signal.
   Caution : MedDRA's official hierarchy (SOC/HLGT) is licensed and not in FAERS files.
             These groups are KEYWORD rules written for this project. They are a practical
             screening aid, not MedDRA SOCs, and a few terms will sit in the wrong group.
             The rules are stored in a table so anyone can read and change them.
   ============================================================================= */
USE faers_pv;

DROP TABLE IF EXISTS pt_group_rules;
CREATE TABLE pt_group_rules (
    priority INT PRIMARY KEY, event_type VARCHAR(24) NOT NULL, clinical_area VARCHAR(40) NOT NULL, pattern VARCHAR(1000) NOT NULL
) ENGINE = InnoDB;

INSERT INTO pt_group_rules VALUES
(1,  'Product/administration', 'Product / administration',
     'INJECTION SITE|PRODUCT|DEVICE|INCORRECT DOSE|WRONG |EXTRA DOSE|UNDERDOSE|OVERDOSE|ACCIDENTAL|MEDICATION ERROR|DOSE OMISSION|EXPOSURE|OFF LABEL|INTENTIONAL|INAPPROPRIATE SCHEDULE|INCORRECT ROUTE|NEEDLE|STORAGE|DRUG INEFFECTIVE|THERAPEUTIC RESPONSE|NO ADVERSE EVENT|COUNTERFEIT|TAMPERING|DISPENSING|LABEL|MISUSE|CONTAMINATION|EXPIRED|NONCOMPLIANCE|NON-COMPLIANCE|PREMATURE|INTERCEPTED|DOSE CALCULATION|INJECTION|TREATMENT FAILURE|DRUG TOLERANCE|ILLNESS|CIRCUMSTANCE|COMPOUND'),
(2,  'Clinical', 'Hepatobiliary & pancreatic', 'PANCREAT|CHOLE|GALLBLADDER|GALLSTONE|BILIARY|HEPAT|LIVER|LIPASE|AMYLASE|JAUNDICE|BILE|BILIRUBIN|TRANSAMINASE'),
(3,  'Clinical', 'Weight & appetite', 'WEIGHT|APPETITE|HUNGER|FOOD CRAVING|EARLY SATIETY|FEEDING|POLYPHAGIA|CACHEXIA|MALNUTRITION|BODY MASS|OBESITY|FOOD AVERSION|THIRST'),
(4,  'Clinical', 'Metabolic & glycaemic', 'GLUCOSE|GLYCAEM|GLYCEMI|DIABET|KETO|HBA1C|GLYCOSYLATED|INSULIN|METABOL|DEHYDRAT|ELECTROLYTE|POTASSIUM|SODIUM|LIPID|CHOLESTEROL|TRIGLYCER|ACIDOSIS|HYPOGLYC|HYPERGLYC|DIABETIC'),
(5,  'Clinical', 'Gastrointestinal', 'NAUSEA|VOMIT|DIARRH|CONSTIPAT|ABDOMINAL|DYSPEPS|ERUCTAT|FLATULEN|GASTR|BOWEL|REFLUX|DEFAECAT|STOMACH|INTESTIN|COLITIS|ILEUS|DYSPHAG|RETCH|BLOAT|DISTENSION|HAEMORRHOID|ANAL |OESOPHAG|ESOPHAG|ABDOMINAL|FAECES|STOOL|GASTROINTESTINAL|EPIGASTRIC|DYSGEUSIA|TASTE|SALIVA|MOUTH|DENTAL|TOOTH|TEETH|BREATH|HALITOSIS|BURP|GAS '),
(6,  'Clinical', 'Cardiovascular', 'CARDI|HEART|HYPERTENS|HYPOTENS|TACHYCARD|BRADYCARD|PALPITAT|ARRHYTH|MYOCARD|ANGINA|STROKE|THROMB|EMBOLI|BLOOD PRESSURE|CEREBROVASC|CORONARY|OEDEMA PERIPHERAL|VASCUL'),
(7,  'Clinical', 'Neurological & psychiatric', 'HEADACHE|DIZZ|MIGRAINE|ANXIETY|DEPRESS|INSOMNIA|SUICID|MOOD|SEIZURE|SYNCOPE|TREMOR|PARAESTH|NEURO|PANIC|SOMNOLENCE|MEMORY|COGNIT|AMNESIA|AGITATION|IRRITAB|SLEEP|LETHARGY|CONFUSION|HYPOAESTH|HYPERAESTH|BRAIN FOG|DISTURBANCE IN ATTENTION|ANGER|CRYING|STRESS|EMOTION|PSYCH'),
(8,  'Clinical', 'Skin, hair & hypersensitivity', 'ALOPECIA|RASH|PRURIT|URTICARIA|HAIR|SKIN|ERYTHEMA|DERMAT|ANGIOEDEMA|HYPERHIDROSIS|ACNE|ANAPHYLAC|HYPERSENSITIV|ALLERG|SWELLING|OEDEMA|BLISTER|NAIL|SCAR|FLUSH'),
(9,  'Clinical', 'Eye', 'VISION|OPTIC|EYE|RETINOP|MACULAR|CATARACT|BLIND|VISUAL|OCULAR|VITREOUS|GLAUCOMA|DIPLOPIA'),
(10, 'Clinical', 'Renal & urinary', 'RENAL|KIDNEY|URIN|CREATININE|NEPHR|BLADDER|MICTURITION|POLLAKIURIA'),
(11, 'Clinical', 'Musculoskeletal', 'MUSCLE|MYALGIA|ARTHRALGIA|BACK PAIN|JOINT|BONE|TENDON|MUSCULOSKELETAL|CRAMP|GOUT|FRACTURE|SARCOPENIA|OSTEO|LIGAMENT'),
(12, 'Clinical', 'Reproductive & breast', 'MENSTR|VAGIN|PREGNAN|BREAST|POSTMENOPAUS|FETAL|ABORTION|CONTRACEPT|OVARIAN|ERECTILE|TESTOSTERONE|LIBIDO|UTERINE|PROSTAT|OVULAT|FERTIL|MENOPAUS|GENITAL'),
(13, 'Clinical', 'Infection & immune', 'INFECT|SEPSIS|PNEUMONIA|COVID|INFLUENZA|IMMUN|ABSCESS|VIRAL|BACTERIAL|FUNG|CANDID'),
(14, 'Clinical', 'Neoplasms', 'CARCINOMA|CANCER|NEOPLASM|TUMOUR|TUMOR|MALIGNAN|LYMPHOMA|METASTA|THYROID'),
(15, 'Clinical', 'General & other', '.');            -- catch-all, always matches last

DROP TABLE IF EXISTS event_catalogue;
CREATE TABLE event_catalogue (
    pt VARCHAR(255) PRIMARY KEY, event_type VARCHAR(24) NOT NULL, clinical_area VARCHAR(40) NOT NULL
) ENGINE = InnoDB;

INSERT INTO event_catalogue
SELECT p.pt, r.event_type, r.clinical_area
FROM candidate_pt p
JOIN pt_group_rules r ON r.priority = (SELECT MIN(r2.priority) FROM pt_group_rules r2 WHERE UPPER(p.pt) REGEXP r2.pattern);

SELECT event_type, clinical_area, COUNT(*) AS events FROM event_catalogue GROUP BY event_type, clinical_area ORDER BY event_type DESC, events DESC;

-- Spot-check: the 5 most frequent target-drug events in each group should look sensible
SELECT ec.clinical_area, s.pt, s.a AS target_cases
FROM signal_stats s JOIN event_catalogue ec ON ec.pt = s.pt
WHERE s.analysis_id = 'A1' AND s.stratum_type = 'overall'
  AND s.a >= (SELECT MIN(a) FROM (SELECT a FROM signal_stats s2 JOIN event_catalogue e2 ON e2.pt = s2.pt
              WHERE s2.analysis_id = 'A1' AND s2.stratum_type = 'overall' AND e2.clinical_area = ec.clinical_area ORDER BY a DESC LIMIT 3) t)
ORDER BY ec.clinical_area, s.a DESC;
