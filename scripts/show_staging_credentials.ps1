param(
    [string]$Path = "$PSScriptRoot\..\.secrets\staging-credentials-2026-07-29.dpapi"
)

$workspace = (Resolve-Path "$PSScriptRoot\..").Path
$secretPath = (Resolve-Path -LiteralPath $Path).Path
if (-not $secretPath.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The credential file must be inside this workspace."
}

$encrypted = [Convert]::FromBase64String(
    (Get-Content -Raw -LiteralPath $secretPath).Trim()
)
$plaintext = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $encrypted,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)

try {
    [Text.Encoding]::UTF8.GetString($plaintext) |
        ConvertFrom-Json |
        Format-Table role, phone, password -AutoSize
}
finally {
    [Array]::Clear($plaintext, 0, $plaintext.Length)
}
