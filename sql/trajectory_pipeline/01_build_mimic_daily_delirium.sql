\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS delirium_trajectory;
SET search_path TO delirium_trajectory, mimiciv_icu, mimiciv_hosp, public;

DROP TABLE IF EXISTS mimic_cam_events CASCADE;
CREATE TABLE mimic_cam_events AS
SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.value AS raw_value,
    LOWER(BTRIM(COALESCE(ce.value, ''))) AS normalized_value,
    CASE
        WHEN LOWER(BTRIM(COALESCE(ce.value, '')))
             ~ '(^|[^a-z])(positive|yes|present)([^a-z]|$)'
             AND LOWER(BTRIM(COALESCE(ce.value, ''))) !~ 'not positive'
            THEN 1
        WHEN LOWER(BTRIM(COALESCE(ce.value, '')))
             ~ '(^|[^a-z])(negative|no|absent)([^a-z]|$)'
            THEN 0
        WHEN LOWER(BTRIM(COALESCE(ce.value, '')))
             ~ '(unable|uta|not assessed|cannot assess|n/?a)'
            THEN -1
    END AS screen_result
FROM mimiciv_icu.chartevents AS ce
WHERE ce.itemid IN (
    228332, -- Delirium assessment
    228688  -- Delirium
);

CREATE INDEX mimic_cam_events_stay_time_idx
    ON mimic_cam_events (stay_id, charttime);

DROP TABLE IF EXISTS mimic_trajectory_cohort CASCADE;
CREATE TABLE mimic_trajectory_cohort AS
WITH ranked_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.first_careunit,
        a.admission_type,
        a.race,
        a.deathtime,
        a.hospital_expire_flag,
        p.gender,
        p.anchor_age
            + EXTRACT(YEAR FROM i.intime)::INTEGER
            - p.anchor_year AS age,
        ROW_NUMBER() OVER (
            PARTITION BY i.subject_id
            ORDER BY i.intime, i.stay_id
        ) AS icu_stay_number
    FROM mimiciv_icu.icustays AS i
    INNER JOIN mimiciv_hosp.patients AS p
        ON i.subject_id = p.subject_id
    INNER JOIN mimiciv_hosp.admissions AS a
        ON i.hadm_id = a.hadm_id
),
eligible AS (
    SELECT *
    FROM ranked_stays
    WHERE icu_stay_number = 1
      AND age >= 65
      AND outtime > intime + INTERVAL '24 hour'
),
baseline AS (
    SELECT
        e.stay_id,
        COUNT(*) FILTER (
            WHERE c.screen_result IN (0, 1)
              AND c.charttime >= e.intime
              AND c.charttime <= e.intime + INTERVAL '24 hour'
        ) AS baseline_valid_count,
        COUNT(*) FILTER (
            WHERE c.screen_result = 0
              AND c.charttime >= e.intime
              AND c.charttime <= e.intime + INTERVAL '24 hour'
        ) AS baseline_negative_count,
        COUNT(*) FILTER (
            WHERE c.screen_result = 1
              AND c.charttime >= e.intime
              AND c.charttime <= e.intime + INTERVAL '24 hour'
        ) AS baseline_positive_count,
        COUNT(*) FILTER (
            WHERE c.screen_result = -1
              AND c.charttime >= e.intime
              AND c.charttime <= e.intime + INTERVAL '24 hour'
        ) AS baseline_unassessable_count
    FROM eligible AS e
    LEFT JOIN mimic_cam_events AS c
        ON e.stay_id = c.stay_id
       AND c.charttime >= e.intime
       AND c.charttime <= e.intime + INTERVAL '24 hour'
    GROUP BY e.stay_id
)
SELECT
    e.*,
    COALESCE(b.baseline_valid_count, 0) AS baseline_valid_count,
    COALESCE(b.baseline_negative_count, 0) AS baseline_negative_count,
    COALESCE(b.baseline_positive_count, 0) AS baseline_positive_count,
    COALESCE(b.baseline_unassessable_count, 0) AS baseline_unassessable_count,
    CASE
        WHEN COALESCE(b.baseline_positive_count, 0) = 0 THEN 1 ELSE 0
    END AS loose_incident_eligible,
    CASE
        WHEN COALESCE(b.baseline_positive_count, 0) = 0
         AND COALESCE(b.baseline_negative_count, 0) > 0
        THEN 1 ELSE 0
    END AS strict_incident_eligible
