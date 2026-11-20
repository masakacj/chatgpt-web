#requires -Version 5.1
<#
Recover Skylab Windows DevSpace after a partial npm install and C-drive exhaustion.
Staging, npm cache and scratch use D:\SkylabDevSpace. The old C: installation
is preserved until a complete candidate is verified and a fixed-domain DevSpace
listener is healthy. Includes pinned, scoped C-drive cleanup.
No changes to unrelated programs, global npm cache, auth.json, or DPAPI token.
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$State=Join-Path $env:LOCALAPPDATA 'SkylabDevSpace'
$SettingsPath=Join-Path $State 'settings.json'
$OldTools=Join-Path $State 'tools'
$DBase='D:\SkylabDevSpace'
$DTools=Join-Path $DBase 'tools'
$DRepair=Join-Path $DBase 'repair'
$DTemp=Join-Path $DBase 'temp'
$DCache=Join-Path $DBase 'npm-cache'
$Prefix=Join-Path $DBase 'npm'
$Archive=Join-Path $DRepair 'devspace-1.1.1.tgz'
$PackageDigest='CEE9F12560E1C1F7E221164A0DE96A5E6B48631457377739E3193BB331D26BF066BAAB4735AF761D1AF380D5526FBFBADE88DE3FCE7738FF57780699D6B010E1'
$CleanupUrl='https://raw.githubusercontent.com/masakacj/chatgpt-web/4ca3ecffb0595daa8a6bbed749fc0c7ff161827b/tools/skylab-devspace/cleanup-c.ps1'
$CleanupDigest='701D791822A107AFA3F89D0D01D770171869E0AA553C59FC57184BA59247F08A'
$Cleanup=Join-Path $DBase 'cleanup-c.ps1'
$InstallerUrl='https://raw.githubusercontent.com/masakacj/chatgpt-web/f6aacccb9001d42d9fb80f483c4140f3e2f68599/tools/skylab-devspace/install.ps1'
$InstallerDigest='4847DC471971FBFC590F26C0660370AA212F8AF42D3182F61CE3120B3C484286'
$Installer=Join-Path $DBase 'start-fixed-tunnel.ps1'
$PublicUrl='https://skylab-mcp.78175132.xyz'
$Stage='initialization'
$BackupSettings=$null
$ConfigUpdated=$false
$Candidate=$null
$HadOldPrefix=$false
$MoveDone=$false
$LockHeld=$false
$InstallHeld=$false
$RepairMutex=New-Object Threading.Mutex($false,'Local\SkylabDevSpaceRepair')
$DeployMutex=New-Object Threading.Mutex($false,'Local\SkylabDevSpaceDeploy')
$OldEnv=@{TEMP=$env:TEMP; TMP=$env:TMP; NPM_CONFIG_CACHE=$env:NPM_CONFIG_CACHE}

