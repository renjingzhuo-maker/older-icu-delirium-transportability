\set ON_ERROR_STOP on

SET search_path TO delirium_trajectory, eicu_crd, public;

CREATE TEMP TABLE strict_temperature_cohort AS
SELECT f.patientunitstayid
FROM delirium_trajectory.eicu_features_24h f
JOIN delirium_trajectory.eicu_outcome_summary o USING (patientunitstayid)
WHERE o.strict_eligible = 1
  AND o.valid_outcome_days >= 2;

CREATE UNIQUE INDEX strict_temperature_cohort_stay_idx
    ON strict_temperature_cohort (patientunitstayid);

CREATE TEMP TABLE nurse_temperature_audit_rows AS
SELECT
    n.patientunitstayid,
    n.nursingchartoffset,
    n.nursingchartentryoffset,
    n.nursingchartcelltypevalname AS unit_name,
    CASE
        WHEN BTRIM(n.nursingchartvalue) ~ '^-?[0-9]+([.][0-9]+)?$'
        THEN BTRIM(n.nursingchartvalue)::numeric
    END AS raw_value
FROM eicu_crd.nursecharting n
JOIN strict_temperature_cohort s USING (patientunitstayid)
WHERE n.nursingchartoffset >= 0
  AND n.nursingchartoffset < 1440
  AND n.nursingchartcelltypevallabel = 'Temperature'
  AND n.nursingchartcelltypevalname IN ('Temperature (C)', 'Temperature (F)');

ALTER TABLE nurse_temperature_audit_rows ADD COLUMN temperature_c numeric;

UPDATE nurse_temperature_audit_rows
SET temperature_c = CASE
    WHEN unit_name = 'Temperature (C)' AND raw_value BETWEEN 25 AND 45
        THEN raw_value
    WHEN unit_name = 'Temperature (F)' AND raw_value BETWEEN 77 AND 113
        THEN (raw_value - 32) * 5.0 / 9.0
END;

CREATE INDEX nurse_temperature_audit_pair_idx
    ON nurse_temperature_audit_rows
       (patientunitstayid, nursingchartoffset, nursingchartentryoffset, unit_name);

CREATE TEMP TABLE periodic_temperature_audit_rows AS
SELECT
    v.patientunitstayid,
    v.observationoffset,
    v.temperature
FROM eicu_crd.vitalperiodic v
JOIN strict_temperature_cohort s USING (patientunitstayid)
WHERE v.observationoffset >= 0
  AND v.observationoffset < 1440
  AND v.temperature IS NOT NULL;

CREATE INDEX periodic_temperature_audit_pair_idx
    ON periodic_temperature_audit_rows (patientunitstayid, observationoffset);

DROP TABLE IF EXISTS delirium_trajectory.eicu_temperature_source_audit;
CREATE TABLE delirium_trajectory.eicu_temperature_source_audit AS
WITH source_rows AS (
    SELECT
        unit_name AS source,
        COUNT(*) AS raw_rows,
        COUNT(temperature_c) AS valid_rows,
        COUNT(*) - COUNT(temperature_c) AS rejected_rows,
        COUNT(DISTINCT patientunitstayid)
            FILTER (WHERE temperature_c IS NOT NULL) AS observed_stays,
        MIN(temperature_c) AS minimum_c,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY temperature_c) AS p01_c,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY temperature_c) AS median_c,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY temperature_c) AS p99_c,
        MAX(temperature_c) AS maximum_c
    FROM nurse_temperature_audit_rows
    GROUP BY unit_name
    UNION ALL
    SELECT
        'vitalPeriodic' AS source,
        COUNT(*) AS raw_rows,
        COUNT(*) FILTER (WHERE temperature BETWEEN 25 AND 45) AS valid_rows,
        COUNT(*) FILTER (WHERE temperature NOT BETWEEN 25 AND 45) AS rejected_rows,
        COUNT(DISTINCT patientunitstayid)
            FILTER (WHERE temperature BETWEEN 25 AND 45) AS observed_stays,
        MIN(temperature) FILTER (WHERE temperature BETWEEN 25 AND 45) AS minimum_c,
        PERCENTILE_CONT(0.01) WITHIN GROUP (
            ORDER BY temperature
        ) FILTER (WHERE temperature BETWEEN 25 AND 45) AS p01_c,
        PERCENTILE_CONT(0.50) WITHIN GROUP (
            ORDER BY temperature
        ) FILTER (WHERE temperature BETWEEN 25 AND 45) AS median_c,
        PERCENTILE_CONT(0.99) WITHIN GROUP (
            ORDER BY temperature
        ) FILTER (WHERE temperature BETWEEN 25 AND 45) AS p99_c,
        MAX(temperature) FILTER (WHERE temperature BETWEEN 25 AND 45) AS maximum_c
    FROM periodic_temperature_audit_rows
    UNION ALL
    SELECT
        'final_combined_feature' AS source,
        COUNT(*) AS raw_rows,
        COUNT(temperature_min) AS valid_rows,
        0 AS rejected_rows,
        COUNT(temperature_min) AS observed_stays,
        MIN(temperature_min) AS minimum_c,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY temperature_min) AS p01_c,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY temperature_mean) AS median_c,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY temperature_max) AS p99_c,
        MAX(temperature_max) AS maximum_c
    FROM delirium_trajectory.eicu_features_24h f
    JOIN strict_temperature_cohort s USING (patientunitstayid)
)
SELECT
    source,
    raw_rows,
    valid_rows,
    rejected_rows,
    observed_stays,
    (SELECT COUNT(*) FROM strict_temperature_cohort) AS strict_cohort_stays,
    observed_stays::numeric
        / (SELECT COUNT(*) FROM strict_temperature_cohort) AS stay_coverage,
    minimum_c,
    p01_c,
    median_c,
    p99_c,
    maximum_c
