# DevSpace tool-use policy installer (Windows PowerShell 5.1+/PowerShell 7).
# Run in Administrator PowerShell for apply/rollback. Only executes verified code.
param([ValidateSet('apply','check','status','rollback')][string]$Action = 'apply')
$ErrorActionPreference = 'Stop'
$Base = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/release/devspace-tool-policy-multihost-20261118-r2/tools/devspace-policy'
$ArchiveSha = '22a131c17958493141bdafccffe643b066c1e36e72789e46c6999b11d1a7f9d8'
$ScriptSha = 'c99722874505ef0598fa30af8d41a8880297a08c3bda0b447a2a3d967a9421ae'
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('devspace-tool-policy-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temp -Force | Out-Null
try {
    $Archive = Join-Path $Temp 'policy.mjs.gz'
    $Script = Join-Path $Temp 'policy.mjs'
    Invoke-WebRequest -Uri "$Base/devspace-tool-policy.mjs.gz" -OutFile $Archive -UseBasicParsing
    if ((Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant() -ne $ArchiveSha) { throw 'Downloaded archive SHA-256 mismatch' }
    $InputStream = [IO.File]::OpenRead($Archive)
    try {
        $Decompress = [IO.Compression.GZipStream]::new($InputStream, [IO.Compression.CompressionMode]::Decompress)
        try {
            $OutputStream = [IO.File]::Create($Script)
            try { $Decompress.CopyTo($OutputStream) } finally { $OutputStream.Dispose() }
        } finally { $Decompress.Dispose() }
    } finally { $InputStream.Dispose() }
    if ((Get-FileHash -Algorithm SHA256 $Script).Hash.ToLowerInvariant() -ne $ScriptSha) { throw 'Extracted source SHA-256 mismatch' }
    & node $Script check
    if ($LASTEXITCODE -ne 0) { throw 'DevSpace source preflight failed' }
    & node $Script $Action
    if ($LASTEXITCODE -ne 0) { throw "Operation failed: $Action" }
} finally {
    Remove-Item -LiteralPath $Temp -Force -Recurse -ErrorAction SilentlyContinue
}
