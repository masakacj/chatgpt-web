#requires -Version 5.1
<#
Recover a damaged @waishnav/devspace 1.1.1 installation on Skylab Windows.
Uses the SHA512-pinned npm release tarball and touches only the package's
own files. Does not change owner OAuth, DPAPI tunnel token, or other workspaces.
Restores the named tunnel using the previously approved installer afterwards.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$State = Join-Path $env:LOCALAPPDATA 'SkylabDevSpace'
$Settings = Join-Path $State 'settings.json'
$PackageRoot = Join-Path $State 'tools\npm\node_modules\@waishnav\devspace'
$PackageManifest = Join-Path $PackageRoot 'package.json'
$Recovery = Join-Path $State 'repair'
$Archive = Join-Path $Recovery 'devspace-1.1.1.tgz'
$ExpectedSHA512 = 'CEE9F12560E1C1F7E221164A0DE96A5E6B48631457377739E3193BB331D26BF066BAAB4735AF761D1AF380D5526FBFBADE88DE3FCE7738FF57780699D6B010E1'
$FixedURL = 'https://skylab-mcp.78175132.xyz'
$InstallerURL = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/f6aacccb9001d42d9fb80f483c4140f3e2f68599/tools/skylab-devspace/install.ps1'
$InstallerSHA256 = '4847DC471971FBFC590F26C0660370AA212F8AF42D3182F61CE3120B3C484286'
$Installer = Join-Path $Recovery 'Deploy-Skylab-v4.ps1'