function Note([string]$Msg) {Write-Host ('[Skylab D recovery] '+$Msg)}
function RequireFile([string]$Path,[string]$Why){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Why : $Path"}
}
function IsUnder([string]$Path,[string]$Parent){
  $a=[IO.Path]::GetFullPath($Path)
  $p=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'
  return $a.StartsWith($p,[StringComparison]::OrdinalIgnoreCase)
}
function Verified([string]$Path,[string]$Alg,[string]$Digest){
  return (Test-Path -LiteralPath $Path -PathType Leaf) -and
    ((Get-FileHash -LiteralPath $Path -Algorithm $Alg).Hash -ieq $Digest)
}
function Download-Verified([string[]]$Urls,[string]$Dest,[string]$Alg,[string]$Digest){
  if (Verified $Dest $Alg $Digest) {Note "Verified cached file: $Dest";return}
  foreach($u in $Urls){
    $part=$Dest+'.partial'
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    try {
      Note ("Downloading " + ([uri]$u).Host)
      Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $part -TimeoutSec 180 -MaximumRedirection 8 -ErrorAction Stop
      if(-not(Verified $part $Alg $Digest)){throw "$Alg mismatch"}
      Move-Item -LiteralPath $part -Destination $Dest -Force -ErrorAction Stop
      return
    } catch {
      Note ("Source failed: "+([uri]$u).Host+" / "+$_.Exception.Message)
    } finally {Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue}
  }
  throw "All download sources failed ($Alg verified bytes required)."
}
function Run([string]$Exe,[string[]]$Argv,[string]$Out,[string]$Err){
  $old=$ErrorActionPreference
  try {
    $ErrorActionPreference='Continue'
    $global:LASTEXITCODE=$null
    try {
      & $Exe @Argv 1> $Out 2> $Err
    } catch {
      Note "Process launch error: $($_.Exception.Message)"
      return 900
    }
    if ($null -eq $LASTEXITCODE){return 901}
    return [int]$LASTEXITCODE
  } finally {$ErrorActionPreference=$old}
}
function ErrorTail([string]$Path){
  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return ((Get-Content $Path -Tail 10 -ErrorAction SilentlyContinue) -join ' ')
  }
  return '(no stderr)'
}
function Check-Module([string]$Root,[string]$Entry){
  $p=Join-Path $Root 'node_modules\@waishnav\devspace'
  foreach($f in @('package.json','dist\cli.js','dist\unsafe-narrow.js','bin\devspace.js',$Entry)){
    RequireFile (Join-Path $p $f) 'Candidate npm package incomplete'
  }
  $meta=Get-Content -LiteralPath (Join-Path $p 'package.json') -Raw | ConvertFrom-Json
  if($meta.name -cne '@waishnav/devspace' -or $meta.version -cne '1.1.1'){throw 'Candidate package identity mismatch'}
}
function CopyOwnedDir([string]$OldExe,[string]$SourceDir,[string]$NewDir,[string]$RelativeExe){
  if (-not(IsUnder $OldExe $SourceDir)) { return $OldExe }
  $normalizedOld=[IO.Path]::GetFullPath($OldExe)
  $expectedOld=[IO.Path]::GetFullPath((Join-Path $SourceDir $RelativeExe))
  if ($normalizedOld -ine $expectedOld){throw "Unexpected installer-owned runtime path: $OldExe"}
  if (-not(Test-Path -LiteralPath $NewDir -PathType Container)){
    Note "Copying installer-owned runtime to D: $RelativeExe"
    Copy-Item -LiteralPath $SourceDir -Destination $NewDir -Recurse -Force -ErrorAction Stop
  }
  $newExe=Join-Path $NewDir $RelativeExe
  RequireFile $newExe 'D: runtime copy incomplete'
  if ((Get-FileHash -LiteralPath $OldExe -Algorithm SHA256).Hash -ine
      (Get-FileHash -LiteralPath $newExe -Algorithm SHA256).Hash){
    throw "D: runtime executable differs: $RelativeExe"
  }
  return $newExe
}
function StopOwned([string]$Name,[string]$Anchor) {
  $pidFile=Join-Path $State ($Name+'.pid')
  if (-not(Test-Path -LiteralPath $pidFile -PathType Leaf)){return}
  $oldPid=0
  if (-not [int]::TryParse((Get-Content $pidFile -Raw).Trim(),[ref]$oldPid)) {return}
  $p=Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid" -ErrorAction SilentlyContinue
  if($p -and $p.CommandLine -and
     $p.CommandLine.IndexOf($Anchor,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
    Note "Stopping old Skylab-owned $Name PID $oldPid"
    Stop-Process -Id $oldPid -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 350
  }
}
function DriveGB([string]$Letter){
  try{return [math]::Round(([IO.DriveInfo]::new($Letter)).AvailableFreeSpace/1GB,2)}
  catch{return -1}
}

try {
  if (-not(Test-Path 'D:\')) {throw 'D: drive not available. No C: files modified.'}
  New-Item -ItemType Directory -Force -Path $DBase,$DRepair,$DCache,$DTemp,$DTools | Out-Null
  $Stage='acquire recovery lock'
  try {$LockHeld=$RepairMutex.WaitOne(120000)}
  catch [Threading.AbandonedMutexException]{$LockHeld=$true}
  if (-not $LockHeld){throw 'Another Skylab repair is still running'}

  $Stage='C-drive targeted cleanup'
  Download-Verified @($CleanupUrl) $Cleanup 'SHA256' $CleanupDigest
  & $Cleanup -Phase Preflight
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {throw 'C cleanup failed'}
  Note ('C: free '+(DriveGB 'C')+' GiB / D: free '+(DriveGB 'D')+' GiB')
  if((DriveGB 'D') -lt 2.5){throw 'D: requires at least 2.5 GiB free for the full npm tree, Git and rollback. C: scratch has been cleaned.'}
  RequireFile $SettingsPath 'Saved installer settings missing'
  RequireFile (Join-Path $State 'tunnel-token.dpapi') 'Cloudflare DPAPI token missing'
  $s=Get-Content -LiteralPath $SettingsPath -Raw|ConvertFrom-Json
  $oldNode=[string]$s.node
  $oldBash=[string]$s.bash
  $oldTunnel=[string]$s.tunnel
  $oldCli=[string]$s.devJs
  foreach($f in @($oldNode,$oldBash,$oldTunnel)){RequireFile $f 'Existing runtime prerequisite missing'}
  $oldModule=Join-Path $State 'tools\npm\node_modules\@waishnav\devspace'
  $newModule=Join-Path $Prefix 'node_modules\@waishnav\devspace'
  $binPaths=@((Join-Path $oldModule 'bin\devspace.js'),(Join-Path $newModule 'bin\devspace.js'))
  $distPaths=@((Join-Path $oldModule 'dist\cli.js'),(Join-Path $newModule 'dist\cli.js'))
  $entry=$null
  if(-not [string]::IsNullOrWhiteSpace($oldCli)){
    $cliCanonical=[IO.Path]::GetFullPath($oldCli)
    if(@($binPaths | ForEach-Object {[IO.Path]::GetFullPath($_)}) -contains $cliCanonical){$entry='bin\devspace.js'}
    elseif(@($distPaths | ForEach-Object {[IO.Path]::GetFullPath($_)}) -contains $cliCanonical){$entry='dist\cli.js'}
  }
  if (-not $entry){throw 'Installer settings point outside the two official package entrypoints'}
  Note "Using verified package entrypoint: $entry"
  if((IsUnder $oldCli $Prefix) -and (Test-Path -LiteralPath $oldCli -PathType Leaf)){
    # A previous run may have installed the entire D: tree and then failed in
    # the final startup/configuration step. Resume it instead of reinstalling.
    Check-Module $Prefix $entry
    $resumeOut=Join-Path $DRepair 'resume-cli.out.log'
    $resumeErr=Join-Path $DRepair 'resume-cli.err.log'
    if((Run $oldNode @($oldCli,'--version') $resumeOut $resumeErr) -eq 0){
      Note 'A verified D: DevSpace installation already exists; resuming startup.'
      Download-Verified @($InstallerUrl) $Installer 'SHA256' $InstallerDigest
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Mode Named -PublicUrl $PublicUrl -ReuseInstalled
      if($LASTEXITCODE -ne 0){throw "Existing D: runtime startup failed. Logs: $State\logs\devspace-init.err.log"}
      & $Cleanup -Phase AfterMigration
      Note ('READY: '+$PublicUrl+'/mcp')
      return
    }
    Note 'Existing D: CLI cannot start; rebuilding the D: package.'
  }

  $Stage='configure D-based npm cache and temp'
  $env:TEMP=$DTemp
  $env:TMP=$DTemp
  $env:NPM_CONFIG_CACHE=$DCache
  $env:PATH="$(Split-Path -Parent $oldNode);$env:PATH"
  $npm=Join-Path (Split-Path -Parent $oldNode) 'npm.cmd'
  RequireFile $npm 'npm.cmd not found alongside Node'

  $Stage='verify official DevSpace archive on D'
  Download-Verified @('https://registry.npmjs.org/@waishnav/devspace/-/devspace-1.1.1.tgz',
       'https://registry.npmmirror.com/@waishnav/devspace/-/devspace-1.1.1.tgz') $Archive 'SHA512' $PackageDigest

  $Stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$PID
  $Candidate=Join-Path $DRepair ('npm-candidate-'+$Stamp)
  $Backup=Join-Path $DRepair ('npm-backup-'+$Stamp)
  if((Test-Path $Candidate) -or (Test-Path $Backup)){throw 'Unique stage/backup path collision'}
  $Stage='install complete DevSpace and dependencies to D'
  $out=Join-Path $DRepair ('npm-'+$Stamp+'.out.log')
  $err=Join-Path $DRepair ('npm-'+$Stamp+'.err.log')
  $result=1
  foreach($registry in @('https://registry.npmjs.org','https://registry.npmmirror.com')){
    if(Test-Path -LiteralPath $Candidate){
      # Only our unique, never-activated candidate in the D: repair directory.
      Remove-Item -LiteralPath $Candidate -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $Candidate|Out-Null
    Note "Installing isolated npm tree through $registry"
    $result=Run $npm @('install','--global','--prefix',$Candidate,'--cache',$DCache,
      '--registry',$registry,'--no-audit','--no-fund','--no-progress',
      '--fetch-retries=1','--fetch-timeout=90000',$Archive) $out $err
    if($result -eq 0){break}
    Note "npm failed (exit=$result): $(ErrorTail $err)"
  }
  if($result -ne 0){throw "D: npm install failed (exit=$result), leaving C: installation intact. Details: $err"}
  Check-Module $Candidate $entry
  $candidateCli=Join-Path (Join-Path $Candidate 'node_modules\@waishnav\devspace') $entry

  $Stage='verify isolated candidate CLI'
  $cliOut=Join-Path $DRepair 'candidate-cli.out.log'
  $cliErr=Join-Path $DRepair 'candidate-cli.err.log'
  if((Run $oldNode @($candidateCli,'--version') $cliOut $cliErr) -ne 0){
    throw "Candidate CLI cannot start: $(ErrorTail $cliErr)"
  }
  $cfgTest=Join-Path $DRepair ('test-config-'+$Stamp)
  New-Item -ItemType Directory -Path $cfgTest -Force|Out-Null
  $previousConfigDir=$env:DEVSPACE_CONFIG_DIR
  try {
    $env:DEVSPACE_CONFIG_DIR=$cfgTest
    if((Run $oldNode @($candidateCli,'config','set','publicBaseUrl',$PublicUrl) $cliOut $cliErr) -ne 0){
      throw "Candidate CLI config test failed: $(ErrorTail $cliErr)"
    }
  } finally {
    if($null -eq $previousConfigDir){Remove-Item Env:\DEVSPACE_CONFIG_DIR -ErrorAction SilentlyContinue}
    else {$env:DEVSPACE_CONFIG_DIR=$previousConfigDir}
  }
  Note 'D: complete npm dependency tree and CLI test passed.'

  $Stage='copy installer-owned runtimes to D'
  $newNode=CopyOwnedDir $oldNode (Join-Path $OldTools 'node') (Join-Path $DTools 'node') 'node.exe'
  $newBash=CopyOwnedDir $oldBash (Join-Path $OldTools 'git') (Join-Path $DTools 'git') 'bin\bash.exe'
  if(IsUnder $oldTunnel $OldTools){
    if([IO.Path]::GetFullPath($oldTunnel) -ine [IO.Path]::GetFullPath((Join-Path $OldTools 'cloudflared.exe'))){
      throw 'Unexpected old cloudflared executable location'
    }
    $newTunnel=Join-Path $DTools 'cloudflared.exe'
    if(-not(Test-Path -LiteralPath $newTunnel)){Copy-Item -LiteralPath $oldTunnel -Destination $newTunnel -ErrorAction Stop}
    if((Get-FileHash $newTunnel -Algorithm SHA256).Hash -ine
       (Get-FileHash $oldTunnel -Algorithm SHA256).Hash){throw 'Copied cloudflared digest mismatch'}
  } else {$newTunnel=$oldTunnel}
  $newCli=Join-Path (Join-Path $Prefix 'node_modules\@waishnav\devspace') $entry
  # Confirm the copies are runnable, not merely matching one executable hash.
  # Git Bash and cloudflared may depend on adjacent support files from their
  # portable installation; detect incomplete copies before changing settings.
  foreach($test in @(
    @{exe=$newNode; args=@('--version'); label='Node'},
    @{exe=$newBash; args=@('--version'); label='Git Bash'},
    @{exe=$newTunnel; args=@('--version'); label='cloudflared'}
  )){
    $runtimeCode=Run ([string]$test.exe) ([string[]]$test.args) $cliOut $cliErr
    if($runtimeCode -ne 0){
      throw ("D: runtime check failed for "+$test.label+": "+(ErrorTail $cliErr))
    }
  }
  Note 'D: Node, Git Bash and cloudflared executable checks passed.'

  $Stage='cut over verified package and settings'
  try {$InstallHeld=$DeployMutex.WaitOne(120000)}
  catch [Threading.AbandonedMutexException]{$InstallHeld=$true}
  if (-not $InstallHeld){throw 'Another instance is deploying; no cutover attempted'}
  if(Test-Path -LiteralPath $Prefix) {
    Move-Item -LiteralPath $Prefix -Destination $Backup -ErrorAction Stop
    $HadOldPrefix=$true
  }
  try {
    Move-Item -LiteralPath $Candidate -Destination $Prefix -ErrorAction Stop
    $MoveDone=$true
    Check-Module $Prefix $entry
    if((Run $newNode @($newCli,'--version') $cliOut $cliErr) -ne 0){
      throw "New installed CLI cannot start: $(ErrorTail $cliErr)"
    }
  } catch {
    if($MoveDone -and(Test-Path -LiteralPath $Prefix)){
      Move-Item -LiteralPath $Prefix -Destination (Join-Path $DRepair ('failed-'+$Stamp)) -ErrorAction Stop
    }
    if($HadOldPrefix -and(Test-Path -LiteralPath $Backup)){
      Move-Item -LiteralPath $Backup -Destination $Prefix -ErrorAction Stop
    }
    throw
  }
  $BackupSettings=Join-Path $DRepair ('settings-original-'+$Stamp+'.json')
  Copy-Item -LiteralPath $SettingsPath -Destination $BackupSettings -ErrorAction Stop
  # The sensitive Owner token and DPAPI connector token are intentionally not moved.
  $s.node=$newNode
  $s.bash=$newBash
  $s.tunnel=$newTunnel
  $s.devJs=$newCli
  $s.mode='Named'
  $s.publicUrl=$PublicUrl
  $newSettings=Join-Path $State ('settings-'+$PID+'.tmp')
  $s|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $newSettings -Encoding UTF8 -ErrorAction Stop
  Move-Item -LiteralPath $newSettings -Destination $SettingsPath -Force -ErrorAction Stop
  $ConfigUpdated=$true

  StopOwned 'devspace' $oldCli
  StopOwned 'tunnel' $oldTunnel
  $DeployMutex.ReleaseMutex()
  $InstallHeld=$false

  $Stage='start fixed named Tunnel and DevSpace from D'
  Download-Verified @($InstallerUrl) $Installer 'SHA256' $InstallerDigest
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Mode Named -PublicUrl $PublicUrl -ReuseInstalled
  if($LASTEXITCODE -ne 0){
    throw "Fixed Tunnel startup failed (exit=$LASTEXITCODE). D: candidate preserved and C: not removed. See $State\logs\devspace-init.err.log"
  }
  Note "Fixed MCP listener started: $PublicUrl/mcp"

  $Stage='C-drive post-migration cleanup'
  & $Cleanup -Phase AfterMigration
  Note ('READY: '+$PublicUrl+'/mcp')
  Note ('C free now: '+(DriveGB 'C')+' GiB; shared npm cache and all OAuth secrets preserved.')
} catch {
  Write-Error ("Recovery stopped at [$Stage]: "+$_.Exception.Message)
  exit 1
} finally {
  $env:TEMP=$OldEnv.TEMP
  $env:TMP=$OldEnv.TMP
  if($null -eq $OldEnv.NPM_CONFIG_CACHE){Remove-Item Env:\NPM_CONFIG_CACHE -ErrorAction SilentlyContinue}
  else{$env:NPM_CONFIG_CACHE=$OldEnv.NPM_CONFIG_CACHE}
  if($InstallHeld){$DeployMutex.ReleaseMutex()}
  if($LockHeld){$RepairMutex.ReleaseMutex()}
  $DeployMutex.Dispose()
  $RepairMutex.Dispose()
}