FROM source_rows
ORDER BY source;

DROP TABLE IF EXISTS delirium_trajectory.eicu_temperature_pair_agreement;
CREATE TABLE delirium_trajectory.eicu_temperature_pair_agreement AS
WITH paired AS (
    SELECT
        c.patientunitstayid,
        ABS(c.temperature_c - f.temperature_c) AS absolute_difference_c
    FROM nurse_temperature_audit_rows c
    JOIN nurse_temperature_audit_rows f
      USING (patientunitstayid, nursingchartoffset, nursingchartentryoffset)
    WHERE c.unit_name = 'Temperature (C)'
      AND f.unit_name = 'Temperature (F)'
      AND c.temperature_c IS NOT NULL
      AND f.temperature_c IS NOT NULL
)
SELECT
    COUNT(*) AS paired_rows,
    COUNT(DISTINCT patientunitstayid) AS paired_stays,
    AVG(absolute_difference_c) AS mean_absolute_difference_c,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY absolute_difference_c
    ) AS median_absolute_difference_c,
    PERCENTILE_CONT(0.99) WITHIN GROUP (
        ORDER BY absolute_difference_c
    ) AS p99_absolute_difference_c,
    MAX(absolute_difference_c) AS maximum_absolute_difference_c,
    AVG((absolute_difference_c <= 0.06)::int) AS proportion_within_006_c
FROM paired;

DROP TABLE IF EXISTS delirium_trajectory.eicu_temperature_cross_source_agreement;
CREATE TABLE delirium_trajectory.eicu_temperature_cross_source_agreement AS
WITH nearest_periodic AS (
    SELECT
        n.patientunitstayid,
        n.temperature_c AS nurse_temperature_c,
        p.temperature AS periodic_temperature_c,
        ABS(n.nursingchartoffset - p.observationoffset) AS time_difference_minutes
    FROM nurse_temperature_audit_rows n
    CROSS JOIN LATERAL (
        SELECT
            v.observationoffset,
            v.temperature
        FROM periodic_temperature_audit_rows v
        WHERE v.patientunitstayid = n.patientunitstayid
          AND v.temperature BETWEEN 25 AND 45
          AND ABS(v.observationoffset - n.nursingchartoffset) <= 60
        ORDER BY
            ABS(v.observationoffset - n.nursingchartoffset),
            v.observationoffset
        LIMIT 1
    ) p
    WHERE n.unit_name = 'Temperature (C)'
      AND n.temperature_c IS NOT NULL
), windows AS (
    SELECT UNNEST(ARRAY[15, 30, 60]) AS match_window_minutes
)
SELECT
    w.match_window_minutes,
    COUNT(*) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS paired_rows,
    COUNT(DISTINCT m.patientunitstayid) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS paired_stays,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY m.time_difference_minutes
    ) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS median_time_difference_minutes,
    AVG(m.nurse_temperature_c - m.periodic_temperature_c) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS mean_nurse_minus_periodic_c,
    STDDEV_SAMP(m.nurse_temperature_c - m.periodic_temperature_c) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS sd_nurse_minus_periodic_c,
    AVG(ABS(m.nurse_temperature_c - m.periodic_temperature_c)) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS mean_absolute_difference_c,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY ABS(m.nurse_temperature_c - m.periodic_temperature_c)
    ) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS median_absolute_difference_c,
    CORR(m.nurse_temperature_c, m.periodic_temperature_c) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS pearson_correlation,
    AVG(m.nurse_temperature_c - m.periodic_temperature_c) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) - 1.96 * STDDEV_SAMP(
        m.nurse_temperature_c - m.periodic_temperature_c
    ) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS lower_loa_c,
    AVG(m.nurse_temperature_c - m.periodic_temperature_c) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) + 1.96 * STDDEV_SAMP(
        m.nurse_temperature_c - m.periodic_temperature_c
    ) FILTER (
        WHERE m.time_difference_minutes <= w.match_window_minutes
    ) AS upper_loa_c
