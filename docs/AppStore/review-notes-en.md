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

AUTOPLAY (ON BY DEFAULT, CAN BE TURNED OFF AT ANY TIME)
- Autoplay is on by default (changed in 1.2.0; it was off by default before). When a video ends, playback continues to the next video in the channel list the user has open.
- It can be switched off at any time on the player screen. When off, playback stops at the end of a video and a "Play next video" button is shown.
- Users who have already chosen a setting keep it: the value is stored on the device and is never overwritten by the change of default.
- The player screen always shows a visible toggle, so the setting can be changed at any moment
  (the user is never asked only after a video has ended).
- Even when it is on, it advances only to the next video of the channel list the user opened.
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
  remote push notifications are used. Allowing notifications is optional; without them the user can
  add a channel with "Add via Share in YouTube" (below). The extensions never write to the clipboard.

ADD VIA SHARE IN YOUTUBE (CLIPBOARD READ)
- From the in-app guide the user taps "Open YouTube", then in YouTube taps Share -> Copy link and
  returns with the "< Channel Timeline Viewer" back link at the top left. The app then reads the
  copied YouTube link and opens that channel.
- The clipboard is read only when the user comes back from YouTube after starting from this guide, and
  only once per copy, after checking without reading the contents (changeCount / detectPatterns) that
  something new and URL-like was copied. iOS shows its paste permission prompt before the read. The
  content is used only to recognize a YouTube URL and show the channel; it is never sent anywhere,
  and anything that is not a YouTube link is ignored.

IN-APP PURCHASE AND ADS
- One non-consumable in-app purchase, "Pro" (pro_unlock), lets you save more than one channel.
  There are no subscriptions. Inside the one free channel, every feature works without limits.
- The free version shows Google AdMob ads: an anchored banner at the bottom of the video list, and one
  300x250 ad below the saved-channel list on the first screen. Ads are never shown on the player screen
  and never overlap the YouTube player or its controls. Ads are labeled as ads.
- Pro users see no ads at all: the ad SDK is not initialized and no ad requests are made.
- Where required (EEA, UK, Switzerland) consent is collected with Google's User Messaging Platform
  before any ad request; users can review it later from "Ad privacy settings" on the "i" screen.
- The app does not use App Tracking Transparency and does not access the IDFA.

HOW TO TEST
1. Launch the app. On first launch a list of popular videos appears (or tap "Pick from popular
   videos" on the first screen). Tap any video — all uploads of its channel are listed oldest first.
   No YouTube app or account is needed.
2. Tap a video — it plays in the official embedded player. Use the navigation buttons to move.
3. Tap the "i" button on the first screen to see the in-app notices (not the official YouTube app, etc.).
4. Optional ("Add via Share in YouTube", needs the YouTube app): tap it on the first screen, tap
   "Open YouTube", open any video, tap Share -> Copy link, return with "< Channel Timeline Viewer" at
   the top left, and allow the paste prompt. The channel of the copied video opens.
5. Optional: share a YouTube channel or video from Safari, choose this app and allow notifications;
   tap the notification that appears to open the channel.

The submitted build contains a valid YouTube Data API v3 key, so no test account is required.

TRADEMARK
YouTube is a trademark of Google LLC. This app is an unofficial app that uses the official API and the
official embedded player, and does not claim endorsement by or affiliation with Google or YouTube.
```
