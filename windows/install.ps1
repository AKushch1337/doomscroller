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
  Copy-Item -LiteralPath $settingsFile -Destination "$settingsFile.bak" -Force
} else {
  $settings = New-Object psobject
}
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
if ($added) {
  $json = $settings | ConvertTo-Json -Depth 50
  [IO.File]::WriteAllText($settingsFile, $json, [Text.UTF8Encoding]::new($false))
  Write-Output "added $added hooks to $settingsFile (backup: settings.json.bak). Restart Claude Code to load them."
} else {
  Write-Output "hooks already installed in $settingsFile"
}
