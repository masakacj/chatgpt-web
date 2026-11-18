# DevSpace tool-use policy installer (Windows PowerShell 5.1+).
# The downloaded code is pinned by SHA-256; restart is detached so this MCP may disconnect safely.
[CmdletBinding()]
param(
  [ValidateSet('apply','check','status','rollback')][string]$Action = 'apply',
  [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
$PolicyBase = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/a28850b162344bc7595d6d8d4124fb77003b5597/tools/devspace-policy'
$RestartBase = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/f5efb0adc5d24d3d61b6e0bcd3706b0167849865/tools/devspace-policy'
$ArchiveSha = '22a131c17958493141bdafccffe643b066c1e36e72789e46c6999b11d1a7f9d8'
$ScriptSha = 'c99722874505ef0598fa30af8d41a8880297a08c3bda0b447a2a3d967a9421ae'
$RestartSha = '5d7424c2963b22e9714143dbd0e7b1d8c67e332a10c9f49f7ffb8367cedf713a'
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('devspace-tool-policy-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temp -Force | Out-Null
try {
  $Archive = Join-Path $Temp 'policy.mjs.gz'
  $Script = Join-Path $Temp 'policy.mjs'
  Invoke-WebRequest -Uri "$PolicyBase/devspace-tool-policy.mjs.gz" -OutFile $Archive -UseBasicParsing
  if ((Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant() -ne $ArchiveSha) { throw 'Archive SHA-256 mismatch' }
  $InputStream = [IO.File]::OpenRead($Archive)
  try {
    $Decompress = New-Object IO.Compression.GZipStream($InputStream, [IO.Compression.CompressionMode]::Decompress)
    try {
      $OutputStream = [IO.File]::Create($Script)
      try { $Decompress.CopyTo($OutputStream) } finally { $OutputStream.Dispose() }
    } finally { $Decompress.Dispose() }
  } finally { $InputStream.Dispose() }
  if ((Get-FileHash -Algorithm SHA256 $Script).Hash.ToLowerInvariant() -ne $ScriptSha) { throw 'Source SHA-256 mismatch' }
  & node $Script check
  if ($LASTEXITCODE -ne 0) { throw 'DevSpace preflight failed' }
  & node $Script $Action
  if ($LASTEXITCODE -ne 0) { throw "DevSpace policy operation failed: $Action" }
  if (($Action -eq 'apply' -or $Action -eq 'rollback') -and -not $NoRestart) {
    $stateText = (& node $Script status | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify DevSpace policy status before restart' }
    $state = $stateText | ConvertFrom-Json
    $Helper = Join-Path $Temp 'restart-managed.ps1'
    Invoke-WebRequest -Uri "$RestartBase/restart-managed.ps1" -OutFile $Helper -UseBasicParsing
    if ((Get-FileHash -Algorithm SHA256 $Helper).Hash.ToLowerInvariant() -ne $RestartSha) { throw 'Restart helper SHA-256 mismatch' }
    & $Helper -Action dispatch -Target ([string]$state.serverFile) -PatchedSha ([string]$state.sourceSHA256)
    if (-not $?) { throw 'Restart dispatch failed' }
  }
  if ($Action -eq 'status') {
    $report = Join-Path $env:ProgramData 'DevSpaceToolPolicy\restart-status.json'
    if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw }
  }
} finally {
  Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
