#requires -Version 5.1
<#
Skylab DevSpace C: cleanup, scoped only to files created by the Skylab installer.
  -Phase Audit          Report candidates only, change nothing (default)
  -Phase Preflight      Remove abandoned repair scratch so C: can operate
  -Phase AfterMigration Remove obsolete C: program files only after D: runtime
                        and the named-tunnel local DevSpace listener are verified
Does NOT touch ~/.devspace, auth.json, tunnel-token.dpapi, settings.json,
shared npm cache, system Git/Node, or files outside this installer's folders.
#>
[CmdletBinding()]
param([ValidateSet('Audit','Preflight','AfterMigration')][string]$Phase='Audit')
$ErrorActionPreference='Stop'
$State=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'SkylabDevSpace'))
$Repair=Join-Path $State 'repair'
$OldTools=Join-Path $State 'tools'
$Config=Join-Path $State 'settings.json'
$DBase=[IO.Path]::GetFullPath('D:\SkylabDevSpace')
$DPackage=Join-Path $DBase 'npm\node_modules\@waishnav\devspace\bin\devspace.js'
$FreeBefore=0L
$FreeAfter=0L
function Note([string]$Text) { Write-Host ('[Skylab C cleanup] '+$Text) }
function FreeBytes {
  try { return [IO.DriveInfo]::new('C').AvailableFreeSpace } catch { return 0L }
}
function IsInside([string]$Child,[string]$Parent) {
  $p=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'
  $c=[IO.Path]::GetFullPath($Child)
  return $c.StartsWith($p,[StringComparison]::OrdinalIgnoreCase)
}
function Safe-Remove([string]$Path,[bool]$IsDirectory) {
  if (-not (IsInside $Path $State)) { throw 'Path escaped Skylab-owned C: directory' }
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $item=Get-Item -LiteralPath $Path -Force
  if (([int]$item.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Refusing to remove reparse point: $Path"
  }
  if ($Phase -eq 'Audit') { Note "Candidate: $Path"; return }
  if ($IsDirectory) {
    Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction Stop
  } else {
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
  }
  Note "Removed: $Path"
}
function HasListener {
  $tcp=New-Object Net.Sockets.TcpClient
  try {
    $a=$tcp.BeginConnect('127.0.0.1',7676,$null,$null)
    if (-not $a.AsyncWaitHandle.WaitOne(900)) { return $false }
    $tcp.EndConnect($a)
    return $true
  } catch {return $false} finally {$tcp.Dispose()}
}

$FreeBefore=FreeBytes
Note ("Phase=$Phase; C free before="+[math]::Round($FreeBefore/1GB,2)+" GiB")
if ($Phase -eq 'AfterMigration') {
  if (-not (Test-Path -LiteralPath $DPackage -PathType Leaf)) {
    throw 'D: runtime is not fully installed; C: program files preserved'
  }
  if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {throw 'Settings missing; C: preserved'}
  $s=Get-Content -LiteralPath $Config -Raw|ConvertFrom-Json
  $url=[string]$s.publicUrl
  if ($s.mode -ne 'Named' -or $url -ne 'https://skylab-mcp.78175132.xyz' -or
      -not (IsInside ([string]$s.devJs) $DBase)) {
    throw 'D: named-tunnel configuration not verified; C: preserved'
  }
  foreach($name in @('node','bash','tunnel')) {
    $path=[string]$s.$name
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
       (IsInside $path $OldTools)) {
      throw "Runtime still depends on C: Skylab tools ($name); preserving old files"
    }
  }
  if (-not (HasListener)) {throw 'Local DevSpace TCP 7676 is not ready; preserving C: files'}
  $owned=[regex]::Escape([IO.Path]::GetFullPath($OldTools))
  $procs=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  if ($procs.Count -eq 0) { throw 'Cannot inspect running processes; preserving old C: files' }
  $busy=@($procs | Where-Object { $_.CommandLine -and $_.CommandLine -match $owned })
  if ($busy.Count -gt 0) {
    Note "Old C: tools appear to be in use by $($busy.Count) process(es). Skipping tools removal."
  } else {
    Safe-Remove $OldTools $true
  }
}
# These folders are created by the older Skylab installer during failed attempts.
# They are not user-managed project or credential paths.
if (Test-Path -LiteralPath $Repair -PathType Container) {
  $safeDirName='^(npm-candidate-|candidate-config-|stage-)[A-Za-z0-9_-]+$'
  $safeFileName='^(npm-rebuild\.(stdout|stderr)\.log|candidate-cli\.(stdout|stderr)\.log|installed-cli\.(stdout|stderr)\.log|devspace-1\.1\.1\.tgz)$'
  foreach($item in @(Get-ChildItem -LiteralPath $Repair -Force -ErrorAction Stop)) {
    if ($item.PSIsContainer -and $item.Name -match $safeDirName) {
      Safe-Remove $item.FullName $true
    } elseif (-not $item.PSIsContainer -and $item.Name -match $safeFileName) {
      Safe-Remove $item.FullName $false
    } elseif ($Phase -eq 'AfterMigration' -and $item.PSIsContainer -and
              $item.Name -match '^(npm-backup-|failed-npm-|changed-files-backup-)[A-Za-z0-9_-]+$') {
      Safe-Remove $item.FullName $true
    }
  }
}
# Preserve the installed bootstrap script, active connection metadata, all audit
# logs, profile OAuth, and the DPAPI-protected tunnel credential on C:.
$FreeAfter=FreeBytes
Note ("C free after="+[math]::Round($FreeAfter/1GB,2)+" GiB; recovered="+
  [math]::Round(($FreeAfter-$FreeBefore)/1MB,1)+" MiB")
Note 'Shared npm cache, DevSpace Owner auth and Cloudflare token were not touched.'
