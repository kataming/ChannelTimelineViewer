# App Review Notes (English — pasted into App Store Connect)

このファイルの「本文」ブロックが、そのまま App Store Connect の「App Review Information → Notes」に入ります
（`scripts/asc_appstore_metadata.py --mode review` が読み取ります）。
日本語の詳細版は [`review-notes.md`](review-notes.md) です。内容を変えたときは両方を合わせてください。

## 本文

```
WHAT THIS APP IS
Channel Timeline Viewer is a viewing companion that lists a YouTube channel's uploads in
chronological order (oldest first) so a viewer can work through an archive, a lecture series
or a long-running series from the beginning and keep track of how far they got.
It is not a replacement for the YouTube app and does not claim any affiliation with YouTube or Google.

HOW DATA IS OBTAINED
- Video lists come only from the official YouTube Data API v3 (videoId, title, description,
  publish date, thumbnail URL). There is no scraping of any kind.

HOW VIDEOS ARE PLAYED
- Playback uses the official YouTube IFrame Player embedded in a WKWebView.
- The app never downloads video files, never uses a custom player, and never blocks or skips ads.

AUTOPLAY (OPTIONAL, OFF BY DEFAULT)
- Autoplay is off by default. When a video ends the app stops and shows a "Play next video" button.
- The player screen always shows a visible toggle. Only if the user turns it on does playback continue.
- Even then it advances only to the next video of the channel list the user opened.
  It never navigates to related or recommended videos (the embed uses rel=0).
- No background playback: closing the app or locking the screen stops playback (no UIBackgroundModes,
  no AVAudioSession, no AVPlayer). While a video is playing the app only disables the idle timer so the
  screen does not dim; this is restored on pause and when leaving the player screen.

RESUME
- Only the playback position in seconds, as reported by the official player, is stored on the device
  and passed back as startSeconds. No video data is stored.

SHARE EXTENSIONS
- Two extensions (share sheet app row and share sheet action list) contain the same code. They only
  extract a YouTube URL from the shared item and open the containing app via the custom URL scheme
  channeltimelineviewer://share?url=... . They perform no networking at all.
- iOS does not allow a share extension to launch its containing app directly, so when the user has
  allowed notifications the app posts a single local notification right after sharing that opens the
  channel when tapped. No promotional, marketing or re-engagement notifications are ever sent, and no
  remote push notifications are used. Allowing notifications is optional; a clipboard fallback exists.

NO PURCHASES, NO ADS
- No in-app purchases, no subscriptions, no StoreKit code, and no advertising SDKs.
- Every user gets exactly the same features; there is no free/paid feature split.

HOW TO TEST
1. Launch the app and enter a public channel URL, for example https://www.youtube.com/@3blue1brown
2. Tap "Get videos" — the uploads are listed oldest first.
3. Tap a video — it plays in the official embedded player. Use the navigation buttons to move.
4. Tap the "i" button on the first screen to see the in-app notices (not the official YouTube app, etc.).
5. Optional: share a YouTube channel or video from Safari and choose this app.

The submitted build contains a valid YouTube Data API v3 key, so no test account is required.

TRADEMARK
YouTube is a trademark of Google LLC. This app is an unofficial app that uses the official API and the
official embedded player, and does not claim endorsement by or affiliation with Google or YouTube.
```
