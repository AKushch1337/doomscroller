# Installs doomscroller for Windows from this checkout:
#  - adds this windows\ folder to your user PATH, so `doomscroller` works in
#    new terminals;
#  - adds the hooks to ~\.claude\settings.json (a backup is saved next to it
#    as settings.json.bak first). Hooks it already has are left alone.
#
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File windows\install.ps1
# Running it again changes nothing.

$ErrorActionPreference = 'Stop'
$windowsDir = $PSScriptRoot
$hookScript = Join-Path $windowsDir 'hooks\session-status.ps1'

# PATH, for the current user.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @(if ($userPath) { $userPath -split ';' | Where-Object { $_ } })
if ($parts -notcontains $windowsDir) {
  [Environment]::SetEnvironmentVariable('Path', (($parts + $windowsDir) -join ';'), 'User')
  Write-Output "added to PATH: $windowsDir"
} else {
  Write-Output "already on PATH: $windowsDir"
}
# Also for this window, so `doomscroller` works right away here.
if (($env:Path -split ';') -notcontains $windowsDir) { $env:Path = "$env:Path;$windowsDir" }

# Claude Code hooks.
$claudeDir = Join-Path $HOME '.claude'
$settingsFile = Join-Path $claudeDir 'settings.json'
[void][IO.Directory]::CreateDirectory($claudeDir)
if (Test-Path -LiteralPath $settingsFile) {
  $raw = [IO.File]::ReadAllText($settingsFile)
  $settings = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { New-Object psobject }
  # Keep the first backup: a rerun shouldn't replace it with a file this script wrote.
  if (-not (Test-Path -LiteralPath "$settingsFile.bak")) {
    Copy-Item -LiteralPath $settingsFile -Destination "$settingsFile.bak"
  }
} else {
  $settings = New-Object psobject
}

# Windows PowerShell 5.1 writes some arrays as {"value": [...], "Count": n}
# because of an extra Count property on System.Array. Remove it, so arrays
# come out as arrays, and undo that shape in a file an older install wrote.
Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue
function unwrap_arrays($node) {
  if ($node -is [Array]) { return ,@($node | ForEach-Object { unwrap_arrays $_ }) }
  if ($node -is [psobject] -and $node -isnot [string] -and $node -isnot [ValueType]) {
    $names = @($node.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names.Count -eq 2 -and $names -contains 'value' -and $names -contains 'Count') {
      return ,@(@($node.value) | ForEach-Object { unwrap_arrays $_ })
    }
    foreach ($property in $node.PSObject.Properties) {
      $property.Value = unwrap_arrays $property.Value
    }
  }
  return $node
}
$settings = unwrap_arrays $settings

if (-not $settings.PSObject.Properties['hooks']) {
  $settings | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object psobject)
}

# The command works whether Claude Code runs hooks in Git Bash or PowerShell.
$hookPath = $hookScript -replace '\\', '/'
$events = [ordered]@{
  SessionStart = 'idle'; UserPromptSubmit = 'busy'; PostToolUse = 'busy'
  Notification = 'waiting'; Stop = 'idle'; SessionEnd = 'end'
}
$added = 0
foreach ($event in $events.Keys) {
  $command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hookPath`" $($events[$event])"
  $entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $command }) }
  $existing = @()
  if ($settings.hooks.PSObject.Properties[$event]) { $existing = @($settings.hooks.$event) }
  $installed = $existing | Where-Object { ($_.hooks | Where-Object { $_.command -like '*session-status.ps1*' }) }
  if ($installed) { continue }
  if ($settings.hooks.PSObject.Properties[$event]) {
    $settings.hooks.$event = @($existing + $entry)
  } else {
    $settings.hooks | Add-Member -NotePropertyName $event -NotePropertyValue @($entry)
  }
  $added++
}
# Always rewrite, so a file broken by an older install gets fixed too.
$json = ConvertTo-Json -InputObject $settings -Depth 50
[IO.File]::WriteAllText($settingsFile, $json, [Text.UTF8Encoding]::new($false))
Write-Output "hooks in ${settingsFile}: $added added, the rest were already there (backup: settings.json.bak)"
Write-Output 'Restart Claude Code to load them.'

# Check the hook itself: feed it a fake session and read the status file back.
# "waiting" counts as idle, so a running watcher doesn't react.
$statusFile = Join-Path $HOME '.doomscroller\claude-status'
'{"session_id":"doomscroller-install-check","cwd":"install"}' |
  powershell -NoProfile -ExecutionPolicy Bypass -File $hookScript waiting
$ok = (Test-Path -LiteralPath $statusFile) -and ((Get-Content -LiteralPath $statusFile) -match 'doomscroller-install-check')
'{"session_id":"doomscroller-install-check"}' |
  powershell -NoProfile -ExecutionPolicy Bypass -File $hookScript end
if ($ok) { Write-Output 'hook check: OK' } else { Write-Output "hook check: FAILED, nothing was written to $statusFile" }
