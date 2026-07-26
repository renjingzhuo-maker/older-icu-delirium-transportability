\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS delirium_trajectory;
SET search_path TO delirium_trajectory, eicu_crd, public;

DROP TABLE IF EXISTS eicu_delirium_events CASCADE;
CREATE TABLE eicu_delirium_events AS
WITH score_rows AS (
    SELECT
        patientunitstayid,
        nursingchartoffset,
        nursingchartentryoffset,
        MAX(BTRIM(nursingchartvalue)) FILTER (
            WHERE nursingchartcelltypecat = 'Scores'
              AND nursingchartcelltypevallabel = 'Delirium Scale/Score'
              AND nursingchartcelltypevalname = 'Delirium Scale'
        ) AS delirium_scale,
        MAX(BTRIM(nursingchartvalue)) FILTER (
            WHERE nursingchartcelltypecat = 'Scores'
              AND nursingchartcelltypevallabel = 'Delirium Scale/Score'
              AND nursingchartcelltypevalname = 'Delirium Score'
        ) AS delirium_score_text
    FROM eicu_crd.nursecharting
    WHERE nursingchartcelltypecat = 'Scores'
      AND nursingchartcelltypevallabel = 'Delirium Scale/Score'
    GROUP BY
        patientunitstayid,
        nursingchartoffset,
        nursingchartentryoffset
),
typed AS (
    SELECT
        *,
        LOWER(BTRIM(COALESCE(delirium_scale, ''))) AS normalized_scale,
        LOWER(BTRIM(COALESCE(delirium_score_text, ''))) AS normalized_score,
        CASE
            WHEN BTRIM(COALESCE(delirium_score_text, ''))
                 ~ '^[0-9]+([.][0-9]+)?$'
            THEN BTRIM(delirium_score_text)::NUMERIC
        END AS numeric_score
    FROM score_rows
)
SELECT
    patientunitstayid,
    nursingchartoffset,
    nursingchartentryoffset,
    delirium_scale,
    delirium_score_text,
    CASE
        WHEN normalized_scale = 'cam-icu' THEN 'CAM-ICU'
        WHEN normalized_scale = 'icdsc' THEN 'ICDSC'
        WHEN normalized_scale = '' THEN 'Unknown'
        ELSE delirium_scale
    END AS instrument,
    CASE
        WHEN normalized_scale = 'cam-icu'
         AND normalized_score IN ('yes', 'positive', '1')
            THEN 1
        WHEN normalized_scale = 'cam-icu'
         AND normalized_score IN ('no', 'negative', '0')
            THEN 0
    END AS cam_icu_result,
    CASE
        WHEN normalized_scale = 'icdsc' AND numeric_score >= 4 THEN 1
        WHEN normalized_scale = 'icdsc'
         AND numeric_score BETWEEN 0 AND 3 THEN 0
    END AS icdsc_result,
    CASE
        WHEN normalized_scale = 'cam-icu'
         AND normalized_score IN ('yes', 'positive', '1')
            THEN 1
        WHEN normalized_scale = 'cam-icu'
         AND normalized_score IN ('no', 'negative', '0')
            THEN 0
        WHEN normalized_scale = 'icdsc' AND numeric_score >= 4 THEN 1
        WHEN normalized_scale = 'icdsc'
         AND numeric_score BETWEEN 0 AND 3 THEN 0
    END AS any_validated_result,
    CASE
        WHEN normalized_score ~ '(unable|uta|not assessed|cannot assess|n/?a)'
            THEN 1 ELSE 0
    END AS unassessable
FROM typed;

CREATE INDEX eicu_delirium_events_stay_offset_idx
    ON eicu_delirium_events (patientunitstayid, nursingchartoffset);

