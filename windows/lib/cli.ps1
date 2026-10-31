# Commands: parses arguments, prints help and results. The work itself
# happens in the other modules.

function usage {
  @"
doomscroller: watch Reels or Shorts while Claude Code works. (Windows)

When Claude starts working, opens the page in the browser ($BROWSER). When it
stops (idle or waiting for you), pauses the video and brings $CLAUDE_APP back.

Usage:
  doomscroller start [--reels | --shorts] [--autoscroll | --no-autoscroll] [--watch] [url]
  doomscroller stop
  doomscroller status
  doomscroller config [list | get <key> | set <key> <value> | unset <key>]
  doomscroller --help

Commands:
  start        start watching in the background (log: ~\.doomscroller\log)
  stop         stop watching
  status       show whether it's running and what Claude is doing
  config       show or change settings (saved in ~\.doomscroller\config)

Flags for start:
  --reels      Instagram Reels, paused with the media play/pause key
  --shorts     YouTube Shorts, paused with space
  --autoscroll, --no-autoscroll
               go to the next video when one ends, or don't (beats the config)
  -w, --watch  stay in this terminal and log Claude's state every second
  url          open this page instead, paused like the chosen site

Settings:
  site         reels or shorts (default: reels)
  browser      chrome, or the path to a Chromium-based browser's .exe (default: chrome)
  claude-app   process name of the app to return to (default: claude;
               e.g. WindowsTerminal, Code)
  autoscroll   on or off: go to the next video when one ends (default: off)
  debug-port   port the browser is controlled through (default: 9222)

  Examples: doomscroller config set site shorts
            doomscroller config set claude-app WindowsTerminal
            doomscroller config set autoscroll on
            doomscroller config unset site

  For one run, environment variables override the config:
  DOOMSCROLLER_SITE, DOOMSCROLLER_BROWSER, DOOMSCROLLER_CLAUDE_APP,
  DOOMSCROLLER_AUTOSCROLL, DOOMSCROLLER_DEBUG_PORT. Flags for start beat both.

The browser runs with its own profile (~\.doomscroller\browser-profile), so
log in to Instagram or YouTube there once.
"@
}

# doomscroller start [--reels | --shorts] [--autoscroll | --no-autoscroll] [--watch] [url]
function cmd_start([string[]]$options) {
  $watchHere = $false
  $customUrl = ''
  foreach ($option in $options) {
    switch ($option) {
      '--reels' { $script:SITE = 'reels' }
      '--shorts' { $script:SITE = 'shorts' }
      '--autoscroll' { $script:AUTOSCROLL = 'on' }
      '--no-autoscroll' { $script:AUTOSCROLL = 'off' }
      { $_ -in '-w', '--watch' } { $watchHere = $true }
      { $_ -in '-h', '--help' } { usage; exit 0 }
      default { if ($option) { $customUrl = $option } }
    }
  }
  use_site $SITE
  if ($customUrl) { $script:URL = $customUrl }
  if (is_running) {
    Write-Output "doomscroller is already running (pid $(watcher_pid))"
    exit 0
  }
  if (-not (browser_exe $BROWSER)) {
    fail "browser not found: $BROWSER (doomscroller config set browser <path to .exe>)"
  }
  if ($watchHere) { run_watcher_here } else { start_watcher }
}

function cmd_status {
  if (is_running) {
    Write-Output "running (pid $(watcher_pid)), Claude is $(claude_state)"
  } else {
    Write-Output "stopped, Claude is $(claude_state)"
  }
}

# doomscroller config [list | get <key> | set <key> <value> | unset <key>]
function cmd_config([string[]]$options) {
  $action = if ($options.Count -ge 1) { $options[0] } else { 'list' }
  $key = if ($options.Count -ge 2) { $options[1] } else { '' }
  $value = if ($options.Count -ge 3) { $options[2..($options.Count - 1)] -join ' ' } else { '' }
  if ($action -notin 'list', 'get', 'set', 'unset') {
    [Console]::Error.WriteLine((usage))
    exit 1
  }
  if ($action -ne 'list') {
    $info = setting_info $key
    if (-not $info) { fail "unknown setting: '$key' (settings: $($CONFIG_KEYS -join ' '))" }
    $envName, $default = $info
  }
  switch ($action) {
    'list' {
      foreach ($name in $CONFIG_KEYS) {
        Write-Output ('{0,-11} {1} ({2})' -f $name, (setting $name), (setting_source $name))
      }
      return
    }
    'get' {
      Write-Output (setting $key)
      return
    }
    'set' {
      if (-not $value) { fail "usage: doomscroller config set $key <value>" }
      $problem = validate_setting $key $value
      if ($problem) { fail $problem }
      save_setting $key $value
      Write-Output "$key = $value"
    }
    'unset' {
      save_setting $key ''
      Write-Output "$key = $default (default)"
    }
  }
  # After set or unset: say when the change doesn't take effect right away.
  $envValue = [Environment]::GetEnvironmentVariable($envName)
  if ($envValue) {
    Write-Output "note: $envName=$envValue is set in this shell and overrides the config"
  }
  if (is_running) {
    Write-Output 'doomscroller is running: restart it to apply (doomscroller stop, then start)'
  }
}

function main([string[]]$argv) {
  $command = if ($argv.Count -ge 1) { $argv[0] } else { '' }
  $rest = if ($argv.Count -ge 2) { [string[]]$argv[1..($argv.Count - 1)] } else { [string[]]@() }
  switch ($command) {
    'start'  { cmd_start $rest }
    'stop'   { stop_watcher }
    'status' { cmd_status }
    'config' { cmd_config $rest }
    # The background watcher started by start_watcher.
    '_watch' { run_background_watcher $rest }
    { $_ -in '-h', '--help', 'help' } { usage }
    default { [Console]::Error.WriteLine((usage)); exit 1 }
  }
}
