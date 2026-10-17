/* =============================================================================
 * 02_analysis.sql
 * Diabetes 130-US Hospitals: 10 clinical questions on 30-day readmission.
 * Run 01_load_and_clean.sql first.
 *
 * Cohort: every query reads from 'analysis_cohort': one encounter per patient (the
 * first whose discharge was not death or hospice).
 * Flow: 101,766 encounters (71,518 patients) -> 2,423 encounters excluded for death or
 * hospice discharge -> 69,990 patients in the cohort.
 *
 * Reading the results:
 * - 'readmission_rate' = share of patients readmitted within 30 days.
 * - All comparisons are unadjusted associations, not causal effects.
 * - Groups under 100 patients are not interpreted.
 * - Findings are written as comments under each query.
 * ============================================================================= */


/* Q1. How big is the cohort and how are readmissions distributed? */

-- 1.1 Cohort flow: from the raw data to the final cohort
SELECT
    (SELECT COUNT(*) FROM diabetes_encounters)                    AS raw_encounters,
    (SELECT COUNT(DISTINCT patient_nbr) FROM diabetes_encounters) AS raw_unique_patients,
    (SELECT COUNT(*) FROM diabetes_encounters
      WHERE discharge_disposition_id IN (11, 13, 14, 19, 20, 21)) AS excluded_death_hospice,
    (SELECT COUNT(*) FROM analysis_cohort)                        AS final_cohort_patients;

-- 1.2 Readmission distribution (count and percentage)
SELECT
    readmitted,
    COUNT(*) AS total_patients,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM analysis_cohort), 2) AS pct_patients
FROM analysis_cohort
GROUP BY readmitted
ORDER BY total_patients DESC;

-- Finding Q1: The raw data holds 101,766 encounters from 71,518 patients. After excluding
-- 2,423 encounters ending in death or hospice discharge and keeping one encounter per
-- patient, the cohort has 69,990 patients. Within 30 days, 8.98% were readmitted
-- (n = 6,285); 31.76% were readmitted after 30 days and 59.26% were not readmitted.


/* Q2. Does early readmission change with age? */
SELECT
    age,
    COUNT(*) AS total_patients,
    ROUND(AVG(early_readmission), 4) AS readmission_rate
FROM analysis_cohort
GROUP BY age
ORDER BY age;

-- Finding Q2: Readmission within 30 days rises with age: about 7% between ages 30 and 60
-- versus 10.2%-10.8% at ages 70-90 (n = 28,861). The 70-80 and 80-90 groups are not
-- distinguishable. Groups under 600 patients (ages 0-20) are not interpreted.


/* Q3. Are there differences by sex or race?
 * Groups with fewer than 100 patients are not shown; missing race, 'Other' race and
 * invalid sex are excluded. */
SELECT
    gender,
    race,
    COUNT(*) AS total_patients,
    ROUND(AVG(early_readmission), 4) AS readmission_rate
FROM analysis_cohort
WHERE gender IS NOT NULL
  AND gender != 'Unknown/Invalid'
  AND race IS NOT NULL
  AND race != 'Other'
GROUP BY gender, race
HAVING COUNT(*) >= 100
ORDER BY readmission_rate DESC;




--3.1 Included and excluded patients
WITH classified AS (
    SELECT
        CASE
            WHEN gender IN ('Male', 'Female')
             AND race IN (
                 'Asian',
                 'Caucasian',
                 'Hispanic',
                 'AfricanAmerican'
             )
            THEN 'Included'
            ELSE 'Excluded'
        END AS group_status
    FROM analysis_cohort
)
SELECT
    group_status,
    COUNT(*) AS patients,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),4) AS percentage
FROM classified
GROUP BY group_status
ORDER BY group_status;

-- Finding Q3: No clear differences by sex or race (6.07%-10.79% vs 8.98% overall). The
-- largest groups are practically identical (Caucasian women 9.29%, n = 26,959; Caucasian
-- men 9.08%, n = 25,346). Hispanic and Asian groups are small (n = 241-807), so their
-- estimates are imprecise. About 4.4% of the cohort is left out (other or missing race,
-- invalid sex, small groups). No adjustment for age or severity.


/* Q4. Is a longer stay associated with more readmissions? */

-- 4.1 Average length of stay by readmission category
SELECT
    readmitted,
    COUNT(*) AS total_patients,
    ROUND(AVG(time_in_hospital), 4) AS avg_days_in_hospital
