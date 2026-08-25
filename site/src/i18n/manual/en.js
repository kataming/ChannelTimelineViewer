// User manual (English). Wording follows the app's own strings (Localization/strings.json).
// Items marked only: 'ios' / 'android' apply to that platform alone.
export default {
  title: 'User manual',
  description: 'How to use Channel Timeline Viewer: adding a channel, sorting, watched tracking, resume, notes, and Pro — for both iPhone and Android.',
  lede: 'Channel Timeline Viewer lists a channel’s uploads oldest-first so you can work through them while keeping track of how far you got. This page walks through every feature.',
  platformNote: 'The iPhone and Android versions work almost identically. Only the steps that differ are marked “iPhone” or “Android”. Anything without a mark applies to both.',
  badges: { ios: 'iPhone', android: 'Android' },
  tocTitle: 'Contents',
  sections: [
    {
      id: 'install',
      title: '1. Getting the app',
      body: 'The app is free. There is no account to create and no sign-in.',
      steps: [
        { title: 'Install from the App Store', body: 'iOS 17 or later is required. Search the App Store for “Channel Timeline Viewer”, or use the App Store button on this site.', only: 'ios' },
        { title: 'Coming to Google Play', body: 'The Android version has been submitted to Google Play and is waiting for review. A link will appear on this site as soon as it is published.', only: 'android' },
        { title: 'No YouTube account needed', body: 'You never sign in. The app only reads public information about videos through YouTube’s official API.' },
      ],
    },
    {
      id: 'add',
      title: '2. Adding a channel',
      body: 'There are two ways to add a channel. Both end up in the same place.',
      steps: [
        { title: 'Paste a URL', body: 'On the first screen, put a channel URL (for example youtube.com/@handle or youtube.com/channel/UC…) into the “Channel URL” field and tap “Get videos”. A video URL works too — the app finds the channel that published it.' },
        { title: 'Large channels take a while', body: 'The first load fetches every upload, so channels with many videos take longer. Just wait while “Loading videos...” is showing.' },
        { title: 'Share from YouTube', body: 'Tap the share button in the YouTube app or Safari and choose “Open in Channel Timeline”. iOS does not let a share sheet launch an app directly, so allow notifications and tap the notification that appears right after sharing. If you prefer not to, open the app and tap “Open shared link”.', only: 'ios' },
        { title: 'Put it at the front of the share sheet', body: 'iOS decides the order of the share sheet, so the app cannot set it. Scroll the row of apps to the far right → “More” → “Edit” → tap “+” next to “Open in Channel Timeline” → drag it to the top → “Done”.', only: 'ios' },
        { title: 'Share from YouTube', body: 'Tap the share button in the YouTube app or your browser and choose “Open in Channel Timeline”. The channel’s video list opens straight away — no notification permission needed.', only: 'android' },
        { title: 'Channels stay available', body: 'Channels you have opened appear under “Recent channels”. Next time they open immediately, and new uploads are checked in the background.' },
      ],
    },
    {
      id: 'list',
      title: '3. Using the video list',
      body: 'Progress sits at the top of the list. This is the heart of keeping your place.',
      steps: [
        { title: 'Progress and “up next”', body: 'The top row shows “Progress” with the watched count, the total, and a percentage. The row below it is the next video: “Continue: #N” if you stopped partway through one, otherwise “Up next: #N”. Tap it to start there.' },
        { title: 'Sorting', body: 'Use the icon at the top right → “Sort” → “Oldest first” or “Newest first”. Oldest first is the default.' },
        { title: 'Filtering', body: 'In the same menu, “Show” lets you pick “All”, “Unwatched only”, or “Watched only”. When filtered, the list shows “N shown / N total”.' },
        { title: 'Getting new uploads', body: 'The same menu has “Check for new videos”, which fetches only what is new. If something looks wrong, “Reload everything” fetches the list again from scratch.' },
        { title: 'Marking watched or skipped', body: 'Each row lets you switch between “Watched”, “Mark unwatched”, “Skip”, and “Unskip”. Skipped videos are passed over during autoplay, but you can still open them with the manual “Next” button.' },
      ],
    },
    {
      id: 'play',
      title: '4. Playing videos',
      body: 'Playback uses YouTube’s official embedded player. The controls sit below it.',
      steps: [
        { title: 'Autoplay (off by default)', body: 'Use the toggle on the player screen. Turned on, it reads “Autoplay on: continue to the next video” and plays only the next video in the list you have open. It never sends you to related videos or another channel. Left off, playback stops at the end and a “Play next video” button appears.' },
        { title: 'Play unwatched only', body: 'The toggle below autoplay. Turned on, videos you have already watched are passed over as well, so only unwatched ones play.' },
        { title: 'Repeat', body: 'The badge at the top right cycles through “Off → One → All”. “One” repeats the same video regardless of the autoplay setting. “All” returns to the first video after the last one (when autoplay is on).' },
        { title: 'Moving around', body: 'Five buttons: “First”, “Previous”, “Undo”, “Next”, “Last”. “Undo” reverses your last jump and returns you to the video and position you were at — useful when you tap the wrong button.' },
        { title: 'Resuming', body: 'Reopen a video you stopped partway through and it continues from the exact second, with “Resuming from (0:00)” shown. To start over, tap “Restart” next to it.' },
      ],
    },
    {
      id: 'tools',
      title: '5. Notes and playback settings',
      steps: [
        { title: 'Writing notes', body: 'Below the player there is a “Notes (for series and study)” field. It saves automatically as you type. Tap elsewhere or “Done” to finish. Notes are kept per video.' },
        { title: 'Speed and captions', body: 'The slider icon at the top right opens the playback settings, where you can change speed and captions. Captions start off by default. The caption list is only prepared once playback begins, so if it is empty, start the video and open the sheet again.' },
        { title: 'About video quality', body: 'YouTube adjusts quality automatically to match your connection, and the official player does not let the app choose it. To pick it yourself, start playback, then use the full-screen button at the bottom right of the player → gear → Quality.' },
        { title: 'Open in YouTube', body: '“Open in YouTube” opens the video in the YouTube app or website. Use it for videos whose owner has blocked playback outside YouTube.' },
      ],
    },
    {
      id: 'fullscreen',
      title: '6. Watching full screen',
      steps: [
        { title: 'Going full screen', body: 'Tap the full-screen button at the bottom right of the player. Turn the phone sideways to fill the screen.', only: 'ios' },
        { title: 'Staying full screen between videos', body: 'From version 1.1, with autoplay on, the next video continues in full screen. To keep it that way the app switches about 0.5 seconds before the current video ends.', only: 'ios' },
        { title: 'Not supported yet', body: 'The Android version does not support full screen yet. It is planned for a future update.', only: 'android' },
      ],
    },
    {
      id: 'pro',
      title: '7. Saved channels and Pro',
      body: 'The app is free and saves one channel. Inside that channel nothing is held back.',
      steps: [
        { title: 'What the free version does', body: 'Oldest- or newest-first sorting, watched tracking, resume, the jump buttons, notes, progress, and playback in the official player — all without limits.' },
        { title: 'When you add a second channel', body: 'A confirmation appears. Choosing “Replace” deletes the watched history, progress, and notes of the channel you had saved, and that cannot be undone. To keep both, consider Pro.' },
        { title: 'Pro (one-time purchase)', body: 'Not a subscription — you buy it once. Save several channels and keep the watched history, progress, and notes of each. The price is whatever the store shows.' },
        { title: 'Restoring a purchase', body: 'After reinstalling or switching devices, open the Pro screen and tap “Restore purchase”. As long as you are signed in with the same Apple Account, it comes back. It is a one-time purchase, so you are never charged twice.', only: 'ios' },
        { title: 'Restoring a purchase', body: 'After reinstalling or switching devices, open the Pro screen and tap “Restore purchase”. As long as you are signed in with the same Google account, it comes back. It is a one-time purchase, so you are never charged twice.', only: 'android' },
        { title: 'Removing a channel', body: 'Swipe a row in “Recent channels” to the left to delete it. Deleting also removes that channel’s watched history, progress, and notes.', only: 'ios' },
        { title: 'Removing a channel', body: 'Use the trash button in “Recent channels”. Removing it also deletes that channel’s watched history, progress, and notes.', only: 'android' },
      ],
    },
    {
      id: 'trouble',
      title: '8. If something goes wrong',
      steps: [
        { title: 'The channel URL is not accepted', body: 'Use the URL of the channel page (youtube.com/@handle, youtube.com/channel/UC…). A video URL works too.' },
        { title: 'The list stops partway or shows an error', body: 'Very large channels take a while on the first load. If the error mentions quota, try again later — the YouTube API has a daily limit.' },
        { title: 'A video will not play', body: 'Some videos are blocked from playing outside YouTube by their owner. Use “Open in YouTube” for those.' },
        { title: 'Sharing does not open the app', body: 'iOS does not allow a share sheet to launch an app directly. Allow notifications and tap the notification that appears right after sharing, or open the app and use “Open shared link”.', only: 'ios' },
        { title: 'Volume differs between videos', body: 'That comes from the recording level of the videos themselves and the app cannot even it out. YouTube’s “Stable Volume” is not available in embedded players, so use “Open in YouTube” for videos where it bothers you.' },
        { title: 'My progress disappeared', body: 'Watched history, progress, and notes are stored on your device only. They are erased when you delete the app, or when you delete or replace a channel, and cannot be recovered.' },
      ],
    },
    {
      id: 'limits',
      title: '9. What the app deliberately does not do',
      body: 'To respect YouTube’s terms of service, the app never does the following.',
      steps: [
        { title: 'It does not download or save videos offline', body: 'There is no way to store a video on your device.' },
        { title: 'It does not use a player of its own', body: 'Playback always happens in YouTube’s official embedded player.' },
        { title: 'It does not block ads or bypass restrictions', body: 'Ads are not hidden and playback restrictions are not circumvented.' },
        { title: 'It does not play in the background', body: 'Playback stops when you leave the app. While a video plays, the screen simply stays awake.' },
        { title: 'Nothing leaves your device', body: 'Watched history, progress, notes, and playback positions are stored on your device only and are never sent to our servers.' },
      ],
    },
  ],
};
