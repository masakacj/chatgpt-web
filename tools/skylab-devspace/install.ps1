#requires -Version 5.1
<#
Skylab Windows -> DevSpace MCP, no inbound firewall/NAT changes.
Run in the target Windows machine's PowerShell (the SAME Windows user who will run DevSpace):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy-Skylab-DevSpace.ps1
For a stable, named Cloudflare Tunnel (configure the tunnel's public hostname first):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy-Skylab-DevSpace.ps1 -Mode Named -PublicUrl https://your-devspace.example.com
Named mode prompts for the Cloudflare tunnel token locally (not on the command line).
Default Quick mode has a TEMPORARY URL and changes on restart; use only to establish first connectivity.
Requires outbound HTTPS access to nodejs.org, npm registry, github.com, and Cloudflare.
#>
[CmdletBinding()]
param(
  [ValidateSet('Quick','Named')][string]$Mode = 'Quick',
  [string]$PublicUrl = '',
  [string]$WorkspaceRoot = '',
  [switch]$Resume,
  [switch]$ReuseInstalled
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$State = Join-Path $env:LOCALAPPDATA 'SkylabDevSpace'
$Tools = Join-Path $State 'tools'
$Logs = Join-Path $State 'logs'
$SettingsFile = Join-Path $State 'settings.json'
$StartupFile = Join-Path $State 'Deploy-Skylab-DevSpace.ps1'
$Port = 7676
$DevVersion = '1.1.1'
$CloudflaredVersion = '2026.11.1'
$script:Stage = 'startup'
$Mutex = New-Object Threading.Mutex($false, 'Local\SkylabDevSpaceDeploy')
$lockHeld = $false
try {
  try {
    Write-Host '[SkylabDevSpace] Waiting for any current startup or deployment to finish...'
    $lockHeld = $Mutex.WaitOne(120000)
  } catch [Threading.AbandonedMutexException] {
    $lockHeld = $true
  }
  if (-not $lockHeld) { throw 'Another installer still holds the mutex after 120 seconds. No process was terminated; inspect the running installer before retrying.' }
  foreach ($dir in @($State,$Tools,$Logs)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  function Note([string]$Text) { Write-Host ('[SkylabDevSpace] ' + $Text) }
  function Stage([string]$Text) {
    $script:Stage = $Text
    Note ("Stage: " + $Text)
  }
  function Require-File([string]$Path,[string]$Why) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Why : $Path" }
  }
  function Invoke-Exe([string]$Exe,[string[]]$Arguments) {
    # PowerShell 5.1 sometimes treats native stderr (including harmless npm warnings) as an error.
    $previousPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      & $Exe @Arguments
      $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "Command failed ($exitCode): $Exe" }
  }
  function Failure-Text($Failure) {
    $code = ''
    try {
      if ($Failure.Exception.Response -and $Failure.Exception.Response.StatusCode) {
        $code = 'HTTP ' + [int]$Failure.Exception.Response.StatusCode + ' '
      }
    } catch { }
    return ($code + $Failure.Exception.Message)
  }
  function Download([string[]]$Urls,[string]$Dest,[string]$ExpectedSha256) {
    $failures = @()
    $part = $Dest + '.partial'
    foreach ($url in $Urls) {
      $hostName = ([uri]$url).Host
      Note ("Downloading [$script:Stage] from " + $hostName)
      try {
        if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $part -MaximumRedirection 8 -TimeoutSec 150
        Require-File $part 'Download incomplete'
        if ($ExpectedSha256) {
          $actual = (Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash
          if ($actual -ine $ExpectedSha256) { throw "SHA256 mismatch from $hostName (rejecting binary)" }
        }
        Move-Item -LiteralPath $part -Destination $Dest -Force
        Note ("Downloaded [$script:Stage] from " + $hostName)
        return
      } catch {
        $reason = Failure-Text $_
        $failures += ("${hostName}: $reason")
        Note ("Source failed [$script:Stage]: ${hostName}: $reason")
        if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
      }
    }
    throw ("All downloads failed at [$script:Stage]. " + ($failures -join '; '))
  }
  function Remote-Text([string[]]$Urls) {
    $failures = @()
    foreach ($url in $Urls) {
      $hostName = ([uri]$url).Host
      try {
        Note ("Fetching [$script:Stage] from " + $hostName)
        $response = Invoke-WebRequest -UseBasicParsing -Uri $url -MaximumRedirection 8 -TimeoutSec 45
        if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { throw 'Empty response' }
        return [string]$response.Content
      } catch {
        $reason = Failure-Text $_
        $failures += ("${hostName}: $reason")
        Note ("Source failed [$script:Stage]: ${hostName}: $reason")
      }
    }
    throw ("All requests failed at [$script:Stage]. " + ($failures -join '; '))
  }
  function Find-GitBash {
    $possible = @(
      (Join-Path $Tools 'git\bin\bash.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'),
      'C:\Program Files\Git\bin\bash.exe',
      'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
      $prefix = Split-Path (Split-Path $git.Source -Parent) -Parent
      $possible += (Join-Path $prefix 'bin\bash.exe')
    }
    foreach ($p in $possible) { if (Test-Path -LiteralPath $p -PathType Leaf) { return $p } }
    return $null
  }
  function Ensure-GitBash {
    $existing = Find-GitBash
    if ($existing) { return $existing }
    if ([Environment]::Is64BitOperatingSystem -eq $false) { throw 'Git Bash requires a supported 64-bit Windows OS.' }
    $portable = Join-Path $Tools 'PortableGit-2.56.1-64-bit.7z.exe'
    # Official Git for Windows release, pinned version. No admin permissions required.
    Stage 'Git Bash download'
    # Git for Windows v2.56.1 official release SHA-256. Mirrors cannot substitute other bytes.
    $gitAsset = 'https://github.com/git-for-windows/git/releases/download/v2.56.1.windows.1/PortableGit-2.56.1-64-bit.7z.exe'
    Download @(
      $gitAsset,
      'https://mirrors.huaweicloud.com/git-for-windows/v2.56.1.windows.1/PortableGit-2.56.1-64-bit.7z.exe',
      ('https://ghfast.top/' + $gitAsset)
    ) $portable '9dd04a608ceb5f6ab32a73709e0ecb159d211da71b697c45ff81f6dd0c6b49c7'
    $gitHome = Join-Path $Tools 'git'
    New-Item -ItemType Directory -Force -Path $gitHome | Out-Null
    Stage 'Git Bash extraction'
    $p = Start-Process -FilePath $portable -ArgumentList @('-y',('-o' + $gitHome)) -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) { throw "Portable Git extraction failed: $($p.ExitCode)" }
    $bash = Join-Path $gitHome 'bin\bash.exe'
    Require-File $bash 'Git Bash is unavailable'
    return $bash
  }
  function Ensure-Node {
    $local = Join-Path $Tools 'node\node.exe'
    if (Test-Path $local) { return $local }
    # Prefer a compatible existing Node; otherwise download a portable official Node 24 LTS.
    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmd) {
      try {
        $v = (& $cmd.Source --version).Trim()
        if ($v -match '^v(\d+)\.(\d+)\.' -and (([int]$Matches[1] -eq 22 -and [int]$Matches[2] -ge 19) -or ([int]$Matches[1] -ge 23 -and [int]$Matches[1] -le 26))) {
          return $cmd.Source
        }
      } catch { }
    }
    if ([Environment]::Is64BitOperatingSystem -eq $false) { throw '64-bit Windows is required.' }
    Stage 'Node 24 release index'
    $index = Remote-Text @(
      'https://nodejs.org/dist/index.json',
      'https://npmmirror.com/mirrors/node/index.json',
      'https://registry.npmmirror.com/-/binary/node/index.json'
    )
    # PowerShell 5.1's @(... ConvertFrom-Json ...) wraps the entire JSON array as
    # ONE object. That creates a massive invalid URL and causes HTTP 400.
    try { $idx = ConvertFrom-Json -InputObject $index } catch { throw "Invalid Node 24 release index: $($_.Exception.Message)" }
    $item = $idx | Where-Object { $_.version -match '^v24\.' } | Select-Object -First 1
    if (-not $item -or $item.version -notmatch '^v24\.\d+\.\d+$') { throw 'Official Node 24 release index unavailable or invalid.' }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $zipName = "node-$($item.version)-win-$arch.zip"
    $baseUrl = "https://nodejs.org/dist/$($item.version)"
    $zipFile = Join-Path $Tools $zipName
    Stage 'Node 24 checksum manifest'
    $paths = @($baseUrl, "https://npmmirror.com/mirrors/node/$($item.version)", "https://registry.npmmirror.com/-/binary/node/$($item.version)")
    $checksums = Remote-Text @($paths | ForEach-Object { "$_/SHASUMS256.txt" })
    $escaped = [regex]::Escape($zipName)
    $match = [regex]::Match($checksums, "(?m)^([a-fA-F0-9]{64})\s+$escaped\s*$")
    if (-not $match.Success) { throw 'Official Node checksum not found.' }
    Stage 'Node 24 ZIP download'
    Download @($paths | ForEach-Object { "$_/$zipName" }) $zipFile $match.Groups[1].Value
    Stage 'Node 24 extraction'
    Expand-Archive -LiteralPath $zipFile -DestinationPath $Tools -Force
    $from = Join-Path $Tools ("node-$($item.version)-win-$arch")
    $to = Join-Path $Tools 'node'
    if (Test-Path $to) { throw "Unexpected existing Node directory: $to" }
    Move-Item -LiteralPath $from -Destination $to
    $node = Join-Path $to 'node.exe'
    Require-File $node 'Node download missing executable'
    return $node
  }
  function Stop-Owned([string]$Label,[string]$CommandAnchor) {
    $pidFile = Join-Path $State ($Label + '.pid')
    if (-not (Test-Path $pidFile)) { return }
    $savedPid = 0
    if (-not [int]::TryParse((Get-Content $pidFile -Raw).Trim(),[ref]$savedPid)) { return }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$savedPid" -ErrorAction SilentlyContinue
    if ($proc -and $proc.CommandLine -and $proc.CommandLine.Contains($CommandAnchor)) {
      Stop-Process -Id $savedPid -Force -ErrorAction SilentlyContinue
      Start-Sleep -Milliseconds 400
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  }
  function Start-Background([string]$Exe,[string[]]$Arguments,[string]$Label) {
    $stdout = Join-Path $Logs ($Label + '.out.log')
    $stderr = Join-Path $Logs ($Label + '.err.log')
    foreach ($f in @($stdout,$stderr)) { if (Test-Path $f) { Remove-Item $f -Force } }
    $process = Start-Process -FilePath $Exe -ArgumentList $Arguments -WorkingDirectory $State -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Set-Content -LiteralPath (Join-Path $State ($Label + '.pid')) -Value $process.Id -Encoding ascii
    return $process
  }
  function Wait-QuickURL([int]$TunnelProcessId) {
    $stderr = Join-Path $Logs 'tunnel.err.log'
    $stdout = Join-Path $Logs 'tunnel.out.log'
    for ($i=0; $i -lt 80; $i++) {
      Start-Sleep -Seconds 1
      $found = @()
      foreach ($log in @($stderr,$stdout)) {
        if (Test-Path $log) {
          $content = Get-Content $log -Raw -ErrorAction SilentlyContinue
          if ($content) { $found += [regex]::Matches($content,'https://[a-z0-9-]+\.trycloudflare\.com') | ForEach-Object Value }
        }
      }
      if ($found.Count -gt 0) { return $found[0] }
      if (-not (Get-Process -Id $TunnelProcessId -ErrorAction SilentlyContinue)) { break }
    }
    throw "Cloudflare Quick Tunnel did not return a URL. Read $stderr"
  }
  function Wait-LocalPort {
    for ($i=0; $i -lt 45; $i++) {
      $client = New-Object Net.Sockets.TcpClient
      try {
        $pending = $client.BeginConnect('127.0.0.1',$Port,$null,$null)
        if ($pending.AsyncWaitHandle.WaitOne(350)) { $client.EndConnect($pending); return }
      } catch { } finally { $client.Close() }
      Start-Sleep -Seconds 1
    }
    throw "DevSpace port $Port not ready. Check $Logs\devspace.err.log"
  }
  if ($Resume -and $ReuseInstalled) { throw 'Do not combine -Resume with -ReuseInstalled.' }
  if ($Resume -or $ReuseInstalled) {
    Stage 'Reading installed configuration'
    Require-File $SettingsFile 'Please run the initial installation first'
    if ($ReuseInstalled) {
      if ($Mode -ne 'Named' -or $PublicUrl -notmatch '^https://[a-zA-Z0-9.-]+$') { throw '-ReuseInstalled requires -Mode Named -PublicUrl https://HOST.' }
      $desiredUrl = $PublicUrl
    }
    $cfg = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    if ($Resume) {
      $Mode = [string]$cfg.mode
      $PublicUrl = [string]$cfg.publicUrl
    } else {
      $Mode = 'Named'
      $PublicUrl = $desiredUrl
    }
    $WorkspaceRoot = [string]$cfg.workspaceRoot
    $Node = [string]$cfg.node
    $DevJS = [string]$cfg.devJs
    $Bash = [string]$cfg.bash
    $Tunnel = [string]$cfg.tunnel
    foreach ($f in @($Node,$DevJS,$Bash,$Tunnel)) { Require-File $f 'Required tool missing' }
    if ($ReuseInstalled) {
      Require-File (Join-Path $State 'tunnel-token.dpapi') 'Previously paired named-tunnel token is missing'
      Require-File $PSCommandPath 'Installer must be run from its .ps1 file'
      if ([IO.Path]::GetFullPath($PSCommandPath) -ine [IO.Path]::GetFullPath($StartupFile)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $StartupFile -Force
      }
      Note 'Reusing installed Node, Git Bash, DevSpace, and cloudflared; no downloads or npm reinstall.'
    }
    if ($Mode -eq 'Quick') { $PublicUrl = '' } # A quick-tunnel URL cannot be reused after relaunch.
  } else {
    Stage 'Validating installation settings'
    if ($Mode -eq 'Named') {
      if ($PublicUrl -notmatch '^https://[a-zA-Z0-9.-]+$' -or $PublicUrl.EndsWith('/mcp')) { throw 'Named mode requires -PublicUrl https://YOUR-HOSTNAME (without /mcp).' }
    } else { if ($PublicUrl) { throw 'Quick mode does not accept -PublicUrl. Use -Mode Named.' } }
    if (-not $WorkspaceRoot) {
      if (Test-Path 'D:\') { $WorkspaceRoot = 'D:\Temp' }
      else { $WorkspaceRoot = Join-Path $env:USERPROFILE 'DevSpaceWork' }
    }
    $WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
    if ([IO.Path]::GetPathRoot($WorkspaceRoot).TrimEnd('\') -eq $WorkspaceRoot.TrimEnd('\')) { throw 'Do not expose an entire disk as a workspace.' }
    if ($WorkspaceRoot.StartsWith('\\')) { throw 'UNC workspace paths are not supported by this installer.' }
    New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
    Stage 'Git Bash'
    $Bash = Ensure-GitBash
    Stage 'Node.js'
    $Node = Ensure-Node
    $env:PATH = "$(Split-Path $Node);$(Split-Path $Bash);$env:PATH"
    Note "Using Node: $(& $Node --version), Git Bash: $Bash"
    $PackageHome = Join-Path $Tools 'npm'
    $DevJS = Join-Path $PackageHome 'node_modules\@waishnav\devspace\dist\cli.js'
    Stage ("Installing DevSpace " + $DevVersion)
    $npm = Join-Path (Split-Path $Node) 'npm.cmd'
    Require-File $npm 'npm.cmd missing next to Node'
    Invoke-Exe $npm @('install','--global','--prefix',$PackageHome,'--no-fund','--no-audit',("@waishnav/devspace@" + $DevVersion))
    $manifest = Join-Path $PackageHome 'node_modules\@waishnav\devspace\package.json'
    Require-File $manifest 'DevSpace package manifest missing'
    $pkg = Get-Content $manifest -Raw | ConvertFrom-Json
    if ([string]$pkg.version -ne $DevVersion) { throw 'Unexpected installed DevSpace version.' }
    $binRel = if ($pkg.bin -is [string]) { [string]$pkg.bin } else { [string]$pkg.bin.devspace }
    if (-not $binRel) { throw 'DevSpace entrypoint not in npm package.' }
    $DevJS = [IO.Path]::GetFullPath((Join-Path (Split-Path $manifest) $binRel))
    Require-File $DevJS 'DevSpace JavaScript entrypoint missing'
    Stage 'Cloudflare tunnel client'
    $Tunnel = Join-Path $Tools 'cloudflared.exe'
    $cloudSha = '341deda3db5ec498a0482254d6c38c0b7cf01a30c37bb5dd95d2216d08955e35'
    if ((Test-Path -LiteralPath $Tunnel -PathType Leaf) -and
        (Get-FileHash -LiteralPath $Tunnel -Algorithm SHA256).Hash -ine $cloudSha) {
      Note 'Replacing an earlier Cloudflare client with the pinned verified release.'
      Remove-Item -LiteralPath $Tunnel -Force
    }
    if (-not (Test-Path -LiteralPath $Tunnel -PathType Leaf)) {
      $cloudAsset = "https://github.com/cloudflare/cloudflared/releases/download/$CloudflaredVersion/cloudflared-windows-amd64.exe"
      Download @($cloudAsset, ('https://ghfast.top/' + $cloudAsset)) $Tunnel $cloudSha
    }
    Invoke-Exe $Tunnel @('--version')
    if ($Mode -eq 'Named') {
      $keyFile = Join-Path $State 'tunnel-token.dpapi'
      if (-not (Test-Path $keyFile)) {
        Note 'Paste your named Cloudflare Tunnel token at the LOCAL prompt. It will be stored using Windows user-bound DPAPI.'
        $secure = Read-Host 'Cloudflare Tunnel token' -AsSecureString
        if (-not $secure -or $secure.Length -lt 10) { throw 'A valid tunnel token is required.' }
        Set-Content -LiteralPath $keyFile -Value ($secure | ConvertFrom-SecureString) -Encoding ASCII
      }
    }
    # Copy only this one installer into a user-owned persistent directory for logon auto-start.
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
      if ([IO.Path]::GetFullPath($PSCommandPath) -ine [IO.Path]::GetFullPath($StartupFile)) { Copy-Item -LiteralPath $PSCommandPath -Destination $StartupFile -Force }
    } else { throw 'Run from a saved .ps1 file so automatic startup can be installed.' }
  }
  $env:PATH = "$(Split-Path $Node);$(Split-Path $Bash);$env:PATH"
  Stop-Owned 'devspace' $DevJS
  Stop-Owned 'tunnel' $Tunnel
  # Reject a collision with another process rather than terminating it.
  $probe = New-Object Net.Sockets.TcpClient
  try {
    $a = $probe.BeginConnect('127.0.0.1',$Port,$null,$null)
    if ($a.AsyncWaitHandle.WaitOne(350)) { $probe.EndConnect($a); throw "Port $Port already used by another process; not touching it." }
  } catch [Net.Sockets.SocketException] { } finally { $probe.Close() }
  if ($Mode -eq 'Quick') {
    Stage 'Starting temporary outbound Cloudflare Quick Tunnel'
    $tun = Start-Background $Tunnel @('tunnel','--no-autoupdate','--protocol','http2','--url',"http://127.0.0.1:$Port") 'tunnel'
    $PublicUrl = Wait-QuickURL $tun.Id
  } else {
    Stage 'Starting named Cloudflare Tunnel'
    $keyFile = Join-Path $State 'tunnel-token.dpapi'
    Require-File $keyFile 'Named tunnel secret missing'
    $secure = Get-Content $keyFile -Raw | ConvertTo-SecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
      $env:TUNNEL_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
      Note 'Starting named outbound Cloudflare Tunnel...'
      $tun = Start-Background $Tunnel @('tunnel','--no-autoupdate','run') 'tunnel'
    } finally {
      Remove-Item Env:\TUNNEL_TOKEN -ErrorAction SilentlyContinue
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
  }
  Stage ("Configuring DevSpace: " + $PublicUrl)
  # DevSpace 1.1.1 supports noninteractive init. Its --json output never includes the Owner password.
  $initOut = Join-Path $Logs 'devspace-init.out.log'
  $initErr = Join-Path $Logs 'devspace-init.err.log'
  if ($Resume -or $ReuseInstalled) {
    $initArgs = @(('"' + $DevJS + '"'),'config','set','publicBaseUrl',$PublicUrl)
  } else {
    # --force reuses the existing Owner token but reconciles an incomplete initial setup.
    $initArgs = @(('"' + $DevJS + '"'),'init','--force','--yes','--public-url',$PublicUrl,'--roots',('"' + $WorkspaceRoot + '"'),'--json')
  }
  # On Windows PowerShell 5.1, Start-Process joins ArgumentList into a single
  # command-line string and may corrupt the CLI arguments. Execute the exact
  # argv directly instead, capturing the real stderr for troubleshooting.
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    if ($Resume -or $ReuseInstalled) {
      & $Node $DevJS config set publicBaseUrl $PublicUrl 1> $initOut 2> $initErr
    } else {
      & $Node $DevJS init --force --yes --public-url $PublicUrl --roots $WorkspaceRoot --json 1> $initOut 2> $initErr
    }
    $initExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($initExitCode -ne 0) {
    $lines = if (Test-Path -LiteralPath $initErr) {
      (Get-Content -LiteralPath $initErr -Tail 12 -ErrorAction SilentlyContinue) -join ' '
    } else { '(stderr unavailable)' }
    throw "DevSpace configuration failed (exit=$initExitCode): $lines. Full log: $initErr"
  }
  # Read back the effective public URL before attempting to restart DevSpace.
  $readback = Join-Path $Logs 'devspace-config-readback.json'
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $Node $DevJS config get 1> $readback 2> $initErr
    $readbackCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($readbackCode -ne 0) {
    throw "DevSpace config readback failed ($readbackCode). See $initErr"
  }
  $effectiveConfig = Get-Content -LiteralPath $readback -Raw | ConvertFrom-Json
  if ([string]$effectiveConfig.server.publicBaseUrl -ne $PublicUrl) {
    throw 'DevSpace publicBaseUrl readback does not match the fixed tunnel URL.'
  }
  Remove-Item -LiteralPath $readback -Force -ErrorAction SilentlyContinue
  Stage 'Starting DevSpace'
  $dev = Start-Background $Node @('"' + $DevJS + '"','serve') 'devspace'
  Wait-LocalPort
  # Save the REAL quick-tunnel URL only after startup succeeds. Never register a
  # broken/partial setup for automatic retry on every Windows login.
  $settings = [ordered]@{mode=$Mode;publicUrl=$PublicUrl;workspaceRoot=$WorkspaceRoot;node=$Node;devJs=$DevJS;bash=$Bash;tunnel=$Tunnel}
  $settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
  if (-not $Resume) {
    $run = 'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $StartupFile + '" -Resume'
    $startupKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $startupKey -Force | Out-Null
    New-ItemProperty -Path $startupKey -Name 'SkylabDevSpace' -Value $run -PropertyType String -Force | Out-Null
  }
  $info = "MCP=$PublicUrl/mcp`r`nROOT=$WorkspaceRoot`r`nMODE=$Mode`r`nUSER=$env:USERNAME`r`nAUTH=$env:USERPROFILE\.devspace\auth.json`r`n"
  Set-Content -LiteralPath (Join-Path $State 'connection.txt') -Value $info -Encoding UTF8
  try {
    $doctor = & $Node $DevJS doctor 2>&1
    $doctor | Set-Content -LiteralPath (Join-Path $Logs 'doctor.log') -Encoding UTF8
  } catch {
    Note 'Doctor returned a warning; inspect doctor.log if connection fails.'
  }
  Note 'DEPLOYMENT COMPLETE: local DevSpace port is accepting TCP connections.'
  Note "MCP URL: $PublicUrl/mcp"
  Note "Workspace: $WorkspaceRoot"
  Note "Connection details: $State\connection.txt"
  Note "Owner-password file: $env:USERPROFILE\.devspace\auth.json (keep PRIVATE)"
  Note 'User-logon autostart enabled. Do not Sign out / Log off the RDP session; Disconnect is OK.'
  if ($Mode -eq 'Quick') { Note 'IMPORTANT: Quick Tunnel URL changes after restart; reconnect the MCP client. Use Named mode for a durable URL.' }
  Note 'Remote MCP authorization and Google API OAuth must still be completed separately.'
} catch {
  Write-Error ("Deployment failed at stage [" + $script:Stage + "]: " + $_.Exception.Message + ". Logs: " + $Logs)
  exit 1
} finally {
  if ($lockHeld) { $Mutex.ReleaseMutex() }
  $Mutex.Dispose()
}