FROM analysis_cohort
GROUP BY readmitted
ORDER BY avg_days_in_hospital DESC;

-- 4.2 Readmission rate by length-of-stay range
WITH stay_ranges AS (
    SELECT
        early_readmission,
        CASE
            WHEN time_in_hospital BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN time_in_hospital BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN time_in_hospital >= 8            THEN '8+ days'
            ELSE 'Others/Error'
        END AS stay_range
    FROM analysis_cohort
)
SELECT
    stay_range,
    COUNT(*) AS total_patients,
    ROUND(AVG(early_readmission), 4) AS readmission_rate
FROM stay_ranges
GROUP BY stay_range
ORDER BY stay_range;

-- Finding Q4: Readmission increases with length of stay: 7.53% (1-3 days, n = 35,146),
-- 9.91% (4-7 days, n = 25,075) and 11.79% (8-14 days, n = 9,769). Patients readmitted
-- within 30 days stayed 4.8 days on average vs 4.1 for those not readmitted. This is an
-- association that likely reflects clinical severity, not a causal effect of the stay.


/* Q5. Does patient complexity matter? Polypharmacy and multimorbidity.
 * Two dimensions of clinical complexity (number of medications and number of diagnoses)
 * are crossed to see their association with 30-day readmission. */
WITH complexity AS (
    SELECT
        early_readmission,
        CASE
            WHEN num_medications BETWEEN 1 AND 10  THEN '1-10 low'
            WHEN num_medications BETWEEN 11 AND 20 THEN '11-20 moderate'
            WHEN num_medications >= 21             THEN '21+ severe'  -- polypharmacy
            ELSE 'Others/Error'
        END AS medication_range,
        CASE
            WHEN number_diagnoses BETWEEN 1 AND 4 THEN '1-4 low'
            WHEN number_diagnoses BETWEEN 5 AND 8 THEN '5-8 moderate'
            WHEN number_diagnoses >= 9            THEN '9+ severe'
            ELSE 'Others/Error'
        END AS diagnosis_range
    FROM analysis_cohort
)
SELECT
    medication_range,
    diagnosis_range,
    COUNT(*) AS total_patients,
    ROUND(AVG(early_readmission), 4) AS readmission_rate
FROM complexity
GROUP BY medication_range, diagnosis_range
ORDER BY readmission_rate DESC;

-- Finding Q5: Readmission rises with clinical complexity, from 5.73% (1-10 medications and
-- 1-4 diagnoses, n = 4,065) to 11.07% (21+ medications and 9+ diagnoses, n = 9,172), with
-- the gradient visible in both dimensions. These indicators overlap with length of stay
-- (a shared severity signal). The 21+ medications / 1-4 diagnoses cell (n = 863) is too
-- small to interpret.


/* Q6. Where is the risk, according to how the patient arrived and how they left?
 * Hospital circuit = admission type + admission source + discharge destination.
 * Deaths and hospice discharges are already excluded by analysis_cohort.
 * Records with 'missing data' IDs in any of the three dimensions are excluded below.
 * Circuits with fewer than 500 patients are not shown. */
SELECT
    t.description AS admission_type_desc,
    s.description AS admission_source_desc,
    d.description AS discharge_destination,
    COUNT(*) AS total_patients,
    ROUND(AVG(p.early_readmission), 4) AS readmission_rate
FROM analysis_cohort p
INNER JOIN admission_type t        ON p.admission_type_id = t.admission_type_id
INNER JOIN admission_source s      ON p.admission_source_id = s.admission_source_id
INNER JOIN discharge_disposition d ON p.discharge_disposition_id = d.discharge_disposition_id
WHERE p.admission_type_id NOT IN (5, 6, 8)                -- 'missing data' IDs: admission type
  AND p.admission_source_id NOT IN (9, 15, 17, 20, 21)    -- 'missing data' IDs: admission source
  AND p.discharge_disposition_id NOT IN (18, 25, 26)      -- 'missing data' IDs: discharge
GROUP BY admission_type_desc, admission_source_desc, discharge_destination
HAVING COUNT(*) >= 500
ORDER BY readmission_rate DESC;

-- Finding Q6: Discharge destination is strongly associated with readmission: 26.4% after
-- discharge to another rehabilitation facility (n = 1,411) vs 6.95% after discharge home
-- (n = 44,322). The highest-risk circuit was emergency admission through the ER followed
-- by discharge to rehabilitation: 29.8% (n = 667) vs 8.98% overall. Records with missing
-- or unmapped IDs were excluded (e.g., 2,474 patients with no discharge destination).
-- Likely confounded by severity.