DROP TABLE IF EXISTS eicu_trajectory_cohort CASCADE;
CREATE TABLE eicu_trajectory_cohort AS
WITH eligible AS (
    SELECT
        p.patientunitstayid,
        p.patienthealthsystemstayid,
        p.uniquepid,
        p.hospitalid,
        p.gender,
        p.ethnicity,
        p.unittype,
        p.unitadmitsource,
        p.unitstaytype,
        p.apacheadmissiondx,
        p.admissionheight,
        p.admissionweight,
        p.unitdischargeoffset,
        p.unitdischargestatus,
        CASE
            WHEN BTRIM(p.age) = '> 89' THEN 90
            WHEN BTRIM(p.age) ~ '^[0-9]+$' THEN BTRIM(p.age)::INTEGER
        END AS age
    FROM eicu_crd.patient AS p
    WHERE p.unitvisitnumber = 1
      AND p.unitdischargeoffset > 1440
),
elderly AS (
    SELECT *
    FROM eligible
    WHERE age >= 65
),
baseline AS (
    SELECT
        e.patientunitstayid,
        COUNT(*) FILTER (
            WHERE d.cam_icu_result IN (0, 1)
              AND d.nursingchartoffset BETWEEN 0 AND 1440
        ) AS baseline_cam_valid_count,
        COUNT(*) FILTER (
            WHERE d.cam_icu_result = 0
              AND d.nursingchartoffset BETWEEN 0 AND 1440
        ) AS baseline_cam_negative_count,
        COUNT(*) FILTER (
            WHERE d.cam_icu_result = 1
              AND d.nursingchartoffset BETWEEN 0 AND 1440
        ) AS baseline_cam_positive_count,
        COUNT(*) FILTER (
            WHERE d.any_validated_result IN (0, 1)
              AND d.nursingchartoffset BETWEEN 0 AND 1440
        ) AS baseline_any_valid_count,
        COUNT(*) FILTER (
            WHERE d.any_validated_result = 0
              AND d.nursingchartoffset BETWEEN 0 AND 1440
        ) AS baseline_any_negative_count,
        COUNT(*) FILTER (
            WHERE d.any_validated_result = 1
              AND d.nursingchartoffset BETWEEN 0 AND 1440
        ) AS baseline_any_positive_count
    FROM elderly AS e
    LEFT JOIN eicu_delirium_events AS d
        ON e.patientunitstayid = d.patientunitstayid
       AND d.nursingchartoffset BETWEEN 0 AND 1440
    GROUP BY e.patientunitstayid
)
SELECT
    e.*,
    COALESCE(b.baseline_cam_valid_count, 0) AS baseline_cam_valid_count,
    COALESCE(b.baseline_cam_negative_count, 0) AS baseline_cam_negative_count,
    COALESCE(b.baseline_cam_positive_count, 0) AS baseline_cam_positive_count,
    COALESCE(b.baseline_any_valid_count, 0) AS baseline_any_valid_count,
    COALESCE(b.baseline_any_negative_count, 0) AS baseline_any_negative_count,
    COALESCE(b.baseline_any_positive_count, 0) AS baseline_any_positive_count,
    CASE
        WHEN COALESCE(b.baseline_cam_positive_count, 0) = 0
        THEN 1 ELSE 0
    END AS loose_cam_eligible,
    CASE
        WHEN COALESCE(b.baseline_cam_positive_count, 0) = 0
         AND COALESCE(b.baseline_cam_negative_count, 0) > 0
        THEN 1 ELSE 0
    END AS strict_cam_eligible,
    CASE
        WHEN COALESCE(b.baseline_any_positive_count, 0) = 0
        THEN 1 ELSE 0
    END AS loose_any_screen_eligible,
    CASE
        WHEN COALESCE(b.baseline_any_positive_count, 0) = 0
         AND COALESCE(b.baseline_any_negative_count, 0) > 0
        THEN 1 ELSE 0
    END AS strict_any_screen_eligible
FROM elderly AS e
LEFT JOIN baseline AS b
    ON e.patientunitstayid = b.patientunitstayid;

CREATE UNIQUE INDEX eicu_trajectory_cohort_stay_idx
    ON eicu_trajectory_cohort (patientunitstayid);

