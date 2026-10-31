# Claude Code's state, read from the status file the hook keeps.
# Lines are tab-separated: state, time, session id, working directory and,
# from the Windows hook, the session's transcript file.

# Returns the status file's lines, an empty list if there's none, or $null if
# it can't be read right now. Opened with full sharing, so the hook can
# replace the file while it's open here.
function status_lines {
  if (-not (Test-Path -LiteralPath $STATUS_FILE)) { return ,@() }
  try {
    $stream = [IO.FileStream]::new($STATUS_FILE, [IO.FileMode]::Open, [IO.FileAccess]::Read,
      [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
      $text = [IO.StreamReader]::new($stream, $UTF8).ReadToEnd()
    } finally { $stream.Dispose() }
  } catch { return $null }
  return ,@($text -split "`r?`n" | Where-Object { $_ })
}

# Whether you stopped this session yourself (Esc or the stop button) after it
# went busy. Claude Code runs no hook for that, so the line would stay busy.
# It does write "[Request interrupted by user]" to the transcript, so this
# looks at the last message there. Reads only the end of the file.
function interrupted_since([string]$transcript, [string]$busySince) {
  if (-not $transcript -or -not (Test-Path -LiteralPath $transcript)) { return $false }
  try {
    $stream = [IO.FileStream]::new($transcript, [IO.FileMode]::Open, [IO.FileAccess]::Read,
      [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
      [void]$stream.Seek([Math]::Max(0, $stream.Length - 262144), [IO.SeekOrigin]::Begin)
      $tail = [IO.StreamReader]::new($stream, $UTF8).ReadToEnd()
    } finally { $stream.Dispose() }
    $lines = $tail -split "`r?`n"
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      if (-not $lines[$i]) { continue }
      try { $entry = $lines[$i] | ConvertFrom-Json } catch { continue }  # a cut-off first line
      if ($entry.type -ne 'user' -and $entry.type -ne 'assistant') { continue }
      # The last message decides: anything after an interrupt means Claude is
      # going again. Only Claude Code's own marker counts: a user message
      # whose text starts with it, not a message that merely mentions it.
      $content = $entry.message.content
      $texts = @(if ($content -is [string]) { $content } else {
        foreach ($part in @($content)) { if ($part.type -eq 'text') { [string]$part.text } }
      })
      $marker = $entry.type -eq 'user' -and ($texts | Where-Object { $_.StartsWith('[Request interrupted by user') })
      if (-not $marker) { return $false }
      # An interrupt from before this busy line is an old one.
      $at = [DateTime]::Parse([string]$entry.timestamp, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
      $since = [DateTime]::ParseExact($busySince, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
      return $at -ge $since
    }
  } catch { }
  return $false
}

# Returns one session's state from its status line: busy, waiting, idle or
# "interrupted" (a busy line for a session you stopped yourself).
function line_state([string]$line) {
  $fields = $line -split "`t"
  if ($fields[0] -eq 'busy' -and $fields.Count -ge 5 -and (interrupted_since $fields[4] $fields[1])) {
    return 'interrupted'
  }
  return $fields[0]
}

# Returns "busy" if any session is busy, otherwise "idle" (waiting and
# interrupted count as idle), or $null if the file can't be read right now.
function claude_state {
  $lines = status_lines
  if ($null -eq $lines) { return $null }
  foreach ($line in $lines) {
    if ((line_state $line) -eq 'busy') { return 'busy' }
  }
  return 'idle'
}

# Returns every session's state with its folder name,
# e.g. "busy doomscroller, idle my-project".
function session_states {
  $lines = status_lines
  if (-not $lines) { return 'no sessions' }
  $parts = foreach ($line in $lines) {
    $fields = $line -split "`t"
    $folder = if ($fields.Count -ge 4 -and $fields[3]) { Split-Path -Leaf $fields[3] } else { '' }
    "$(line_state $line) $folder"
  }
  return ($parts -join ', ')
}
