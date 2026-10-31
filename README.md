# doomscroller

<img width="600" height="558" alt="image" src="https://github.com/user-attachments/assets/6bea4bb8-e625-4ddb-a439-d38fd3fdf03b" />


Watch Instagram Reels or YouTube Shorts while Claude Code works, and get pulled
back the moment it needs you.

When Claude starts working, doomscroller opens the feed in your browser. When
Claude finishes or stops to ask you something, it pauses the video and brings
Claude back to the front.

macOS: plain bash, no dependencies beyond what ships with macOS.
Windows: PowerShell and Google Chrome, see [Windows](#windows).

## How it works

```
Claude Code hooks ──▶ ~/.doomscroller/claude-status ──▶ doomscroller ──▶ browser / Claude
```

1. **Hook** ([hooks/session-status.sh](hooks/session-status.sh)). Claude Code
   runs it on its lifecycle events. It keeps one line per open session in
   `~/.doomscroller/claude-status`:
   - `busy` when you send a prompt and after every tool call;
   - `waiting` when Claude asks for permission or input;
   - `idle` when a session starts or Claude finishes its turn;
   - the line is removed when the session ends.
2. **Watcher** ([doomscroller](doomscroller), with its modules in
   [lib/](lib)). It reads that file once a
   second. Claude counts as busy if any session is busy. On a change:
   - **idle → busy**: shows the feed in the browser. It prefers a tab
     already on the feed and doesn't reload it, so you keep your place.
     Otherwise it takes any tab on the same site and points it at the feed,
     for example an Instagram profile becomes Reels. Without such a tab, it
     opens a new one.

     On Reels it also turns the sound on. A freshly loaded Instagram page
     starts muted, because the browser allows sound only after you've
     interacted with the page. So doomscroller presses F13, a key that types
     nothing but counts as interaction, then clicks Instagram's own sound
     button and starts the reel. It does this once per page load, so if you
     mute a reel yourself, it stays muted.

     With autoscroll on, it also makes the feed move by itself: when the
     video on screen finishes, it clicks the site's "next" button. Videos
     always play to the end. While Claude is idle the video is paused, so the
     feed stops too.
   - **busy → idle/waiting**: pauses the video if the browser is still in
     front, then switches to the Claude app.

## Install

1. Clone the repo and put `doomscroller` on your `PATH`:

   ```bash
   git clone https://github.com/kreslavskiy/doomscroller.git ~/Developer/doomscroller
   ```

   ```bash
   ln -s ~/Developer/doomscroller/doomscroller /opt/homebrew/bin/doomscroller
   ```

   Use a symlink rather than a copy: the command finds its `lib/` folder
   next to the file the link points to.

2. Install the hook. Link the script into Claude's hooks folder:

   ```bash
   mkdir -p ~/.claude/hooks && ln -s ~/Developer/doomscroller/hooks/session-status.sh ~/.claude/hooks/session-status.sh
   ```

   Then add this to `~/.claude/settings.json`, merging it with any `hooks` you
   already have:

   ```json
   {
     "hooks": {
       "SessionStart":     [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh idle" }] }],
       "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh busy" }] }],
       "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh busy" }] }],
       "Notification":     [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh waiting" }] }],
       "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh idle" }] }],
       "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh end" }] }]
     }
   }
   ```

   Sessions started after this change will show up in
   `~/.doomscroller/claude-status`.

3. Allow two permissions for the app you run `doomscroller` from (Terminal,
   iTerm, Claude…). Both are in System Settings → Privacy & Security:
   - **Accessibility**, for pressing keys (pause, and F13 before unmuting
     Reels). Without it, videos aren't paused and Reels stay muted.
   - **Automation → your browser**, for finding the open tab and turning on
     Reels sound. macOS asks the first time. Without it, the page opens once,
     later turns only bring the browser forward, and Reels stay muted.

   The log tells you when something is missing.

   Tab reuse works in Arc, Safari, Google Chrome, Brave, Edge, Chromium and
   Vivaldi. Other browsers fall back to opening the page once. Turning on
   Reels sound runs JavaScript in the tab. Arc allows that as is. Chrome-like
   browsers need View → Developer → Allow JavaScript from Apple Events, and
   Safari needs Develop → Allow JavaScript from Apple Events.

## Usage

```bash
doomscroller start              # Reels (or your configured site), in the background
doomscroller start --shorts     # YouTube Shorts this time
doomscroller start --autoscroll # go to the next video when one ends
doomscroller start -w           # stay in the terminal and log Claude's state every second
doomscroller status             # running? what is Claude doing?
doomscroller stop
doomscroller --help
```

`start` also takes a URL to open instead of the feed. It gets paused the same
way as the chosen site.

The background watcher logs every switch to `~/.doomscroller/log`. In watch
mode (`-w`) it prints to the terminal instead, including every poll:

```
14:26:47 watching, Claude is idle
14:26:48 busy | idle my-project, busy doomscroller
14:26:48 busy -> Arc
14:26:51 idle | idle my-project, idle doomscroller
14:26:51 idle -> Claude
14:26:51 paused video (play key)
```

## Configuration

```bash
doomscroller config                          # show all settings and where each comes from
doomscroller config set site shorts
doomscroller config set browser Google Chrome
doomscroller config set claude-app iTerm
doomscroller config set autoscroll on
doomscroller config get browser
doomscroller config unset browser            # back to the default
```

| Setting      | Values                           | Default  |
|--------------|----------------------------------|----------|
| `site`       | `reels`, `shorts`                | `reels`  |
| `browser`    | any app in `/Applications` etc.  | `Arc`    |
| `claude-app` | the app to return to             | `Claude` |
| `autoscroll` | `on`, `off`                      | `off`    |

Settings live in `~/.doomscroller/config`. For a one-off run, the environment
variables `DOOMSCROLLER_SITE`, `DOOMSCROLLER_BROWSER`,
`DOOMSCROLLER_CLAUDE_APP` and `DOOMSCROLLER_AUTOSCROLL` override the config.
Flags for `start` beat both: `--reels`/`--shorts` override `site`, and
`--autoscroll`/`--no-autoscroll` override `autoscroll`. A running watcher
picks up changes only after a restart.

How each site gets paused:

| Site     | Page                               | Pause key                               | Autoscroll clicks              |
|----------|------------------------------------|-----------------------------------------|--------------------------------|
| `reels`  | `https://www.instagram.com/reels/` | media play/pause (F8 on a Mac keyboard) | "Navigate to next reel"        |
| `shorts` | `https://www.youtube.com/shorts`   | space                                   | the down arrow next to a Short |

Autoscroll runs JavaScript in the tab, like Reels sound, so it needs the same
browser setup.

## Security

doomscroller makes no network requests of its own. In the browser it only
touches the feed's tab: the video player and its buttons. Its config is
parsed, never executed. But the permissions it needs are broad, so know what you're
granting:

- **Accessibility and Automation go to the whole app you run it from,** not
  to doomscroller. If that's Terminal, any script you run in Terminal can
  then press keys and control your browser without asking again. To limit
  this, run doomscroller from a terminal app you don't use for anything
  else, and remove the permissions when you stop using it.
- **"Allow JavaScript from Apple Events"** (needed in Chrome-like browsers
  and Safari for Reels sound and autoscroll) lets any app with Automation
  access to the browser run JavaScript in every tab, including tabs where
  you're logged in. Arc allows this without a setting. Leave the option off
  if you don't need those two features. Tab switching and pausing work
  without it.
- The hook and the watcher write only to `~/.doomscroller/`.

## Caveats

- **Pausing toggles.** Both keys toggle playback, so a video you had already
  paused will start playing again.
- **Space goes to the page.** On Shorts, if a text field such as the search
  box has focus, the space is typed into it instead.
- **Stale busy lines.** If a session crashes without its `SessionEnd` hook, its
  `busy` line stays in the status file and doomscroller thinks Claude is still
  working. Delete that line from `~/.doomscroller/claude-status`.
- **Reels sound and autoscroll depend on the sites' pages.** They find
  buttons by their labels (`Audio is muted`, `Press to play`,
  `Navigate to next reel`) or by YouTube's element id, so a redesign can
  break them. If the "next" button is gone, autoscroll falls back to
  scrolling the feed by a screen.
- **Seeking back counts as finishing.** On Shorts, a video that jumps from
  its last second back to the start counts as finished, because that's how
  Shorts loop. Rewinding to the start during the last second does the same.
- **The feed takes over the site's tab.** Every turn sends the Instagram (or
  YouTube) tab back to the feed, even if you were reading DMs there.
