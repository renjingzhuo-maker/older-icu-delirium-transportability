\set ON_ERROR_STOP on

\if :{?database}
\else
  \echo 'Required variable missing: -v database=mimic or -v database=eicu'
  \quit
\endif

SELECT :'database' = 'mimic' AS is_mimic,
       :'database' = 'eicu' AS is_eicu
\gset

\if :is_mimic
SET search_path TO delirium_trajectory, mimiciv_delirium, public;

SELECT
    COUNT(*) FILTER (
        WHERE strict_eligible = 1 AND valid_outcome_days >= 2
    ) AS primary_trajectory_n,
    SUM(late_persistent_delirium) FILTER (
        WHERE strict_eligible = 1 AND valid_outcome_days >= 2
    ) AS late_persistent_cases,
    ROUND(100.0 * AVG(late_persistent_delirium) FILTER (
        WHERE strict_eligible = 1 AND valid_outcome_days >= 2
    ), 2) AS late_persistent_percent,
    COUNT(*) FILTER (
        WHERE loose_eligible = 1 AND valid_outcome_days >= 2
    ) AS loose_sensitivity_n
FROM mimic_outcome_summary;

SELECT
    ROUND(100.0 * AVG((f.rass_min IS NULL)::int), 2) AS missing_rass_percent,
    ROUND(100.0 * AVG((f.gcs_min IS NULL)::int), 2) AS missing_gcs_percent,
    ROUND(100.0 * AVG((f.pain_mean IS NULL)::int), 2) AS missing_pain_percent,
    ROUND(100.0 * AVG((f.spo2_min IS NULL)::int), 2) AS missing_spo2_percent,
    ROUND(100.0 * AVG((f.temperature_mean IS NULL)::int), 2)
        AS missing_temperature_percent,
    ROUND(100.0 * AVG((f.lactate_max IS NULL)::int), 2) AS missing_lactate_percent
FROM mimiciv_delirium.delirium_mimiciv_all_eligible f
JOIN mimic_outcome_summary o USING (stay_id)
WHERE o.strict_eligible = 1 AND o.valid_outcome_days >= 2;

SELECT
    SUM(f.restraint_24h) AS restraint_positive,
    SUM(f.transfusion_24h) AS transfusion_positive,
    SUM(f.antipsychotic_24h) AS antipsychotic_positive,
    COUNT(*) AS primary_n
FROM mimiciv_delirium.delirium_mimiciv_all_eligible f
JOIN mimic_outcome_summary o USING (stay_id)
WHERE o.strict_eligible = 1 AND o.valid_outcome_days >= 2;

\elif :is_eicu
SET search_path TO delirium_trajectory, eicu_crd, public;

SELECT
    COUNT(*) FILTER (
        WHERE strict_eligible = 1 AND valid_outcome_days >= 2
    ) AS primary_external_n,
    SUM(late_persistent_delirium) FILTER (
        WHERE strict_eligible = 1 AND valid_outcome_days >= 2
    ) AS late_persistent_cases,
    ROUND(100.0 * AVG(late_persistent_delirium) FILTER (
        WHERE strict_eligible = 1 AND valid_outcome_days >= 2
    ), 2) AS late_persistent_percent,
    COUNT(*) FILTER (
        WHERE loose_eligible = 1 AND valid_outcome_days >= 2
    ) AS loose_sensitivity_n,
    COUNT(DISTINCT hospitalid) FILTER (
        WHERE strict_eligible = 1 AND valid_outcome_days >= 2
    ) AS hospitals
FROM eicu_outcome_summary;

SELECT
    ROUND(100.0 * AVG((f.rass_min IS NULL)::int), 2) AS missing_rass_percent,
    ROUND(100.0 * AVG((f.gcs_min IS NULL)::int), 2) AS missing_gcs_percent,
    ROUND(100.0 * AVG((f.pain_mean IS NULL)::int), 2) AS missing_pain_percent,
    ROUND(100.0 * AVG((f.spo2_min IS NULL)::int), 2) AS missing_spo2_percent,
    ROUND(100.0 * AVG((f.temperature_mean IS NULL)::int), 2)
        AS missing_temperature_percent,
    ROUND(100.0 * AVG((f.lactate_max IS NULL)::int), 2) AS missing_lactate_percent
FROM eicu_features_24h f
JOIN eicu_outcome_summary o USING (patientunitstayid)
WHERE o.strict_eligible = 1 AND o.valid_outcome_days >= 2;

SELECT
    SUM(f.restraint_24h) AS restraint_positive,
    SUM(f.transfusion_24h) AS transfusion_positive,
    SUM(f.antipsychotic_24h) AS antipsychotic_positive,
    COUNT(*) AS primary_n
FROM eicu_features_24h f
JOIN eicu_outcome_summary o USING (patientunitstayid)
WHERE o.strict_eligible = 1 AND o.valid_outcome_days >= 2;

\else
  \echo 'Invalid database variable. Use mimic or eicu.'
  \quit
\endif