DROP TABLE IF EXISTS eicu_daily_delirium CASCADE;
CREATE TABLE eicu_daily_delirium AS
WITH day_grid AS (
    SELECT
        c.*,
        d.icu_day,
        (d.icu_day - 1) * 1440 AS day_start_offset,
        d.icu_day * 1440 AS day_end_offset
    FROM eicu_trajectory_cohort AS c
    CROSS JOIN GENERATE_SERIES(2, 5) AS d(icu_day)
),
daily_counts AS (
    SELECT
        g.patientunitstayid,
        g.icu_day,
        COUNT(*) FILTER (WHERE e.cam_icu_result = 1) AS cam_positive_count,
        COUNT(*) FILTER (WHERE e.cam_icu_result = 0) AS cam_negative_count,
        COUNT(*) FILTER (
            WHERE e.any_validated_result = 1
        ) AS any_positive_count,
        COUNT(*) FILTER (
            WHERE e.any_validated_result = 0
        ) AS any_negative_count,
        COUNT(*) FILTER (WHERE e.unassessable = 1) AS unassessable_count
    FROM day_grid AS g
    LEFT JOIN eicu_delirium_events AS e
        ON g.patientunitstayid = e.patientunitstayid
       AND e.nursingchartoffset > g.day_start_offset
       AND e.nursingchartoffset <= LEAST(
            g.day_end_offset,
            g.unitdischargeoffset
       )
    GROUP BY g.patientunitstayid, g.icu_day
)
SELECT
    g.patientunitstayid,
    g.patienthealthsystemstayid,
    g.uniquepid,
    g.hospitalid,
    g.age,
    g.gender,
    g.ethnicity,
    g.unittype,
    g.unitadmitsource,
    g.unitstaytype,
    g.unitdischargeoffset,
    g.unitdischargestatus,
    g.icu_day,
    g.day_start_offset,
    g.day_end_offset,
    g.loose_cam_eligible,
    g.strict_cam_eligible,
    g.loose_any_screen_eligible,
    g.strict_any_screen_eligible,
    COALESCE(d.cam_positive_count, 0) AS cam_positive_count,
    COALESCE(d.cam_negative_count, 0) AS cam_negative_count,
    COALESCE(d.any_positive_count, 0) AS any_positive_count,
    COALESCE(d.any_negative_count, 0) AS any_negative_count,
    COALESCE(d.unassessable_count, 0) AS unassessable_count,
    CASE
        WHEN g.unitdischargestatus = 'Expired'
         AND g.unitdischargeoffset <= g.day_start_offset
            THEN 'dead_before_day'
        WHEN g.unitdischargeoffset <= g.day_start_offset
            THEN 'discharged_before_day'
        WHEN COALESCE(d.cam_positive_count, 0) > 0
            THEN 'positive'
        WHEN COALESCE(d.cam_negative_count, 0) > 0
            THEN 'negative'
        WHEN COALESCE(d.unassessable_count, 0) > 0
            THEN 'unassessable'
        WHEN g.unitdischargestatus = 'Expired'
         AND g.unitdischargeoffset <= g.day_end_offset
            THEN 'dead_during_day'
        WHEN g.unitdischargeoffset <= g.day_end_offset
            THEN 'discharged_during_day'
        ELSE 'missing'
    END AS cam_daily_state,
    CASE
        WHEN COALESCE(d.cam_positive_count, 0) > 0 THEN 1
        WHEN COALESCE(d.cam_negative_count, 0) > 0 THEN 0
    END AS cam_daily_delirium,
    CASE
        WHEN COALESCE(d.any_positive_count, 0) > 0 THEN 1
        WHEN COALESCE(d.any_negative_count, 0) > 0 THEN 0
    END AS any_screen_daily_delirium
FROM day_grid AS g
LEFT JOIN daily_counts AS d
    ON g.patientunitstayid = d.patientunitstayid
   AND g.icu_day = d.icu_day;

CREATE UNIQUE INDEX eicu_daily_delirium_stay_day_idx
    ON eicu_daily_delirium (patientunitstayid, icu_day);
CREATE INDEX eicu_daily_delirium_hospital_day_idx
    ON eicu_daily_delirium (hospitalid, icu_day);

ANALYZE eicu_delirium_events;
ANALYZE eicu_trajectory_cohort;
ANALYZE eicu_daily_delirium;
