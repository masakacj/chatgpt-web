#requires -Version 5.1
<#
Skylab DevSpace v1.1.1 recovery from an interrupted/incomplete npm installation.
- Downloads the official npm archive, validates its pinned SHA512
- Installs program AND dependencies in a fresh isolated npm prefix
- Tests the candidate CLI before changing the installed prefix
- Renames the old prefix to an exclusive rollback backup, never deletes it
- Reuses the already paired DPAPI Tunnel token, DevSpace OAuth, and workspace
- Calls the registered fixed-tunnel startup after releasing the installer lock
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$State = Join-Path $env:LOCALAPPDATA 'SkylabDevSpace'
$SettingsPath = Join-Path $State 'settings.json'
$Prefix = Join-Path $State 'tools\npm'
$ExpectedModule = Join-Path $Prefix 'node_modules\@waishnav\devspace'
$Repair = Join-Path $State 'repair'
$Archive = Join-Path $Repair 'devspace-1.1.1.tgz'
$ExpectedArchiveHash = 'CEE9F12560E1C1F7E221164A0DE96A5E6B48631457377739E3193BB331D26BF066BAAB4735AF761D1AF380D5526FBFBADE88DE3FCE7738FF57780699D6B010E1'
$InstallerURL = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/f6aacccb9001d42d9fb80f483c4140f3e2f68599/tools/skylab-devspace/install.ps1'
$InstallerSHA256 = '4847DC471971FBFC590F26C0660370AA212F8AF42D3182F61CE3120B3C484286'
$Installer = Join-Path $Repair 'Deploy-Skylab-v4.ps1'
$FixedURL = 'https://skylab-mcp.78175132.xyz'
$Stage = 'preflight'
$Candidate = $null
$Backup = $null
$Swapped = $false
$NewInstalled = $false
$RepairMutex = New-Object Threading.Mutex($false, 'Local\SkylabDevSpaceRepair')
$InstallMutex = New-Object Threading.Mutex($false, 'Local\SkylabDevSpaceDeploy')
$RepairHeld = $false
$InstallHeld = $false

function Note([string]$Message) { Write-Host ('[Skylab repair] ' + $Message) }
function Must-Exist([string]$Path, [string]$Reason) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Reason : $Path" }
}
function Verified([string]$Path,[string]$Algorithm,[string]$Hash) {
  return ((Test-Path -LiteralPath $Path -PathType Leaf) -and
    (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash -ieq $Hash)
}
function Download-Verified([string[]]$Urls,[string]$Destination,[string]$Algorithm,[string]$Hash) {
  if (Verified $Destination $Algorithm $Hash) {
    Note "Reusing verified $([IO.Path]::GetFileName($Destination))"
    return
  }
  foreach ($url in $Urls) {
    $part = $Destination + '.partial'
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    try {
      Note "Downloading from $(([uri]$url).Host)"
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $part -MaximumRedirection 8 -TimeoutSec 180
      if (-not (Verified $part $Algorithm $Hash)) { throw "$Algorithm mismatch" }
      Move-Item -LiteralPath $part -Destination $Destination -Force
      Note "$Algorithm verified"
      return
    } catch {
      Note "Source failed: $(([uri]$url).Host) ($($_.Exception.Message))"
    } finally {
      Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    }
  }
  throw "All download sources failed verification ($Algorithm)."
}
function Run-Native([string]$Exe,[string[]]$Argv,[string]$Out,[string]$Err) {
  $old = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $Exe @Argv 1> $Out 2> $Err
    $result = $LASTEXITCODE
  } finally { $ErrorActionPreference = $old }
  return [int]$result
}
function Last-Error([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return '(no stderr)' }
  return ((Get-Content -LiteralPath $Path -Tail 14 -ErrorAction SilentlyContinue) -join ' ')
}
function Ensure-Package([string]$Root) {
  $mod = Join-Path $Root 'node_modules\@waishnav\devspace'
  foreach ($p in @(
    (Join-Path $mod 'package.json'),
    (Join-Path $mod 'dist\cli.js'),
    (Join-Path $mod 'dist\unsafe-narrow.js'),
    (Join-Path $mod 'bin\devspace.js')
  )) { Must-Exist $p 'Incomplete candidate npm package' }
  $manifest = Get-Content -LiteralPath (Join-Path $mod 'package.json') -Raw | ConvertFrom-Json
  if ($manifest.name -cne '@waishnav/devspace' -or $manifest.version -cne '1.1.1') {
    throw 'Candidate npm package identity mismatch'
  }
}

