# Keeps ~/.doomscroller/claude-status: one line per open Claude Code session.
# The Windows twin of hooks/session-status.sh, with the same file format.
# Usage: session-status.ps1 <busy|waiting|idle|end>, hook JSON on stdin.
#
# Never fails the hook: any error is swallowed and it exits 0.

param([string]$State)

try {
  # Read stdin as UTF-8 bytes: the console code page would mangle a
  # non-ASCII folder name in "cwd".
  $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
  $hook = $reader.ReadToEnd() | ConvertFrom-Json
  $sessionId = [string]$hook.session_id
  if (-not $sessionId) { exit 0 }
  $cwd = [string]$hook.cwd

  $statusFile = Join-Path (Join-Path $HOME '.doomscroller') 'claude-status'
  [void][IO.Directory]::CreateDirectory((Split-Path $statusFile))

  # A named mutex shared by parallel sessions, like the mkdir lock on macOS.
  $mutex = [Threading.Mutex]::new($false, 'Local\doomscroller-claude-status')
  $locked = $false
  try {
    try { $locked = $mutex.WaitOne(1000) } catch [Threading.AbandonedMutexException] { $locked = $true }

    $lines = New-Object Collections.Generic.List[string]
    if (Test-Path -LiteralPath $statusFile) {
      foreach ($line in [IO.File]::ReadAllLines($statusFile)) {
        if ($line -and -not $line.Contains($sessionId)) { $lines.Add($line) }
      }
    }
    if ($State -ne 'end') {
      $lines.Add(("{0}`t{1}`t{2}`t{3}" -f $State, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $sessionId, $cwd))
    }

    # Write a temp file, then move it over the old one, so the watcher never
    # reads half a file. The watcher may hold the file open for a moment, so retry.
    $tmp = "$statusFile.$PID.tmp"
    $text = ($lines | ForEach-Object { "$_`n" }) -join ''
    [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($false))
    for ($i = 0; $i -lt 50; $i++) {
      try { Move-Item -LiteralPath $tmp -Destination $statusFile -Force -ErrorAction Stop; break }
      catch { Start-Sleep -Milliseconds 20 }
    }
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
  } finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
  }
} catch { }
exit 0
