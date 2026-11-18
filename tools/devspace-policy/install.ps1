# DevSpace tool-use policy installer (Windows PowerShell 5.1+/PowerShell 7).
# Run in Administrator PowerShell for apply/rollback. Only executes verified code.
param([ValidateSet('apply','check','status','rollback')][string]$Action = 'apply')
$ErrorActionPreference = 'Stop'
$Base = 'https://raw.githubusercontent.com/masakacj/chatgpt-web/release/devspace-tool-policy-multihost-20261118/tools/devspace-policy'
$ArchiveSha = '9d5fd70b70cf12b4f3744b9368dea0bce02b4d618512f794a62725b724869b44'
$ScriptSha = '77ed48dab778ccb66fdddc20b3b70fa173dd234447fd30c423b5828f454a3850'
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
