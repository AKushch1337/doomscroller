# CLAUDE.md

doomscroller opens Instagram Reels or YouTube Shorts in the browser while
Claude Code is busy. When Claude goes idle, it pauses the video and switches
back to Claude. It's a macOS bash CLI, with a Windows port in PowerShell under
`windows/` (see [Windows](#windows) below). See README.md for the user-facing
docs.

## Architecture

```
hooks/session-status.sh ──▶ ~/.doomscroller/claude-status ──▶ doomscroller (watcher) ──▶ browser tab / Claude app
   (Claude Code hook)            (one line per session)        polls every second
```

```
doomscroller            entry point: finds lib/ (following the symlink), sources the modules, calls main
lib/
  core.sh               paths (STATUS_FILE, STATE_DIR, PID/LOG/CONFIG_FILE) and log()
  settings.sh           settings: env var > config file > default; load_settings, validate, save
  sites.sh              use_site: per-feed URL, PAUSE_KEY, NEXT_BUTTON
  claude.sh             reads the status file: claude_state, session_states
  macos.sh              apps and keyboard: app_exists, frontmost_app, press_key_code, press_play_pause_key
  browser.sh            AppleScript for tabs: show_page (find/reuse/open the tab), run_tab_js, page_js
  player.sh             the video: pause_video, unmute_reels, start_autoscroll
  watcher.sh            the process: watch_claude loop, start_watcher (background), run_watcher_here (-w), stop_watcher
  cli.sh                usage, cmd_start/cmd_status/cmd_config, main (command dispatch)
  page/*.js             JavaScript run inside the feed's tab (via run_tab_js)
    reels-check.js        is a reel on screen, and does it need sound?
    reels-unmute.js       click Instagram's sound button
    reels-play.js         click Instagram's "Press to play" if the reel is paused
    autoscroll.js         a function; installs the "next video when this one ends" listener
    video-state.js        is the video on screen playing? (Windows only, before pausing)
  jxa/play-pause-key.js JavaScript for Automation, run by osascript: posts the media play/pause key
hooks/session-status.sh the Claude Code hook (see below)
```

### Layers and dependencies

Modules only define functions and constants. Nothing runs when a module is
sourced, apart from the constants in `core.sh`, `settings.sh` and
`browser.sh`. The entry point sources them in a fixed order
(`core settings sites claude macos browser player watcher cli`), then runs
`load_settings` and `main "$@"`.

Calls go downward only:

- `cli` → `watcher`, `settings`, `sites`, `claude`
- `watcher` → `browser`, `player`, `claude`
- `player` → `browser`, `macos`
- `browser` → `core`
- `settings` → `macos` (`app_exists`)

`claude.sh` knows nothing about the browser. `browser.sh` knows nothing about
Reels or Shorts. Site-specific knowledge lives in `sites.sh` (data) and in
`player.sh` with `page/` (behavior).

### Global state

Set once, then read by everyone:

| Variable | Set by | Meaning |
|----------|--------|---------|
| `DOOMSCROLLER`, `LIB_DIR` | entry point | the command as it was run (the watcher re-runs it); the `lib/` path |
| `SITE`, `BROWSER`, `CLAUDE_APP`, `AUTOSCROLL` | `load_settings`; `cmd_start` flags override `SITE`/`AUTOSCROLL` | settings |
| `URL`, `PAUSE_KEY`, `NEXT_BUTTON` | `use_site`; a `url` argument overrides `URL` | the feed |
| `PAGE_OPENED` | `show_page` | fallback: the page was already opened once this run |

### Commands

`start [--reels|--shorts] [--autoscroll|--no-autoscroll] [-w] [url]`, `stop`,
`status`, `config [list|get|set|unset]` and `--help`. There is also an
internal `_watch <site> <autoscroll> <url>`. `start_watcher` re-runs the
command with it as the background process, passing the already-resolved
settings so flags survive.

### The hook

`hooks/session-status.sh <busy|waiting|idle|end>` gets the hook JSON on
stdin. It keeps `~/.doomscroller/claude-status` (creating the folder if
needed) with one tab-separated line per session:
`state  time  session_id  cwd`. `end` removes the line. The path is written
both in the hook and in `STATUS_FILE` (core.sh): change them together. A `mkdir` lock
protects the file from parallel sessions, and it is replaced atomically. It is
wired to SessionStart/Stop (idle), UserPromptSubmit/PostToolUse (busy),
Notification (waiting) and SessionEnd (end) in `~/.claude/settings.json`.

### Installed copies are symlinks

`/opt/homebrew/bin/doomscroller` points to `doomscroller`, and
`~/.claude/hooks/session-status.sh` points to `hooks/session-status.sh`.
**Editing the files here changes the live tool.** A watcher that is already
running keeps the old code until it is restarted.

## How the watcher works

- `watch_claude` polls `claude_state` every second. The aggregate state is
  `busy` if any line is `busy`. Everything else, including `waiting`, counts
  as idle. It acts only on transitions, and starts from `idle`, so if Claude
  is already busy at start, the first poll opens the page.
- **busy**:
  1. `show_page` runs `tab_script`. It picks the feed's tab with
     `FIND_TAB_START`: first a tab whose URL starts with the feed URL, then
     any tab on the domain. It points that tab at the feed unless it's
     already there, so the video isn't reloaded, and selects it. With no tab,
     it opens a new one. If the browser can't be scripted, it opens the page
     once per run and afterwards only brings the browser forward.
  2. `unmute_reels`, on Instagram only: polls `reels-check.js` until a reel
     is on screen, presses F13, runs `reels-unmute.js`, then retries
     `reels-play.js` until the reel plays. The `window.__doomscroller` mark
     limits this to once per page load.
  3. `start_autoscroll`, if `AUTOSCROLL=on`: injects `autoscroll.js` with the
     feed URL and `NEXT_BUTTON`, once per page load
     (`window.__doomscrollerScroll`). From then on, the page itself clicks
     "next" whenever the on-screen video finishes. Bash doesn't poll for it.
- **idle**: `pause_video` presses the site's pause key, but only if the
  browser is the frontmost app, then the watcher runs `open -a "$CLAUDE_APP"`.

## Non-obvious decisions, keep them

- **Background start goes through `perl -MPOSIX -e 'setsid; exec @ARGV'`.**
  The Claude desktop app kills the whole process group of a `!` command, so
  without a new session the watcher dies with that shell. macOS has no
  `setsid` binary.
- **The Reels pause key is the media play/pause key, not the F8 key code.**
  F8 on a Mac keyboard sends `NX_KEYTYPE_PLAY` (16), which macOS routes to
  whatever is playing. `key code 100` sends a plain F8, which the page
  ignores. `jxa/play-pause-key.js` posts the system-defined event. It checks
  `AXIsProcessTrusted()` first and throws without access, so failures show up
  in the log.
- **Keys are pressed only when the browser is in front** (`frontmost_app` via
  `lsappinfo`, which needs no permissions). Otherwise a space would be typed
  into whatever app the user switched to, for example Claude's prompt box.
- **Apps are validated by looking for `<name>.app` in the standard folders.**
  Don't use `open -Ra`, which reveals the app in Finder, or AppleScript
  `application "X"`, which can pop up a "Where is X?" dialog.
- **Tabs are addressed by index (`tab i of w`), not by `repeat with t in`
  references,** so the same script body works in Arc, Safari and Chromium
  browsers. Only the select or execute line differs per browser. Check a new
  browser case with `osacompile`: it compiles against the app's dictionary
  without sending events, so no permission prompt appears.
- **Reels sound needs a real key press first.** Chromium allows unmuted
  playback only after user activation. Clicks made from JavaScript don't
  count, and neither does `execute` from AppleScript. A System Events key
  press does count. F13 is used because it types nothing and Instagram
  ignores it. Without activation, unmuting works, but `play()` rejects with
  `NotAllowedError`. This was verified live in Arc.
- **Use Instagram's own controls, not the `<video>` element.** Clicking the
  `Audio is muted` button makes Instagram keep sound on for later reels.
  Calling `video.play()` directly gets undone, because Instagram still
  thinks the reel is paused and pauses it again. So `reels-play.js` clicks
  the `Press to play` overlay instead.
- **Arc's `execute` blocks while a page loads,** sometimes for over a minute,
  which used to freeze the watcher. `tab_js_script` wraps it in
  `with timeout of 2 seconds` and returns `"timeout"`, and callers retry.
- **Page scripts are self-contained expressions.** Every `execute` runs in
  the page's global scope, so a second top-level `const` fails and returns
  `null`. Each `page/*.js` is an IIFE whose value is the result.
  `autoscroll.js` is a bare function, and `start_autoscroll` appends the call
  with its arguments. Results come back JSON-quoted, and `run_tab_js` strips
  the quotes.
- **Autoscroll listens on `document` in the capture phase** (`ended`,
  `timeupdate`), because both feeds swap `<video>` elements as you scroll.
  Reels fire `ended` (`loop` is false). Shorts have `loop` set and never fire
  it, so a jump from the last 1.5 s back to under 1 s counts as finishing.
  A 2 s debounce keeps one finish from moving two videos.
- **YouTube labels are localized** (the user's account is Russian: "Следующее
  видео"). Select YouTube elements by id (`#navigation-button-down button`).
  Instagram's labels are English for this user, and nothing else to select by
  has been found.
- `autoscroll.js` returns `"wrong page"` while the tab still shows the
  previous page, for example right after it was pointed at the feed.
  Otherwise the script would install itself into the page that is about to
  be replaced.
- Pressing keys needs Accessibility access, and reading tabs needs Automation
  access to the browser. Both are granted to the *responsible* app, meaning
  the one the user launched doomscroller from, not doomscroller itself.

## Windows

`windows/` is a port of the same design to Windows PowerShell 5.1 and
Chromium browsers. It mirrors the macOS modules and function names, so a
change on one side is easy to find on the other:

```
windows/
  doomscroller.cmd      shim on PATH: runs doomscroller.ps1 with -ExecutionPolicy Bypass
  doomscroller.ps1      entry point: dot-sources lib/*.ps1, load_settings, main
  lib/
    core.ps1            paths (adds PROFILE_DIR), log() to the console or $LOG_FILE
    settings.ps1        as settings.sh; browser is "chrome" or an .exe path; adds debug-port
    sites.ps1           same as sites.sh
    claude.ps1          as claude.sh; reads with full sharing so the hook can replace the file
    win32.ps1           counterpart of macos.sh: C# via Add-Type (window focus, keybd_event)
    browser.ps1         counterpart of browser.sh, over the Chrome DevTools Protocol
    player.ps1          as player.sh, using ../lib/page/*.js unchanged
    watcher.ps1         as watcher.sh
    cli.ps1             as cli.sh
  hooks/session-status.ps1   the hook, same file format as session-status.sh
```

The page scripts in `lib/page/` are shared. Keep them browser-neutral.

### Non-obvious decisions on Windows, keep them

- **Chrome is driven over CDP, started by doomscroller** with
  `--remote-debugging-port` and its own `--user-data-dir`
  (`~/.doomscroller/browser-profile`). Chrome 136+ ignores the port for the
  default profile. Tabs come from `GET /json/list`, `GET /json/activate/<id>`
  selects one, and `Target.createTarget` (browser WebSocket) opens one.
  `/json/new` needs `PUT` since Chrome 111, so it isn't used. CDP commands go
  over `System.Net.WebSockets.ClientWebSocket`, one connection per command.
  .NET's client sends no `Origin`, so no `--remote-allow-origins` is needed.
  Don't add it: it would let web pages connect.
- **Reels sound uses `Runtime.evaluate` with `userGesture: true`,** not F13.
  It sets `navigator.userActivation`, and `video.play()` with sound then
  works. Verified with headless Chrome 153: `NotAllowedError` without it,
  `played` with it.
- **Shorts' space is `Input.dispatchKeyEvent` `rawKeyDown`/`keyUp` with no
  `text`.** It's trusted (`isTrusted` is true), reaches the tab without
  focus, and types nothing into a focused input. Verified headless. Reels
  keep the media play/pause key (`VK_MEDIA_PLAY_PAUSE`) as on macOS.
- **`pause_video` asks `video-state.js` first** and presses only for a
  playing video, so pausing doesn't toggle a paused video back on. That
  replaces the "only when the browser is in front" check.
- **The background watcher is created with WMI `Win32_Process.Create`,** the
  setsid equivalent: it belongs to no job object or process tree, so it
  survives the shell that ran `start`. WMI processes don't inherit the
  caller's environment, so `_watch` takes every resolved setting as an
  argument: `_watch <site> <autoscroll> <browser> <claude-app> <debug-port>
  <status-file> <url>`.
- **Focusing a window** uses `AttachThreadInput` to the foreground thread,
  then `SetForegroundWindow`; if Windows still refuses, it presses F13 (so
  this process sent the last input) and tries again. The browser's window is
  found from its main process: the one whose command line has the debugging
  port and no `--type=`.
- **The hook command works in Git Bash and in PowerShell.** Claude Code runs
  hooks in Git Bash when it's installed, otherwise PowerShell.
  `powershell ... -File "$HOME/..."` expands in both, and Git Bash converts
  `/c/Users/...` to a Windows path for `powershell.exe`. The hook reads stdin
  as UTF-8 bytes (the console code page would mangle Cyrillic folder names)
  and serializes through a named mutex instead of `mkdir`.

### Windows conventions

- Target Windows PowerShell **5.1**: no `??`, no ternary, no `&&`/`||`
  between commands, no `ForEach-Object -Parallel`. `::new()` is fine.
  C# in `Add-Type` is compiled by .NET Framework's C# 5: no `out var`, no
  string interpolation.
- `$ErrorActionPreference = 'Stop'` is set in the entry point. Cmdlets that
  may legitimately fail take `-ErrorAction SilentlyContinue`, and
  `watch_claude` catches errors per transition so one failure doesn't stop
  the watcher.
- Functions return everything they don't capture: wrap calls whose output
  isn't wanted in `[void](...)`. `switch` runs every matching case, and
  `continue`/`break` inside it act on the `switch`, not the loop around it.
- Files are UTF-8 without BOM, written with `$UTF8`. `.ps1` and `.cmd` are
  checked out with CRLF (`.gitattributes`).

### Testing on Windows

The same rules as above apply: fake status file
(`DOOMSCROLLER_STATUS_FILE`), throwaway `HOME`, and never focus windows or
press keys on the user's desktop. CDP behavior can be checked from any OS
against `chrome --headless=new --remote-debugging-port=<port>
--user-data-dir=<tmp>` with a small local page.

## Conventions

- Target the system `/bin/bash`, which is **3.2**: no `mapfile`, no
  associative arrays, no `${var,,}`, and `source <(…)` doesn't work. Use only
  macOS built-ins (`open`, `osascript`, `lsappinfo`, `perl`, `awk`, `jq` for
  the hook). No installs.
- Put code in the module that owns the concern, and keep calls going down
  the layers. JavaScript goes in its own file under `page/` or `jxa/`, never
  inline in bash strings.
- Each module starts with a comment saying what it owns. Each function gets
  a short comment saying what it does or why.
- Comments and user-facing text are in English.
- When you add a command, flag or setting, update `usage()` (cli.sh) and
  README.md in the same change. `usage()` is the single source for the CLI
  reference. A new setting also needs `setting_info`, `validate_setting` and
  `load_settings`. A new site needs `use_site` and `validate_setting`.
- Errors go to stderr and exit 1. Help and success output go to stdout and
  exit 0.

## Testing

There is no test suite. Exercise the code in isolation, and **never switch
windows or press keys on the real desktop** while the user is working:

- Point it at a fake status file: `DOOMSCROLLER_STATUS_FILE=/tmp/…/status.txt`.
- Use a throwaway `HOME=…` so the real `~/.doomscroller` (pid, config, log) is
  untouched. A real watcher may be running.
- Put stub `open`, `osascript` and `lsappinfo` scripts first in `PATH`. Have
  them log their arguments and return a fake frontmost app for `lsappinfo`.
  `run_tab_js` calls `osascript - <host> <url> <js>`, so a stub can answer by
  what the JS contains.
- Rewrite the fake status file to drive transitions, then check the stub
  calls and `$HOME/.doomscroller/log`. Give a busy step about 3.5 s, because
  unmuting Reels retries for a while.
- For a refactor, diff old and new: run `git show HEAD:doomscroller` (or
  `HEAD:lib/…`) and the working copy through the same cases, and compare the
  output.
- Call single functions by sourcing modules:
  `bash -c 'LIB_DIR=lib; source lib/core.sh; source lib/browser.sh; BROWSER=Arc; tab_script'`.
- Syntax: run `bash -n` on `doomscroller` and `lib/*.sh`. For JS, run
  `osacompile` on the generated AppleScripts, and parse `page/*.js` with
  `new Function(src)` under `osascript -l JavaScript`.
- Page scripts can only really be tested live, through `run_tab_js`
  against the user's tab. Read-only probes are fine. Ask before anything
  that reloads, pauses or unmutes. The agent's shell has no Accessibility
  access, so the F13 and pause-key steps can only be tested by the user.
- **Instagram keeps reels paused while the browser window isn't focused.**
  Testing playback with Claude in front doesn't work. Test autoscroll by
  dispatching `new Event("ended")` on the visible video instead. On Shorts,
  seeking to `duration - 2` works in a background tab (`open -g -a Arc …`).

The Bash tool's shell is zsh: unquoted `$args` doesn't word-split, and
`echo ===` fails. Pass arguments explicitly in test loops.
