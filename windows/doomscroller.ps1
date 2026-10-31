# doomscroller for Windows: while Claude Code is working, show Reels or Shorts
# in Chrome; when it stops (idle or waiting for you), pause the video and
# bring Claude back to the front.
#
# Reads ~/.doomscroller/claude-status, kept by hooks/session-status.ps1.
# Commands, flags and settings: run doomscroller --help.
# How the code is laid out: CLAUDE.md, section "Windows".
#
# Targets Windows PowerShell 5.1, which ships with Windows 10 and 11.

$ErrorActionPreference = 'Stop'

# This script. The background watcher re-runs it.
$DOOMSCROLLER = $PSCommandPath
$WIN_DIR = $PSScriptRoot
# The page scripts are shared with the macOS version.
$PAGE_DIR = Join-Path (Split-Path $PSScriptRoot) 'lib\page'

foreach ($module in 'core', 'settings', 'sites', 'claude', 'win32', 'browser', 'player', 'watcher', 'cli') {
  . (Join-Path $PSScriptRoot "lib\$module.ps1")
}

load_settings
main $args
exit 0
