// Runs in the feed's tab. Says "playing" if the video on screen is playing,
// "paused" if it isn't, or "no video".
//
// Pause keys toggle, so the Windows watcher asks this first and presses the
// key only for a playing video. A video you had paused stays paused.
(() => {
  const visible = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.top >= 0 && r.top < innerHeight; };
  const video = [...document.querySelectorAll("video")].find(visible);
  if (!video) return "no video";
  return video.paused ? "paused" : "playing";
})()
