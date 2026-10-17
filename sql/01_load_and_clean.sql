/* =============================================================================
 * 01_load_and_clean.sql
 * Diabetes 130-US Hospitals (1999-2008): load, validate and define the cohort.
 * Engine: DuckDB. Run from the repository root so the relative paths resolve.
 * Data: UCI Machine Learning Repository, "Diabetes 130-US Hospitals for Years 1999-2008".
 * Reference: Strack et al. (2014), https://doi.org/10.1155/2014/781670
 * Expected files in data/: diabetic_data.csv, admission_type.csv,
 *                          admission_source.csv, discharge_disposition.csv
 * ============================================================================= */


/* PHASE 1: LOAD AND VERIFY THE DATA
 * sample_size=-1 forces DuckDB to scan 100% of the rows to infer column types.
 * nullstr='?' converts every '?' into NULL, so data types stay correct
 * (INT, VARCHAR, ...) in a single step.
 */
CREATE OR REPLACE TABLE diabetes_encounters AS
SELECT *
FROM read_csv_auto('data/diabetic_data.csv',
    sample_size = -1,
    nullstr = '?'
);

-- 1.1 Column names, data types and null information
DESCRIBE SELECT * FROM diabetes_encounters;

-- 1.2 Number of columns
SELECT COUNT(*) AS total_columns
FROM (DESCRIBE SELECT * FROM diabetes_encounters);

-- 1.3 Number of records
SELECT COUNT(*) AS total_rows
FROM diabetes_encounters;

-- 1.4 First 10 rows, to confirm the file loaded correctly
SELECT *
FROM diabetes_encounters
LIMIT 10;

-- 1.5 Data quality: encounter_id must be unique (both numbers should be equal)
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT encounter_id) AS unique_encounter_ids
FROM diabetes_encounters;

-- 1.6 Data quality: profile of every column (see null_percentage)
SUMMARIZE diabetes_encounters;


/* PHASE 2: BINARY READMISSION VARIABLE
 * 'early_readmission' = 1 only when the patient was readmitted within 30 days ('<30'),
 * the classic hospital convention (Strack et al., 2014).
 * Both '>30' and 'NO' are coded 0 (not an early readmission).
 */

-- 2.1 Add the new column to the existing table
ALTER TABLE diabetes_encounters ADD COLUMN early_readmission INT;

-- 2.2 Fill it with the analytical rule
UPDATE diabetes_encounters
SET early_readmission = CASE WHEN readmitted = '<30' THEN 1 ELSE 0 END;

-- 2.3 Check: only '<30' must map to 1
SELECT readmitted,
       early_readmission,
       COUNT(*) AS total_rows
FROM diabetes_encounters
GROUP BY readmitted, early_readmission
ORDER BY readmitted;


/* PHASE 3: LOOKUP TABLES
 * IDs_mapping.csv (included with the original dataset) stacks three lookup tables
 * in one file. They were split manually into three CSV files so they can be used in JOINs.
 */

-- 3.1 Admission type
CREATE OR REPLACE TABLE admission_type AS
SELECT * FROM read_csv_auto('data/admission_type.csv');

-- 3.2 Admission source
CREATE OR REPLACE TABLE admission_source AS
SELECT * FROM read_csv_auto('data/admission_source.csv');

-- 3.3 Discharge disposition
CREATE OR REPLACE TABLE discharge_disposition AS
SELECT * FROM read_csv_auto('data/discharge_disposition.csv');

-- 3.4 Check the lookup tables
SELECT * FROM admission_type LIMIT 6;
SELECT * FROM admission_source LIMIT 6;
SELECT * FROM discharge_disposition LIMIT 6;


/* PHASE 4: ANALYSIS COHORT
 * View 'analysis_cohort': the group of patients every analysis query runs on.
 * The original table is not modified.
 *
 * Criteria:
 * 1. Exclude encounters ending in death or hospice discharge
 *    (discharge_disposition_id 11, 13, 14, 19, 20, 21): these patients cannot be
 *    readmitted and would underestimate the readmission rate.
 * 2. Keep one encounter per patient (the first eligible one by encounter_id), so a
 *    patient with many encounters does not weigh more than once.
 *
 * Limitation: the dataset has no dates, so encounter_id is only an approximation of
 * the temporal order.
 */
CREATE OR REPLACE VIEW analysis_cohort AS
WITH eligible AS (
    SELECT *
    FROM diabetes_encounters
    WHERE discharge_disposition_id NOT IN (11, 13, 14, 19, 20, 21)  -- death and hospice
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY patient_nbr ORDER BY encounter_id) AS enc_order
    FROM eligible
)
SELECT * EXCLUDE (enc_order)
FROM ranked
WHERE enc_order = 1;  -- one encounter per patient

-- 4.1 Check: both numbers must be equal (one row per patient)
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT patient_nbr) AS unique_patients
FROM analysis_cohort;
