# The browser: starting it, finding the feed's tab, showing it, and running
# JavaScript in it. The Windows counterpart of lib/browser.sh.
#
# Windows has no AppleScript, so this drives Chrome through the Chrome
# DevTools Protocol (CDP): doomscroller starts Chrome with
# --remote-debugging-port, lists tabs over HTTP and runs JavaScript over a
# WebSocket. Chrome 136+ ignores that flag for the default profile, so the
# browser runs with its own profile in $PROFILE_DIR. Works with any
# Chromium-based browser that takes the same flags.

# Returns a URL's domain without "www.", e.g. "instagram.com".
function url_host([string]$url) {
  return ($url -replace '^[a-z]+://', '' -replace '/.*$', '' -replace '^www\.', '')
}

# Returns the page script lib/page/<name>.js.
function page_js([string]$name) {
  return [IO.File]::ReadAllText((Join-Path $PAGE_DIR "$name.js"), $UTF8)
}

# Returns the path of the browser's .exe for a browser setting: "chrome"
# (looked up in the usual install folders) or a path to an .exe. $null if missing.
function browser_exe([string]$browser) {
  if ($browser -eq 'chrome') {
    $candidates = @(
      (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
      (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
  } else {
    $candidates = @($browser)
  }
  foreach ($path in $candidates) {
    if ($path -and $path.EndsWith('.exe') -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
  }
  return $null
}

# Sends a GET to the browser's debugging HTTP endpoint and returns the parsed
# JSON, or $null if the browser doesn't answer. Skips any system proxy.
function cdp_http([string]$path) {
  try {
    $request = [Net.HttpWebRequest]::Create("http://127.0.0.1:$DEBUG_PORT$path")
    $request.Proxy = $null
    $request.Timeout = 2000
    $response = $request.GetResponse()
    try {
      $text = [IO.StreamReader]::new($response.GetResponseStream(), $UTF8).ReadToEnd()
    } finally { $response.Dispose() }
    if ($text.StartsWith('[') -or $text.StartsWith('{')) { return ,($text | ConvertFrom-Json) }
    return $text
  } catch {
    return $null
  }
}

# Sends one CDP command over a WebSocket and returns the parsed reply, or a
# string "timeout" if no reply comes within $timeoutMs. One connection per
# command keeps it simple; they're local and cheap.
function cdp_call([string]$webSocketUrl, [string]$method, [hashtable]$params = @{}, [int]$timeoutMs = 3000) {
  $socket = [Net.WebSockets.ClientWebSocket]::new()
  $cancel = [Threading.CancellationTokenSource]::new($timeoutMs)
  try {
    $socket.ConnectAsync([Uri]$webSocketUrl, $cancel.Token).GetAwaiter().GetResult()
    $message = @{ id = 1; method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    $bytes = $UTF8.GetBytes($message)
    $socket.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text,
      $true, $cancel.Token).GetAwaiter().GetResult()
    $buffer = New-Object byte[] 65536
    $received = [IO.MemoryStream]::new()
    while ($true) {
      $received.SetLength(0)
      do {
        $result = $socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), $cancel.Token).GetAwaiter().GetResult()
        $received.Write($buffer, 0, $result.Count)
      } while (-not $result.EndOfMessage)
      $reply = $UTF8.GetString($received.ToArray()) | ConvertFrom-Json
      if ($reply.id -eq 1) { return $reply }
    }
  } catch {
    return 'timeout'
  } finally {
    $socket.Dispose()
    $cancel.Dispose()
  }
}

# Whether the browser answers on the debugging port.
function browser_running {
  return $null -ne (cdp_http '/json/version')
}

# Finds the feed's tab: first a tab already on the feed, then any tab on the
# same site. So a YouTube video you're watching isn't taken over while a
# Shorts tab is open. Returns the tab (id, url, webSocketDebuggerUrl) or $null.
function find_tab([string]$url) {
  $tabs = cdp_http '/json/list'
  if ($null -eq $tabs) { return $null }
  $pages = @($tabs | Where-Object { $_.type -eq 'page' })
  $siteHost = url_host $url
  foreach ($tab in $pages) {
    if ($tab.url.StartsWith($url)) { return $tab }
  }
  foreach ($tab in $pages) {
    if ($tab.url.Contains("://$siteHost/") -or $tab.url.Contains(".$siteHost/")) { return $tab }
  }
  return $null
}

# Starts the browser with the debugging port and doomscroller's profile,
# opening a URL, and waits up to 15 s for it to answer. Returns whether it did.
function start_browser([string]$url) {
  $exe = browser_exe $BROWSER
  if (-not $exe) {
    log "browser not found: $BROWSER (doomscroller config set browser <path to .exe>)"
    return $false
  }
  [void][IO.Directory]::CreateDirectory($PROFILE_DIR)
  # Start-Process doesn't quote arguments, so quote the ones that may contain spaces.
  Start-Process -FilePath $exe -ArgumentList @(
    "--remote-debugging-port=$DEBUG_PORT", "--user-data-dir=`"$PROFILE_DIR`"",
    '--no-first-run', '--no-default-browser-check', "`"$url`"")
  $clock = [Diagnostics.Stopwatch]::StartNew()
  while ($clock.Elapsed.TotalSeconds -lt 15) {
    if (browser_running) { return $true }
    Start-Sleep -Milliseconds 500
  }
  log "the browser doesn't answer on port $DEBUG_PORT. If it was already open with doomscroller's profile but without that port, close it and try again"
  return $false
}

# Returns the id of the browser's main process, the one started with our
# debugging port, or $null. Its windows are the browser's windows.
function browser_pid {
  if ($script:BROWSER_PID -and (Get-Process -Id $script:BROWSER_PID -ErrorAction SilentlyContinue)) {
    return $script:BROWSER_PID
  }
  $script:BROWSER_PID = $null
  $filter = "CommandLine LIKE '%--remote-debugging-port=$DEBUG_PORT%' AND NOT CommandLine LIKE '%--type=%'"
  $process = Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($process) { $script:BROWSER_PID = [int]$process.ProcessId }
  return $script:BROWSER_PID
}

# Brings the browser window to the front.
function focus_browser {
  $id = browser_pid
  if (-not $id -or -not (focus_app $id)) { log "can't bring the browser to the front" }
}

# Shows the page: reuses a tab already open on the same site, or opens a new
# one. Starts the browser if it isn't running with the debugging port.
function show_page([string]$url) {
  $siteHost = url_host $url
  if (-not (browser_running)) {
    if (start_browser $url) {
      log "started the browser on $siteHost"
      focus_browser
    }
    return
  }
  $tab = find_tab $url
  if ($tab) {
    # Don't reload a tab already on the feed, so the current video keeps playing.
    if (-not $tab.url.StartsWith($url)) {
      [void](cdp_call $tab.webSocketDebuggerUrl 'Page.navigate' @{ url = $url })
    }
    [void](cdp_http "/json/activate/$($tab.id)")
    log "switched to the $siteHost tab"
  } else {
    $browserSocket = (cdp_http '/json/version').webSocketDebuggerUrl
    $reply = cdp_call $browserSocket 'Target.createTarget' @{ url = $url }
    if ($reply -is [string] -or $reply.error) { log "can't open a tab: $reply" } else {
      [void](cdp_http "/json/activate/$($reply.result.targetId)")
    }
  }
  focus_browser
}

# Runs JavaScript in the feed's tab and returns the result as a string, or
# "no tab", or "timeout" (the page is busy loading or navigating; callers
# retry). With $gesture, Chrome counts the script as user interaction, which
# lets a video play with sound. Usage: run_tab_js <url> <javascript> [gesture]
function run_tab_js([string]$url, [string]$js, [switch]$gesture) {
  $tab = find_tab $url
  if (-not $tab) { return 'no tab' }
  $reply = cdp_call $tab.webSocketDebuggerUrl 'Runtime.evaluate' @{
    expression = $js; returnByValue = $true; userGesture = [bool]$gesture
  }
  if ($reply -is [string]) { return $reply }
  if ($reply.error) {
    # The page is between documents: no context to run in yet.
    if ($reply.error.message -match 'context') { return 'timeout' }
    return "error: $($reply.error.message)"
  }
  if ($reply.result.exceptionDetails) {
    $details = $reply.result.exceptionDetails
    $text = if ($details.exception.description) { $details.exception.description } else { $details.text }
    return "error: $text"
  }
  return [string]$reply.result.result.value
}

# Presses a key inside the feed's tab, by its DOM key and code (" ", "Space").
# It's sent as a raw key down and up with no text, so it types nothing into a
# focused text field. The browser doesn't need to be in front.
function press_tab_key([string]$url, [string]$key, [string]$code, [int]$keyCode) {
  $tab = find_tab $url
  if (-not $tab) { return $false }
  foreach ($type in 'rawKeyDown', 'keyUp') {
    $reply = cdp_call $tab.webSocketDebuggerUrl 'Input.dispatchKeyEvent' @{
      type = $type; key = $key; code = $code; windowsVirtualKeyCode = $keyCode
    }
    if ($reply -is [string] -or $reply.error) { return $false }
  }
  return $true
}
