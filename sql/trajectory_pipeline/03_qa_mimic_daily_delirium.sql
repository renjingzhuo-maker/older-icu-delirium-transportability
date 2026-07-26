\set ON_ERROR_STOP on

SET search_path TO delirium_trajectory, mimiciv_icu, mimiciv_hosp, public;

-- Raw values must be reviewed before the outcome mapping is frozen.
SELECT
    itemid,
    raw_value,
    screen_result,
    COUNT(*) AS n
FROM mimic_cam_events
GROUP BY itemid, raw_value, screen_result
ORDER BY itemid, n DESC;

SELECT
    COUNT(*) AS elderly_first_stays_over_24h,
    SUM(loose_incident_eligible) AS loose_baseline_eligible,
    SUM(strict_incident_eligible) AS strict_baseline_eligible,
    SUM((baseline_positive_count > 0)::INTEGER) AS baseline_positive,
    SUM((baseline_valid_count = 0)::INTEGER) AS no_valid_baseline_screen
FROM mimic_trajectory_cohort;

SELECT
    icu_day,
    daily_state,
    COUNT(*) AS stay_days,
    ROUND(
        COUNT(*)::NUMERIC
        / SUM(COUNT(*)) OVER (PARTITION BY icu_day) * 100,
        2
    ) AS percent
FROM mimic_daily_delirium
WHERE loose_incident_eligible = 1
GROUP BY icu_day, daily_state
ORDER BY icu_day, daily_state;

SELECT
    valid_day_count,
    COUNT(*) AS stays
FROM (
    SELECT
        stay_id,
        COUNT(*) FILTER (WHERE daily_delirium IN (0, 1)) AS valid_day_count
    FROM mimic_daily_delirium
    WHERE loose_incident_eligible = 1
    GROUP BY stay_id
) AS x
GROUP BY valid_day_count
ORDER BY valid_day_count;

SELECT
    first_careunit,
    COUNT(DISTINCT stay_id) AS eligible_stays,
    COUNT(DISTINCT stay_id) FILTER (
        WHERE daily_delirium IN (0, 1)
    ) AS stays_with_any_day_2_5_screen
FROM mimic_daily_delirium
WHERE loose_incident_eligible = 1
GROUP BY first_careunit
ORDER BY eligible_stays DESC;