FROM eligible AS e
LEFT JOIN baseline AS b
    ON e.stay_id = b.stay_id;

CREATE UNIQUE INDEX mimic_trajectory_cohort_stay_idx
    ON mimic_trajectory_cohort (stay_id);

DROP TABLE IF EXISTS mimic_daily_delirium CASCADE;
CREATE TABLE mimic_daily_delirium AS
WITH day_grid AS (
    SELECT
        c.*,
        d.icu_day,
        c.intime + (d.icu_day - 1) * INTERVAL '24 hour' AS day_start,
        c.intime + d.icu_day * INTERVAL '24 hour' AS day_end
    FROM mimic_trajectory_cohort AS c
    CROSS JOIN GENERATE_SERIES(2, 5) AS d(icu_day)
),
daily_counts AS (
    SELECT
        g.stay_id,
        g.icu_day,
        COUNT(*) FILTER (WHERE e.screen_result = 1) AS positive_count,
        COUNT(*) FILTER (WHERE e.screen_result = 0) AS negative_count,
        COUNT(*) FILTER (WHERE e.screen_result = -1) AS unassessable_count,
        COUNT(*) FILTER (WHERE e.screen_result IN (0, 1)) AS valid_count,
        MIN(e.charttime) FILTER (WHERE e.screen_result IN (0, 1)) AS first_valid_time
    FROM day_grid AS g
    LEFT JOIN mimic_cam_events AS e
        ON g.stay_id = e.stay_id
       AND e.charttime > g.day_start
       AND e.charttime <= LEAST(g.day_end, g.outtime)
    GROUP BY g.stay_id, g.icu_day
)
SELECT
    g.subject_id,
    g.hadm_id,
    g.stay_id,
    g.age,
    g.gender,
    g.first_careunit,
    g.admission_type,
    g.race,
    g.intime,
    g.outtime,
    g.icu_day,
    g.day_start,
    g.day_end,
    g.loose_incident_eligible,
    g.strict_incident_eligible,
    COALESCE(d.positive_count, 0) AS positive_count,
    COALESCE(d.negative_count, 0) AS negative_count,
    COALESCE(d.unassessable_count, 0) AS unassessable_count,
    COALESCE(d.valid_count, 0) AS valid_count,
    d.first_valid_time,
    CASE
        WHEN g.deathtime IS NOT NULL
         AND g.deathtime <= g.day_start
            THEN 'dead_before_day'
        WHEN g.outtime <= g.day_start
            THEN 'discharged_before_day'
        WHEN COALESCE(d.positive_count, 0) > 0
            THEN 'positive'
        WHEN COALESCE(d.negative_count, 0) > 0
            THEN 'negative'
        WHEN COALESCE(d.unassessable_count, 0) > 0
            THEN 'unassessable'
        WHEN g.deathtime IS NOT NULL
         AND g.deathtime <= g.day_end
            THEN 'dead_during_day'
        WHEN g.outtime <= g.day_end
            THEN 'discharged_during_day'
        ELSE 'missing'
    END AS daily_state,
    CASE
        WHEN COALESCE(d.positive_count, 0) > 0 THEN 1
        WHEN COALESCE(d.negative_count, 0) > 0 THEN 0
    END AS daily_delirium
FROM day_grid AS g
LEFT JOIN daily_counts AS d
    ON g.stay_id = d.stay_id
   AND g.icu_day = d.icu_day;

CREATE UNIQUE INDEX mimic_daily_delirium_stay_day_idx
    ON mimic_daily_delirium (stay_id, icu_day);

ANALYZE mimic_cam_events;
ANALYZE mimic_trajectory_cohort;
ANALYZE mimic_daily_delirium;
