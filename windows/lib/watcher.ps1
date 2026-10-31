# The watcher process: follows Claude's state and switches between the feed
# and Claude. One instance at a time, tracked by $PID_FILE.

function is_running {
  if (-not (Test-Path -LiteralPath $PID_FILE)) { return $false }
  $id = 0
  if (-not [int]::TryParse(([IO.File]::ReadAllText($PID_FILE)).Trim(), [ref]$id)) { return $false }
  $process = Get-Process -Id $id -ErrorAction SilentlyContinue
  return [bool]($process -and $process.ProcessName -eq 'powershell')
}

function watcher_pid {
  return ([IO.File]::ReadAllText($PID_FILE)).Trim()
}

# Polls Claude's state every second and acts only when it changes.
# With -everyPoll, also logs every poll.
function watch_claude([string]$url, [switch]$everyPoll) {
  log "watching, Claude is $(claude_state)"
  # Start from idle, so if Claude is already busy the first poll opens the page.
  $last = 'idle'
  while ($true) {
    Start-Sleep -Seconds 1
    $now = claude_state
    # The hook is replacing the file right now: try again next second.
    if ($null -eq $now) { continue }
    if ($everyPoll) { log "$now | $(session_states)" }
    if ($now -eq $last) { continue }
    try {
      if ($now -eq 'busy') {
        log 'busy -> browser'
        show_page $url
        unmute_reels $url
        if ($AUTOSCROLL -eq 'on') { start_autoscroll $url }
      } else {
        log "idle -> $CLAUDE_APP"
        pause_video $url
        if (-not (focus_app $CLAUDE_APP)) {
          log "can't bring $CLAUDE_APP to the front. Is it running? Set its process name with: doomscroller config set claude-app <name>"
        }
      }
    } catch {
      # One failed switch shouldn't stop the watcher.
      log "error: $($_.Exception.Message)"
    }
    $last = $now
  }
}

# Runs the watcher in this terminal, logging every poll, until Ctrl+C.
function run_watcher_here {
  [void][IO.Directory]::CreateDirectory($STATE_DIR)
  [IO.File]::WriteAllText($PID_FILE, "$PID")
  try {
    Write-Host "doomscroller watching: $URL in $BROWSER, autoscroll $AUTOSCROLL (Ctrl+C to stop)"
    load_win32
    watch_claude $URL -everyPoll
  } finally {
    Remove-Item -LiteralPath $PID_FILE -Force -ErrorAction SilentlyContinue
  }
}

# Wraps a command-line argument in quotes.
function quote([string]$value) { return '"' + $value + '"' }

# Starts the watcher in the background, logging to $LOG_FILE. It re-runs this
# script as `doomscroller.ps1 _watch <site> <autoscroll> <browser>
# <claude-app> <debug-port> <status-file> <url>`.
#
# The process is created through WMI (Win32_Process.Create), so it doesn't
# belong to the shell that started it and survives it, the way setsid does
# on macOS: the Claude app can kill a `!` command's whole process tree. A
# WMI process doesn't inherit this shell's environment variables, so every
# setting is passed as an argument.
function start_watcher {
  [void][IO.Directory]::CreateDirectory($STATE_DIR)
  $command = @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', (quote $DOOMSCROLLER), '_watch', $SITE, $AUTOSCROLL, (quote $BROWSER), (quote $CLAUDE_APP),
    $DEBUG_PORT, (quote $STATUS_FILE), (quote $URL)) -join ' '
  $startup = New-CimInstance -Namespace root/cimv2 -ClassName Win32_ProcessStartup -ClientOnly `
    -Property @{ ShowWindow = [uint16]0 }
  $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
    -Arguments @{ CommandLine = $command; ProcessStartupInformation = $startup }
  if ($result.ReturnValue -ne 0) { fail "can't start the watcher (Win32_Process.Create returned $($result.ReturnValue))" }
  [IO.File]::WriteAllText($PID_FILE, "$($result.ProcessId)")
  Write-Output "doomscroller started: $URL in $BROWSER, autoscroll $AUTOSCROLL"
}

# The background process started by start_watcher.
function run_background_watcher([string[]]$settings) {
  $script:SITE, $script:AUTOSCROLL, $script:BROWSER, $script:CLAUDE_APP, $script:DEBUG_PORT, $script:STATUS_FILE, $url = $settings
  use_site $SITE
  $script:LOG_TO_FILE = $true
  try {
    load_win32
    watch_claude $url
  } catch {
    log "watcher stopped: $($_.Exception.Message)"
    exit 1
  }
}

function stop_watcher {
  if (is_running) {
    Stop-Process -Id ([int](watcher_pid)) -Force
    Write-Output 'doomscroller stopped'
  } else {
    Write-Output 'doomscroller is not running'
  }
  Remove-Item -LiteralPath $PID_FILE -Force -ErrorAction SilentlyContinue
}
