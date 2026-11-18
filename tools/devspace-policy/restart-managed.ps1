# Restart only a DevSpace Managed task. The dispatcher exits before the node is stopped.
# PowerShell 5.1+; invoked by the SHA-256 verified policy installer.
[CmdletBinding()]
param(
  [ValidateSet('dispatch','worker','status')][string]$Action = 'dispatch',
  [int]$OldProcessId = 0,
  [long]$OldCreationTicks = 0,
  [int]$Port = 0,
  [string]$Target = '',
  [string]$PatchedSha = ''
)
$ErrorActionPreference = 'Stop'
$ManagedTask = 'DevSpace Managed'
$OneShotTask = 'DevSpace Tool Policy Restart'
$DataDir = Join-Path $env:ProgramData 'DevSpaceToolPolicy'
$Worker = Join-Path $DataDir 'restart-managed.ps1'
$Report = Join-Path $DataDir 'restart-status.json'

function DevspaceNode([int]$ProcessId) {
  if ($ProcessId -lt 1) { return $null }
  $p = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f $ProcessId) -ErrorAction SilentlyContinue
  if ($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -match '@waishnav[\\/]devspace[\\/]dist[\\/]cli\.js') { return $p }
  return $null
}
function PortOwner([int]$LocalPort) {
  $s = Get-NetTCPConnection -State Listen -LocalPort $LocalPort -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $s) { return $null }
  return DevspaceNode ([int]$s.OwningProcess)
}
function HealthyNewNode([int]$OldId,[int]$LocalPort,[int]$Attempts = 30) {
  for ($i=0; $i -lt $Attempts; $i++) {
    Start-Sleep -Seconds 2
    $p = PortOwner $LocalPort
    if ($p -and [int]$p.ProcessId -ne $OldId) {
      try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri ("http://127.0.0.1:{0}/healthz" -f $LocalPort)
        if ($r.StatusCode -eq 200) { return [int]$p.ProcessId }
      } catch {}
    }
  }
  return 0
}
function Save-Report([hashtable]$Record) {
  $Record.timestamp = (Get-Date).ToUniversalTime().ToString('o')
  $Record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Report -Encoding UTF8
}
if ($Action -eq 'status') {
  if (Test-Path -LiteralPath $Report) { Get-Content -LiteralPath $Report -Raw }
  else { Write-Output '{"ok":false,"reason":"no_restart_report"}' }
  return
}
if ($Action -eq 'dispatch') {
  $t = Get-ScheduledTask -TaskName $ManagedTask -ErrorAction SilentlyContinue
  if (-not $t) { Write-Output '{"restart":{"scheduled":false,"method":"manual","reason":"DevSpace Managed task not found"}}'; return }
  $nodes = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
    Where-Object { $_.CommandLine -match '@waishnav[\\/]devspace[\\/]dist[\\/]cli\.js' })
  if ($nodes.Count -ne 1) { throw "Expected one DevSpace node, found $($nodes.Count); refusing restart" }
  $node = $nodes[0]
  $ports = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { [int]$_.OwningProcess -eq [int]$node.ProcessId })
  if ($ports.Count -ne 1) { throw 'Expected exactly one listening port owned by the DevSpace node' }
  if ($Target -notmatch '@waishnav[\\/]devspace[\\/]dist[\\/]server\.js$' -or
      -not (Test-Path -LiteralPath $Target)) { throw 'Invalid patched DevSpace target' }
  $actual = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($PatchedSha.ToLowerInvariant() -ne $actual) { throw 'Patched source changed; refusing restart' }
  New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
  if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($Worker)) {
    Copy-Item -LiteralPath $PSCommandPath -Destination $Worker -Force
  }
  $id = [int]$node.ProcessId
  $ticks = [long]$node.CreationDate.ToUniversalTime().Ticks
  $portNum = [int]$ports[0].LocalPort
  $arg = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action worker -OldProcessId {1} -OldCreationTicks {2} -Port {3} -Target "{4}" -PatchedSha {5}' -f $Worker,$id,$ticks,$portNum,$Target,$PatchedSha
  $actionSpec = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument $arg
  $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 4) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName $OneShotTask -Action $actionSpec -Principal $principal -Settings $settings -Force | Out-Null
  Start-ScheduledTask -TaskName $OneShotTask
  Save-Report @{ok=$false;state='scheduled';oldPid=$id;port=$portNum}
  Write-Output ('{"restart":{"scheduled":true,"method":"detached_scheduled_task","oldPid":' + $id + ',"port":' + $portNum + '},"report":"' + $Report.Replace('\','\\') + '"}')
  return
}
if ($Action -eq 'worker') {
  Start-Sleep -Seconds 4
  $old = DevspaceNode $OldProcessId
  try {
    if ($old -and [long]$old.CreationDate.ToUniversalTime().Ticks -ne $OldCreationTicks) {
      throw 'PID reused; refusing restart'
    }
    Stop-ScheduledTask -TaskName $ManagedTask -ErrorAction Stop
    Start-Sleep -Seconds 3
    $remaining = DevspaceNode $OldProcessId
    if ($remaining) {
      if ([long]$remaining.CreationDate.ToUniversalTime().Ticks -ne $OldCreationTicks) { throw 'PID reused after stop' }
      Stop-Process -Id $OldProcessId -Force -ErrorAction Stop
    }
    $other = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($other) { throw "Port $Port still occupied after managed stop; refusing takeover" }
    Start-ScheduledTask -TaskName $ManagedTask -ErrorAction Stop
    $newId = HealthyNewNode $OldProcessId $Port
    if ($newId -eq 0) { throw "New DevSpace failed health check on port $Port" }
    Save-Report @{ok=$true;state='healthy';oldPid=$OldProcessId;newPid=$newId;port=$Port}
  } catch {
    $reason = $_.Exception.Message
    $restored = $false
    try {
      $backup = Join-Path $DataDir 'server.js.before'
      if ((Test-Path -LiteralPath $backup) -and (Test-Path -LiteralPath $Target) -and
          (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $PatchedSha.ToLowerInvariant()) {
        Stop-ScheduledTask -TaskName $ManagedTask -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $owner = PortOwner $Port
        if ($owner) { Stop-Process -Id ([int]$owner.ProcessId) -Force -ErrorAction Stop }
        Copy-Item -LiteralPath $backup -Destination $Target -Force -ErrorAction Stop
        Start-ScheduledTask -TaskName $ManagedTask -ErrorAction Stop
        $restored = (HealthyNewNode $OldProcessId $Port) -gt 0
      }
    } catch { $reason += '; rollback: ' + $_.Exception.Message }
    Save-Report @{ok=$false;state='restart_failed';reason=$reason;rollbackHealthy=$restored;oldPid=$OldProcessId;port=$Port}
    throw $reason
  }
}
