-- Build eICU-CRD predictors available from ICU admission through minute 1439.
-- The column names intentionally mirror the transportable MIMIC-IV feature set.

SET search_path TO delirium_trajectory, eicu_crd, public;

DROP TABLE IF EXISTS eicu_features_24h CASCADE;
CREATE TABLE eicu_features_24h AS
WITH cohort AS (
    SELECT c.*, p.hospitaladmitsource
    FROM eicu_trajectory_cohort c
    JOIN eicu_crd.patient p USING (patientunitstayid)
),
apache AS (
    SELECT
        c.patientunitstayid,
        MAX(apr.acutephysiologyscore)
            FILTER (WHERE apr.apacheversion = 'IVa') AS acute_physiology_score,
        MAX(apr.apachescore)
            FILTER (WHERE apr.apacheversion = 'IVa') AS apache_iv_score,
        MAX(aav.vent) AS apache_vent_24h,
        MAX(aav.dialysis) AS apache_dialysis_24h,
        MAX(NULLIF(aav.urine, -1)) AS urineoutput_24h,
        MIN(
            CASE
                WHEN aav.eyes BETWEEN 1 AND 4
                 AND aav.motor BETWEEN 1 AND 6
                 AND aav.verbal BETWEEN 1 AND 5
                THEN aav.eyes + aav.motor + aav.verbal
            END
        ) AS apache_gcs_min
    FROM cohort c
    LEFT JOIN eicu_crd.apachepatientresult apr USING (patientunitstayid)
    LEFT JOIN eicu_crd.apacheapsvar aav USING (patientunitstayid)
    GROUP BY c.patientunitstayid
),
comorbidity_rows AS MATERIALIZED (
    SELECT
        ph.patientunitstayid,
        lower(concat_ws(' ', ph.pasthistorypath, ph.pasthistoryvalue,
                        ph.pasthistoryvaluetext)) AS term
    FROM eicu_crd.pasthistory ph
    JOIN cohort c USING (patientunitstayid)
    UNION ALL
    SELECT
        d.patientunitstayid,
        lower(concat_ws(' ', d.diagnosisstring, d.icd9code)) AS term
    FROM eicu_crd.diagnosis d
    JOIN cohort c USING (patientunitstayid)
    WHERE d.diagnosisoffset < 1440
),
comorbidity AS (
    SELECT
        c.patientunitstayid,
        MAX((x.term ~ '(dement|alzheimer|cognitive impairment)')::int) AS dementia,
        MAX((x.term ~ '(stroke|cerebrovascular|cva|transient ischemic)')::int)
            AS cerebrovascular_disease,
        MAX((x.term ~ '(hypertension|high blood pressure)')::int) AS hypertension,
        MAX((x.term ~ 'diabet')::int) AS diabetes,
        MAX((x.term ~ '(chronic kidney|chronic renal|renal failure|end stage renal|esrd)')::int)
            AS chronic_kidney_disease,
        MAX((x.term ~ '(copd|chronic obstructive|emphysema|chronic bronchitis)')::int)
            AS chronic_pulmonary_disease,
        MAX((x.term ~ '(congestive heart failure|heart failure)')::int)
            AS congestive_heart_failure,
        MAX((x.term ~ '(cirrhos|chronic liver|hepatic failure)')::int) AS liver_disease,
        MAX((x.term ~ '(cancer|carcinoma|malignan|metastatic|leukemia|lymphoma)')::int)
            AS cancer,
        MAX((x.term ~ '(depress|psychiatr|schizophren|bipolar|psychosis)')::int)
            AS psychiatric_disorder,
        MAX((x.term ~ '(alcohol|ethanol)')::int) AS alcohol_use_disorder
    FROM cohort c
    LEFT JOIN comorbidity_rows x USING (patientunitstayid)
    GROUP BY c.patientunitstayid
),
periodic AS (
    SELECT
        c.patientunitstayid,
        MIN(v.heartrate) FILTER (WHERE v.heartrate BETWEEN 20 AND 250) AS heart_rate_min,
        MAX(v.heartrate) FILTER (WHERE v.heartrate BETWEEN 20 AND 250) AS heart_rate_max,
        AVG(v.heartrate) FILTER (WHERE v.heartrate BETWEEN 20 AND 250) AS heart_rate_mean,
        STDDEV_SAMP(v.heartrate) FILTER (WHERE v.heartrate BETWEEN 20 AND 250) AS heart_rate_sd,
        MIN(v.respiration) FILTER (WHERE v.respiration BETWEEN 4 AND 80) AS resp_rate_min,
        MAX(v.respiration) FILTER (WHERE v.respiration BETWEEN 4 AND 80) AS resp_rate_max,
        AVG(v.respiration) FILTER (WHERE v.respiration BETWEEN 4 AND 80) AS resp_rate_mean,
        STDDEV_SAMP(v.respiration) FILTER (WHERE v.respiration BETWEEN 4 AND 80) AS resp_rate_sd,
        MIN(v.sao2) FILTER (WHERE v.sao2 BETWEEN 50 AND 100) AS spo2_min,
        MAX(v.sao2) FILTER (WHERE v.sao2 BETWEEN 50 AND 100) AS spo2_max,
        AVG(v.sao2) FILTER (WHERE v.sao2 BETWEEN 50 AND 100) AS spo2_mean,
        STDDEV_SAMP(v.sao2) FILTER (WHERE v.sao2 BETWEEN 50 AND 100) AS spo2_sd,
        MIN(v.temperature) FILTER (WHERE v.temperature BETWEEN 25 AND 45) AS temperature_min,
        MAX(v.temperature) FILTER (WHERE v.temperature BETWEEN 25 AND 45) AS temperature_max,
        AVG(v.temperature) FILTER (WHERE v.temperature BETWEEN 25 AND 45) AS temperature_mean,
        STDDEV_SAMP(v.temperature) FILTER (WHERE v.temperature BETWEEN 25 AND 45) AS temperature_sd,
        MIN(v.systemicsystolic) FILTER (WHERE v.systemicsystolic BETWEEN 30 AND 300) AS sbp_min,
        MAX(v.systemicsystolic) FILTER (WHERE v.systemicsystolic BETWEEN 30 AND 300) AS sbp_max,
        AVG(v.systemicsystolic) FILTER (WHERE v.systemicsystolic BETWEEN 30 AND 300) AS sbp_mean,
        MIN(v.systemicdiastolic) FILTER (WHERE v.systemicdiastolic BETWEEN 10 AND 200) AS dbp_min,
        MAX(v.systemicdiastolic) FILTER (WHERE v.systemicdiastolic BETWEEN 10 AND 200) AS dbp_max,
        AVG(v.systemicdiastolic) FILTER (WHERE v.systemicdiastolic BETWEEN 10 AND 200) AS dbp_mean,
        MIN(v.systemicmean) FILTER (WHERE v.systemicmean BETWEEN 20 AND 250) AS mbp_min,
        MAX(v.systemicmean) FILTER (WHERE v.systemicmean BETWEEN 20 AND 250) AS mbp_max,
        AVG(v.systemicmean) FILTER (WHERE v.systemicmean BETWEEN 20 AND 250) AS mbp_mean
    FROM cohort c
    LEFT JOIN eicu_crd.vitalperiodic v
      ON v.patientunitstayid = c.patientunitstayid
     AND v.observationoffset >= 0 AND v.observationoffset < 1440
    GROUP BY c.patientunitstayid
),
aperiodic AS (
    SELECT
        c.patientunitstayid,
        MIN(v.noninvasivesystolic) FILTER (WHERE v.noninvasivesystolic BETWEEN 30 AND 300) AS sbp_min,
        MAX(v.noninvasivesystolic) FILTER (WHERE v.noninvasivesystolic BETWEEN 30 AND 300) AS sbp_max,
        AVG(v.noninvasivesystolic) FILTER (WHERE v.noninvasivesystolic BETWEEN 30 AND 300) AS sbp_mean,
        MIN(v.noninvasivediastolic) FILTER (WHERE v.noninvasivediastolic BETWEEN 10 AND 200) AS dbp_min,
        MAX(v.noninvasivediastolic) FILTER (WHERE v.noninvasivediastolic BETWEEN 10 AND 200) AS dbp_max,
        AVG(v.noninvasivediastolic) FILTER (WHERE v.noninvasivediastolic BETWEEN 10 AND 200) AS dbp_mean,
        MIN(v.noninvasivemean) FILTER (WHERE v.noninvasivemean BETWEEN 20 AND 250) AS mbp_min,
        MAX(v.noninvasivemean) FILTER (WHERE v.noninvasivemean BETWEEN 20 AND 250) AS mbp_max,
        AVG(v.noninvasivemean) FILTER (WHERE v.noninvasivemean BETWEEN 20 AND 250) AS mbp_mean
    FROM cohort c
    LEFT JOIN eicu_crd.vitalaperiodic v
      ON v.patientunitstayid = c.patientunitstayid
     AND v.observationoffset >= 0 AND v.observationoffset < 1440
    GROUP BY c.patientunitstayid
),
score_rows AS (
    SELECT
        n.patientunitstayid, n.nursingchartoffset, n.nursingchartentryoffset,
        MAX(n.nursingchartvalue) FILTER (
            WHERE n.nursingchartcelltypevallabel = 'Sedation Scale/Score/Goal'
              AND n.nursingchartcelltypevalname = 'Sedation Scale'
        ) AS sedation_scale,
        MAX(n.nursingchartvalue) FILTER (
            WHERE n.nursingchartcelltypevallabel = 'Sedation Scale/Score/Goal'
              AND n.nursingchartcelltypevalname = 'Sedation Score'
        ) AS sedation_score,
        MAX(n.nursingchartvalue) FILTER (
            WHERE n.nursingchartcelltypevallabel = 'Pain Score/Goal'
              AND n.nursingchartcelltypevalname = 'Pain Score'
        ) AS pain_score,
        MAX(n.nursingchartvalue) FILTER (
            WHERE (n.nursingchartcelltypevallabel = 'Glasgow coma score'
                   AND n.nursingchartcelltypevalname = 'GCS Total')
               OR (n.nursingchartcelltypevallabel = 'Score (Glasgow Coma Scale)'
                   AND n.nursingchartcelltypevalname = 'Value')
        ) AS gcs_score
    FROM eicu_crd.nursecharting n
    JOIN cohort c USING (patientunitstayid)
    WHERE n.nursingchartoffset >= 0 AND n.nursingchartoffset < 1440
      AND n.nursingchartcelltypevallabel IN (
          'Sedation Scale/Score/Goal', 'Pain Score/Goal',
          'Glasgow coma score', 'Score (Glasgow Coma Scale)'
      )
    GROUP BY n.patientunitstayid, n.nursingchartoffset, n.nursingchartentryoffset
),
nursing AS (
    SELECT
        c.patientunitstayid,
        MIN(CASE
            WHEN (s.sedation_scale ILIKE '%rass%'
                  OR s.sedation_scale ILIKE '%richmond%')
             AND s.sedation_score ~ '^[+-]?[0-9]+([.][0-9]+)?$'
             AND s.sedation_score::numeric BETWEEN -5 AND 4
            THEN s.sedation_score::numeric END) AS rass_min,
        MAX(CASE
            WHEN (s.sedation_scale ILIKE '%rass%'
                  OR s.sedation_scale ILIKE '%richmond%')
             AND s.sedation_score ~ '^[+-]?[0-9]+([.][0-9]+)?$'
             AND s.sedation_score::numeric BETWEEN -5 AND 4
            THEN s.sedation_score::numeric END) AS rass_max,
        AVG(CASE
            WHEN (s.sedation_scale ILIKE '%rass%'
                  OR s.sedation_scale ILIKE '%richmond%')
             AND s.sedation_score ~ '^[+-]?[0-9]+([.][0-9]+)?$'
             AND s.sedation_score::numeric BETWEEN -5 AND 4
            THEN s.sedation_score::numeric END) AS rass_mean,
        MIN(CASE WHEN s.pain_score ~ '^[+]?[0-9]+([.][0-9]+)?$'
                      AND s.pain_score::numeric BETWEEN 0 AND 10
                 THEN s.pain_score::numeric END) AS pain_min,
        MAX(CASE WHEN s.pain_score ~ '^[+]?[0-9]+([.][0-9]+)?$'
                      AND s.pain_score::numeric BETWEEN 0 AND 10
                 THEN s.pain_score::numeric END) AS pain_max,
        AVG(CASE WHEN s.pain_score ~ '^[+]?[0-9]+([.][0-9]+)?$'
                      AND s.pain_score::numeric BETWEEN 0 AND 10
                 THEN s.pain_score::numeric END) AS pain_mean,
        MIN(CASE WHEN s.gcs_score ~ '^[+]?[0-9]+([.][0-9]+)?$'
                      AND s.gcs_score::numeric BETWEEN 3 AND 15
                 THEN s.gcs_score::numeric END) AS gcs_min,
        MAX(CASE WHEN s.gcs_score ~ '^[+]?[0-9]+([.][0-9]+)?$'
                      AND s.gcs_score::numeric BETWEEN 3 AND 15
                 THEN s.gcs_score::numeric END) AS gcs_max,
        AVG(CASE WHEN s.gcs_score ~ '^[+]?[0-9]+([.][0-9]+)?$'
                      AND s.gcs_score::numeric BETWEEN 3 AND 15
                 THEN s.gcs_score::numeric END) AS gcs_mean
    FROM cohort c
    LEFT JOIN score_rows s USING (patientunitstayid)
    GROUP BY c.patientunitstayid
),
nursing_temperature_rows AS MATERIALIZED (
    SELECT
        n.patientunitstayid,
        CASE
            WHEN n.nursingchartcelltypevalname = 'Temperature (C)'
             AND BTRIM(n.nursingchartvalue) ~ '^-?[0-9]+([.][0-9]+)?$'
             AND BTRIM(n.nursingchartvalue)::numeric BETWEEN 25 AND 45
                THEN BTRIM(n.nursingchartvalue)::numeric
            WHEN n.nursingchartcelltypevalname = 'Temperature (F)'
             AND BTRIM(n.nursingchartvalue) ~ '^-?[0-9]+([.][0-9]+)?$'
             AND BTRIM(n.nursingchartvalue)::numeric BETWEEN 77 AND 113
                THEN (BTRIM(n.nursingchartvalue)::numeric - 32) * 5.0 / 9.0
        END AS temperature_c
    FROM eicu_crd.nursecharting n
    JOIN cohort c USING (patientunitstayid)
    WHERE n.nursingchartoffset >= 0
      AND n.nursingchartoffset < 1440
      AND n.nursingchartcelltypevallabel = 'Temperature'
      AND n.nursingchartcelltypevalname IN ('Temperature (C)', 'Temperature (F)')
),
nursing_temperature AS (
    SELECT
        c.patientunitstayid,
        MIN(t.temperature_c) AS temperature_min,
        MAX(t.temperature_c) AS temperature_max,
        AVG(t.temperature_c) AS temperature_mean,
        STDDEV_SAMP(t.temperature_c) AS temperature_sd
    FROM cohort c
    LEFT JOIN nursing_temperature_rows t USING (patientunitstayid)
    GROUP BY c.patientunitstayid
),
labs AS (
    SELECT
        c.patientunitstayid,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) IN ('wbc x 1000', 'wbc')) AS wbc_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) IN ('wbc x 1000', 'wbc')) AS wbc_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) IN ('hgb', 'hemoglobin')) AS hemoglobin_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) IN ('hgb', 'hemoglobin')) AS hemoglobin_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) IN ('platelets x 1000', 'platelets')) AS platelet_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) IN ('platelets x 1000', 'platelets')) AS platelet_max,
        MIN(l.labresult) FILTER (
            WHERE lower(l.labname) = 'sodium'
              AND l.labresult BETWEEN 100 AND 200
        ) AS sodium_min,
        MAX(l.labresult) FILTER (
            WHERE lower(l.labname) = 'sodium'
              AND l.labresult BETWEEN 100 AND 200
        ) AS sodium_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'potassium') AS potassium_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'potassium') AS potassium_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'chloride') AS chloride_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'chloride') AS chloride_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'calcium') AS calcium_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'calcium') AS calcium_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'magnesium') AS magnesium_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'magnesium') AS magnesium_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'bun') AS bun_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'bun') AS bun_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'creatinine') AS creatinine_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'creatinine') AS creatinine_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) IN ('ast (sgot)', 'ast')) AS ast_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) IN ('ast (sgot)', 'ast')) AS ast_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) IN ('alt (sgpt)', 'alt')) AS alt_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) IN ('alt (sgpt)', 'alt')) AS alt_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) IN ('total bilirubin', 'bilirubin total')) AS bilirubin_total_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) IN ('total bilirubin', 'bilirubin total')) AS bilirubin_total_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'albumin') AS albumin_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'albumin') AS albumin_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'inr') AS inr_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'inr') AS inr_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'ph') AS ph_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'ph') AS ph_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'pao2') AS po2_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'pao2') AS po2_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'paco2') AS pco2_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'paco2') AS pco2_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) IN ('bicarbonate', 'hco3')) AS bicarbonate_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) IN ('bicarbonate', 'hco3')) AS bicarbonate_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'lactate') AS lactate_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'lactate') AS lactate_max,
        MIN(l.labresult) FILTER (WHERE lower(l.labname) = 'glucose') AS glucose_lab_min,
        MAX(l.labresult) FILTER (WHERE lower(l.labname) = 'glucose') AS glucose_lab_max
    FROM cohort c
    LEFT JOIN eicu_crd.lab l
      ON l.patientunitstayid = c.patientunitstayid
     AND l.labresultoffset >= 0 AND l.labresultoffset < 1440
    GROUP BY c.patientunitstayid
),
medication_rows AS MATERIALIZED (
    SELECT i.patientunitstayid, lower(i.drugname) AS term
    FROM eicu_crd.infusiondrug i
    JOIN cohort c USING (patientunitstayid)
    WHERE i.infusionoffset >= 0 AND i.infusionoffset < 1440
    UNION ALL
    SELECT med.patientunitstayid, lower(med.drugname) AS term
    FROM eicu_crd.medication med
    JOIN cohort c USING (patientunitstayid)
    WHERE med.drugstartoffset < 1440
      AND med.drugstopoffset >= 0
      AND med.drugordercancelled <> 'Yes'
),
medications AS (
    SELECT
        c.patientunitstayid,
        MAX((m.term ~ '(propofol|midazolam|lorazepam|dexmedetomidine|precedex)')::int) AS sedative_24h,
        MAX((m.term ~ '(midazolam|lorazepam|diazepam|alprazolam|clonazepam|temazepam)')::int)
            AS benzodiazepine_24h,
        MAX((m.term ~ '(fentanyl|morphine|hydromorphone|oxycodone|hydrocodone|remifentanil)')::int)
            AS opioid_24h,
        MAX((m.term ~ '(haloperidol|quetiapine|olanzapine|risperidone|ziprasidone)')::int)
            AS antipsychotic_24h,
        MAX((m.term ~ '(norepinephrine|levophed|epinephrine|phenylephrine|vasopressin|dopamine|dobutamine|milrinone)')::int)
            AS vasoactive_24h
    FROM cohort c
    LEFT JOIN medication_rows m USING (patientunitstayid)
    GROUP BY c.patientunitstayid
),
treatment_rows AS MATERIALIZED (
    SELECT tr.patientunitstayid, lower(tr.treatmentstring) AS treatmentstring
    FROM eicu_crd.treatment tr
    JOIN cohort c USING (patientunitstayid)
    WHERE tr.treatmentoffset >= 0 AND tr.treatmentoffset < 1440
    UNION ALL
    SELECT
        n.patientunitstayid,
        lower(concat_ws(' ', n.nursingchartcelltypevallabel,
                        n.nursingchartcelltypevalname, n.nursingchartvalue))
    FROM eicu_crd.nursecharting n
    JOIN cohort c USING (patientunitstayid)
    WHERE n.nursingchartoffset >= 0 AND n.nursingchartoffset < 1440
      AND (n.nursingchartcelltypevallabel ILIKE '%restraint%'
           OR n.nursingchartcelltypevalname ILIKE '%restraint%')
),
treatments AS (
    SELECT
        c.patientunitstayid,
        MAX((t.treatmentstring ~ '(mechanical ventilation|ventilator|endotracheal intubation)')::int)
            AS mechvent_treatment_24h,
        MAX((t.treatmentstring ~ '(hemodialysis|continuous renal replacement|crrt|renal replacement)')::int)
            AS rrt_24h,
        MAX((t.treatmentstring ~ '(packed red blood|red blood cell|platelet transfusion|fresh frozen plasma|blood products)')::int)
            AS transfusion_24h,
        MAX((t.treatmentstring ~ 'restraint')::int) AS restraint_24h
    FROM cohort c
    LEFT JOIN treatment_rows t USING (patientunitstayid)
    GROUP BY c.patientunitstayid
)
SELECT
    c.patientunitstayid,
    c.patienthealthsystemstayid,
    c.uniquepid,
    c.hospitalid,
    c.age,
    c.gender AS sex,
    c.ethnicity AS race,
    c.unittype AS icu_type,
    c.unitadmitsource AS admission_type,
    c.apacheadmissiondx,
    c.hospitaladmitsource,
    c.unitdischargeoffset / 1440.0 AS los_icu,
    c.unitdischargestatus,
    c.admissionheight AS height,
    c.admissionweight AS weight_admit,
    CASE
        WHEN c.admissionheight BETWEEN 100 AND 250
             AND c.admissionweight BETWEEN 20 AND 300
             AND c.admissionweight / power(c.admissionheight / 100.0, 2) BETWEEN 10 AND 80
        THEN c.admissionweight / power(c.admissionheight / 100.0, 2)
    END AS bmi,
    COALESCE(cm.dementia, 0) AS dementia,
    COALESCE(cm.cerebrovascular_disease, 0) AS cerebrovascular_disease,
    COALESCE(cm.hypertension, 0) AS hypertension,
    COALESCE(cm.diabetes, 0) AS diabetes,
    COALESCE(cm.chronic_kidney_disease, 0) AS chronic_kidney_disease,
    COALESCE(cm.chronic_pulmonary_disease, 0) AS chronic_pulmonary_disease,
    COALESCE(cm.congestive_heart_failure, 0) AS congestive_heart_failure,
    COALESCE(cm.liver_disease, 0) AS liver_disease,
    COALESCE(cm.cancer, 0) AS cancer,
    COALESCE(cm.psychiatric_disorder, 0) AS psychiatric_disorder,
    COALESCE(cm.alcohol_use_disorder, 0) AS alcohol_use_disorder,
    a.acute_physiology_score,
    a.apache_iv_score,
    COALESCE(n.gcs_min, a.apache_gcs_min) AS gcs_min,
    n.gcs_max,
    n.gcs_mean,
    n.rass_min, n.rass_max, n.rass_mean,
    n.pain_min, n.pain_max, n.pain_mean,
    p.heart_rate_min, p.heart_rate_max, p.heart_rate_mean, p.heart_rate_sd,
    LEAST(ap.sbp_min, p.sbp_min) AS sbp_min,
    GREATEST(ap.sbp_max, p.sbp_max) AS sbp_max,
    COALESCE(ap.sbp_mean, p.sbp_mean) AS sbp_mean,
    LEAST(ap.dbp_min, p.dbp_min) AS dbp_min,
    GREATEST(ap.dbp_max, p.dbp_max) AS dbp_max,
    COALESCE(ap.dbp_mean, p.dbp_mean) AS dbp_mean,
    LEAST(ap.mbp_min, p.mbp_min) AS mbp_min,
    GREATEST(ap.mbp_max, p.mbp_max) AS mbp_max,
    COALESCE(ap.mbp_mean, p.mbp_mean) AS mbp_mean,
    p.resp_rate_min, p.resp_rate_max, p.resp_rate_mean, p.resp_rate_sd,
    LEAST(p.temperature_min, nt.temperature_min) AS temperature_min,
    GREATEST(p.temperature_max, nt.temperature_max) AS temperature_max,
    COALESCE(nt.temperature_mean, p.temperature_mean) AS temperature_mean,
    COALESCE(nt.temperature_sd, p.temperature_sd) AS temperature_sd,
    p.spo2_min, p.spo2_max, p.spo2_mean, p.spo2_sd,
    l.wbc_min, l.wbc_max, l.hemoglobin_min, l.hemoglobin_max,
    l.platelet_min, l.platelet_max, l.sodium_min, l.sodium_max,
    l.potassium_min, l.potassium_max, l.chloride_min, l.chloride_max,
    l.calcium_min, l.calcium_max, l.magnesium_min, l.magnesium_max,
    l.bun_min, l.bun_max, l.creatinine_min, l.creatinine_max,
    l.ast_min, l.ast_max, l.alt_min, l.alt_max,
    l.bilirubin_total_min, l.bilirubin_total_max, l.albumin_min, l.albumin_max,
    l.inr_min, l.inr_max, l.ph_min, l.ph_max, l.po2_min, l.po2_max,
    l.pco2_min, l.pco2_max, l.bicarbonate_min, l.bicarbonate_max,
    l.lactate_min, l.lactate_max, l.glucose_lab_min, l.glucose_lab_max,
    a.urineoutput_24h,
    GREATEST(COALESCE(a.apache_vent_24h, 0), COALESCE(t.mechvent_treatment_24h, 0))
        AS mechvent_24h,
    COALESCE(m.sedative_24h, 0) AS sedative_24h,
    COALESCE(m.benzodiazepine_24h, 0) AS benzodiazepine_24h,
    COALESCE(m.opioid_24h, 0) AS opioid_24h,
    COALESCE(m.antipsychotic_24h, 0) AS antipsychotic_24h,
    COALESCE(m.vasoactive_24h, 0) AS vasoactive_24h,
    GREATEST(COALESCE(a.apache_dialysis_24h, 0), COALESCE(t.rrt_24h, 0)) AS rrt_24h,
    COALESCE(t.transfusion_24h, 0) AS transfusion_24h,
    COALESCE(t.restraint_24h, 0) AS restraint_24h
FROM cohort c
LEFT JOIN apache a USING (patientunitstayid)
LEFT JOIN comorbidity cm USING (patientunitstayid)
LEFT JOIN periodic p USING (patientunitstayid)
LEFT JOIN aperiodic ap USING (patientunitstayid)
LEFT JOIN nursing n USING (patientunitstayid)
LEFT JOIN nursing_temperature nt USING (patientunitstayid)
LEFT JOIN labs l USING (patientunitstayid)
LEFT JOIN medications m USING (patientunitstayid)
LEFT JOIN treatments t USING (patientunitstayid);

CREATE UNIQUE INDEX eicu_features_24h_stay_idx
    ON eicu_features_24h (patientunitstayid);
ANALYZE eicu_features_24h;
