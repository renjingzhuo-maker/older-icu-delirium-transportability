-- Run this file separately in each database after the corresponding daily table.
-- psql variable: database = mimic or eicu
\if :{?database}
\else
  \echo 'Required variable missing: -v database=mimic or -v database=eicu'
  \quit
\endif

SELECT :'database' = 'mimic' AS is_mimic,
       :'database' = 'eicu' AS is_eicu
\gset

\if :is_mimic
SET search_path TO delirium_trajectory, mimiciv_derived, mimiciv_hosp, mimiciv_icu, public;

DROP TABLE IF EXISTS mimic_outcome_summary CASCADE;
CREATE TABLE mimic_outcome_summary AS
SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    MAX(d.strict_incident_eligible) AS strict_eligible,
    MAX(d.loose_incident_eligible) AS loose_eligible,
    COUNT(*) FILTER (WHERE d.daily_delirium IS NOT NULL) AS valid_outcome_days,
    COUNT(*) FILTER (WHERE d.daily_delirium = 1) AS delirium_positive_days,
    MIN(d.icu_day) FILTER (WHERE d.daily_delirium = 1) AS first_positive_day,
    MAX(d.icu_day) FILTER (WHERE d.daily_delirium = 1) AS last_positive_day,
    MAX(COALESCE(d.daily_delirium, 0)) AS any_delirium_day2_5,
    CASE
      WHEN COUNT(*) FILTER (WHERE d.daily_delirium IS NOT NULL) >= 2
       AND (
           COUNT(*) FILTER (WHERE d.daily_delirium = 1) >= 2
           OR MAX(d.icu_day) FILTER (WHERE d.daily_delirium = 1)
              = MAX(d.icu_day) FILTER (WHERE d.daily_delirium IS NOT NULL)
       )
      THEN 1 ELSE 0
    END AS late_persistent_delirium
FROM mimic_daily_delirium d
GROUP BY d.subject_id, d.hadm_id, d.stay_id;

CREATE UNIQUE INDEX mimic_outcome_summary_stay_idx
    ON mimic_outcome_summary (stay_id);
ANALYZE mimic_outcome_summary;

\elif :is_eicu
SET search_path TO delirium_trajectory, eicu_crd, public;

DROP TABLE IF EXISTS eicu_outcome_summary CASCADE;
CREATE TABLE eicu_outcome_summary AS
SELECT
    d.patientunitstayid,
    d.patienthealthsystemstayid,
    d.hospitalid,
    MAX(d.strict_cam_eligible) AS strict_eligible,
    MAX(d.loose_cam_eligible) AS loose_eligible,
    COUNT(*) FILTER (WHERE d.cam_daily_delirium IS NOT NULL) AS valid_outcome_days,
    COUNT(*) FILTER (WHERE d.cam_daily_delirium = 1) AS delirium_positive_days,
    MIN(d.icu_day) FILTER (WHERE d.cam_daily_delirium = 1) AS first_positive_day,
    MAX(d.icu_day) FILTER (WHERE d.cam_daily_delirium = 1) AS last_positive_day,
    MAX(COALESCE(d.cam_daily_delirium, 0)) AS any_delirium_day2_5,
    CASE
      WHEN COUNT(*) FILTER (WHERE d.cam_daily_delirium IS NOT NULL) >= 2
       AND (
           COUNT(*) FILTER (WHERE d.cam_daily_delirium = 1) >= 2
           OR MAX(d.icu_day) FILTER (WHERE d.cam_daily_delirium = 1)
              = MAX(d.icu_day) FILTER (WHERE d.cam_daily_delirium IS NOT NULL)
       )
      THEN 1 ELSE 0
    END AS late_persistent_delirium,
    COUNT(*) FILTER (WHERE d.any_screen_daily_delirium IS NOT NULL)
        AS valid_any_screen_days,
    MAX(COALESCE(d.any_screen_daily_delirium, 0)) AS any_screen_delirium_day2_5
FROM eicu_daily_delirium d
GROUP BY d.patientunitstayid, d.patienthealthsystemstayid, d.hospitalid;

CREATE UNIQUE INDEX eicu_outcome_summary_stay_idx
    ON eicu_outcome_summary (patientunitstayid);
CREATE INDEX eicu_outcome_summary_hospital_idx
    ON eicu_outcome_summary (hospitalid);
ANALYZE eicu_outcome_summary;

\else
  \echo 'Invalid database variable. Use mimic or eicu.'
  \quit
\endif
