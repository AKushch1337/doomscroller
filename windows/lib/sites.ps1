# What differs between the feeds. To add a site, add a case here and
# teach validate_setting (settings.ps1) and usage (cli.ps1) about it.

# Sets SITE, URL (the feed), PAUSE_KEY (space or play, see press_pause_key)
# and NEXT_BUTTON (CSS selector autoscroll clicks) for a site.
function use_site([string]$site) {
  switch ($site) {
    'reels' {
      $script:URL = 'https://www.instagram.com/reels/'
      $script:PAUSE_KEY = 'play'
      $script:NEXT_BUTTON = '[aria-label="Navigate to next reel"]'
    }
    # YouTube's labels follow the account language, so go by id instead.
    'shorts' {
      $script:URL = 'https://www.youtube.com/shorts'
      $script:PAUSE_KEY = 'space'
      $script:NEXT_BUTTON = '#navigation-button-down button'
    }
    default { fail "unknown site: $site (use reels or shorts)" }
  }
  $script:SITE = $site
}
