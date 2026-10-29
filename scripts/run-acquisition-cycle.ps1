param(
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [string]$BaseUrl = "http://crm.localhost:8000",
    [string]$CsvPath = "..\outputs\apollo_platform_research\hotel_travel_platform_research.csv",
    [string]$RunLog = "..\outputs\crm_acquisition_runs.jsonl"
)

$ErrorActionPreference = "Stop"
$started = Get-Date
$syncScript = Join-Path $PSScriptRoot "sync-sales-intelligence.ps1"

try {
    $output = & $syncScript -Password $Password -BaseUrl $BaseUrl -CsvPath $CsvPath
    $status = "completed"
    $errorMessage = $null
} catch {
    $output = @()
    $status = "failed"
    $errorMessage = $_.Exception.Message
}

$record = @{
    started_at = $started.ToString("o")
    finished_at = (Get-Date).ToString("o")
    status = $status
    source = (Resolve-Path $CsvPath).Path
    output = @($output)
    error = $errorMessage
} | ConvertTo-Json -Compress

$logPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $RunLog))
$logDirectory = Split-Path $logPath -Parent
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
Add-Content -Path $logPath -Value $record -Encoding UTF8

$output | Write-Output
Write-Output "Cycle status: $status"
Write-Output "Run log: $logPath"

if ($status -ne "completed") { exit 1 }
