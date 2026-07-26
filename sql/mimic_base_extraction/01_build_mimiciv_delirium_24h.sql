-- Build an elderly ICU delirium prediction dataset for MIMIC-IV.
--
-- Outcome:
--   delirium = 1 if a positive CAM-ICU / Delirium assessment occurs strictly
--   after ICU hour 24 and before ICU discharge; 0 if post-24h assessments are all
--   negative.
--
-- Predictors:
--   Baseline demographics/comorbidity and ICU hour 0-24 measurements/exposures.
--
-- Required prerequisite:
--   Run MIT-LCP/mimic-code MIMIC-IV PostgreSQL concepts first, e.g.
--   psql -d mimiciv -v ON_ERROR_STOP=1 -f mimic-code/mimic-iv/concepts_postgres/postgres-make-concepts.sql

DROP SCHEMA IF EXISTS mimiciv_delirium CASCADE;
CREATE SCHEMA mimiciv_delirium;

SET search_path TO mimiciv_delirium, mimiciv_derived, mimiciv_hosp, mimiciv_icu, public;

CREATE TABLE mimiciv_delirium.delirium_mimiciv_all_eligible AS
WITH cohort AS (
    SELECT
        isd.subject_id,
        isd.hadm_id,
        isd.stay_id,
        isd.gender,
        isd.race,
        adm.admission_type,
        adm.insurance,
        adm.language,
        adm.marital_status,
        adm.hospital_expire_flag,
        isd.admission_age
            + EXTRACT(EPOCH FROM (isd.icu_intime - isd.admittime)) / 31556908.8
            AS age,
        isd.admittime,
        isd.dischtime,
        isd.icu_intime,
        isd.icu_outtime,
        isd.los_hospital,
        isd.los_icu,
        ie.first_careunit,
        ie.last_careunit,
        isd.hospstay_seq,
        isd.icustay_seq,
        isd.first_hosp_stay,
        isd.first_icu_stay,
        EXTRACT(EPOCH FROM (isd.icu_intime - isd.admittime)) / 3600.0 AS pre_icu_los_hours
    FROM mimiciv_derived.icustay_detail AS isd
    INNER JOIN mimiciv_hosp.admissions AS adm
        ON isd.hadm_id = adm.hadm_id
    INNER JOIN mimiciv_icu.icustays AS ie
        ON isd.stay_id = ie.stay_id
    WHERE
        isd.admission_age
            + EXTRACT(EPOCH FROM (isd.icu_intime - isd.admittime)) / 31556908.8
            >= 65
        AND isd.first_icu_stay = TRUE
        AND isd.icu_outtime > isd.icu_intime + INTERVAL '24 HOUR'
),
anthro AS (
    SELECT
        c.stay_id,
        fdw.weight_admit,
        fdw.weight,
        fdw.weight_min,
        fdw.weight_max,
        fdh.height,
        CASE
            WHEN COALESCE(fdw.weight_admit, fdw.weight) BETWEEN 20 AND 300
                 AND fdh.height BETWEEN 100 AND 250
                 AND COALESCE(fdw.weight_admit, fdw.weight)
                     / POWER(fdh.height / 100.0, 2) BETWEEN 10 AND 80
            THEN COALESCE(fdw.weight_admit, fdw.weight) / POWER(fdh.height / 100.0, 2)
        END AS bmi
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.first_day_weight AS fdw
        ON c.stay_id = fdw.stay_id
    LEFT JOIN mimiciv_derived.first_day_height AS fdh
        ON c.stay_id = fdh.stay_id
),
diag AS (
    SELECT
        hadm_id,
        CASE WHEN icd_version = 9 THEN icd_code END AS icd9_code,
        CASE WHEN icd_version = 10 THEN icd_code END AS icd10_code
    FROM mimiciv_hosp.diagnoses_icd
),
diagnosis_flags AS (
    SELECT
        c.hadm_id,
        MAX(CASE
            WHEN SUBSTR(icd9_code, 1, 3) BETWEEN '401' AND '405'
                 OR SUBSTR(icd10_code, 1, 3) BETWEEN 'I10' AND 'I16'
            THEN 1 ELSE 0 END) AS hypertension_dx,
        MAX(CASE
            WHEN SUBSTR(icd9_code, 1, 3) = '584'
                 OR SUBSTR(icd10_code, 1, 3) = 'N17'
            THEN 1 ELSE 0 END) AS acute_kidney_injury_dx,
        MAX(CASE
            WHEN SUBSTR(icd9_code, 1, 4) = '7855'
                 OR SUBSTR(icd10_code, 1, 3) = 'R57'
            THEN 1 ELSE 0 END) AS shock_dx,
        MAX(CASE
            WHEN SUBSTR(icd9_code, 1, 3) IN ('291', '303')
                 OR SUBSTR(icd9_code, 1, 4) = '3050'
                 OR SUBSTR(icd10_code, 1, 3) IN ('F10', 'K70')
                 OR SUBSTR(icd10_code, 1, 3) = 'T51'
            THEN 1 ELSE 0 END) AS alcohol_use_disorder_dx,
        MAX(CASE
            WHEN SUBSTR(icd9_code, 1, 4) IN ('2962', '2963', '3004', '3090', '3091')
                 OR SUBSTR(icd9_code, 1, 3) = '311'
                 OR SUBSTR(icd10_code, 1, 3) IN ('F32', 'F33')
                 OR SUBSTR(icd10_code, 1, 4) = 'F341'
            THEN 1 ELSE 0 END) AS depression_dx,
        MAX(CASE
            WHEN SUBSTR(icd9_code, 1, 3) BETWEEN '290' AND '319'
                 OR SUBSTR(icd10_code, 1, 3) BETWEEN 'F20' AND 'F48'
            THEN 1 ELSE 0 END) AS psychiatric_disorder_dx
    FROM cohort AS c
    LEFT JOIN diag AS d
        ON c.hadm_id = d.hadm_id
    GROUP BY c.hadm_id
),
vitals_24h AS (
    SELECT
        c.stay_id,
        MIN(vs.heart_rate) AS heart_rate_min,
        MAX(vs.heart_rate) AS heart_rate_max,
        AVG(vs.heart_rate) AS heart_rate_mean,
        STDDEV_SAMP(vs.heart_rate) AS heart_rate_sd,
        MIN(vs.sbp) AS sbp_min,
        MAX(vs.sbp) AS sbp_max,
        AVG(vs.sbp) AS sbp_mean,
        STDDEV_SAMP(vs.sbp) AS sbp_sd,
        MIN(vs.dbp) AS dbp_min,
        MAX(vs.dbp) AS dbp_max,
        AVG(vs.dbp) AS dbp_mean,
        STDDEV_SAMP(vs.dbp) AS dbp_sd,
        MIN(vs.mbp) AS mbp_min,
        MAX(vs.mbp) AS mbp_max,
        AVG(vs.mbp) AS mbp_mean,
        STDDEV_SAMP(vs.mbp) AS mbp_sd,
        MIN(vs.resp_rate) AS resp_rate_min,
        MAX(vs.resp_rate) AS resp_rate_max,
        AVG(vs.resp_rate) AS resp_rate_mean,
        STDDEV_SAMP(vs.resp_rate) AS resp_rate_sd,
        MIN(vs.temperature) AS temperature_min,
        MAX(vs.temperature) AS temperature_max,
        AVG(vs.temperature) AS temperature_mean,
        STDDEV_SAMP(vs.temperature) AS temperature_sd,
        MIN(vs.spo2) AS spo2_min,
        MAX(vs.spo2) AS spo2_max,
        AVG(vs.spo2) AS spo2_mean,
        STDDEV_SAMP(vs.spo2) AS spo2_sd,
        MIN(vs.glucose) AS glucose_chart_min,
        MAX(vs.glucose) AS glucose_chart_max,
        AVG(vs.glucose) AS glucose_chart_mean,
        COUNT(*) AS vital_chart_count
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.vitalsign AS vs
        ON c.stay_id = vs.stay_id
        AND vs.charttime >= c.icu_intime
        AND vs.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
gcs_24h AS (
    SELECT
        c.stay_id,
        MIN(g.gcs) AS gcs_min,
        MAX(g.gcs) AS gcs_max,
        AVG(g.gcs) AS gcs_mean,
        MIN(g.gcs_motor) AS gcs_motor_min,
        MIN(g.gcs_verbal) AS gcs_verbal_min,
        MIN(g.gcs_eyes) AS gcs_eyes_min,
        MAX(g.gcs_unable) AS gcs_unable_24h,
        COUNT(g.gcs) AS gcs_count
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.gcs AS g
        ON c.stay_id = g.stay_id
        AND g.charttime >= c.icu_intime
        AND g.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
rass_24h AS (
    SELECT
        c.stay_id,
        MIN(ce.valuenum) AS rass_min,
        MAX(ce.valuenum) AS rass_max,
        AVG(ce.valuenum) AS rass_mean,
        COUNT(ce.valuenum) AS rass_count
    FROM cohort AS c
    LEFT JOIN mimiciv_icu.chartevents AS ce
        ON c.stay_id = ce.stay_id
        AND ce.charttime >= c.icu_intime
        AND ce.charttime < c.icu_intime + INTERVAL '24 HOUR'
        AND ce.itemid = 228096
        AND ce.valuenum BETWEEN -5 AND 4
    GROUP BY c.stay_id
),
pain_24h AS (
    SELECT
        c.stay_id,
        MIN(CASE WHEN ce.itemid IN (223791, 224409, 227881, 229702) AND ce.valuenum BETWEEN 0 AND 10 THEN ce.valuenum END) AS pain_min,
        MAX(CASE WHEN ce.itemid IN (223791, 224409, 227881, 229702) AND ce.valuenum BETWEEN 0 AND 10 THEN ce.valuenum END) AS pain_max,
        AVG(CASE WHEN ce.itemid IN (223791, 224409, 227881, 229702) AND ce.valuenum BETWEEN 0 AND 10 THEN ce.valuenum END) AS pain_mean,
        MAX(CASE
            WHEN ce.itemid IN (223781, 225113)
                 AND LOWER(COALESCE(ce.value, '')) IN ('yes', 'y', 'present')
            THEN 1 ELSE 0 END) AS pain_present_24h,
        COUNT(CASE WHEN ce.itemid IN (223791, 224409, 227881, 229702, 223781, 225113) THEN 1 END) AS pain_assessment_count
    FROM cohort AS c
    LEFT JOIN mimiciv_icu.chartevents AS ce
        ON c.stay_id = ce.stay_id
        AND ce.charttime >= c.icu_intime
        AND ce.charttime < c.icu_intime + INTERVAL '24 HOUR'
        AND ce.itemid IN (223791, 224409, 227881, 229702, 223781, 225113)
    GROUP BY c.stay_id
),
cam_raw AS (
    SELECT
        c.stay_id,
        ce.charttime,
        ce.itemid,
        ce.value,
        CASE
            WHEN LOWER(COALESCE(ce.value, '')) ~ '(positive|yes|present)'
                 AND LOWER(COALESCE(ce.value, '')) !~ '(negative|unable|uta|not|no )'
            THEN 1
            WHEN LOWER(COALESCE(ce.value, '')) ~ '(negative|no|absent)'
            THEN 0
        END AS delirium_positive
    FROM cohort AS c
    INNER JOIN mimiciv_icu.chartevents AS ce
        ON c.stay_id = ce.stay_id
        AND ce.charttime >= c.icu_intime
        AND ce.charttime <= c.icu_outtime
        AND ce.itemid IN (
            228332, -- Delirium assessment
            228688  -- Delirium
        )
),
delirium_outcome AS (
    SELECT
        c.stay_id,
        MAX(CASE
            WHEN cr.charttime >= c.icu_intime
                 AND cr.charttime < c.icu_intime + INTERVAL '24 HOUR'
                 AND cr.delirium_positive = 1
            THEN 1 ELSE 0 END) AS baseline_delirium_24h,
        COUNT(CASE
            WHEN cr.charttime >= c.icu_intime
                 AND cr.charttime < c.icu_intime + INTERVAL '24 HOUR'
                 AND cr.delirium_positive IS NOT NULL
            THEN 1 END) AS baseline_cam_assessment_count,
        COUNT(CASE
            WHEN cr.charttime > c.icu_intime + INTERVAL '24 HOUR'
                 AND cr.charttime <= c.icu_outtime
                 AND cr.delirium_positive IS NOT NULL
            THEN 1 END) AS post24_cam_assessment_count,
        MAX(CASE
            WHEN cr.charttime > c.icu_intime + INTERVAL '24 HOUR'
                 AND cr.charttime <= c.icu_outtime
                 AND cr.delirium_positive = 1
            THEN 1 ELSE 0 END) AS delirium,
        MIN(CASE
            WHEN cr.charttime > c.icu_intime + INTERVAL '24 HOUR'
                 AND cr.charttime <= c.icu_outtime
                 AND cr.delirium_positive = 1
            THEN cr.charttime END) AS first_delirium_time
    FROM cohort AS c
    LEFT JOIN cam_raw AS cr
        ON c.stay_id = cr.stay_id
    GROUP BY c.stay_id
),
cam_component_frequency AS (
    SELECT
        c.stay_id,
        COUNT(ce.itemid) AS cam_related_chart_count_24h
    FROM cohort AS c
    LEFT JOIN mimiciv_icu.chartevents AS ce
        ON c.stay_id = ce.stay_id
        AND ce.charttime >= c.icu_intime
        AND ce.charttime < c.icu_intime + INTERVAL '24 HOUR'
        AND ce.itemid IN (
            224063, 224064, 224068,
            227669, 227670, 227671, 227678, 227679, 227680, 227682,
            227945, 227948, 227950, 227959, 227962, 227965
        )
        AND ce.itemid IN (
            228300, 228301, 228302, 228303,
            228334, 228335, 228336, 228337,
            229324, 229325, 229326
        )
    GROUP BY c.stay_id
),
restraints_24h AS (
    SELECT
        c.stay_id,
        MAX(CASE
            WHEN di.label ILIKE '%restraint%'
                 AND LOWER(COALESCE(ce.value, '')) !~ '(none|no|off|removed|not applied)'
            THEN 1 ELSE 0 END) AS restraint_24h,
        COUNT(CASE WHEN di.label ILIKE '%restraint%' THEN 1 END) AS restraint_chart_count
    FROM cohort AS c
    LEFT JOIN mimiciv_icu.chartevents AS ce
        ON c.stay_id = ce.stay_id
        AND ce.charttime >= c.icu_intime
        AND ce.charttime < c.icu_intime + INTERVAL '24 HOUR'
    LEFT JOIN mimiciv_icu.d_items AS di
        ON ce.itemid = di.itemid
    GROUP BY c.stay_id
),
cbc_24h AS (
    SELECT
        c.stay_id,
        MIN(cbc.wbc) AS wbc_min,
        MAX(cbc.wbc) AS wbc_max,
        MIN(cbc.hemoglobin) AS hemoglobin_min,
        MAX(cbc.hemoglobin) AS hemoglobin_max,
        MIN(cbc.platelet) AS platelet_min,
        MAX(cbc.platelet) AS platelet_max
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.complete_blood_count AS cbc
        ON c.subject_id = cbc.subject_id
        AND cbc.charttime >= c.icu_intime
        AND cbc.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
chem_24h AS (
    SELECT
        c.stay_id,
        MIN(chem.sodium) AS sodium_min,
        MAX(chem.sodium) AS sodium_max,
        MIN(chem.potassium) AS potassium_min,
        MAX(chem.potassium) AS potassium_max,
        MIN(chem.chloride) AS chloride_min,
        MAX(chem.chloride) AS chloride_max,
        MIN(chem.calcium) AS calcium_min,
        MAX(chem.calcium) AS calcium_max,
        MIN(chem.bun) AS bun_min,
        MAX(chem.bun) AS bun_max,
        MIN(chem.creatinine) AS creatinine_min,
        MAX(chem.creatinine) AS creatinine_max,
        MIN(chem.albumin) AS albumin_min,
        MAX(chem.albumin) AS albumin_max,
        MIN(chem.glucose) AS glucose_lab_min,
        MAX(chem.glucose) AS glucose_lab_max
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.chemistry AS chem
        ON c.subject_id = chem.subject_id
        AND chem.charttime >= c.icu_intime
        AND chem.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
coag_24h AS (
    SELECT
        c.stay_id,
        MIN(coag.inr) AS inr_min,
        MAX(coag.inr) AS inr_max,
        MIN(coag.pt) AS pt_min,
        MAX(coag.pt) AS pt_max,
        MIN(coag.ptt) AS ptt_min,
        MAX(coag.ptt) AS ptt_max
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.coagulation AS coag
        ON c.subject_id = coag.subject_id
        AND coag.charttime >= c.icu_intime
        AND coag.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
enzyme_24h AS (
    SELECT
        c.stay_id,
        MIN(enz.alt) AS alt_min,
        MAX(enz.alt) AS alt_max,
        MIN(enz.ast) AS ast_min,
        MAX(enz.ast) AS ast_max,
        MIN(enz.bilirubin_total) AS bilirubin_total_min,
        MAX(enz.bilirubin_total) AS bilirubin_total_max
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.enzyme AS enz
        ON c.subject_id = enz.subject_id
        AND enz.charttime >= c.icu_intime
        AND enz.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
bg_24h AS (
    SELECT
        c.stay_id,
        MIN(bg.calcium) AS ionized_calcium_min,
        MAX(bg.calcium) AS ionized_calcium_max,
        MIN(bg.potassium) AS blood_gas_potassium_min,
        MAX(bg.potassium) AS blood_gas_potassium_max,
        MIN(bg.sodium) AS blood_gas_sodium_min,
        MAX(bg.sodium) AS blood_gas_sodium_max,
        MIN(bg.ph) AS ph_min,
        MAX(bg.ph) AS ph_max,
        MIN(bg.po2) AS po2_min,
        MAX(bg.po2) AS po2_max,
        MIN(bg.pco2) AS pco2_min,
        MAX(bg.pco2) AS pco2_max,
        MIN(bg.bicarbonate) AS blood_gas_bicarbonate_min,
        MAX(bg.bicarbonate) AS blood_gas_bicarbonate_max,
        MIN(bg.lactate) AS lactate_min,
        MAX(bg.lactate) AS lactate_max
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.bg AS bg
        ON c.subject_id = bg.subject_id
        AND bg.charttime >= c.icu_intime
        AND bg.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
lab_24h AS (
    SELECT
        c.stay_id,
        cbc.wbc_min,
        cbc.wbc_max,
        cbc.hemoglobin_min,
        cbc.hemoglobin_max,
        cbc.platelet_min,
        cbc.platelet_max,
        chem.sodium_min,
        chem.sodium_max,
        chem.potassium_min,
        chem.potassium_max,
        chem.chloride_min,
        chem.chloride_max,
        chem.calcium_min,
        chem.calcium_max,
        bg.ionized_calcium_min,
        bg.ionized_calcium_max,
        bg.blood_gas_potassium_min,
        bg.blood_gas_potassium_max,
        bg.blood_gas_sodium_min,
        bg.blood_gas_sodium_max,
        chem.bun_min,
        chem.bun_max,
        chem.creatinine_min,
        chem.creatinine_max,
        enz.alt_min,
        enz.alt_max,
        enz.ast_min,
        enz.ast_max,
        enz.bilirubin_total_min,
        enz.bilirubin_total_max,
        chem.albumin_min,
        chem.albumin_max,
        coag.inr_min,
        coag.inr_max,
        coag.pt_min,
        coag.pt_max,
        coag.ptt_min,
        coag.ptt_max,
        bg.ph_min,
        bg.ph_max,
        bg.po2_min,
        bg.po2_max,
        bg.pco2_min,
        bg.pco2_max,
        bg.blood_gas_bicarbonate_min,
        bg.blood_gas_bicarbonate_max,
        bg.lactate_min,
        bg.lactate_max,
        chem.glucose_lab_min,
        chem.glucose_lab_max
    FROM cohort AS c
    LEFT JOIN cbc_24h AS cbc
        ON c.stay_id = cbc.stay_id
    LEFT JOIN chem_24h AS chem
        ON c.stay_id = chem.stay_id
    LEFT JOIN coag_24h AS coag
        ON c.stay_id = coag.stay_id
    LEFT JOIN enzyme_24h AS enz
        ON c.stay_id = enz.stay_id
    LEFT JOIN bg_24h AS bg
        ON c.stay_id = bg.stay_id
),
urine_24h AS (
    SELECT
        c.stay_id,
        SUM(uo.urineoutput) AS urineoutput_24h,
        SUM(uo.urineoutput) / NULLIF(a.weight, 0) AS urineoutput_ml_kg_24h
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.urine_output AS uo
        ON c.stay_id = uo.stay_id
        AND uo.charttime >= c.icu_intime
        AND uo.charttime < c.icu_intime + INTERVAL '24 HOUR'
    LEFT JOIN anthro AS a
        ON c.stay_id = a.stay_id
    GROUP BY c.stay_id, a.weight
),
ventilation_24h AS (
    SELECT
        c.stay_id,
        MAX(CASE WHEN v.ventilation_status IN ('InvasiveVent', 'Tracheostomy') THEN 1 ELSE 0 END) AS mechvent_24h,
        MAX(CASE WHEN v.ventilation_status = 'NonInvasiveVent' THEN 1 ELSE 0 END) AS niv_24h,
        MAX(CASE WHEN v.ventilation_status = 'HFNC' THEN 1 ELSE 0 END) AS hfnc_24h,
        SUM(CASE
            WHEN v.ventilation_status IN ('InvasiveVent', 'Tracheostomy')
            THEN GREATEST(
                0.0,
                EXTRACT(EPOCH FROM (
                    LEAST(v.endtime, c.icu_intime + INTERVAL '24 HOUR')
                    - GREATEST(v.starttime, c.icu_intime)
                )) / 60.0
            )
            ELSE 0 END) AS mechvent_minutes_24h
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.ventilation AS v
        ON c.stay_id = v.stay_id
        AND v.starttime < c.icu_intime + INTERVAL '24 HOUR'
        AND v.endtime > c.icu_intime
    GROUP BY c.stay_id
),
vasoactive_24h AS (
    SELECT
        c.stay_id,
        MAX(CASE
            WHEN COALESCE(va.dopamine, va.epinephrine, va.norepinephrine,
                          va.phenylephrine, va.vasopressin, va.dobutamine,
                          va.milrinone) IS NOT NULL
            THEN 1 ELSE 0 END) AS vasoactive_24h,
        MAX(va.dopamine) AS dopamine_max_24h,
        MAX(va.epinephrine) AS epinephrine_max_24h,
        MAX(va.norepinephrine) AS norepinephrine_max_24h,
        MAX(va.phenylephrine) AS phenylephrine_max_24h,
        MAX(va.vasopressin) AS vasopressin_max_24h,
        MAX(va.dobutamine) AS dobutamine_max_24h,
        MAX(va.milrinone) AS milrinone_max_24h
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.vasoactive_agent AS va
        ON c.stay_id = va.stay_id
        AND va.starttime < c.icu_intime + INTERVAL '24 HOUR'
        AND va.endtime > c.icu_intime
    GROUP BY c.stay_id
),
rrt_24h AS (
    SELECT
        c.stay_id,
        MAX(CASE WHEN rrt.dialysis_active = 1 THEN 1 ELSE 0 END) AS rrt_24h,
        MAX(CASE WHEN crrt.crrt_mode IS NOT NULL THEN 1 ELSE 0 END) AS crrt_24h
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.rrt AS rrt
        ON c.stay_id = rrt.stay_id
        AND rrt.charttime >= c.icu_intime
        AND rrt.charttime < c.icu_intime + INTERVAL '24 HOUR'
    LEFT JOIN mimiciv_derived.crrt AS crrt
        ON c.stay_id = crrt.stay_id
        AND crrt.charttime >= c.icu_intime
        AND crrt.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
aki_24h AS (
    SELECT
        c.stay_id,
        MAX(ks.aki_stage) AS aki_stage_24h,
        MAX(ks.aki_stage_smoothed) AS aki_stage_smoothed_24h,
        MAX(CASE WHEN ks.aki_stage >= 1 THEN 1 ELSE 0 END) AS aki_24h
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.kdigo_stages AS ks
        ON c.stay_id = ks.stay_id
        AND ks.charttime >= c.icu_intime
        AND ks.charttime < c.icu_intime + INTERVAL '24 HOUR'
    GROUP BY c.stay_id
),
sepsis_24h AS (
    SELECT
        c.stay_id,
        MAX(CASE
            WHEN s3.sepsis3 = TRUE
                 AND s3.suspected_infection_time <= c.icu_intime + INTERVAL '24 HOUR'
            THEN 1 ELSE 0 END) AS sepsis3_24h
    FROM cohort AS c
    LEFT JOIN mimiciv_derived.sepsis3 AS s3
        ON c.stay_id = s3.stay_id
    GROUP BY c.stay_id
),
med_raw AS (
    SELECT
        c.stay_id,
        LOWER(COALESCE(di.label, '')) AS drug_name,
        ie.itemid,
        'inputevents' AS med_source,
        GREATEST(
            0.0,
            EXTRACT(EPOCH FROM (
                LEAST(ie.endtime, c.icu_intime + INTERVAL '24 HOUR')
                - GREATEST(ie.starttime, c.icu_intime)
            )) / 60.0
        ) AS exposure_minutes
    FROM cohort AS c
    INNER JOIN mimiciv_icu.inputevents AS ie
        ON c.stay_id = ie.stay_id
        AND ie.starttime < c.icu_intime + INTERVAL '24 HOUR'
        AND ie.endtime > c.icu_intime
        AND COALESCE(ie.amount, ie.rate, ie.originalamount, ie.originalrate) IS NOT NULL
    LEFT JOIN mimiciv_icu.d_items AS di
        ON ie.itemid = di.itemid

    UNION ALL

    SELECT
        c.stay_id,
        LOWER(COALESCE(e.medication, '')) AS drug_name,
        NULL::INTEGER AS itemid,
        'emar' AS med_source,
        0.0 AS exposure_minutes
    FROM cohort AS c
    INNER JOIN mimiciv_hosp.emar AS e
        ON c.hadm_id = e.hadm_id
        AND e.charttime >= c.icu_intime
        AND e.charttime < c.icu_intime + INTERVAL '24 HOUR'
        AND NOT (
            LOWER(COALESCE(e.event_txt, '')) LIKE ANY (
                ARRAY['%not given%', '%held%', '%refused%', '%stopped%', '%cancel%']
            )
        )
),
medication_24h AS (
    SELECT
        stay_id,
        MAX(CASE
            WHEN itemid IN (222168, 221668, 221385, 229420, 225150)
                 OR drug_name LIKE ANY (ARRAY[
                     '%propofol%', '%midazolam%', '%versed%', '%lorazepam%',
                     '%ativan%', '%dexmedetomidine%', '%precedex%'
                 ])
            THEN 1 ELSE 0 END) AS sedative_24h,
        MAX(CASE
            WHEN itemid IN (221668, 221385)
                 OR drug_name LIKE ANY (ARRAY[
                     '%midazolam%', '%versed%', '%lorazepam%', '%ativan%',
                     '%diazepam%', '%clonazepam%', '%alprazolam%',
                     '%chlordiazepoxide%', '%temazepam%', '%oxazepam%'
                 ])
            THEN 1 ELSE 0 END) AS benzodiazepine_24h,
        MAX(CASE
            WHEN itemid IN (221744, 225942, 225154, 221833)
                 OR drug_name LIKE ANY (ARRAY[
                     '%fentanyl%', '%morphine%', '%hydromorphone%', '%dilaudid%'
                 ])
            THEN 1 ELSE 0 END) AS opioid_24h,
        MAX(CASE
            WHEN itemid IN (221824)
                 OR drug_name LIKE ANY (ARRAY[
                     '%haloperidol%', '%haldol%', '%quetiapine%',
                     '%seroquel%', '%olanzapine%', '%zyprexa%'
                 ])
            THEN 1 ELSE 0 END) AS antipsychotic_24h,
        MAX(CASE
            WHEN drug_name LIKE ANY (ARRAY[
                '%diphenhydramine%', '%benadryl%', '%scopolamine%',
                '%promethazine%', '%benztropine%', '%oxybutynin%', '%atropine%'
            ])
            THEN 1 ELSE 0 END) AS anticholinergic_24h,
        SUM(CASE
            WHEN med_source = 'inputevents'
                 AND (
                     itemid IN (222168, 221668, 221385, 229420, 225150)
                     OR drug_name LIKE ANY (ARRAY[
                         '%propofol%', '%midazolam%', '%versed%', '%lorazepam%',
                         '%ativan%', '%dexmedetomidine%', '%precedex%'
                     ])
                 )
            THEN exposure_minutes ELSE 0 END) AS sedative_minutes_24h,
        SUM(CASE
            WHEN med_source = 'inputevents'
                 AND (
                     itemid IN (221744, 225942, 225154, 221833)
                     OR drug_name LIKE ANY (ARRAY[
                         '%fentanyl%', '%morphine%', '%hydromorphone%', '%dilaudid%'
                     ])
                 )
            THEN exposure_minutes ELSE 0 END) AS opioid_minutes_24h
    FROM med_raw
    GROUP BY stay_id
),
blood_product_24h AS (
    SELECT
        c.stay_id,
        MAX(CASE
            WHEN LOWER(COALESCE(di.label, '')) LIKE ANY (
                ARRAY[
                    '%packed red%', '%prbc%', '%rbc%', '%red blood%',
                    '%platelet%', '%plasma%', '%ffp%', '%cryoprecipitate%',
                    '%blood product%', '%transfusion%'
                ]
            )
            THEN 1 ELSE 0 END) AS transfusion_24h
    FROM cohort AS c
    LEFT JOIN mimiciv_icu.inputevents AS ie
        ON c.stay_id = ie.stay_id
        AND ie.starttime < c.icu_intime + INTERVAL '24 HOUR'
        AND ie.endtime > c.icu_intime
    LEFT JOIN mimiciv_icu.d_items AS di
        ON ie.itemid = di.itemid
    GROUP BY c.stay_id
)
SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,

    -- Demographics and admission information
    c.age,
    c.gender AS sex,
    c.race,
    c.admission_type,
    c.insurance,
    c.language,
    c.marital_status,
    c.first_careunit AS icu_type,
    c.last_careunit,
    c.icu_intime,
    c.icu_outtime,
    c.los_icu,
    c.admittime,
    c.dischtime,
    c.los_hospital,
    c.pre_icu_los_hours,
    c.hospital_expire_flag,
    CASE WHEN c.first_careunit ILIKE '%surgical%' OR c.first_careunit ILIKE '%SICU%' THEN 1 ELSE 0 END AS surgical_icu,
    a.weight_admit,
    a.weight,
    a.height,
    a.bmi,

    -- Comorbidity and diagnosis flags
    COALESCE(ch.charlson_comorbidity_index, 0) AS charlson_comorbidity_index,
    COALESCE(ch.dementia, 0) AS dementia,
    COALESCE(ch.cerebrovascular_disease, 0) AS cerebrovascular_disease,
    COALESCE(df.hypertension_dx, 0) AS hypertension,
    GREATEST(COALESCE(ch.diabetes_without_cc, 0), COALESCE(ch.diabetes_with_cc, 0)) AS diabetes,
    COALESCE(ch.renal_disease, 0) AS chronic_kidney_disease,
    COALESCE(ch.chronic_pulmonary_disease, 0) AS chronic_pulmonary_disease,
    COALESCE(ch.congestive_heart_failure, 0) AS congestive_heart_failure,
    GREATEST(COALESCE(ch.mild_liver_disease, 0), COALESCE(ch.severe_liver_disease, 0)) AS liver_disease,
    GREATEST(COALESCE(ch.malignant_cancer, 0), COALESCE(ch.metastatic_solid_tumor, 0)) AS cancer,
    COALESCE(df.depression_dx, 0) AS depression,
    COALESCE(df.psychiatric_disorder_dx, 0) AS psychiatric_disorder,
    COALESCE(df.alcohol_use_disorder_dx, 0) AS alcohol_use_disorder,

    -- Severity and organ dysfunction
    fs.sofa AS sofa_24h,
    fs.respiration AS sofa_respiration,
    fs.coagulation AS sofa_coagulation,
    fs.liver AS sofa_liver,
    fs.cardiovascular AS sofa_cardiovascular,
    fs.cns AS sofa_cns,
    fs.renal AS sofa_renal,
    oa.oasis,
    sa.sapsii,
    ap.apsiii,
    COALESCE(ch.charlson_comorbidity_index, 0) AS cci,
    COALESCE(sp.sepsis3_24h, 0) AS sepsis3_24h,
    COALESCE(va.vasoactive_24h, 0) AS vasoactive_24h,
    COALESCE(df.shock_dx, 0) AS shock_diagnosis,
    COALESCE(ak.aki_24h, 0) AS aki_24h,
    ak.aki_stage_24h,
    ak.aki_stage_smoothed_24h,

    -- Neurologic, psychiatric, pain, and nursing assessments
    g.gcs_min,
    g.gcs_max,
    g.gcs_mean,
    g.gcs_motor_min,
    g.gcs_verbal_min,
    g.gcs_eyes_min,
    g.gcs_unable_24h,
    g.gcs_count,
    r.rass_min,
    r.rass_max,
    r.rass_mean,
    r.rass_count,
    p.pain_min,
    p.pain_max,
    p.pain_mean,
    COALESCE(p.pain_present_24h, 0) AS pain_present_24h,
    p.pain_assessment_count,
    COALESCE(rs.restraint_24h, 0) AS restraint_24h,
    rs.restraint_chart_count,
    ccf.cam_related_chart_count_24h,

    -- Vital signs in ICU hour 0-24
    v.heart_rate_min,
    v.heart_rate_max,
    v.heart_rate_mean,
    v.heart_rate_sd,
    v.sbp_min,
    v.sbp_max,
    v.sbp_mean,
    v.sbp_sd,
    v.dbp_min,
    v.dbp_max,
    v.dbp_mean,
    v.dbp_sd,
    v.mbp_min,
    v.mbp_max,
    v.mbp_mean,
    v.mbp_sd,
    v.resp_rate_min,
    v.resp_rate_max,
    v.resp_rate_mean,
    v.resp_rate_sd,
    v.temperature_min,
    v.temperature_max,
    v.temperature_mean,
    v.temperature_sd,
    v.spo2_min,
    v.spo2_max,
    v.spo2_mean,
    v.spo2_sd,
    v.glucose_chart_min,
    v.glucose_chart_max,
    v.glucose_chart_mean,
    v.vital_chart_count,
    u.urineoutput_24h,
    u.urineoutput_ml_kg_24h,

    -- Laboratory values in ICU hour 0-24
    l.wbc_min,
    l.wbc_max,
    l.hemoglobin_min,
    l.hemoglobin_max,
    l.platelet_min,
    l.platelet_max,
    l.sodium_min,
    l.sodium_max,
    l.potassium_min,
    l.potassium_max,
    l.chloride_min,
    l.chloride_max,
    l.calcium_min,
    l.calcium_max,
    l.ionized_calcium_min,
    l.ionized_calcium_max,
    l.bun_min,
    l.bun_max,
    l.creatinine_min,
    l.creatinine_max,
    l.alt_min,
    l.alt_max,
    l.ast_min,
    l.ast_max,
    l.bilirubin_total_min,
    l.bilirubin_total_max,
    l.albumin_min,
    l.albumin_max,
    l.inr_min,
    l.inr_max,
    l.pt_min,
    l.pt_max,
    l.ptt_min,
    l.ptt_max,
    l.ph_min,
    l.ph_max,
    l.po2_min,
    l.po2_max,
    l.pco2_min,
    l.pco2_max,
    l.blood_gas_bicarbonate_min,
    l.blood_gas_bicarbonate_max,
    l.lactate_min,
    l.lactate_max,
    l.glucose_lab_min,
    l.glucose_lab_max,

    -- ICU treatments and medication exposures in ICU hour 0-24
    COALESCE(vent.mechvent_24h, 0) AS mechvent_24h,
    COALESCE(vent.niv_24h, 0) AS niv_24h,
    COALESCE(vent.hfnc_24h, 0) AS hfnc_24h,
    vent.mechvent_minutes_24h,
    COALESCE(med.sedative_24h, 0) AS sedative_24h,
    COALESCE(med.benzodiazepine_24h, 0) AS benzodiazepine_24h,
    COALESCE(med.opioid_24h, 0) AS opioid_24h,
    COALESCE(med.antipsychotic_24h, 0) AS antipsychotic_24h,
    COALESCE(med.anticholinergic_24h, 0) AS anticholinergic_24h,
    med.sedative_minutes_24h,
    med.opioid_minutes_24h,
    COALESCE(rrt.rrt_24h, 0) AS rrt_24h,
    COALESCE(rrt.crrt_24h, 0) AS crrt_24h,
    COALESCE(bp.transfusion_24h, 0) AS transfusion_24h,
    va.dopamine_max_24h,
    va.epinephrine_max_24h,
    va.norepinephrine_max_24h,
    va.phenylephrine_max_24h,
    va.vasopressin_max_24h,
    va.dobutamine_max_24h,
    va.milrinone_max_24h,

    -- Outcome audit fields
    COALESCE(outc.baseline_delirium_24h, 0) AS baseline_delirium_24h,
    outc.baseline_cam_assessment_count,
    outc.post24_cam_assessment_count,
    CASE WHEN outc.post24_cam_assessment_count > 0 THEN 1 ELSE 0 END AS has_post24_delirium_assessment,
    outc.first_delirium_time,
    outc.delirium
FROM cohort AS c
LEFT JOIN anthro AS a
    ON c.stay_id = a.stay_id
LEFT JOIN mimiciv_derived.charlson AS ch
    ON c.hadm_id = ch.hadm_id
LEFT JOIN diagnosis_flags AS df
    ON c.hadm_id = df.hadm_id
LEFT JOIN mimiciv_derived.first_day_sofa AS fs
    ON c.stay_id = fs.stay_id
LEFT JOIN mimiciv_derived.oasis AS oa
    ON c.stay_id = oa.stay_id
LEFT JOIN mimiciv_derived.sapsii AS sa
    ON c.stay_id = sa.stay_id
LEFT JOIN mimiciv_derived.apsiii AS ap
    ON c.stay_id = ap.stay_id
LEFT JOIN sepsis_24h AS sp
    ON c.stay_id = sp.stay_id
LEFT JOIN vitals_24h AS v
    ON c.stay_id = v.stay_id
LEFT JOIN gcs_24h AS g
    ON c.stay_id = g.stay_id
LEFT JOIN rass_24h AS r
    ON c.stay_id = r.stay_id
LEFT JOIN pain_24h AS p
    ON c.stay_id = p.stay_id
LEFT JOIN restraints_24h AS rs
    ON c.stay_id = rs.stay_id
LEFT JOIN cam_component_frequency AS ccf
    ON c.stay_id = ccf.stay_id
LEFT JOIN lab_24h AS l
    ON c.stay_id = l.stay_id
LEFT JOIN urine_24h AS u
    ON c.stay_id = u.stay_id
LEFT JOIN ventilation_24h AS vent
    ON c.stay_id = vent.stay_id
LEFT JOIN vasoactive_24h AS va
    ON c.stay_id = va.stay_id
LEFT JOIN rrt_24h AS rrt
    ON c.stay_id = rrt.stay_id
LEFT JOIN aki_24h AS ak
    ON c.stay_id = ak.stay_id
LEFT JOIN medication_24h AS med
    ON c.stay_id = med.stay_id
LEFT JOIN blood_product_24h AS bp
    ON c.stay_id = bp.stay_id
LEFT JOIN delirium_outcome AS outc
    ON c.stay_id = outc.stay_id;

CREATE INDEX delirium_mimiciv_all_eligible_stay_id_idx
    ON mimiciv_delirium.delirium_mimiciv_all_eligible (stay_id);

CREATE TABLE mimiciv_delirium.delirium_mimiciv_24h AS
SELECT *
FROM mimiciv_delirium.delirium_mimiciv_all_eligible
WHERE
    COALESCE(baseline_delirium_24h, 0) = 0
    AND has_post24_delirium_assessment = 1;

CREATE INDEX delirium_mimiciv_24h_stay_id_idx
    ON mimiciv_delirium.delirium_mimiciv_24h (stay_id);

CREATE TABLE mimiciv_delirium.delirium_mimiciv_24h_sensitivity_missing_cam_negative AS
SELECT *
FROM mimiciv_delirium.delirium_mimiciv_all_eligible
WHERE
    COALESCE(baseline_delirium_24h, 0) = 0;

CREATE INDEX delirium_mimiciv_24h_sensitivity_missing_cam_negative_stay_id_idx
    ON mimiciv_delirium.delirium_mimiciv_24h_sensitivity_missing_cam_negative (stay_id);

-- Basic QA readouts.
SELECT
    COUNT(*) AS all_eligible_stays,
    SUM(CASE WHEN baseline_delirium_24h = 1 THEN 1 ELSE 0 END) AS excluded_baseline_delirium,
    SUM(CASE WHEN has_post24_delirium_assessment = 0 THEN 1 ELSE 0 END) AS missing_post24_delirium_assessment
FROM mimiciv_delirium.delirium_mimiciv_all_eligible;

SELECT
    COUNT(*) AS analytic_stays,
    SUM(delirium) AS delirium_cases,
    AVG(delirium::DOUBLE PRECISION) AS delirium_rate
FROM mimiciv_delirium.delirium_mimiciv_24h;

SELECT
    COUNT(*) AS sensitivity_stays,
    SUM(delirium) AS delirium_cases,
    AVG(delirium::DOUBLE PRECISION) AS delirium_rate
FROM mimiciv_delirium.delirium_mimiciv_24h_sensitivity_missing_cam_negative;
