# App Review Notes (English — pasted into App Store Connect)

このファイルの「本文」ブロックが、そのまま App Store Connect の「App Review Information → Notes」に入ります
（`scripts/asc_appstore_metadata.py --mode review` が読み取ります）。
**App Store の上限は 4,000 文字**。超えると登録できない（2026-10-06 に 5,662 文字で失敗して書き直した）。
日本語の詳細版は [`review-notes.md`](review-notes.md) です。内容を変えたときは両方を合わせてください。

## 本文

```
WHAT THIS APP IS
A viewing companion that lists a YouTube channel's uploads oldest first, so a viewer can work through an
archive or a long series from the beginning and track progress. It is not a replacement for the YouTube
app and claims no affiliation with YouTube or Google.

DATA AND PLAYBACK
- Video lists come only from the official YouTube Data API v3. No scraping.
- Playback uses the official YouTube IFrame Player in a WKWebView. No downloads, no custom player, no ad blocking.
- Resume stores only the playback position in seconds reported by the official player. No video data is stored.

AUTOPLAY (ON BY DEFAULT, CAN BE TURNED OFF)
- When a video ends, playback continues to the next video of the channel list the user opened. It never goes
  to related or recommended videos (rel=0). A toggle is always visible on the player screen; when off, playback
  stops and a "Play next video" button appears. A user's own choice is kept and never overwritten.
- No background playback (no UIBackgroundModes, AVAudioSession or AVPlayer). The idle timer is disabled only
  while a video plays.

SHARE EXTENSIONS
- Two share extensions only extract a YouTube URL and hand it to the app via channeltimelineviewer://share?url=...
  No networking. They never write to the clipboard.
- iOS does not let a share extension open its app, so if the user allowed notifications, one local notification
  is posted right after sharing; tapping it opens the channel. No promotional notifications, no remote push.

ADD VIA SHARE IN YOUTUBE (CLIPBOARD READ)
- From the in-app guide the user opens YouTube, taps Share -> Copy link and returns with "< Channel Timeline
  Viewer". The app then reads the copied YouTube link and opens that channel.
- The clipboard is read only on return from this guide, once per copy, after checking without reading the
  content (changeCount / detectPatterns) that something URL-like was newly copied. iOS shows its paste prompt.
  The link is used only to show the channel, never sent anywhere; non-YouTube content is ignored.

IN-APP PURCHASE AND ADS
- One non-consumable IAP, "Pro" (pro_unlock), allows saving more than one channel. No subscriptions.
  Within the one free channel every feature works.
- The free version shows Google AdMob ads: a banner at the bottom of the video list and one 300x250 ad below the
  saved channel on the first screen. Never on the player screen, never over the player. Ads are labeled.
- Pro: no ads, the ad SDK is not initialized. Consent (EEA/UK/CH) via Google UMP before any ad request; it can be
  reviewed from "Ad privacy settings" on the "i" screen. No ATT, no IDFA.

HOW TO TEST
1. Launch the app. Popular videos appear on first launch (or tap "Pick from popular videos"). Tap one - all
   uploads of its channel are listed oldest first. No YouTube app or account needed.
2. Tap a video - it plays in the official embedded player.
3. Tap "i" on the first screen to see the in-app notices.
4. Optional (needs the YouTube app): "Add via Share in YouTube" -> "Open YouTube" -> any video -> Share ->
   Copy link -> "< Channel Timeline Viewer" at the top left -> allow paste. The channel opens.
5. Optional: share a YouTube page from Safari to this app, allow notifications, tap the notification.

The build contains a valid YouTube Data API v3 key; no test account is required.

TRADEMARK
YouTube is a trademark of Google LLC. This unofficial app uses the official API and embedded player and does
not claim endorsement by or affiliation with Google or YouTube.
```