FROM windows w
CROSS JOIN nearest_periodic m
GROUP BY w.match_window_minutes
ORDER BY w.match_window_minutes;

DROP TABLE IF EXISTS delirium_trajectory.eicu_temperature_value_distribution;
CREATE TABLE delirium_trajectory.eicu_temperature_value_distribution AS
WITH rounded_values AS (
    SELECT ROUND(temperature_c, 1) AS temperature_c_rounded
    FROM nurse_temperature_audit_rows
    WHERE unit_name = 'Temperature (C)'
      AND temperature_c IS NOT NULL
), counts AS (
    SELECT temperature_c_rounded, COUNT(*) AS rows
    FROM rounded_values
    GROUP BY temperature_c_rounded
)
SELECT
    temperature_c_rounded,
    rows,
    rows::numeric / SUM(rows) OVER () AS proportion,
    RANK() OVER (ORDER BY rows DESC) AS frequency_rank
FROM counts
ORDER BY rows DESC, temperature_c_rounded;

DROP TABLE IF EXISTS delirium_trajectory.eicu_temperature_stay_summary;
CREATE TABLE delirium_trajectory.eicu_temperature_stay_summary AS
WITH stay_counts AS (
    SELECT
        patientunitstayid,
        COUNT(*) AS reading_count,
        COUNT(DISTINCT temperature_c) AS distinct_temperature_count
    FROM nurse_temperature_audit_rows
    WHERE unit_name = 'Temperature (C)'
      AND temperature_c IS NOT NULL
    GROUP BY patientunitstayid
)
SELECT
    COUNT(*) AS stays_with_nurse_temperature,
    MIN(reading_count) AS minimum_readings,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY reading_count) AS p25_readings,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY reading_count) AS median_readings,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY reading_count) AS p75_readings,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY reading_count) AS p99_readings,
    MAX(reading_count) AS maximum_readings,
    AVG((distinct_temperature_count = 1)::int) AS proportion_single_unique_value,
    AVG((reading_count >= 4)::int) AS proportion_with_at_least_four_readings
FROM stay_counts;

DO $$
DECLARE
    combined_coverage numeric;
    median_pair_difference numeric;
    largest_rounded_value_share numeric;
BEGIN
    SELECT stay_coverage
    INTO combined_coverage
    FROM delirium_trajectory.eicu_temperature_source_audit
    WHERE source = 'final_combined_feature';

    SELECT median_absolute_difference_c
    INTO median_pair_difference
    FROM delirium_trajectory.eicu_temperature_pair_agreement;

    SELECT MAX(proportion)
    INTO largest_rounded_value_share
    FROM delirium_trajectory.eicu_temperature_value_distribution;

    IF combined_coverage < 0.95 THEN
        RAISE EXCEPTION
            'Temperature coverage below audit threshold: %',
            combined_coverage;
    END IF;
    IF median_pair_difference > 0.10 THEN
        RAISE EXCEPTION
            'C/F temperature conversion disagreement exceeds 0.10 C: %',
            median_pair_difference;
    END IF;
    IF largest_rounded_value_share > 0.25 THEN
        RAISE EXCEPTION
            'Potential temperature sentinel/default-value concentration: %',
            largest_rounded_value_share;
    END IF;
END
$$;

SELECT * FROM delirium_trajectory.eicu_temperature_source_audit;
SELECT * FROM delirium_trajectory.eicu_temperature_pair_agreement;
SELECT * FROM delirium_trajectory.eicu_temperature_cross_source_agreement;
SELECT * FROM delirium_trajectory.eicu_temperature_stay_summary;
SELECT *
FROM delirium_trajectory.eicu_temperature_value_distribution
WHERE frequency_rank <= 15
ORDER BY frequency_rank, temperature_c_rounded;
