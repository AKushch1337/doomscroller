# Claude Code's state, read from the status file the hook keeps.
# Lines are tab-separated: state, time, session id, working directory.

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

# Returns "busy" if any session is busy, otherwise "idle" (waiting counts as
# idle), or $null if the file can't be read right now.
function claude_state {
  $lines = status_lines
  if ($null -eq $lines) { return $null }
  foreach ($line in $lines) {
    if (($line -split "`t")[0] -eq 'busy') { return 'busy' }
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
    "$($fields[0]) $folder"
  }
  return ($parts -join ', ')
}
