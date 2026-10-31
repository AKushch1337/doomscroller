# The video in the feed: pausing it, turning Reels sound on, and autoscroll.
# The page scripts in lib/page/ are the same ones the macOS version runs.

# Presses the site's pause key: space inside the tab, or the media
# play/pause key, which Windows hands to the browser that's playing.
function press_pause_key([string]$url) {
  switch ($PAUSE_KEY) {
    'space' { return press_tab_key $url ' ' 'Space' 32 }
    'play'  { press_play_pause_key; return $true }
  }
  return $false
}

# Pauses the video, but only if it's playing: the keys toggle, so a video
# you had paused yourself would start again.
function pause_video([string]$url) {
  $state = run_tab_js $url (page_js 'video-state')
  if ($state -ne 'playing') { return }
  if (press_pause_key $url) {
    log "paused video ($PAUSE_KEY key)"
    Start-Sleep -Milliseconds 200
  } else {
    log "can't pause the video"
  }
}

# Turns the sound on in a freshly loaded Reels page. The browser allows sound
# only after the user has interacted with the page. On macOS that takes a
# real F13 key press; here the scripts run as a user gesture through CDP,
# which the browser counts as interaction, so no key and no focus is needed.
function unmute_reels([string]$url) {
  if ((url_host $url) -ne 'instagram.com') { return }
  # Wait up to 15 s for the page to load and show a reel.
  $state = ''
  $clock = [Diagnostics.Stopwatch]::StartNew()
  while ($clock.Elapsed.TotalSeconds -lt 15) {
    $state = run_tab_js $url (page_js 'reels-check')
    if ($state -ne 'loading' -and $state -ne 'timeout') { break }
    Start-Sleep -Milliseconds 500
  }
  switch ($state) {
    'muted' { }
    { $_ -in 'skip', 'loading', 'timeout', 'no tab' } { return }
    default { log "can't run JavaScript in the browser: $state"; return }
  }
  $result = run_tab_js $url (page_js 'reels-unmute') -gesture
  # Make sure the reel plays: a second later Instagram may have paused it.
  $playing = ''
  for ($tries = 0; $tries -lt 3 -and $playing -ne 'playing'; $tries++) {
    Start-Sleep -Seconds 1
    $playing = run_tab_js $url (page_js 'reels-play') -gesture
  }
  log "turned on Reels sound ($result, video $playing)"
}

# Installs autoscroll (lib/page/autoscroll.js) in the feed's tab. Right after
# opening or redirecting the tab, the old page may still be there or the new
# one may still load, so it retries for up to 15 s.
function start_autoscroll([string]$url) {
  # autoscroll.js is a function: append the call. JSON strings are valid JS strings.
  $js = (page_js 'autoscroll').TrimEnd() + '(' + (ConvertTo-Json $url) + ', ' + (ConvertTo-Json $NEXT_BUTTON) + ')'
  $clock = [Diagnostics.Stopwatch]::StartNew()
  while ($clock.Elapsed.TotalSeconds -lt 15) {
    $state = run_tab_js $url $js
    switch ($state) {
      'on' { log 'autoscroll on'; return }
      { $_ -in 'already on', 'no tab' } { return }
      { $_ -in 'timeout', 'wrong page' } { Start-Sleep -Milliseconds 500 }
      default { log "can't start autoscroll: $state"; return }
    }
  }
}
