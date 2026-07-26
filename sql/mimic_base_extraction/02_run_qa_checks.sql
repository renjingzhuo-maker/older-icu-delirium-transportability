-- QA checks for the MIMIC-IV elderly ICU delirium extraction.
-- Run after 01_build_mimiciv_delirium_24h.sql.

SET search_path TO mimiciv_delirium, mimiciv_derived, mimiciv_hosp, mimiciv_icu, public;

-- 1. Final primary analysis sample size and delirium rate.
SELECT
    COUNT(*) AS n,
    SUM(delirium) AS delirium_cases,
    ROUND(AVG(delirium::NUMERIC) * 100, 2) AS delirium_rate_percent
FROM mimiciv_delirium.delirium_mimiciv_24h;

-- 2. Sensitivity sample size if missing post-24h CAM is treated as no recorded delirium.
SELECT
    COUNT(*) AS n,
    SUM(delirium) AS delirium_cases,
    ROUND(AVG(delirium::NUMERIC) * 100, 2) AS delirium_rate_percent,
    SUM(CASE WHEN has_post24_delirium_assessment = 0 THEN 1 ELSE 0 END) AS missing_post24_cam_count
FROM mimiciv_delirium.delirium_mimiciv_24h_sensitivity_missing_cam_negative;

-- 3. Exclusion audit.
SELECT
    COUNT(*) AS all_eligible,
    SUM(CASE WHEN baseline_delirium_24h = 1 THEN 1 ELSE 0 END) AS baseline_delirium,
    SUM(CASE WHEN has_post24_delirium_assessment = 0 THEN 1 ELSE 0 END) AS no_post24_assessment
FROM mimiciv_delirium.delirium_mimiciv_all_eligible;

-- 4. Post-24h CAM assessment count distribution in the primary analysis set.
SELECT
    MIN(post24_cam_assessment_count) AS min_count,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY post24_cam_assessment_count) AS q1,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY post24_cam_assessment_count) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY post24_cam_assessment_count) AS q3,
    MAX(post24_cam_assessment_count) AS max_count
FROM mimiciv_delirium.delirium_mimiciv_24h;

-- 5. Missingness in core nursing/bedside variables.
SELECT
    AVG((rass_min IS NULL)::INT) AS missing_rass,
    AVG((gcs_min IS NULL)::INT) AS missing_gcs,
    AVG((pain_mean IS NULL)::INT) AS missing_pain,
    AVG((spo2_min IS NULL)::INT) AS missing_spo2,
    AVG((temperature_mean IS NULL)::INT) AS missing_temperature
FROM mimiciv_delirium.delirium_mimiciv_24h;

-- 6. Surveillance-bias check: CAM assessment frequency by outcome.
SELECT
    delirium,
    COUNT(*) AS n,
    AVG(post24_cam_assessment_count) AS mean_post24_cam_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY post24_cam_assessment_count) AS median_post24_cam_count
FROM mimiciv_delirium.delirium_mimiciv_24h
GROUP BY delirium
ORDER BY delirium;

-- 7. Raw outcome value distribution. Inspect this before locking the delirium regex.
SELECT
    ce.itemid,
    ce.value,
    COUNT(*) AS n
FROM mimiciv_icu.chartevents AS ce
WHERE ce.itemid IN (228332, 228688)
GROUP BY ce.itemid, ce.value
ORDER BY ce.itemid, n DESC;

-- 8. Restraint and transfusion frequencies.
SELECT
    restraint_24h,
    COUNT(*) AS n
FROM mimiciv_delirium.delirium_mimiciv_24h
GROUP BY restraint_24h
ORDER BY restraint_24h;

SELECT
    transfusion_24h,
    COUNT(*) AS n
FROM mimiciv_delirium.delirium_mimiciv_24h
GROUP BY transfusion_24h
ORDER BY transfusion_24h;

-- 9. Antipsychotic exposure frequency for sensitivity modeling decisions.
SELECT
    antipsychotic_24h,
    COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent
FROM mimiciv_delirium.delirium_mimiciv_24h
GROUP BY antipsychotic_24h
ORDER BY antipsychotic_24h;

-- 10. Exact 24h boundary audit. The legacy binary extraction excludes these
-- records; the trajectory analysis conservatively assigns them to baseline.
SELECT
    COUNT(*) AS exact_24h_delirium_assessment_count
FROM mimiciv_delirium.delirium_mimiciv_all_eligible AS d
INNER JOIN mimiciv_icu.chartevents AS ce
    ON d.stay_id = ce.stay_id
    AND ce.charttime = d.icu_intime + INTERVAL '24 HOUR'
    AND ce.itemid IN (228332, 228688);
