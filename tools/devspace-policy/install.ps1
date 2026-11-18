# R4 DevSpace policy one-click installer: base v2 + bash.command correction + detached restart.
[CmdletBinding()]
param(
  [ValidateSet('apply','check','status','rollback')][string]$Action = 'apply',
  [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
$BaseUrl = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/fa01199a0760930e7246ba04c30df6b44e48caba/tools/devspace-policy/install.ps1'
$RestartUrl = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/f5efb0adc5d24d3d61b6e0bcd3706b0167849865/tools/devspace-policy/restart-managed.ps1'
$FixUrl = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/6e89a45a9014334ebf96cb8dbb1b519587bae84b/tools/devspace-policy/fix-bash-parameter.mjs'
$BaseSha = '2030122ffe48f2ed9c40a3c4aa171198550778691539a26a1da6a2ed968ae365'
$RestartSha = '5d7424c2963b22e9714143dbd0e7b1d8c67e332a10c9f49f7ffb8367cedf713a'
$FixSha = 'f2ebb1b83358d8e3eadbaaa6267b35420a2735a2b5089236ed376563c39a9960'
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('devspace-policy-r4-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Temp | Out-Null
try {
  $Base = Join-Path $Temp 'install-base.ps1'
  $Fix = Join-Path $Temp 'fix-bash-parameter.mjs'
  $Restart = Join-Path $Temp 'restart-managed.ps1'
  foreach ($entry in @(
    @($BaseUrl,$Base,$BaseSha),
    @($FixUrl,$Fix,$FixSha),
    @($RestartUrl,$Restart,$RestartSha)
  )) {
    Invoke-WebRequest -UseBasicParsing -Uri $entry[0] -OutFile $entry[1]
    if ((Get-FileHash -LiteralPath $entry[1] -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry[2]) {
      throw ('Download SHA-256 mismatch: ' + $entry[1])
    }
  }
  & node --check $Fix
  if ($LASTEXITCODE -ne 0) { throw 'R4 correction syntax check failed' }

  switch ($Action) {
    'check' {
      & $Base -Action check
      if (-not $?) { throw 'Base policy preflight failed' }
      & node $Fix check
      if ($LASTEXITCODE -ne 0) { throw 'R4 preflight failed' }
    }
    'status' {
      & $Base -Action status
      if (-not $?) { throw 'Base policy status failed' }
      & node $Fix status
      if ($LASTEXITCODE -ne 0) { throw 'R4 status failed' }
    }
    'apply' {
      & $Base -Action apply -NoRestart
      if (-not $?) { throw 'Base policy install failed' }
      & node $Fix apply
      if ($LASTEXITCODE -ne 0) { throw 'R4 correction failed' }
    }
    'rollback' {
      & node $Fix rollback
      if ($LASTEXITCODE -ne 0) { throw 'R4 correction rollback failed' }
      & $Base -Action rollback -NoRestart
      if (-not $?) { throw 'Base policy rollback failed' }
    }
  }
  if (($Action -eq 'apply' -or $Action -eq 'rollback') -and -not $NoRestart) {
    $metaJson = & node $Fix status
    if ($LASTEXITCODE -ne 0) { throw 'Final source integrity check failed' }
    $meta = $metaJson | ConvertFrom-Json
    if (-not $meta.manifestMatches) { throw 'Final manifest and source SHA-256 do not match' }
    & $Restart -Action dispatch -Target ([string]$meta.target) -PatchedSha ([string]$meta.sourceSHA256)
    if (-not $?) { throw 'DevSpace restart dispatch failed' }
  }
} finally {
  Remove-Item -LiteralPath $Temp -Force -Recurse -ErrorAction SilentlyContinue
}
