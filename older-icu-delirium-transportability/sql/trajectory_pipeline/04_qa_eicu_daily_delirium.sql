\set ON_ERROR_STOP on

SET search_path TO delirium_trajectory, eicu_crd, public;

SELECT
    instrument,
    delirium_scale,
    delirium_score_text,
    cam_icu_result,
    icdsc_result,
    any_validated_result,
    COUNT(*) AS n
FROM eicu_delirium_events
GROUP BY
    instrument,
    delirium_scale,
    delirium_score_text,
    cam_icu_result,
    icdsc_result,
    any_validated_result
ORDER BY instrument, n DESC;

SELECT
    COUNT(*) AS elderly_first_stays_over_24h,
    SUM(loose_cam_eligible) AS loose_cam_eligible,
    SUM(strict_cam_eligible) AS strict_cam_eligible,
    SUM((baseline_cam_positive_count > 0)::INTEGER) AS baseline_cam_positive,
    SUM((baseline_cam_valid_count = 0)::INTEGER) AS no_valid_baseline_cam,
    SUM(loose_any_screen_eligible) AS loose_any_screen_eligible,
    SUM(strict_any_screen_eligible) AS strict_any_screen_eligible
FROM eicu_trajectory_cohort;

SELECT
    icu_day,
    cam_daily_state,
    COUNT(*) AS stay_days,
    ROUND(
        COUNT(*)::NUMERIC
        / SUM(COUNT(*)) OVER (PARTITION BY icu_day) * 100,
        2
    ) AS percent
FROM eicu_daily_delirium
WHERE loose_cam_eligible = 1
GROUP BY icu_day, cam_daily_state
ORDER BY icu_day, cam_daily_state;

SELECT
    valid_day_count,
    COUNT(*) AS stays
FROM (
    SELECT
        patientunitstayid,
        COUNT(*) FILTER (
            WHERE cam_daily_delirium IN (0, 1)
        ) AS valid_day_count
    FROM eicu_daily_delirium
    WHERE loose_cam_eligible = 1
    GROUP BY patientunitstayid
) AS x
GROUP BY valid_day_count
ORDER BY valid_day_count;

-- Site coverage determines whether multiclass trajectory evaluation is viable.
SELECT
    hospitalid,
    COUNT(DISTINCT patientunitstayid) AS eligible_stays,
    COUNT(DISTINCT patientunitstayid) FILTER (
        WHERE cam_daily_delirium IN (0, 1)
    ) AS stays_with_any_day_2_5_cam,
    ROUND(
        COUNT(DISTINCT patientunitstayid) FILTER (
            WHERE cam_daily_delirium IN (0, 1)
        )::NUMERIC
        / NULLIF(COUNT(DISTINCT patientunitstayid), 0) * 100,
        2
    ) AS cam_coverage_percent
FROM eicu_daily_delirium
WHERE loose_cam_eligible = 1
GROUP BY hospitalid
ORDER BY cam_coverage_percent DESC, eligible_stays DESC;