function Say([string]$Message) { Write-Host ('[Skylab repair] ' + $Message) }
function Require-File([string]$Path, [string]$Why) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Why : $Path" }
}
function Correct-Hash([string]$Path,[string]$Kind,[string]$Expected) {
    return ((Test-Path -LiteralPath $Path -PathType Leaf) -and
       ((Get-FileHash -LiteralPath $Path -Algorithm $Kind).Hash -ieq $Expected))
}
function Download-Pinned([string[]]$Urls,[string]$Destination,[string]$Kind,[string]$Expected) {
    if (Correct-Hash $Destination $Kind $Expected) { Say "Using verified cached file: $([IO.Path]::GetFileName($Destination))"; return }
    foreach ($url in $Urls) {
        $partial = $Destination + '.partial'
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        try {
            Say ("Downloading from " + ([uri]$url).Host)
            Invoke-WebRequest -UseBasicParsing -Uri $url -MaximumRedirection 8 -TimeoutSec 180 -OutFile $partial
            if (-not (Correct-Hash $partial $Kind $Expected)) { throw "Untrusted download: $Kind mismatch" }
            Move-Item -LiteralPath $partial -Destination $Destination -Force
            Say "Verified downloaded $Kind."
            return
        } catch {
            Say ("Download source unavailable: " + ([uri]$url).Host + " (" + $_.Exception.Message + ")")
        } finally {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
    }
    throw "All package sources failed or did not match the pinned $Kind digest."
}

$Mutex = New-Object Threading.Mutex($false,'Local\SkylabDevSpaceRepair')
$lockHeld = $false
$Stage = ''
try {
    try { $lockHeld = $Mutex.WaitOne(120000) }
    catch [Threading.AbandonedMutexException] { $lockHeld = $true }
    if (-not $lockHeld) { throw 'An existing repair is still active. Do not delete the package directory.' }
    $Stage = 'Check existing installation'
    Require-File $Settings 'Skylab installation settings are missing'
    Require-File $PackageManifest 'DevSpace package manifest is missing'
    $config = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
    $pkg = Get-Content -LiteralPath $PackageManifest -Raw | ConvertFrom-Json
    if ($pkg.name -cne '@waishnav/devspace' -or $pkg.version -cne '1.1.1') {
        throw 'Installed package is not @waishnav/devspace@1.1.1. Refusing to mix package versions.'
    }
    $Node = [string]$config.node
    $DevJs = [string]$config.devJs
    Require-File $Node 'Node runtime missing'
    Require-File $DevJs 'DevSpace CLI missing'
    Require-File (Join-Path $State 'tunnel-token.dpapi') 'The previously paired named-tunnel token is missing'
    $expectedDevJs = [IO.Path]::GetFullPath((Join-Path $PackageRoot 'dist\cli.js'))
    if ([IO.Path]::GetFullPath($DevJs) -ine $expectedDevJs) {
        throw 'The installed DevSpace CLI points outside the expected package.'
    }
    New-Item -ItemType Directory -Force -Path $Recovery | Out-Null
    Say "DevSpace package version confirmed: $($pkg.version)"

    $Stage = 'Download official npm tarball'
    Download-Pinned @(
        'https://registry.npmjs.org/@waishnav/devspace/-/devspace-1.1.1.tgz',
        'https://registry.npmmirror.com/@waishnav/devspace/-/devspace-1.1.1.tgz'
    ) $Archive 'SHA512' $ExpectedSHA512

    $Stage = 'Unpack trusted npm tarball'
    # Prefer Windows-native tar: Git Bash's tar may misinterpret C:\\ paths.
    $tarBin = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tarBin -PathType Leaf)) {
        $tarBin = $null
    }
    if (-not $tarBin) {
        $gitRoot = Join-Path $State 'tools\git\usr\bin\tar.exe'
        Require-File $gitRoot 'Windows tar.exe and PortableGit tar.exe are unavailable'
        $tarBin = $gitRoot
    }
    $WorkDir = Join-Path $Recovery ('stage-' + $PID)
    if (Test-Path -LiteralPath $WorkDir) { throw 'Repair staging directory collision' }
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
    & $tarBin -xzf $Archive -C $WorkDir
    if ($LASTEXITCODE -ne 0) { throw "Trusted tarball extraction failed (code $LASTEXITCODE)" }
    $SourceRoot = Join-Path $WorkDir 'package'
    Require-File (Join-Path $SourceRoot 'dist\unsafe-narrow.js') 'Trusted tarball is missing unsafe-narrow.js'
    $sourcePackage = Get-Content (Join-Path $SourceRoot 'package.json') -Raw | ConvertFrom-Json
    if ($sourcePackage.name -cne $pkg.name -or $sourcePackage.version -cne $pkg.version) {
        throw 'Extracted package identity mismatch'
    }

    $Stage = 'Restore missing or modified package files'
    $missing = 0
    $replaced = 0
    $verified = 0
    $sourcePrefix = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\') + '\'
    $destinationPrefix = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\') + '\'
    $backupRoot = Join-Path $Recovery ('changed-files-backup-' + $PID)
    foreach ($source in Get-ChildItem -LiteralPath $SourceRoot -Recurse -File) {
        $rel = $source.FullName.Substring($sourcePrefix.Length)
        if (-not $rel -or $rel.StartsWith('..') -or [IO.Path]::IsPathRooted($rel)) { throw 'Unsafe package-relative path' }
        $dest = [IO.Path]::GetFullPath((Join-Path $PackageRoot $rel))
        if (-not $dest.StartsWith($destinationPrefix,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Archive path escapes the package directory'
        }
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Item -LiteralPath $source.FullName -Destination $dest -ErrorAction Stop
            $missing += 1
        } elseif ((Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash -ine
                  (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash) {
            # Only package-owned dist/bin runtime assets are repaired in place.
            # Preserve original bytes first in an exclusive local backup folder.
            if ($rel -match '^(dist|bin)[\\/]') {
                $backup = Join-Path $backupRoot $rel
                New-Item -ItemType Directory -Path (Split-Path $backup) -Force | Out-Null
                Copy-Item -LiteralPath $dest -Destination $backup -ErrorAction Stop
                Copy-Item -LiteralPath $source.FullName -Destination $dest -Force -ErrorAction Stop
                $replaced += 1
            }
        }
        if ((Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash -ieq
            (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash) { $verified += 1 }
    }
    Say "Package repair verified $verified files; restored $missing missing, repaired $replaced modified runtime files."

    $Stage = 'Test DevSpace CLI'
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Node $DevJs --version
        $cliExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($cliExit -ne 0) {
        throw "DevSpace CLI remains unhealthy after repairing package files (exit=$cliExit). No credentials were touched."
    }
    Say 'DevSpace CLI works.'

    $Stage = 'Restore fixed Cloudflare Tunnel'
    Download-Pinned @($InstallerURL) $Installer 'SHA256' $InstallerSHA256
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Mode Named -PublicUrl $FixedURL -ReuseInstalled
    if ($LASTEXITCODE -ne 0) { throw "Named tunnel startup failed (exit=$LASTEXITCODE). See SkylabDevSpace\logs\devspace-init.err.log" }
    Say "READY: $FixedURL/mcp"
} catch {
    Write-Error ("Repair failed at [$Stage]: " + $_.Exception.Message)
    exit 1
} finally {
    if ($WorkDir -and (Test-Path -LiteralPath $WorkDir)) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($lockHeld) { $Mutex.ReleaseMutex() }
    $Mutex.Dispose()
}
