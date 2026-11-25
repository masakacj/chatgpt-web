#requires -Version 5.1
<#
Prepare the normal ChatGPT custom MCP connection page in the current user's
desktop session. Only the public URL goes to the clipboard. Does not read
Owner credentials, click permission/consent controls, or submit a connector.
#>
param([Parameter(Mandatory=$true)][string]$ReceiptFile)
$ErrorActionPreference='Stop'
$r=Get-Content -LiteralPath $ReceiptFile -Raw|ConvertFrom-Json
if($r.status -ne 'ready'){throw 'Deployment receipt is not ready'}
$u=[uri]$r.mcpUrl
if($u.Scheme -ne 'https' -or $u.AbsolutePath -ne '/mcp' -or $u.UserInfo -or $u.Query -or $u.Fragment){throw 'Invalid public MCP URL'}
Set-Clipboard -Value $u.AbsoluteUri
Start-Process 'https://chatgpt.com/plugins'
Write-Output ('MCP name: '+$r.name)
Write-Output 'Public MCP URL copied. Select Add custom MCP server, paste the URL, use OAuth, and review/approve the connection yourself.'

