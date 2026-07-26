[CmdletBinding()]
param(
    [string]$Psql = 'psql',
    [string]$Python = 'python',
    [string]$HostName = '127.0.0.1',
    [int]$Port = 5432,
    [string]$DatabaseUser = 'postgres'
)

$ErrorActionPreference = 'Stop'
$psql = $Psql
$python = $Python
$outputDirectory = Join-Path $PSScriptRoot 'results\qa'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$env:PGHOST = $HostName
$env:PGPORT = [string]$Port
$env:PGUSER = $DatabaseUser

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Export-Query {
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $path = (Join-Path $outputDirectory $FileName) -replace '\\', '/'
    $command = "\copy ($Query) TO '$path' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8')"
    & $psql -X -v ON_ERROR_STOP=1 -d eicu -c $command
    if ($LASTEXITCODE -ne 0) {
        throw "Export failed: $FileName"
    }
}

Write-Step 'Auditing eICU temperature sources and unit conversion'
& $psql -X -v ON_ERROR_STOP=1 -d eicu `
    -f (Join-Path $PSScriptRoot 'sql\trajectory_pipeline\15_qa_eicu_temperature.sql')
if ($LASTEXITCODE -ne 0) {
    throw 'eICU temperature audit failed.'
}

Export-Query `
    -Query 'SELECT * FROM delirium_trajectory.eicu_temperature_source_audit ORDER BY source' `
    -FileName 'eicu_temperature_source_audit.csv'
Export-Query `
    -Query 'SELECT * FROM delirium_trajectory.eicu_temperature_pair_agreement' `
    -FileName 'eicu_temperature_pair_agreement.csv'
Export-Query `
    -Query 'SELECT * FROM delirium_trajectory.eicu_temperature_cross_source_agreement ORDER BY match_window_minutes' `
    -FileName 'eicu_temperature_cross_source_agreement.csv'
Export-Query `
    -Query 'SELECT * FROM delirium_trajectory.eicu_temperature_stay_summary' `
    -FileName 'eicu_temperature_stay_summary.csv'
Export-Query `
    -Query 'SELECT * FROM delirium_trajectory.eicu_temperature_value_distribution ORDER BY frequency_rank, temperature_c_rounded' `
    -FileName 'eicu_temperature_value_distribution.csv'

Write-Step 'Explaining assessment selection and hospital representation'
& $python (Join-Path $PSScriptRoot '16_analyze_assessment_selection.py') $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw 'Assessment-selection diagnostics failed.'
}

Write-Step 'Post-hoc diagnostics completed successfully'
