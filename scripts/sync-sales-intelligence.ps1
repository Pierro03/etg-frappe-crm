param(
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [string]$BaseUrl = "http://crm.localhost:8000",
    [string]$CsvPath = "..\outputs\apollo_platform_research\hotel_travel_platform_research.csv"
)

$ErrorActionPreference = "Stop"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

Invoke-RestMethod -Uri "$BaseUrl/api/method/login" -Method Post -Body @{
    usr = "Administrator"
    pwd = $Password
} -WebSession $session | Out-Null

function Get-EncodedType([string]$Doctype) {
    return [uri]::EscapeDataString($Doctype)
}

function Get-MatchKey([string]$Value) {
    if (-not $Value) { return "" }
    $valueWithLatinI = $Value.Replace([char]0x0131, "i")
    $decomposed = $valueWithLatinI.Normalize([Text.NormalizationForm]::FormD)
    $withoutMarks = -join ($decomposed.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne `
            [Globalization.UnicodeCategory]::NonSpacingMark
    })
    return ($withoutMarks.ToLowerInvariant() -replace "[^a-z0-9]", "")
}

function Ensure-NamedRecord([string]$Doctype, [string]$Name, [string]$Fieldname) {
    $type = Get-EncodedType $Doctype
    $recordName = [uri]::EscapeDataString($Name)
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$type/$recordName" -WebSession $session | Out-Null
    } catch {
        $record = @{ doctype = $Doctype }
        $record[$Fieldname] = $Name
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$type" -Method Post `
            -ContentType "application/json" -Body ($record | ConvertTo-Json) `
            -WebSession $session | Out-Null
    }
}

Ensure-NamedRecord "CRM Lead Source" "Sales Intelligence" "source_name"
Ensure-NamedRecord "CRM Industry" "Travel Technology" "industry"

$rows = Import-Csv $CsvPath
$leadType = Get-EncodedType "CRM Lead"
$leadFields = [uri]::EscapeDataString('["name","organization"]')
$leadFilters = [uri]::EscapeDataString('[["source","=","Sales Intelligence"]]')
$leadRows = (Invoke-RestMethod `
    -Uri "$BaseUrl/api/resource/${leadType}?fields=$leadFields&filters=$leadFilters&limit_page_length=500" `
    -WebSession $session).data
$leadByOrganization = @{}
foreach ($leadRow in $leadRows) {
    $key = Get-MatchKey $leadRow.organization
    if (-not $leadByOrganization.ContainsKey($key)) {
        $leadByOrganization[$key] = $leadRow
    }
}
$created = 0
$updated = 0

foreach ($row in $rows) {
    $organizationName = $row.platform_name.Trim()
    if (-not $organizationName) { continue }

    $employees = if ($row.employee_count -in @(
        "1-10", "11-50", "51-200", "201-500", "501-1000", "1000+"
    )) { $row.employee_count } else { "" }

    $description = @(
        "Platform type: $($row.platform_type)",
        "Headquarters: $($row.headquarters)",
        "Markets: $($row.markets_served)",
        "Research confidence: $($row.confidence)"
    ) -join "`n"

    $organization = @{
        doctype = "CRM Organization"
        organization_name = $organizationName
        industry = "Travel Technology"
        no_of_employees = $employees
        company_description = $description
    }

    if ($row.matched_website -and $row.matched_website -notmatch "linkedin\.com|owler\.com") {
        $organization.website = $row.matched_website
    }

    $organizationType = Get-EncodedType "CRM Organization"
    $encodedOrganization = [uri]::EscapeDataString($organizationName)
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$organizationType/$encodedOrganization" `
            -Method Put -ContentType "application/json" `
            -Body ($organization | ConvertTo-Json -Depth 4) -WebSession $session | Out-Null
    } catch {
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/$organizationType" `
                -Method Post -ContentType "application/json" `
                -Body ($organization | ConvertTo-Json -Depth 4) -WebSession $session | Out-Null
        } catch {
            if ($_.ErrorDetails.Message -notmatch "DuplicateEntryError") { throw }
        }
    }

    $lead = @{
        doctype = "CRM Lead"
        first_name = $organizationName
        organization = $organizationName
        source = "Sales Intelligence"
        industry = "Travel Technology"
        intelligence_confidence = $row.confidence
        platform_type = $row.platform_type
        markets_served = $row.markets_served
        source_count = [int]($row.source_count)
        research_sources = $row.source_urls
        company_description = $description
    }

    $organizationKey = Get-MatchKey $organizationName
    $existing = $leadByOrganization[$organizationKey]
    if ($existing) {
        $leadName = [uri]::EscapeDataString($existing.name)
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$leadType/$leadName" `
            -Method Put -ContentType "application/json" -Body ($lead | ConvertTo-Json -Depth 4) `
            -WebSession $session | Out-Null
        $updated++
    } else {
        $lead.status = "New"
        $lead.lead_owner = "Administrator"
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$leadType" `
            -Method Post -ContentType "application/json" -Body ($lead | ConvertTo-Json -Depth 4) `
            -WebSession $session | ForEach-Object {
                $leadByOrganization[$organizationKey] = $_.data
            }
        $created++
    }
}

Write-Output "Sales Intelligence synchronization complete."
Write-Output "Created: $created"
Write-Output "Updated: $updated"
