$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($entry in $manifest.files) {
    $file = Join-Path $root $entry.path
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing: $($entry.path)" }
    if ((Get-Item -LiteralPath $file).Length -ne $entry.bytes) { throw "Size mismatch: $($entry.path)" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $entry.sha256) {
        throw "SHA-256 mismatch: $($entry.path)"
    }
}
$p = Join-Path $root 'prj/project_13'
foreach ($item in @('vivado', 'out', 'scripts/pre_impl_debug.dcp', 'scripts/post_route.dcp')) {
    if (Test-Path -LiteralPath (Join-Path $p $item)) { throw "Expected fresh build root: $item exists" }
}
Write-Output "V4_INPUTS_OK files=$($manifest.files.Count) base=$($manifest.base_commit)"