-- 6.1 Validation: discharge destination alone, without crossing other dimensions
SELECT
    d.description AS discharge_destination,
    COUNT(*) AS total_patients,
    ROUND(AVG(p.early_readmission), 4) AS readmission_rate
FROM analysis_cohort p
JOIN discharge_disposition d ON p.discharge_disposition_id = d.discharge_disposition_id
GROUP BY d.description
HAVING COUNT(*) >= 100
ORDER BY readmission_rate DESC;

-- Finding Q6.1: The same pattern holds with discharge destination alone: rehabilitation
-- 26.36% (n = 1,411), another inpatient care institution 20.59% (n = 913), SNF 13.42%
-- (n = 8,790), home with home health 9.54% (n = 8,291) and home 6.95% (n = 44,322).
-- Groups under 100 patients are not shown.


/* Q7. Is measuring HbA1c associated with readmission?
 * HbA1c (glycated hemoglobin) is the standard biomarker of average glycemic control over
 * the previous ~3 months. The original study (Strack et al., 2014) asked whether measuring
 * it during the hospital stay was associated with fewer early readmissions.
 * 'None' means the test was not measured. */
SELECT
    A1Cresult,
    COUNT(*) AS total_patients,
    ROUND(AVG(early_readmission), 4) AS readmission_rate
FROM analysis_cohort
GROUP BY A1Cresult
ORDER BY readmission_rate DESC;

-- 7.1 Measured vs not measured
SELECT
    CASE WHEN A1Cresult = 'None' THEN 'Not measured' ELSE 'Measured' END AS hba1c,
    COUNT(*) AS total_patients,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM analysis_cohort), 2) AS pct_patients,
    ROUND(AVG(early_readmission), 4) AS readmission_rate
FROM analysis_cohort
GROUP BY 1
ORDER BY 1;

-- Finding Q7: HbA1c was measured in 18.35% of patients (12,846 of 69,990), consistent with
-- the original study. Readmission was 8.40% when measured vs 9.11% when not: a small
-- difference (about 0.7 points). It is an unadjusted association; the original study found
-- the relationship depends on the primary diagnosis, and 'not measured' may include tests
-- recorded elsewhere in the health system.


/* Q8. Are treatment changes associated with readmission?
 * Pharmacological intervention, insulin and readmission. Only combinations that exist in
 * the data appear: an insulin change implies 'Ch', and no diabetes medication implies no
 * insulin and no change. */
SELECT
    change,
    diabetesMed,
    insulin,
    COUNT(*) AS total_patients,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM analysis_cohort), 2) AS pct_patients,
    ROUND(AVG(early_readmission), 4) AS readmission_rate
FROM analysis_cohort
WHERE change IS NOT NULL
  AND diabetesMed IS NOT NULL
  AND insulin IS NOT NULL
GROUP BY change, diabetesMed, insulin
HAVING COUNT(*) >= 100
ORDER BY readmission_rate DESC;


-- -- 8.1. Does the rate of early readmission differ between patients with and without medication changes?
SELECT
    change,
    COUNT(*) AS total_patients,
    ROUND(COUNT(*) * 100.0 /(SELECT COUNT(*) FROM analysis_cohort),4) AS pct_cohort,
	SUM(early_readmission) AS early_readmissions,
    ROUND(AVG(early_readmission) * 100.0,4) AS early_readmission_pct
FROM analysis_cohort
WHERE change IN ('Ch', 'No')
GROUP BY change
ORDER BY change;

-- 8.2 Same comparison among patients taking diabetes medication only
SELECT change,
       COUNT(*) AS total_patients,
       ROUND(AVG(early_readmission), 4) AS readmission_rate
FROM analysis_cohort
WHERE diabetesMed = true
GROUP BY change
ORDER BY change;

--- Finding Q8 (medication change): among treated patients, any medication change showed
-- no difference (about 9.4% with and without change). In the whole cohort the 'no change'
-- group (8.60%) looks lower only because it includes 16,686 patients without diabetes
-- medication (7.56%).


/* Q9. Which principal diagnoses concentrate the most cases and readmissions?
 * diag_1 (ICD-9) is converted to numeric before range comparisons, because text comparison
 * would misplace short codes (e.g. '41' or '53').
 * Groups follow the ICD-9 chapters used in the original study. */
