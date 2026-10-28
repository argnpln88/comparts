$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskConnection = Get-Content -LiteralPath (Join-Path $taskRoot '.env.account-connection.json') -Raw | ConvertFrom-Json
$taskLinked = (Get-Content -LiteralPath (Join-Path $taskRoot 'supabase/.temp/project-ref') -Raw).Trim()
if ($taskConnection.SUPABASE_PROJECT_REF -ne $taskLinked) { throw 'Activate the new account project before using this wrapper.' }
if (-not $taskConnection.SUPABASE_ACCESS_TOKEN) { throw 'The project deployment token is missing.' }
$taskPreviousToken = $env:SUPABASE_ACCESS_TOKEN
try {
    $env:SUPABASE_ACCESS_TOKEN = $taskConnection.SUPABASE_ACCESS_TOKEN
    Push-Location -LiteralPath $taskRoot
    try { & npx.cmd --yes supabase @args; if ($LASTEXITCODE -ne 0) { throw 'Supabase command failed.' } }
    finally { Pop-Location }
} finally { $env:SUPABASE_ACCESS_TOKEN = $taskPreviousToken }
