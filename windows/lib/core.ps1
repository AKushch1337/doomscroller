# Paths and logging shared by every module.

$STATE_DIR = Join-Path $HOME '.doomscroller'
$PID_FILE = Join-Path $STATE_DIR 'pid'
$LOG_FILE = Join-Path $STATE_DIR 'log'
$CONFIG_FILE = Join-Path $STATE_DIR 'config'
# The browser profile doomscroller starts the browser with (see browser.ps1).
$PROFILE_DIR = Join-Path $STATE_DIR 'browser-profile'

# Written by hooks/session-status.ps1: one line per Claude Code session.
$STATUS_FILE = if ($env:DOOMSCROLLER_STATUS_FILE) { $env:DOOMSCROLLER_STATUS_FILE } else { Join-Path $STATE_DIR 'claude-status' }

# Set by the background watcher: log to $LOG_FILE instead of the console.
$script:LOG_TO_FILE = $false

$UTF8 = [Text.UTF8Encoding]::new($false)

function log([string]$message) {
  $line = (Get-Date -Format 'HH:mm:ss') + ' ' + $message
  if ($script:LOG_TO_FILE) {
    [IO.File]::AppendAllText($LOG_FILE, "$line`r`n", $UTF8)
  } else {
    Write-Host $line
  }
}

# Prints an error to stderr and exits 1.
function fail([string]$message) {
  [Console]::Error.WriteLine($message)
  exit 1
}