WITH coded AS (
    SELECT early_readmission, diag_1, TRY_CAST(diag_1 AS DOUBLE) AS code_num
    FROM analysis_cohort
),
classified AS (
    SELECT
        early_readmission,
        CASE
            WHEN diag_1 IS NULL                              THEN 'Unknown/missing'
            WHEN diag_1 LIKE 'V%' OR diag_1 LIKE 'E%'        THEN 'Other (V/E codes)'
            WHEN code_num >= 250 AND code_num < 251          THEN 'Diabetes'
            WHEN (code_num >= 390 AND code_num < 460)
                 OR FLOOR(code_num) = 785                    THEN 'Circulatory'
            WHEN (code_num >= 460 AND code_num < 520)
                 OR FLOOR(code_num) = 786                    THEN 'Respiratory'
            WHEN (code_num >= 520 AND code_num < 580)
                 OR FLOOR(code_num) = 787                    THEN 'Digestive'
            WHEN (code_num >= 580 AND code_num < 630)
                 OR FLOOR(code_num) = 788                    THEN 'Genitourinary'
            WHEN code_num >= 140 AND code_num < 240          THEN 'Neoplasms'
            WHEN code_num >= 710 AND code_num < 740          THEN 'Musculoskeletal'
            WHEN code_num >= 800 AND code_num < 1000         THEN 'Injury/poisoning'
            ELSE 'Other'
        END AS diag_group
    FROM coded
),
by_group AS (
    SELECT
        diag_group,
        COUNT(*)              AS total_patients,
        SUM(early_readmission) AS readmissions,
        AVG(early_readmission) AS readmission_rate
    FROM classified
    GROUP BY diag_group
)
SELECT
    diag_group,
    total_patients,
    ROUND(100.0 * total_patients / SUM(total_patients) OVER (), 2) AS pct_of_patients,
    ROUND(100.0 * readmissions   / SUM(readmissions)   OVER (), 2) AS pct_of_readmissions,
    ROUND(readmission_rate, 4)                                     AS readmission_rate,
    RANK() OVER (ORDER BY readmission_rate DESC)                   AS risk_rank
FROM by_group
ORDER BY risk_rank;

-- Finding Q9: Circulatory diseases were the most frequent principal diagnosis (30.6% of
-- patients) and accounted for a third of readmissions (32.9%), with a rate close to the
-- overall one (9.68% vs 8.98%). Injury/poisoning had a higher rate (10.80%, n = 4,696) and
-- respiratory diseases the lowest (7.30%, n = 9,491). Only 8.2% of patients had diabetes as
-- principal diagnosis. Groups under 100 patients (e.g., missing diagnosis, n = 10) are not
-- interpreted, even if they rank first.


/* Q10. Which specialties deviate from the hospital average?
 * Specialties with >= 200 patients. The baseline is the GLOBAL readmission rate (all
 * patients in the cohort), not an average of specialty rates.
 * Missing specialty is reported as 'Unknown', not as a real specialty. */
WITH global AS (
    SELECT AVG(early_readmission) AS global_rate  -- 0/1 column: AVG = rate
    FROM analysis_cohort
),
by_specialty AS (
    SELECT
        COALESCE(medical_specialty, 'Unknown') AS medical_specialty,
        COUNT(*)                               AS total_patients,
        AVG(early_readmission)                 AS readmission_rate
    FROM analysis_cohort
    GROUP BY 1
    HAVING COUNT(*) >= 200
)
SELECT
    s.medical_specialty,
    s.total_patients,
    ROUND(s.readmission_rate, 4)                   AS readmission_rate,
    ROUND(s.readmission_rate - g.global_rate, 4)   AS diff_vs_global,
    RANK() OVER (ORDER BY s.readmission_rate DESC) AS risk_rank
FROM by_specialty s
CROSS JOIN global g
ORDER BY risk_rank;

-- 10.1 Percentage of patients with no recorded specialty
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE medical_specialty IS NULL) / COUNT(*), 1) AS pct_unknown
FROM analysis_cohort;

-- Finding Q10: Among the 19 groups with 200+ patients, Oncology had about twice the overall
-- readmission rate (18.05% vs 8.98%, n = 205) and Obstetrics and Gynecology the lowest
-- (3.71%, n = 593). The other specialties, including those ranked 2nd and 3rd (Vascular
-- Surgery 11.98%, Psychiatry 11.09%), are within the margin of error of the overall rate.
-- Specialty is missing for [48.1]% of patients (see 10.1), so results describe only those
-- with a recorded specialty.
