\set ON_ERROR_STOP on

-- Partial index for sparse nursing assessments used by this study. This avoids
-- repeatedly scanning the full 433-million-row chartevents table.
CREATE INDEX IF NOT EXISTS chartevents_delirium_nursing_idx
ON mimiciv_icu.chartevents (stay_id, charttime, itemid)
WHERE itemid IN (
    223781, 223791, 224409, 225113, 227881, 229702,
    228096,
    228300, 228301, 228302, 228303, 228332,
    228334, 228335, 228336, 228337, 228688,
    229324, 229325, 229326,
    224063, 224064, 224068,
    227669, 227670, 227671, 227678, 227679, 227680, 227682,
    227945, 227948, 227950, 227959, 227962, 227965
);

ANALYZE mimiciv_icu.chartevents;
