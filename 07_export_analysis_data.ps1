[CmdletBinding()]
param(
    [string]$Psql = 'psql',
    [string]$HostName = '127.0.0.1',
    [int]$Port = 5432,
    [string]$DatabaseUser = 'postgres'
)

$ErrorActionPreference = 'Stop'
$psql = $Psql
$outputDirectory = Join-Path $PSScriptRoot 'data'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$env:PGHOST = $HostName
$env:PGPORT = [string]$Port
$env:PGUSER = $DatabaseUser

function Export-Query {
    param(
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $path = (Join-Path $outputDirectory $FileName) -replace '\\', '/'
    $command = "\copy ($Query) TO '$path' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8')"
    & $psql -X -v ON_ERROR_STOP=1 -d $Database -c $command
    if ($LASTEXITCODE -ne 0) {
        throw "Export failed: $FileName"
    }
}

Export-Query -Database mimiciv -FileName 'mimic_daily_long.csv' -Query @'
SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    d.icu_day,
    d.daily_state,
    d.daily_delirium,
    d.strict_incident_eligible AS strict_eligible,
    d.loose_incident_eligible AS loose_eligible
FROM delirium_trajectory.mimic_daily_delirium d
ORDER BY d.stay_id, d.icu_day
'@

Export-Query -Database mimiciv -FileName 'mimic_features_outcomes.csv' -Query @'
SELECT
    f.*,
    o.strict_eligible AS trajectory_strict_eligible,
    o.loose_eligible AS trajectory_loose_eligible,
    o.valid_outcome_days,
    o.delirium_positive_days,
    o.first_positive_day,
    o.last_positive_day,
    o.any_delirium_day2_5,
    o.late_persistent_delirium
FROM mimiciv_delirium.delirium_mimiciv_all_eligible f
JOIN delirium_trajectory.mimic_outcome_summary o USING (stay_id)
ORDER BY f.stay_id
'@

Export-Query -Database eicu -FileName 'eicu_daily_long.csv' -Query @'
SELECT
    d.patientunitstayid,
    d.patienthealthsystemstayid,
    d.uniquepid,
    d.hospitalid,
    d.icu_day,
    d.cam_daily_state,
    d.cam_daily_delirium,
    d.any_screen_daily_delirium,
    d.strict_cam_eligible AS strict_eligible,
    d.loose_cam_eligible AS loose_eligible
FROM delirium_trajectory.eicu_daily_delirium d
ORDER BY d.patientunitstayid, d.icu_day
'@

Export-Query -Database eicu -FileName 'eicu_features_outcomes.csv' -Query @'
SELECT
    f.*,
    o.strict_eligible AS trajectory_strict_eligible,
    o.loose_eligible AS trajectory_loose_eligible,
    o.valid_outcome_days,
    o.delirium_positive_days,
    o.first_positive_day,
    o.last_positive_day,
    o.any_delirium_day2_5,
    o.late_persistent_delirium,
    o.valid_any_screen_days,
    o.any_screen_delirium_day2_5
FROM delirium_trajectory.eicu_features_24h f
JOIN delirium_trajectory.eicu_outcome_summary o USING (patientunitstayid)
ORDER BY f.patientunitstayid
'@

Get-ChildItem -LiteralPath $outputDirectory -Filter '*.csv' |
    Select-Object Name, Length, LastWriteTime |
    Format-Table -AutoSize
