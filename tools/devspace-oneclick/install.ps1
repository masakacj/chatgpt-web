#requires -Version 5.1
<#
DevSpace OneClick bootstrap. Fresh, dedicated Windows x64 deployment.
Use -ProfileFile for a previously provisioned named tunnel. -Quick is temporary.
The profile contains secrets: create/deliver it privately, never paste its contents.
#>
[CmdletBinding()]
param([string]$InstallDir='', [string]$Workspace='', [string]$ProfileFile='',
      [switch]$Quick, [switch]$NoAutostart, [switch]$TestOnly)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$CoreUrl='https://raw.githubusercontent.com/masakacj/chatgpt-web/57fe0125c214689c399d093a0064d84bcb15bddf/tools/devspace-oneclick/installer.mjs'
$CoreHash='220B70ED339D09B534D0C8C55C0C261962AEE9FB0F82CE5FE58A9ACE3FBF30DF'
$NodeVersion='24.22.3'
$NodeHash='E612AF99F626AB415EA225AF6BCE5C971FEB448CB5CAE250BB1C3FA50C5F7D9F'
$GitHash='9DD04A608CEB5F6AB32A73709E0ECB159D211DA71B697C45FF81F6DD0C6B49C7'
function Say([string]$m){Write-Host ('[DevSpace bootstrap] '+$m)}
function DownloadPinned([string]$url,[string]$dest,[string]$sha){
 if((Test-Path -LiteralPath $dest -PathType Leaf) -and (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ieq $sha){return}
 $part=$dest+'.'+$PID+'.part'
 try{
  Say ('Downloading '+([uri]$url).Host)
  try{Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $part -TimeoutSec 240}
  catch{
   $curl=Get-Command curl.exe -ErrorAction SilentlyContinue
   if(-not $curl){throw}
   & $curl.Source --fail --location --silent --show-error --connect-timeout 20 --max-time 240 --output $part $url
   if($LASTEXITCODE -ne 0){throw 'Download failed'}
  }
  if((Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash -ine $sha){throw 'SHA256 mismatch'}
  Move-Item -LiteralPath $part -Destination $dest -Force
 }finally{Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue}
}
function NodeOK([string]$exe){
 if(-not $exe -or -not(Test-Path -LiteralPath $exe -PathType Leaf)){return $false}
 try{
  $v=(& $exe --version).Trim().TrimStart('v')
  $ver=[version]$v
  return ($ver -ge [version]'22.19.0' -and $ver.Major -lt 27 -and
   (Test-Path (Join-Path (Split-Path -Parent $exe) 'node_modules\npm\bin\npm-cli.js')))
 }catch{return $false}
}
if(-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){throw 'This Windows bootstrap targets x64 Windows'}
if(-not $InstallDir){
 $c=Join-Path $env:LOCALAPPDATA 'DevSpaceOneClick'
 $d='D:\DevSpaceOneClick'
 if(Test-Path -LiteralPath (Join-Path $d 'private\runtime.json')){$InstallDir=$d}
 elseif(Test-Path -LiteralPath (Join-Path $c 'private\runtime.json')){$InstallDir=$c}
 elseif((Test-Path 'D:\') -and [IO.DriveInfo]::new('D').AvailableFreeSpace -ge 4GB){$InstallDir=$d}
 else{$InstallDir=$c}
}
$Root=[IO.Path]::GetFullPath($InstallDir)
if($Root.TrimEnd('\') -eq [IO.Path]::GetPathRoot($Root).TrimEnd('\')){throw 'Use a dedicated install directory, not a drive root'}
if(-not $ProfileFile){$ProfileFile=$env:DEVSPACE_PROFILE_FILE}
if($ProfileFile){$ProfileFile=[IO.Path]::GetFullPath($ProfileFile);if(-not(Test-Path -LiteralPath $ProfileFile -PathType Leaf)){throw 'Private profile file missing'}}
if(-not $ProfileFile -and -not $Quick -and -not $TestOnly -and -not(Test-Path (Join-Path $Root 'private\deployment.json'))){throw 'Named tunnel needs a privately provisioned profile; pass -ProfileFile. For temporary testing use -Quick.'}
$drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($Root))
if(-not(Test-Path (Join-Path $Root 'program\devspace-1.1.1')) -and $drive.AvailableFreeSpace -lt 4GB){throw 'Installation volume needs at least 4 GiB free. Select -InstallDir on another disk.'}
$Downloads=Join-Path $Root 'downloads';$Tools=Join-Path $Root 'tools';$Tmp=Join-Path $Root 'tmp'
New-Item -ItemType Directory -Path $Root,$Downloads,$Tools,$Tmp -Force|Out-Null
$env:TEMP=$Tmp;$env:TMP=$Tmp;$env:NPM_CONFIG_CACHE=Join-Path $Root 'npm-cache'
Say ('Install directory: '+$Root)
$Node=Join-Path $Tools 'node\node.exe'
if(-not(NodeOK $Node)){
 $existing=Get-Command node.exe -ErrorAction SilentlyContinue
 if($existing -and (NodeOK $existing.Source)){$Node=$existing.Source}
 else{
  $zip=Join-Path $Downloads ('node-v'+$NodeVersion+'-win-x64.zip')
  DownloadPinned ('https://nodejs.org/dist/v'+$NodeVersion+'/node-v'+$NodeVersion+'-win-x64.zip') $zip $NodeHash
  $stage=Join-Path $Tools ('node-stage-'+[guid]::NewGuid().ToString('N'))
  Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
  $candidate=Join-Path $stage ('node-v'+$NodeVersion+'-win-x64')
  if(-not(NodeOK (Join-Path $candidate 'node.exe'))){throw 'Portable Node validation failed'}
  $target=Join-Path $Tools 'node'
  if(Test-Path -LiteralPath $target){Move-Item -LiteralPath $target -Destination ($target+'.old-'+[guid]::NewGuid().ToString('N'))}
  Move-Item -LiteralPath $candidate -Destination $target
  Remove-Item -LiteralPath $stage -Force
  $Node=Join-Path $target 'node.exe'
 }
}
if(-not(NodeOK $Node)){throw 'Node/npm validation failed'}
$env:PATH=(Split-Path -Parent $Node)+';'+$env:PATH
$gitRoot=$null
$git=Get-Command git.exe -ErrorAction SilentlyContinue
$roots=@((Join-Path $Tools 'git'),'D:\Git','C:\Program Files\Git',(Join-Path $env:LOCALAPPDATA 'Programs\Git'))
if($git){$roots=@((Split-Path -Parent (Split-Path -Parent $git.Source)))+$roots}
foreach($g in $roots){if((Test-Path (Join-Path $g 'bin\bash.exe')) -and (Test-Path (Join-Path $g 'cmd\git.exe'))){$gitRoot=$g;break}}
if(-not $gitRoot){
 $asset='PortableGit-2.56.1-64-bit.7z.exe'
 $installer=Join-Path $Downloads $asset
 DownloadPinned ('https://github.com/git-for-windows/git/releases/download/v2.56.1.windows.1/'+$asset) $installer $GitHash
 $candidate=Join-Path $Tools ('git-stage-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $candidate|Out-Null
 $p=Start-Process -FilePath $installer -ArgumentList @('-y',('-o"'+$candidate+'"')) -Wait -PassThru -WindowStyle Hidden
 if($p.ExitCode -ne 0 -or -not(Test-Path (Join-Path $candidate 'bin\bash.exe')) -or -not(Test-Path (Join-Path $candidate 'cmd\git.exe'))){throw 'Portable Git extraction failed'}
 $gitRoot=Join-Path $Tools 'git'
 if(Test-Path $gitRoot){Move-Item -LiteralPath $gitRoot -Destination ($gitRoot+'.old-'+[guid]::NewGuid().ToString('N'))}
 Move-Item -LiteralPath $candidate -Destination $gitRoot
}
$env:PATH=(Join-Path $gitRoot 'cmd')+';'+(Join-Path $gitRoot 'bin')+';'+$env:PATH
& (Join-Path $gitRoot 'cmd\git.exe') --version
if($LASTEXITCODE -ne 0){throw 'Git runtime check failed'}
& (Join-Path $gitRoot 'bin\bash.exe') --version | Select-Object -First 1
if($LASTEXITCODE -ne 0){throw 'Git Bash runtime check failed'}
$core=Join-Path $Root 'installer.mjs'
DownloadPinned $CoreUrl $core $CoreHash
$argv=@($core,'deploy','--root',$Root)
if($Workspace){$argv+=@('--workspace',[IO.Path]::GetFullPath($Workspace))}
if($ProfileFile){$argv+=@('--profile',$ProfileFile)}
if($Quick){$argv+='--quick'}
if($NoAutostart){$argv+='--no-autostart'}
if($TestOnly){$argv+='--test-only'}
& $Node @argv
if($LASTEXITCODE -ne 0){throw ('DevSpace installer failed, exit '+$LASTEXITCODE+'. See logs on the installation volume.')}