try {
  try { $RepairHeld = $RepairMutex.WaitOne(120000) }
  catch [Threading.AbandonedMutexException] { $RepairHeld = $true }
  if (-not $RepairHeld) { throw 'Another repair is still running' }
  Must-Exist $SettingsPath 'Original Skylab configuration is missing'
  Must-Exist (Join-Path $State 'tunnel-token.dpapi') 'Previously paired Tunnel token is missing'
  $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
  $Node = [string]$settings.node
  $DevJs = [string]$settings.devJs
  Must-Exist $Node 'Original Node runtime missing'
  $ExpectedCli = [IO.Path]::GetFullPath((Join-Path $ExpectedModule 'dist\cli.js'))
  if (-not $DevJs -or [IO.Path]::GetFullPath($DevJs) -ine $ExpectedCli) {
    throw 'Original DevSpace CLI path does not match this dedicated installation'
  }
  $npm = Join-Path (Split-Path -Parent $Node) 'npm.cmd'
  Must-Exist $npm 'npm.cmd is missing from the installed Node.js'
  New-Item -ItemType Directory -Path $Repair -Force | Out-Null
  $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $Candidate = Join-Path $Repair ("npm-candidate-$Stamp-$PID")
  $Backup = Join-Path $Repair ("npm-backup-$Stamp-$PID")
  if ((Test-Path -LiteralPath $Candidate) -or (Test-Path -LiteralPath $Backup)) {
    throw 'Recovery directories already exist; refusing to overwrite'
  }
  Note 'Current OAuth, DPAPI credentials and workspace are preserved.'

  $Stage = 'verify official package download'
  Download-Verified @(
    'https://registry.npmjs.org/@waishnav/devspace/-/devspace-1.1.1.tgz',
    'https://registry.npmmirror.com/@waishnav/devspace/-/devspace-1.1.1.tgz'
  ) $Archive 'SHA512' $ExpectedArchiveHash

  $Stage = 'install isolated full dependency tree'
  $NpmOut = Join-Path $Repair 'npm-rebuild.stdout.log'
  $NpmErr = Join-Path $Repair 'npm-rebuild.stderr.log'
  $env:PATH = "$(Split-Path -Parent $Node);$env:PATH"
  $exitCode = 1
  foreach ($registry in @('https://registry.npmjs.org','https://registry.npmmirror.com')) {
    if (Test-Path -LiteralPath $Candidate) {
      Remove-Item -LiteralPath $Candidate -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $Candidate | Out-Null
    Note "Installing complete dependencies in isolated folder using $registry"
    $exitCode = Run-Native $npm @(
      'install','--global','--prefix',$Candidate,
      '--registry',$registry,'--no-audit','--no-fund','--no-progress',
      '--fetch-retries=1','--fetch-timeout=90000',$Archive
    ) $NpmOut $NpmErr
    if ($exitCode -eq 0) { break }
    Note "Dependency install failed (exit $exitCode): $(Last-Error $NpmErr)"
  }
  if ($exitCode -ne 0) {
    throw "Both package registries failed. No installed files were modified. Inspect $NpmErr"
  }
  Ensure-Package $Candidate

  $Stage = 'isolated candidate runtime verification'
  $CandidateCli = Join-Path $Candidate 'node_modules\@waishnav\devspace\dist\cli.js'
  $CliOut = Join-Path $Repair 'candidate-cli.stdout.log'
  $CliErr = Join-Path $Repair 'candidate-cli.stderr.log'
  $candidateVersionCode = Run-Native $Node @($CandidateCli,'--version') $CliOut $CliErr
  if ($candidateVersionCode -ne 0) {
    throw "Isolated candidate CLI cannot boot: $(Last-Error $CliErr)"
  }
  $testConfig = Join-Path $Repair ("candidate-config-$PID")
  New-Item -ItemType Directory -Path $testConfig -Force | Out-Null
  $previousConfigDir = $env:DEVSPACE_CONFIG_DIR
  try {
    $env:DEVSPACE_CONFIG_DIR = $testConfig
    $candidateConfigCode = Run-Native $Node @(
      $CandidateCli,'config','set','publicBaseUrl',$FixedURL
    ) $CliOut $CliErr
    if ($candidateConfigCode -ne 0) {
      throw "Candidate CLI configuration failed: $(Last-Error $CliErr)"
    }
  } finally {
    if ($null -eq $previousConfigDir) {
      Remove-Item Env:\DEVSPACE_CONFIG_DIR -ErrorAction SilentlyContinue
    } else { $env:DEVSPACE_CONFIG_DIR = $previousConfigDir }
  }
  Note 'Isolated full npm dependency tree and CLI checks passed.'

  $Stage = 'acquire installation lock'
  try { $InstallHeld = $InstallMutex.WaitOne(120000) }
  catch [Threading.AbandonedMutexException] { $InstallHeld = $true }
  if (-not $InstallHeld) { throw 'Existing DevSpace startup is busy; preserving candidate for retry.' }

  $Stage = 'replace dedicated npm prefix with rollback'
  if (Test-Path -LiteralPath $Prefix) {
    Move-Item -LiteralPath $Prefix -Destination $Backup -ErrorAction Stop
    $Swapped = $true
    Note "Damaged npm installation saved in $Backup"
  }
  try {
    Move-Item -LiteralPath $Candidate -Destination $Prefix -ErrorAction Stop
    $NewInstalled = $true
    Ensure-Package $Prefix
    $NewCliOut = Join-Path $Repair 'installed-cli.stdout.log'
    $NewCliErr = Join-Path $Repair 'installed-cli.stderr.log'
    $afterCode = Run-Native $Node @($DevJs,'--version') $NewCliOut $NewCliErr
    if ($afterCode -ne 0) {
      throw "Installed CLI failed after prefix swap: $(Last-Error $NewCliErr)"
    }
  } catch {
    Note 'New package check failed; rolling back the original npm folder.'
    if ($NewInstalled -and (Test-Path -LiteralPath $Prefix)) {
      $Bad = Join-Path $Repair ("failed-npm-$Stamp-$PID")
      Move-Item -LiteralPath $Prefix -Destination $Bad -ErrorAction Stop
    }
    if ($Swapped -and (Test-Path -LiteralPath $Backup)) {
      Move-Item -LiteralPath $Backup -Destination $Prefix -ErrorAction Stop
    }
    throw
  } finally {
    if ($InstallHeld) { $InstallMutex.ReleaseMutex(); $InstallHeld = $false }
  }
  Note 'Full dependency restoration completed; previous npm installation retained for rollback.'

  $Stage = 'start fixed named Tunnel and DevSpace'
  Download-Verified @($InstallerURL) $Installer 'SHA256' $InstallerSHA256
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Mode Named -PublicUrl $FixedURL -ReuseInstalled
  if ($LASTEXITCODE -ne 0) {
    throw "DevSpace startup failed (exit $LASTEXITCODE). Full dependency installation is available; inspect $State\logs\devspace-init.err.log."
  }
  Note "READY: $FixedURL/mcp"
} catch {
  Write-Error ("Repair failed during [$Stage]: " + $_.Exception.Message)
  exit 1
} finally {
  if ($InstallHeld) { $InstallMutex.ReleaseMutex() }
  if ($RepairHeld) { $RepairMutex.ReleaseMutex() }
  $InstallMutex.Dispose()
  $RepairMutex.Dispose()
}