- **Fast replies.** A reply that takes a couple of seconds still sends you to
  the browser and right back.

## Windows

The Windows version lives in [windows/](windows). It does the same thing with
the same commands, for Google Chrome (or another Chromium-based browser), in
Windows PowerShell 5.1, which ships with Windows 10 and 11. Nothing to
install.

Windows has no AppleScript, so doomscroller drives Chrome through its
debugging port (the Chrome DevTools Protocol). Since Chrome 136 that port
works only with a separate profile, so **doomscroller starts its own Chrome
window with its own profile** in `~\.doomscroller\browser-profile`. Your usual
Chrome profile isn't touched. The first time, log in to Instagram or YouTube
in that window.

### Install

After cloning, `windows\install.ps1` does steps 1 and 2 for you (it backs up
`settings.json` first):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $HOME\doomscroller\windows\install.ps1
```

By hand:

1. Clone the repo and put `windows\` on your `PATH` (in PowerShell):

   ```powershell
   git clone https://github.com/kreslavskiy/doomscroller.git $HOME\doomscroller
   ```

   ```powershell
   [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ";$HOME\doomscroller\windows", 'User')
   ```

   Open a new terminal afterwards, so it sees the new `PATH`.

2. Install the hook. Add this to `~\.claude\settings.json`, merging it with any
   `hooks` you already have. It points at the clone from step 1, so change the
   path if you cloned elsewhere. The command works whether Claude Code runs
   hooks in Git Bash or in PowerShell.

   ```json
   {
     "hooks": {
       "SessionStart":     [{ "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/doomscroller/windows/hooks/session-status.ps1\" idle" }] }],
       "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/doomscroller/windows/hooks/session-status.ps1\" busy" }] }],
       "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/doomscroller/windows/hooks/session-status.ps1\" busy" }] }],
       "Notification":     [{ "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/doomscroller/windows/hooks/session-status.ps1\" waiting" }] }],
       "Stop":             [{ "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/doomscroller/windows/hooks/session-status.ps1\" idle" }] }],
       "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/doomscroller/windows/hooks/session-status.ps1\" end" }] }]
     }
   }
   ```

3. If you don't use the Claude desktop app, tell doomscroller which app to
   return to, by its process name (the name in Task Manager's Details tab,
   without `.exe`):

   ```powershell
   doomscroller config set claude-app WindowsTerminal
   ```

4. Run `doomscroller start`, send Claude a prompt, and log in to the feed's
   site in the Chrome window that opens.

### Usage and settings

The commands and flags are the same as on macOS. The settings differ a little:

| Setting      | Values                                                     | Default  |
|--------------|------------------------------------------------------------|----------|
| `site`       | `reels`, `shorts`                                          | `reels`  |
| `browser`    | `chrome`, or the full path to a Chromium-based browser's `.exe` | `chrome` |
| `claude-app` | process name of the app to return to (`claude`, `WindowsTerminal`, `Code`…) | `claude` |
| `autoscroll` | `on`, `off`                                                | `off`    |
| `debug-port` | port Chrome is controlled through                          | `9222`   |

`DOOMSCROLLER_DEBUG_PORT` overrides `debug-port` like the other environment
variables.

### What's different from macOS

- **No permissions to grant.** There's no Accessibility or Automation
  prompt, and no "Allow JavaScript from Apple Events".
- **Reels sound needs no key press.** Scripts run through the debugging
  port count as user interaction, so the sound comes on even if Chrome isn't
  in front.
- **Pausing doesn't toggle.** doomscroller checks that the video is playing
  before it presses the pause key, so a video you paused stays paused.
- **Space on Shorts goes to the tab, not the keyboard.** It's sent straight
  to the Shorts tab without typing anything, so it never lands in another app
  or in YouTube's search box. Reels still use the media play/pause key, which
  Windows sends to whatever is playing.

### Windows security

The debugging port gives any program on your computer full control of the
Chrome window doomscroller starts, including the sites you're logged in to
there. Chrome accepts connections only from this computer, and doomscroller
uses its own profile so your usual Chrome isn't exposed. Log in to nothing
but the feed's site in that window. When you stop using doomscroller, close
that window, and delete `~\.doomscroller\browser-profile` if you want the
logins gone.

### Windows caveats

- **That Chrome window must be started by doomscroller.** If you open the
  doomscroller profile some other way, it runs without the debugging port.
  Close it and let doomscroller start it.
- **Bringing windows to the front can fail.** Windows limits which programs
  may switch the window in front. If it refuses, the window's taskbar button
  flashes instead, and the log says so.
- **Each hook call starts PowerShell,** which adds a fraction of a second to
  every tool call.

## Files

| Path                            | What                                |
|---------------------------------|-------------------------------------|
| `~/.doomscroller/claude-status` | session states, written by the hook |
| `~/.doomscroller/config`        | settings (`key=value` lines)        |
| `~/.doomscroller/log`           | background watcher log              |
| `~/.doomscroller/pid`           | pid of the running watcher          |
| `~/.doomscroller/browser-profile` | Windows: the Chrome profile doomscroller starts Chrome with |
