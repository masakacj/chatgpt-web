#requires -Version 5.1
<#
Pair the Windows Skylab DevSpace connector with its pre-created named
Cloudflare Tunnel. The one-time code is not a Cloudflare credential.
Never prints, uploads to GitHub, or passes the connector token on a CLI.
The existing DevSpace owner OAuth credential is preserved by the installer.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PairCode
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$State = Join-Path $env:LOCALAPPDATA 'SkylabDevSpace'
$TokenFile = Join-Path $State 'tunnel-token.dpapi'
$Installer = Join-Path $env:TEMP 'Deploy-Skylab-DevSpace.ps1'
$InstallUrl = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/6370465e61fc711f27b27b7b75b69e1048c2dabd/tools/skylab-devspace/install.ps1'
$ExpectedHash = 'DB7D35DBD368CDDA4213F480950E77C48DAAECE79B1BDD8D18CB4B1E9FA75F26'
$Hostname = 'skylab-mcp.78175132.xyz'
$TunnelId = 'f13ef98c-9052-40c7-811b-9120ce08363c'
$Bootstrap = 'https://skylab-pair.78175132.xyz/skylab-pair'
try {
  New-Item -ItemType Directory -Path $State -Force | Out-Null
  if (-not (Test-Path -LiteralPath $TokenFile -PathType Leaf)) {
    Write-Host '[Skylab] Requesting one-time pairing from mcpdebian...'
    $Response = Invoke-RestMethod -Uri $Bootstrap -Method Post -Headers @{'X-Skylab-Pair'=$PairCode} -TimeoutSec 35
    if ($Response.hostname -cne $Hostname -or $Response.tunnel_id -cne $TunnelId -or
        -not ($Response.token -is [string]) -or $Response.token.Length -lt 50) {
      throw 'Unexpected tunnel identity or empty token; nothing saved.'
    }
    $Protected = ConvertTo-SecureString ([string]$Response.token) -AsPlainText -Force |
      ConvertFrom-SecureString
    Set-Content -LiteralPath $TokenFile -Value $Protected -Encoding ASCII -NoNewline
    Remove-Variable Response,Protected -ErrorAction SilentlyContinue
    Write-Host '[Skylab] Tunnel token protected with Windows user DPAPI.'
  } else {
    Write-Host '[Skylab] Existing user-protected tunnel token found; reusing it.'
  }
  if (-not (Test-Path -LiteralPath $Installer -PathType Leaf) -or
      (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash -ine $ExpectedHash) {
    Write-Host '[Skylab] Downloading pinned DevSpace installer...'
    Invoke-WebRequest -UseBasicParsing -Uri $InstallUrl -OutFile $Installer -ErrorAction Stop
  }
  if ((Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash -ine $ExpectedHash) {
    throw 'Pinned installer checksum failed; not executing.'
  }
  Write-Host "[Skylab] Switching to fixed tunnel https://$Hostname/mcp ..."
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Mode Named -PublicUrl ("https://" + $Hostname)
  if ($LASTEXITCODE -ne 0) { throw "DevSpace named-tunnel installer exited $LASTEXITCODE" }
  Write-Host "[Skylab] CONNECTOR DEPLOYED; URL: https://$Hostname/mcp"
} finally {
  Remove-Variable PairCode -ErrorAction SilentlyContinue
}
