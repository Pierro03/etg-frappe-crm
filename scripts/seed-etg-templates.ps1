param(
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [string]$BaseUrl = "http://crm.localhost:8000"
)

$ErrorActionPreference = "Stop"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Invoke-RestMethod -Uri "$BaseUrl/api/method/login" -Method Post -Body @{
    usr = "Administrator"
    pwd = $Password
} -WebSession $session | Out-Null

$templates = @(
    @{
        template_name = "ETG API Partnership Introduction"
        subject = "Exploring an ETG API distribution partnership"
        response = @"
<p>Hello {{ doc.first_name }},</p>
<p>We identified {{ doc.organization or doc.first_name }} while researching travel platforms that could benefit from broader accommodation distribution.</p>
<p>ETG provides API access to global accommodation inventory. I would like to understand your current supply model and whether an integration discussion would be useful.</p>
<p>Would you be open to a short introductory conversation?</p>
<p>Regards,<br>ETG Partnerships</p>
"@
    },
    @{
        template_name = "ETG API Partnership Follow-up"
        subject = "Following up on ETG accommodation distribution"
        response = @"
<p>Hello {{ doc.first_name }},</p>
<p>I am following up on the potential fit between {{ doc.organization or doc.first_name }} and ETG's accommodation API.</p>
<p>If distribution coverage, supply depth, or API connectivity is currently a priority, we can prepare a focused integration discussion.</p>
<p>Is there a colleague who owns partnerships or accommodation supply integrations?</p>
<p>Regards,<br>ETG Partnerships</p>
"@
    },
    @{
        template_name = "ETG Sales Handoff Summary"
        subject = "Qualified ETG API opportunity: {{ doc.organization or doc.first_name }}"
        response = @"
<p>A Sales Intelligence lead is ready for Sales review.</p>
<p><strong>Organization:</strong> {{ doc.organization or doc.first_name }}<br>
<strong>Fit score:</strong> {{ doc.lead_score }}/100<br>
<strong>Platform type:</strong> {{ doc.platform_type }}<br>
<strong>Markets:</strong> {{ doc.markets_served }}</p>
<p>Review qualification notes and conversation history before accepting the handoff.</p>
"@
    }
)

$type = [uri]::EscapeDataString("Email Template")
foreach ($template in $templates) {
    $name = [uri]::EscapeDataString($template.template_name)
    $payload = @{
        doctype = "Email Template"
        name = $template.template_name
        subject = $template.subject
        response = $template.response
        use_html = 1
    }

    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$type/$name" -Method Put `
            -ContentType "application/json" -Body ($payload | ConvertTo-Json -Depth 4) `
            -WebSession $session | Out-Null
        Write-Output "Updated: $($template.template_name)"
    } catch {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$type" -Method Post `
            -ContentType "application/json" -Body ($payload | ConvertTo-Json -Depth 4) `
            -WebSession $session | Out-Null
        Write-Output "Created: $($template.template_name)"
    }
}
