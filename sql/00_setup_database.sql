/* =============================================================================
   00_setup_database.sql
   Project : Hidden subgroup safety signals for tirzepatide in FDA FAERS (2025 Q1-Q4)
   Purpose : Create the database, a run-log table and the helper functions used by
             the statistical steps later on.
   Engine  : MySQL 8.0
   Run     : mysql --local-infile=1 -u <user> -p < sql/00_setup_database.sql
   ============================================================================= */

CREATE DATABASE IF NOT EXISTS faers_pv
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE faers_pv;

-- ETL / cleaning log: every cleaning step writes the rows it kept and removed here,
-- so the cleaning can be audited and exported (outputs/cleaning_log.csv).
DROP TABLE IF EXISTS etl_log;
CREATE TABLE etl_log (
    log_id      INT AUTO_INCREMENT PRIMARY KEY,
    step_no     VARCHAR(8)   NOT NULL,
    step_name   VARCHAR(120) NOT NULL,
    metric      VARCHAR(160) NOT NULL,
    row_count   BIGINT       NOT NULL,
    note        VARCHAR(400) NULL,
    logged_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

/* -----------------------------------------------------------------------------
   Helper function: upper-tail probability of the standard normal distribution,
   P(Z > z). MySQL has no built-in normal CDF, so this uses the Abramowitz and
   Stegun approximation 26.2.17 (absolute error < 7.5e-8), which is far more
   accurate than needed for p-values in signal detection.
   ----------------------------------------------------------------------------- */
DROP FUNCTION IF EXISTS norm_sf;
DELIMITER $$
CREATE FUNCTION norm_sf(z DOUBLE) RETURNS DOUBLE
    DETERMINISTIC NO SQL
BEGIN
    DECLARE x DOUBLE;
    DECLARE t DOUBLE;
    DECLARE q DOUBLE;
    IF z IS NULL THEN RETURN NULL; END IF;
    SET x = ABS(z);
    SET t = 1e0 / (1e0 + 0.2316419e0 * x);
    SET q = EXP(-0.5e0 * x * x) / SQRT(2e0 * PI())
            * t * (0.319381530e0 + t * (-0.356563782e0 + t * (1.781477937e0
              + t * (-1.821255978e0 + t * 1.330274429e0))));
    IF z >= 0 THEN RETURN q; ELSE RETURN 1e0 - q; END IF;
END$$
DELIMITER ;

-- Quick self-test: P(Z > 1.96) should be about 0.0250 and P(Z > 0) = 0.5
SELECT ROUND(norm_sf(1.96e0), 4) AS p_above_1_96, ROUND(norm_sf(0e0), 4) AS p_above_0;

/* -----------------------------------------------------------------------------
   Helper function: upper-tail probability of the chi-square distribution,
   P(X > x) with `df` degrees of freedom (integer df 1-30). Closed-form series,
   used for Cochran's Q heterogeneity test and chi-square based criteria.
   ----------------------------------------------------------------------------- */
DROP FUNCTION IF EXISTS chisq_sf;
DELIMITER $$
CREATE FUNCTION chisq_sf(x DOUBLE, df INT) RETURNS DOUBLE
    DETERMINISTIC NO SQL
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE term DOUBLE;
    DECLARE total DOUBLE DEFAULT 0;
    DECLARE r INT;
    DECLARE denom DOUBLE;
    IF x IS NULL OR df IS NULL OR df < 1 THEN RETURN NULL; END IF;
    IF x <= 0 THEN RETURN 1e0; END IF;
    IF df MOD 2 = 0 THEN
        SET term = 1e0;                                   -- (x/2)^0 / 0!
        WHILE i < df DIV 2 DO
            SET total = total + term;
            SET i = i + 1;
            SET term = term * (x / 2e0) / i;
        END WHILE;
        RETURN EXP(-x / 2e0) * total;
    ELSE
        SET term = SQRT(x);                               -- x^(1/2) / 1
        SET denom = 1e0;
        SET r = 1;
        WHILE r <= (df - 1) DIV 2 DO
            SET total = total + term / denom;
            SET r = r + 1;
            SET term = term * x;
            SET denom = denom * (2 * r - 1);
        END WHILE;
        RETURN 2e0 * norm_sf(SQRT(x)) + 2e0 * EXP(-x / 2e0) / SQRT(2e0 * PI()) * total;
    END IF;
END$$
DELIMITER ;

-- Self-test: P(chi2_1 > 3.841) = 0.05 ; P(chi2_2 > 5.991) = 0.05 ; P(chi2_5 > 11.07) = 0.05
SELECT ROUND(chisq_sf(3.841e0, 1), 3) AS df1, ROUND(chisq_sf(5.991e0, 2), 3) AS df2, ROUND(chisq_sf(11.07e0, 5), 3) AS df5;
