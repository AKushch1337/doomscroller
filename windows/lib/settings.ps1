# Settings: each one comes from its environment variable, then the config
# file (key=value lines in $CONFIG_FILE), then its default.

$CONFIG_KEYS = 'site', 'browser', 'claude-app', 'autoscroll', 'debug-port'

# Returns a setting's environment variable and default, or $null if unknown.
function setting_info([string]$key) {
  switch ($key) {
    'site'       { return 'DOOMSCROLLER_SITE', 'reels' }
    'browser'    { return 'DOOMSCROLLER_BROWSER', 'chrome' }
    'claude-app' { return 'DOOMSCROLLER_CLAUDE_APP', 'claude' }
    'autoscroll' { return 'DOOMSCROLLER_AUTOSCROLL', 'off' }
    'debug-port' { return 'DOOMSCROLLER_DEBUG_PORT', '9222' }
  }
  return $null
}

# Returns the value saved in the config file, empty if none.
function config_value([string]$key) {
  $value = ''
  if (Test-Path -LiteralPath $CONFIG_FILE) {
    foreach ($line in [IO.File]::ReadAllLines($CONFIG_FILE)) {
      if ($line.StartsWith("$key=")) { $value = $line.Substring($key.Length + 1) }
    }
  }
  return $value
}

# Returns where a setting comes from: env, config or default.
function setting_source([string]$key) {
  $envName = (setting_info $key)[0]
  if ([Environment]::GetEnvironmentVariable($envName)) { return 'env' }
  if (config_value $key) { return 'config' }
  return 'default'
}

# Returns a setting's current value.
function setting([string]$key) {
  $envName, $default = setting_info $key
  switch (setting_source $key) {
    'env'    { return [Environment]::GetEnvironmentVariable($envName) }
    'config' { return config_value $key }
  }
  return $default
}

# Sets the globals the rest of the app reads. Flags for start may change
# SITE and AUTOSCROLL afterwards.
function load_settings {
  $script:SITE = setting 'site'
  $script:BROWSER = setting 'browser'
  $script:CLAUDE_APP = (setting 'claude-app') -replace '\.exe$', ''
  $script:AUTOSCROLL = setting 'autoscroll'
  $script:DEBUG_PORT = setting 'debug-port'
}

# Checks a value before it's saved. Returns what's wrong, or nothing if it's valid.
function validate_setting([string]$key, [string]$value) {
  switch ($key) {
    'site' {
      if ($value -notin 'reels', 'shorts') { return 'site must be reels or shorts' }
    }
    'autoscroll' {
      if ($value -notin 'on', 'off') { return 'autoscroll must be on or off' }
    }
    'browser' {
      if (-not (browser_exe $value)) {
        return "browser not found: $value (use chrome, or the full path to a Chromium-based browser's .exe)"
      }
    }
    'debug-port' {
      $port = 0
      if (-not [int]::TryParse($value, [ref]$port) -or $port -lt 1024 -or $port -gt 65535) {
        return 'debug-port must be a number from 1024 to 65535'
      }
    }
  }
}

# Writes key=value to the config file, or removes the key if no value is given.
function save_setting([string]$key, [string]$value) {
  [void][IO.Directory]::CreateDirectory($STATE_DIR)
  $lines = New-Object Collections.Generic.List[string]
  if (Test-Path -LiteralPath $CONFIG_FILE) {
    foreach ($line in [IO.File]::ReadAllLines($CONFIG_FILE)) {
      if (-not $line.StartsWith("$key=")) { $lines.Add($line) }
    }
  }
  if ($value) { $lines.Add("$key=$value") }
  $text = ($lines | ForEach-Object { "$_`n" }) -join ''
  $tmp = "$CONFIG_FILE.$PID.tmp"
  [IO.File]::WriteAllText($tmp, $text, $UTF8)
  Move-Item -LiteralPath $tmp -Destination $CONFIG_FILE -Force
}
