// サイトの文言（7言語）。ここが唯一の原本で、各ページはこの辞書だけを見る。
// アプリ内文言（Localization/strings.json）とは別物だが、言い回しは揃えている。

export const languages = [
  { code: 'en', slug: 'en', label: 'English', htmlLang: 'en', ogLocale: 'en_US' },
  { code: 'ja', slug: 'ja', label: '日本語', htmlLang: 'ja', ogLocale: 'ja_JP' },
  { code: 'zh', slug: 'zh', label: '简体中文', htmlLang: 'zh-Hans', ogLocale: 'zh_CN' },
  { code: 'es', slug: 'es', label: 'Español', htmlLang: 'es', ogLocale: 'es_ES' },
  { code: 'de', slug: 'de', label: 'Deutsch', htmlLang: 'de', ogLocale: 'de_DE' },
  { code: 'fr', slug: 'fr', label: 'Français', htmlLang: 'fr', ogLocale: 'fr_FR' },
  { code: 'ko', slug: 'ko', label: '한국어', htmlLang: 'ko', ogLocale: 'ko_KR' },
];

const en = {
  meta: {
    title: 'Channel Timeline Viewer — watch a YouTube channel oldest-first',
    description:
      'An iOS viewing companion that lists a channel’s uploads oldest-first, tracks how far you have watched, and resumes exactly where you stopped. Playback uses YouTube’s official embedded player.',
  },
  nav: { features: 'Features', how: 'How it works', faq: 'FAQ', support: 'Support', privacy: 'Privacy' },
  hero: {
    badge: 'iOS 17+ · 7 languages',
    title: 'Watch a channel from its very first video.',
    subtitle:
      'Channel Timeline Viewer sorts a channel’s uploads by publication date — oldest first — and keeps track of how far you got. Ideal for archives, lecture series, and long-running shows.',
    cta: 'Download on the App Store',
    ctaPending: 'Coming soon to the App Store',
    ctaNote: 'No ads. No subscriptions. No in-app purchases.',
  },
  problem: {
    title: 'YouTube shows newest first. Series start at the beginning.',
    body:
      'Catching up on a channel with hundreds of uploads means scrolling to the bottom, remembering which video you stopped at, and finding it again tomorrow. Channel Timeline Viewer turns that into a list you can simply work down.',
  },
  featuresTitle: 'What it does',
  features: [
    { title: 'Oldest-first order', body: 'Enter a channel URL and every upload is listed by publication date. Flip to newest-first whenever you want.' },
    { title: 'Progress you can see', body: 'Watched count, percentage, and a progress bar for each channel — like a course you are working through.' },
    { title: 'Resume to the second', body: 'Stop in the middle of a video and it picks up from the exact second next time.' },
    { title: 'Watched and skipped', body: 'Mark videos watched or skipped, filter the list, and play only what you have not seen yet.' },
    { title: 'Repeat and autoplay', body: 'Repeat one video or the whole list. Autoplay to the next video is optional and off by default.' },
    { title: 'Share from YouTube', body: 'Share a channel or a video from the YouTube app or Safari and open its timeline straight away.' },
    { title: 'Notes per video', body: 'Keep a short note on each video — useful for lectures, tutorials, and long series.' },
    { title: 'Instant reopen', body: 'Channels you have opened before appear immediately from a saved list, then check for new uploads in the background.' },
  ],
  howTitle: 'Three steps',
  how: [
    { title: 'Paste or share a channel URL', body: 'Type it in, or use the share sheet in the YouTube app or Safari.' },
    { title: 'Start at video #1', body: 'The uploads appear oldest-first. Tap “Up next” to jump back in at any time.' },
    { title: 'Keep your place', body: 'Watched marks, progress, and playback positions stay on your device.' },
  ],
  faqTitle: 'Questions',
  faq: [
    { q: 'Is this the official YouTube app?', a: 'No. It is an independent viewing companion that uses YouTube’s official API and official embedded player. It is not endorsed by or affiliated with YouTube or Google.' },
    { q: 'Can it download videos?', a: 'No. There is no download or offline saving of any kind, and no ad blocking.' },
    { q: 'Does it play in the background?', a: 'No. Playback stops when you leave the app. While a video is playing the screen simply stays awake so it does not dim on you.' },
    { q: 'Do I need to sign in?', a: 'No account or sign-in. The app only reads public channel and video information through the YouTube Data API v3.' },
    { q: 'Where is my progress stored?', a: 'On your device only. Watch history, progress, notes, and playback positions never leave the phone, and they are deleted with the app.' },
    { q: 'Are there ads or subscriptions?', a: 'None. No ads, no subscriptions, no in-app purchases, and no difference in features between users.' },
  ],
  notesTitle: 'What it deliberately does not do',
  notes: [
    'No downloading or offline saving',
    'No custom player — playback is YouTube’s official embedded player',
    'No ad blocking or bypassing of playback restrictions',
    'No scraping — the video list comes from the YouTube Data API v3',
    'No background playback',
  ],
  footer: {
    tagline: 'A viewing companion for watching channels in order.',
    trademark: 'YouTube is a trademark of Google LLC. This app is an unofficial app that uses the official API and player; it is not endorsed by or affiliated with Google or YouTube.',
    language: 'Language',
    source: 'Source code',
  },
  support: {
    title: 'Support',
    description: 'How to get help with Channel Timeline Viewer.',
    intro: 'If something does not work as expected, get in touch — include your iOS version, the app version, and what you were doing.',
    contactTitle: 'Contact',
    contactBody: 'Email:',
    faqTitle: 'Before you write',
    faq: [
      { q: 'The channel URL is not accepted', a: 'Use the channel page URL (for example youtube.com/@handle or youtube.com/channel/UC…). A video URL works too — the app finds the channel that published it.' },
      { q: 'The list stops partway or shows an error', a: 'Very large channels take a while on first load. If the error mentions quota, try again later — the app uses the YouTube Data API, which has a daily limit.' },
      { q: 'A video will not play', a: 'Some videos are restricted from playing outside YouTube by their owner. Use “Open in YouTube” for those.' },
      { q: 'Sharing from YouTube does not open the app', a: 'iOS does not allow a share sheet to launch an app directly. Allow notifications and tap the notification that appears right after sharing, or open the app and use “Open shared link”.' },
    ],
    responseTitle: 'Response time',
    responseBody: 'Usually within a few business days.',
  },
  privacy: {
    title: 'Privacy Policy',
    description: 'What Channel Timeline Viewer stores and what it does not.',
    updated: 'Last updated: 18 August 2026',
    sections: [
      { title: '1. Summary', body: ['Channel Timeline Viewer keeps your data on your device. There is no account, no analytics in the app, and no server operated by us that receives your information.'] },
      { title: '2. What is stored on your device', body: [
        'The following are saved locally (iOS UserDefaults / app cache) and never sent to us:',
        '• Identifiers of videos you marked as watched or skipped, with timestamps',
        '• Per-channel progress (total count, watched count, last opened video)',
        '• Recently used channels (channel ID, name, thumbnail URL, last used time)',
        '• Notes you write for a video',
        '• Playback position (in seconds) for each video',
        '• A cached copy of the video list of channels you opened',
        'Deleting the app removes all of it.'] },
      { title: '3. YouTube and Google', body: [
        'The app uses two official YouTube (Google LLC) services:',
        '• YouTube Data API v3 — to fetch the public list of uploads for the channel you enter.',
        '• YouTube IFrame Player — the official embedded player used for playback. During playback YouTube and Google may collect and process information under their own policies.',
        'The app does not download videos, block ads, scrape, play in the background, or use a custom player.',
        'Google Privacy Policy: https://policies.google.com/privacy',
        'YouTube Terms of Service: https://www.youtube.com/t/terms'] },
      { title: '4. The relay page used for playback', body: [
        'To display the official embedded player correctly, the player screen loads a small static page we publish on GitHub Pages (https://kataming.github.io/ChannelTimelineViewer/player.html) and embeds the official player inside it. That page only displays the player; it contains no analytics or tracking. As with any web request, GitHub may log standard connection information (such as IP address).'] },
      { title: '5. Sharing from other apps', body: [
        'The share extension receives only the URL (or text containing a URL) you share. It is parsed on the device and used to look up the channel through the official API. It is not sent anywhere else. Non-YouTube URLs are ignored.'] },
      { title: '6. Notifications', body: [
        'iOS does not allow a share sheet to launch an app directly. If — and only if — you allow notifications, the app posts one local notification right after you share, so you can tap it to open the channel. It contains only the shared YouTube URL and is handled on the device. No promotional, re-engagement, or server push notifications are ever sent.'] },
      { title: '7. Tracking', body: ['The app does not use the advertising identifier (IDFA) and does not use App Tracking Transparency, because it does not track you.'] },
      { title: '8. Children', body: ['The app does not knowingly collect personal information from children.'] },
      { title: '9. This website', body: ['This site is a set of static pages. It sets no cookies and runs no analytics.'] },
      { title: '10. Changes', body: ['This policy may be updated. Significant changes will be announced with an app update.'] },
      { title: '11. Contact', body: ['Email:'] },
    ],
    trademark: 'YouTube is a trademark of Google LLC. This app is an unofficial app that uses the official API and player; it is not endorsed by or affiliated with Google or YouTube.',
  },
  notFound: { title: 'Page not found', body: 'The page you were looking for is not here.', cta: 'Go to the home page' },
};

const ja = {
  meta: {
    title: 'Channel Timeline Viewer — YouTube チャンネルを古い順で見る',
    description:
      'チャンネルの投稿動画を公開日順（古い順）に並べ、どこまで見たかを管理し、止めた秒数から再生を再開する iOS 視聴補助アプリ。再生は YouTube 公式の埋め込みプレイヤーを使用します。',
  },
  nav: { features: '機能', how: '使い方', faq: 'よくある質問', support: 'サポート', privacy: 'プライバシー' },
  hero: {
    badge: 'iOS 17+ ・ 7言語対応',
    title: 'チャンネルを、最初の動画から。',
    subtitle:
      'Channel Timeline Viewer は、チャンネルの投稿動画を公開日順（古い順）に並べ、どこまで見たかを覚えておきます。過去動画の一気見、講座、長期連載に向いています。',
    cta: 'App Store でダウンロード',
    ctaPending: 'App Store 公開準備中',
    ctaNote: '広告なし・サブスクなし・アプリ内課金なし。',
  },
  problem: {
    title: 'YouTube は新しい順。シリーズは最初から見たい。',
    body:
      '何百本もあるチャンネルを追いかけようとすると、一番下までスクロールして、どこで止めたかを覚えて、翌日また探すことになります。Channel Timeline Viewer は、それを「上から順に消していけるリスト」に変えます。',
  },
  featuresTitle: 'できること',
  features: [
    { title: '古い順に並べる', body: 'チャンネルURLを入れるだけで、投稿動画が公開日順に並びます。新しい順への切り替えも自由です。' },
    { title: '進捗が見える', body: 'チャンネルごとに視聴済み数・進捗率・進捗バーを表示。教材のように進み具合が分かります。' },
    { title: '秒単位で続きから', body: '途中で止めても、次に開いたときは止めた秒数から再生します。' },
    { title: '視聴済みとスキップ', body: '視聴済み／スキップを記録し、絞り込み、未視聴だけを再生できます。' },
    { title: 'リピートと自動再生', body: '1本リピート／全体リピートに対応。次の動画への自動再生は任意で、初期状態はオフです。' },
    { title: 'YouTube から共有', body: 'YouTube アプリや Safari の共有シートから、チャンネルや動画をそのまま開けます。' },
    { title: '動画ごとのメモ', body: '各動画に短いメモを残せます。講義・チュートリアル・長編シリーズに便利です。' },
    { title: 'すぐ開き直せる', body: '一度開いたチャンネルは保存済みの一覧からすぐ表示。新着はその後ろで確認します。' },
  ],
  howTitle: '3ステップ',
  how: [
    { title: 'チャンネルURLを入力／共有', body: '直接入力するか、YouTube アプリ・Safari の共有シートから渡します。' },
    { title: '1本目から見る', body: '投稿動画が古い順に並びます。「次に見る」でいつでも続きに戻れます。' },
    { title: '場所を覚えておく', body: '視聴済み・進捗・再生位置は、すべて端末内に保存されます。' },
  ],
  faqTitle: 'よくある質問',
  faq: [
    { q: 'YouTube 公式アプリですか？', a: 'いいえ。YouTube 公式の API と公式の埋め込みプレイヤーを使う独立した視聴補助アプリです。YouTube／Google による承認・提携を示すものではありません。' },
    { q: '動画をダウンロードできますか？', a: 'いいえ。ダウンロードやオフライン保存は一切行いません。広告回避も行いません。' },
    { q: 'バックグラウンド再生はできますか？', a: 'いいえ。アプリを離れると再生は止まります。再生中は画面が自動で暗くならないようにしているだけです。' },
    { q: 'ログインは必要ですか？', a: '不要です。YouTube Data API v3 を通じて公開情報だけを読み取ります。' },
    { q: '進捗はどこに保存されますか？', a: '端末内だけです。視聴履歴・進捗・メモ・再生位置は外部に出ず、アプリを削除すると消えます。' },
    { q: '広告やサブスクはありますか？', a: 'ありません。広告・サブスクリプション・アプリ内課金はなく、利用者による機能差もありません。' },
  ],
  notesTitle: 'あえてやらないこと',
  notes: [
    'ダウンロード・オフライン保存はしない',
    '独自プレイヤーで再生しない（公式の埋め込みプレイヤーのみ）',
    '広告回避・再生制限の回避はしない',
    'スクレイピングはしない（一覧は YouTube Data API v3）',
    'バックグラウンド再生はしない',
  ],
  footer: {
    tagline: 'チャンネルを順番に見るための視聴補助アプリ。',
    trademark: 'YouTube は Google LLC の商標です。本アプリは公式 API・公式プレイヤーを利用する非公式アプリであり、Google／YouTube による承認・提携を示すものではありません。',
    language: '言語',
    source: 'ソースコード',
  },
  support: {
    title: 'サポート',
    description: 'Channel Timeline Viewer の困りごとの連絡先と、よくある確認事項。',
    intro: '思ったとおりに動かないときはご連絡ください。iOS のバージョン・アプリのバージョン・操作内容を書き添えていただけると助かります。',
    contactTitle: 'お問い合わせ',
    contactBody: 'メール:',
    faqTitle: '連絡の前に',
    faq: [
      { q: 'チャンネルURLが受け付けられない', a: 'チャンネルページのURL（例: youtube.com/@handle、youtube.com/channel/UC…）をお使いください。動画のURLでも構いません（投稿元チャンネルを特定します）。' },
      { q: '一覧が途中で止まる／エラーが出る', a: '本数が非常に多いチャンネルは初回に時間がかかります。quota（上限）に関するエラーの場合は時間をおいてお試しください。YouTube Data API には1日の上限があります。' },
      { q: '動画が再生できない', a: '投稿者の設定により YouTube 外での再生が制限されている動画があります。その場合は「YouTubeで開く」をご利用ください。' },
      { q: '共有してもアプリが開かない', a: 'iOS の仕様上、共有シートからアプリを直接起動することはできません。通知を許可して、共有直後に出る通知をタップするか、アプリを開いて「共有されたURLを開く」をご利用ください。' },
    ],
    responseTitle: '返信について',
    responseBody: '通常は数営業日以内にご返信します。',
  },
  privacy: {
    title: 'プライバシーポリシー',
    description: 'Channel Timeline Viewer が保存するもの・しないこと。',
    updated: '最終更新日: 2026年8月18日',
    sections: [
      { title: '1. 概要', body: ['Channel Timeline Viewer は、利用者のデータを端末内に保存します。アカウントはなく、アプリ内に解析ツールもなく、当方が運営するサーバーが利用者の情報を受け取ることもありません。'] },
      { title: '2. 端末内に保存する情報', body: [
        '次の情報は端末内（iOS の UserDefaults／アプリのキャッシュ）にのみ保存し、当方へ送信しません。',
        '・視聴済み／スキップにした動画の識別子と日時',
        '・チャンネルごとの進捗（総本数・視聴済み数・最後に開いた動画）',
        '・最近使ったチャンネル（チャンネルID・名称・サムネイルURL・最終利用日時）',
        '・動画ごとのメモ',
        '・動画ごとの再生位置（秒）',
        '・開いたチャンネルの動画一覧のキャッシュ',
        'アプリを削除すると、これらはすべて消去されます。'] },
      { title: '3. YouTube / Google について', body: [
        '本アプリは YouTube（Google LLC）の公式サービスを2つ利用します。',
        '・YouTube Data API v3 — 入力されたチャンネルの公開された動画一覧の取得に使用します。',
        '・YouTube IFrame Player — 再生に使う公式の埋め込みプレイヤーです。再生時、YouTube／Google が独自のポリシーに基づき情報を取得・処理する場合があります。',
        '本アプリは、動画のダウンロード、広告回避、スクレイピング、バックグラウンド再生、独自プレイヤーでの再生を一切行いません。',
        'Google プライバシーポリシー: https://policies.google.com/privacy',
        'YouTube 利用規約: https://www.youtube.com/t/terms'] },
      { title: '4. 再生時に読み込む中継ページ', body: [
        '公式の埋め込みプレイヤーを正しく表示するため、再生画面では当方が GitHub Pages 上で公開している静的ページ（https://kataming.github.io/ChannelTimelineViewer/player.html）を読み込み、その中に公式プレイヤーを埋め込みます。このページは公式プレイヤーを表示するだけで、解析やトラッキングは行いません。なお、一般的な Web アクセスと同様に、配信元である GitHub 社に通信記録（IPアドレス等）が残る場合があります。'] },
      { title: '5. 他アプリからの共有', body: [
        '共有シートが受け取るのは、共有された URL（または URL を含むテキスト）だけです。端末内で解析し、公式 API へのチャンネル／動画の問い合わせにのみ使用します。他所へ送信することはありません。YouTube 以外の URL は何もせず無視します。'] },
      { title: '6. 通知', body: [
        'iOS の仕様上、共有シートからアプリを直接起動できません。通知を許可いただいた場合に限り、共有した直後に「タップして開く」ためのローカル通知を1件だけ表示します。内容は共有された YouTube の URL のみで、端末内で処理します。お知らせ・宣伝・再訪を促す通知や、サーバーからのプッシュ通知は一切送りません。'] },
      { title: '7. トラッキング', body: ['広告識別子（IDFA）は使用せず、App Tracking Transparency も使用しません（トラッキングを行わないため）。'] },
      { title: '8. 子どものプライバシー', body: ['本アプリは、子どもから個人情報を意図的に収集することはありません。'] },
      { title: '9. このウェブサイトについて', body: ['本サイトは静的ページのみで構成されており、Cookie の設定やアクセス解析は行っていません。'] },
      { title: '10. ポリシーの変更', body: ['本ポリシーは必要に応じて更新されることがあります。重要な変更はアプリの更新等でお知らせします。'] },
      { title: '11. お問い合わせ', body: ['メール:'] },
    ],
    trademark: 'YouTube は Google LLC の商標です。本アプリは公式 API・公式プレイヤーを利用する非公式アプリであり、Google／YouTube による承認・提携を示すものではありません。',
  },
  notFound: { title: 'ページが見つかりません', body: 'お探しのページはありません。', cta: 'ホームへ' },
};

const zh = {
  meta: {
    title: 'Channel Timeline Viewer — 按发布顺序观看 YouTube 频道',
    description:
      '一款 iOS 观看辅助应用：将频道的投稿视频按发布日期（从旧到新）排列，记录你看到哪里，并从上次停止的秒数继续播放。播放使用 YouTube 官方嵌入式播放器。',
  },
  nav: { features: '功能', how: '使用方法', faq: '常见问题', support: '支持', privacy: '隐私' },
  hero: {
    badge: 'iOS 17+ ・ 支持 7 种语言',
    title: '从频道的第一个视频开始看。',
    subtitle:
      'Channel Timeline Viewer 会按发布日期（从旧到新）排列频道的投稿视频，并记住你看到哪里。适合补看往期内容、课程与长期连载。',
    cta: '在 App Store 下载',
    ctaPending: 'App Store 即将上线',
    ctaNote: '没有广告，没有订阅，没有应用内购买。',
  },
  problem: {
    title: 'YouTube 从新到旧，而系列要从头看起。',
    body:
      '想补看一个有几百个视频的频道，就得一直滑到最底部，记住自己停在哪里，第二天再重新找一遍。Channel Timeline Viewer 把这件事变成一份可以从上往下逐个完成的清单。',
  },
  featuresTitle: '功能一览',
  features: [
    { title: '从旧到新排列', body: '输入频道网址，投稿视频便按发布日期排列，也可随时切换为从新到旧。' },
    { title: '看得见的进度', body: '每个频道都会显示已观看数、百分比与进度条，像课程一样清楚。' },
    { title: '精确到秒的续播', body: '中途停下也没关系，下次打开会从停止的秒数继续。' },
    { title: '已观看与跳过', body: '记录已观看／跳过状态，可筛选列表，只播放尚未观看的视频。' },
    { title: '重复与自动播放', body: '支持单个重复与整个列表重复。自动播放下一个视频为可选，默认关闭。' },
    { title: '从 YouTube 分享', body: '在 YouTube 应用或 Safari 中分享频道或视频，即可直接打开对应的时间线。' },
    { title: '每个视频的笔记', body: '可为每个视频记下简短笔记，适合讲座、教程与长篇系列。' },
    { title: '立即重新打开', body: '打开过的频道会从已保存的列表立即显示，随后在后台检查新视频。' },
  ],
  howTitle: '三个步骤',
  how: [
    { title: '输入或分享频道网址', body: '直接输入，或使用 YouTube 应用、Safari 的分享面板。' },
    { title: '从第 1 个视频开始', body: '投稿视频按从旧到新排列，点按“接下来”随时回到进度。' },
    { title: '记住你的位置', body: '已观看状态、进度与播放位置都保存在你的设备上。' },
  ],
  faqTitle: '常见问题',
  faq: [
    { q: '这是 YouTube 官方应用吗？', a: '不是。这是一款使用 YouTube 官方 API 与官方嵌入式播放器的独立观看辅助应用，未获得 YouTube／Google 的认可或与其存在合作关系。' },
    { q: '可以下载视频吗？', a: '不可以。本应用完全不提供下载或离线保存，也不屏蔽广告。' },
    { q: '支持后台播放吗？', a: '不支持。离开应用后播放会停止。播放期间只是让屏幕保持常亮，避免自动变暗。' },
    { q: '需要登录吗？', a: '不需要账号或登录。应用仅通过 YouTube Data API v3 读取公开信息。' },
    { q: '进度保存在哪里？', a: '仅保存在你的设备上。观看记录、进度、笔记与播放位置不会离开手机，删除应用后即被清除。' },
    { q: '有广告或订阅吗？', a: '没有。没有广告、订阅与应用内购买，用户之间也没有功能差异。' },
  ],
  notesTitle: '我们刻意不做的事',
  notes: [
    '不下载、不离线保存',
    '不使用自制播放器（仅官方嵌入式播放器）',
    '不屏蔽广告、不绕过播放限制',
    '不抓取网页（列表来自 YouTube Data API v3）',
    '不进行后台播放',
  ],
  footer: {
    tagline: '让你按顺序看完一个频道的观看辅助应用。',
    trademark: 'YouTube 是 Google LLC 的商标。本应用是使用官方 API 与播放器的非官方应用，未获得 Google／YouTube 的认可，也与其无关联。',
    language: '语言',
    source: '源代码',
  },
  support: {
    title: '支持',
    description: '如何获得 Channel Timeline Viewer 的帮助。',
    intro: '如果运行不符合预期，请联系我们，并附上 iOS 版本、应用版本以及当时的操作。',
    contactTitle: '联系方式',
    contactBody: '电子邮件：',
    faqTitle: '联系之前',
    faq: [
      { q: '频道网址无法识别', a: '请使用频道页面的网址（例如 youtube.com/@handle、youtube.com/channel/UC…）。视频网址也可以，应用会找到发布该视频的频道。' },
      { q: '列表中途停止或出现错误', a: '视频数量非常多的频道首次加载会较慢。若错误提到配额（quota），请稍后再试——YouTube Data API 有每日上限。' },
      { q: '视频无法播放', a: '部分视频被发布者限制在 YouTube 之外播放。此时请使用“在 YouTube 中打开”。' },
      { q: '分享后应用没有打开', a: '由于 iOS 的限制，分享面板无法直接启动应用。请允许通知并点按分享后立即出现的通知，或打开应用使用“打开分享的链接”。' },
    ],
    responseTitle: '回复时间',
    responseBody: '通常在数个工作日内回复。',
  },
  privacy: {
    title: '隐私政策',
    description: 'Channel Timeline Viewer 会保存什么，不会做什么。',
    updated: '最后更新：2026 年 8 月 18 日',
    sections: [
      { title: '1. 概述', body: ['Channel Timeline Viewer 将你的数据保存在设备中。没有账号，应用内没有分析工具，我们也没有接收你信息的服务器。'] },
      { title: '2. 保存在设备上的信息', body: [
        '以下内容仅保存在本地（iOS UserDefaults／应用缓存），不会发送给我们：',
        '• 标记为已观看或跳过的视频标识符与时间',
        '• 每个频道的进度（总数、已观看数、最后打开的视频）',
        '• 最近使用的频道（频道 ID、名称、缩略图网址、最后使用时间）',
        '• 你为视频记录的笔记',
        '• 每个视频的播放位置（秒）',
        '• 已打开频道的视频列表缓存',
        '删除应用后，这些内容会全部清除。'] },
      { title: '3. 关于 YouTube 与 Google', body: [
        '本应用使用两项 YouTube（Google LLC）官方服务：',
        '• YouTube Data API v3 —— 获取你所输入频道的公开投稿列表。',
        '• YouTube IFrame Player —— 用于播放的官方嵌入式播放器。播放期间，YouTube 与 Google 可能依据其自身政策收集与处理信息。',
        '本应用不下载视频、不屏蔽广告、不抓取网页、不后台播放，也不使用自制播放器。',
        'Google 隐私政策：https://policies.google.com/privacy',
        'YouTube 服务条款：https://www.youtube.com/t/terms'] },
      { title: '4. 播放时加载的中转页面', body: [
        '为了正确显示官方嵌入式播放器，播放界面会加载我们发布在 GitHub Pages 上的一个静态页面（https://kataming.github.io/ChannelTimelineViewer/player.html），并在其中嵌入官方播放器。该页面仅用于显示播放器，不含分析或追踪代码。与一般网页访问一样，页面的分发方 GitHub 可能会保留通信记录（如 IP 地址）。'] },
      { title: '5. 来自其他应用的分享', body: [
        '共享扩展只接收你分享的网址（或包含网址的文本）。它在设备上解析，仅用于通过官方 API 查询频道／视频，不会发送到其他地方。非 YouTube 网址会被忽略。'] },
      { title: '6. 通知', body: [
        '由于 iOS 的限制，分享面板无法直接启动应用。仅当你允许通知时，应用会在分享后立即发送一条本地通知，点按即可打开频道。通知只包含所分享的 YouTube 网址，并在设备上处理。我们绝不发送宣传、召回类通知或服务器推送通知。'] },
      { title: '7. 追踪', body: ['本应用不使用广告标识符（IDFA），也不使用 App Tracking Transparency，因为它不会追踪你。'] },
      { title: '8. 儿童隐私', body: ['本应用不会有意收集儿童的个人信息。'] },
      { title: '9. 关于本网站', body: ['本网站由静态页面构成，不设置 Cookie，也不进行访问分析。'] },
      { title: '10. 政策变更', body: ['本政策可能会更新。重要变更将随应用更新一并说明。'] },
      { title: '11. 联系我们', body: ['电子邮件：'] },
    ],
    trademark: 'YouTube 是 Google LLC 的商标。本应用是使用官方 API 与播放器的非官方应用，未获得 Google／YouTube 的认可，也与其无关联。',
  },
  notFound: { title: '找不到页面', body: '你要找的页面不在这里。', cta: '前往首页' },
};

const es = {
  meta: {
    title: 'Channel Timeline Viewer — mira un canal de YouTube del más antiguo al más reciente',
    description:
      'App complementaria para iOS que ordena las subidas de un canal de las más antiguas a las más recientes, registra hasta dónde has visto y reanuda en el segundo exacto. La reproducción usa el reproductor incrustado oficial de YouTube.',
  },
  nav: { features: 'Funciones', how: 'Cómo funciona', faq: 'Preguntas', support: 'Soporte', privacy: 'Privacidad' },
  hero: {
    badge: 'iOS 17+ · 7 idiomas',
    title: 'Mira un canal desde su primer vídeo.',
    subtitle:
      'Channel Timeline Viewer ordena las subidas de un canal por fecha de publicación —de las más antiguas a las más recientes— y recuerda hasta dónde llegaste. Ideal para archivos, clases y series largas.',
    cta: 'Descargar en el App Store',
    ctaPending: 'Próximamente en el App Store',
    ctaNote: 'Sin anuncios. Sin suscripciones. Sin compras dentro de la app.',
  },
  problem: {
    title: 'YouTube muestra lo más nuevo. Las series empiezan por el principio.',
    body:
      'Ponerse al día con un canal de cientos de vídeos significa bajar hasta el final, recordar dónde lo dejaste y volver a buscarlo mañana. Channel Timeline Viewer lo convierte en una lista que simplemente vas tachando.',
  },
  featuresTitle: 'Qué hace',
  features: [
    { title: 'Orden del más antiguo', body: 'Pega la URL de un canal y verás todas sus subidas por fecha. Cambia a «más recientes primero» cuando quieras.' },
    { title: 'Progreso visible', body: 'Vídeos vistos, porcentaje y barra de progreso por canal, como un curso que vas completando.' },
    { title: 'Reanudar al segundo', body: 'Si paras a mitad de un vídeo, la próxima vez continúa en el segundo exacto.' },
    { title: 'Vistos y omitidos', body: 'Marca vídeos como vistos u omitidos, filtra la lista y reproduce solo lo que te falta.' },
    { title: 'Repetir y autoplay', body: 'Repite un vídeo o toda la lista. La reproducción automática es opcional y está desactivada por defecto.' },
    { title: 'Compartir desde YouTube', body: 'Comparte un canal o un vídeo desde la app de YouTube o Safari y abre su cronología al instante.' },
    { title: 'Notas por vídeo', body: 'Guarda una nota breve en cada vídeo: útil para clases, tutoriales y series largas.' },
    { title: 'Reapertura instantánea', body: 'Los canales ya abiertos aparecen de inmediato desde una lista guardada y luego se buscan novedades.' },
  ],
  howTitle: 'Tres pasos',
  how: [
    { title: 'Pega o comparte la URL', body: 'Escríbela o usa la hoja para compartir de la app de YouTube o de Safari.' },
    { title: 'Empieza por el vídeo n.º 1', body: 'Las subidas aparecen de la más antigua a la más reciente. Toca «Siguiente» para volver donde estabas.' },
    { title: 'Conserva tu sitio', body: 'Marcas de visto, progreso y posiciones de reproducción se quedan en tu dispositivo.' },
  ],
  faqTitle: 'Preguntas frecuentes',
  faq: [
    { q: '¿Es la app oficial de YouTube?', a: 'No. Es una app complementaria independiente que usa la API oficial de YouTube y su reproductor incrustado oficial. No está avalada por YouTube ni por Google ni afiliada a ellos.' },
    { q: '¿Puede descargar vídeos?', a: 'No. No hay descargas ni guardado sin conexión de ningún tipo, ni bloqueo de anuncios.' },
    { q: '¿Reproduce en segundo plano?', a: 'No. La reproducción se detiene al salir de la app. Mientras un vídeo se reproduce, la pantalla solo se mantiene encendida para que no se atenúe.' },
    { q: '¿Hay que iniciar sesión?', a: 'No hace falta cuenta. La app solo lee información pública mediante la API de datos de YouTube v3.' },
    { q: '¿Dónde se guarda mi progreso?', a: 'Solo en tu dispositivo. Historial, progreso, notas y posiciones nunca salen del teléfono y se borran con la app.' },
    { q: '¿Hay anuncios o suscripciones?', a: 'Ninguno. Sin anuncios, sin suscripciones, sin compras internas y sin diferencias de funciones entre usuarios.' },
  ],
  notesTitle: 'Lo que deliberadamente no hace',
  notes: [
    'No descarga ni guarda sin conexión',
    'No usa reproductor propio: solo el reproductor incrustado oficial',
    'No bloquea anuncios ni elude restricciones de reproducción',
    'No hace scraping: la lista viene de la API de datos de YouTube v3',
    'No reproduce en segundo plano',
  ],
  footer: {
    tagline: 'Una app complementaria para ver canales en orden.',
    trademark: 'YouTube es una marca comercial de Google LLC. Esta app es una app no oficial que usa la API y el reproductor oficiales; no está avalada por Google o YouTube ni afiliada a ellos.',
    language: 'Idioma',
    source: 'Código fuente',
  },
  support: {
    title: 'Soporte',
    description: 'Cómo obtener ayuda con Channel Timeline Viewer.',
    intro: 'Si algo no funciona como esperabas, escríbenos e incluye tu versión de iOS, la versión de la app y qué estabas haciendo.',
    contactTitle: 'Contacto',
    contactBody: 'Correo:',
    faqTitle: 'Antes de escribir',
    faq: [
      { q: 'No acepta la URL del canal', a: 'Usa la URL de la página del canal (por ejemplo youtube.com/@handle o youtube.com/channel/UC…). También sirve una URL de vídeo: la app localiza el canal que lo publicó.' },
      { q: 'La lista se detiene o da error', a: 'Los canales muy grandes tardan en la primera carga. Si el error menciona la cuota, inténtalo más tarde: la API de datos de YouTube tiene un límite diario.' },
      { q: 'Un vídeo no se reproduce', a: 'Algunos vídeos tienen restringida la reproducción fuera de YouTube por su autor. En esos casos usa «Abrir en YouTube».' },
      { q: 'Compartir no abre la app', a: 'iOS no permite que una hoja para compartir abra una app directamente. Permite las notificaciones y toca la que aparece justo después de compartir, o abre la app y usa «Abrir el enlace compartido».' },
    ],
    responseTitle: 'Tiempo de respuesta',
    responseBody: 'Normalmente en unos pocos días laborables.',
  },
  privacy: {
    title: 'Política de privacidad',
    description: 'Qué guarda Channel Timeline Viewer y qué no hace.',
    updated: 'Última actualización: 18 de agosto de 2026',
    sections: [
      { title: '1. Resumen', body: ['Channel Timeline Viewer guarda tus datos en tu dispositivo. No hay cuentas, no hay analítica dentro de la app y no existe un servidor nuestro que reciba tu información.'] },
      { title: '2. Qué se guarda en tu dispositivo', body: [
        'Lo siguiente se guarda localmente (UserDefaults de iOS y caché de la app) y nunca se nos envía:',
        '• Identificadores de vídeos marcados como vistos u omitidos, con su fecha',
        '• Progreso por canal (total, vistos, último vídeo abierto)',
        '• Canales usados recientemente (ID, nombre, URL de miniatura, último uso)',
        '• Las notas que escribes para un vídeo',
        '• La posición de reproducción (en segundos) de cada vídeo',
        '• Una copia en caché de la lista de vídeos de los canales que abriste',
        'Al eliminar la app se borra todo.'] },
      { title: '3. YouTube y Google', body: [
        'La app usa dos servicios oficiales de YouTube (Google LLC):',
        '• API de datos de YouTube v3: para obtener la lista pública de subidas del canal que indiques.',
        '• YouTube IFrame Player: el reproductor incrustado oficial usado para la reproducción. Durante la reproducción, YouTube y Google pueden recopilar y tratar información según sus propias políticas.',
        'La app no descarga vídeos, no bloquea anuncios, no hace scraping, no reproduce en segundo plano y no usa un reproductor propio.',
        'Política de privacidad de Google: https://policies.google.com/privacy',
        'Términos del servicio de YouTube: https://www.youtube.com/t/terms'] },
      { title: '4. La página intermedia usada para reproducir', body: [
        'Para mostrar correctamente el reproductor incrustado oficial, la pantalla del reproductor carga una pequeña página estática que publicamos en GitHub Pages (https://kataming.github.io/ChannelTimelineViewer/player.html) e incrusta el reproductor oficial dentro. Esa página solo muestra el reproductor; no contiene analítica ni rastreo. Como en cualquier petición web, GitHub puede registrar datos de conexión habituales (como la dirección IP).'] },
      { title: '5. Compartir desde otras apps', body: [
        'La extensión para compartir recibe únicamente la URL (o el texto que la contiene) que compartes. Se analiza en el dispositivo y se usa solo para consultar el canal mediante la API oficial. No se envía a ningún otro sitio. Las URL que no son de YouTube se ignoran.'] },
      { title: '6. Notificaciones', body: [
        'iOS no permite que una hoja para compartir abra una app directamente. Solo si permites las notificaciones, la app envía una notificación local justo después de compartir para que puedas tocarla y abrir el canal. Contiene únicamente la URL de YouTube compartida y se procesa en el dispositivo. Nunca se envían notificaciones promocionales, de reenganche ni push desde servidores.'] },
      { title: '7. Rastreo', body: ['La app no usa el identificador de publicidad (IDFA) ni App Tracking Transparency, porque no te rastrea.'] },
      { title: '8. Menores', body: ['La app no recopila conscientemente información personal de menores.'] },
      { title: '9. Este sitio web', body: ['Este sitio son páginas estáticas. No usa cookies ni analítica.'] },
      { title: '10. Cambios', body: ['Esta política puede actualizarse. Los cambios relevantes se anunciarán con una actualización de la app.'] },
      { title: '11. Contacto', body: ['Correo:'] },
    ],
    trademark: 'YouTube es una marca comercial de Google LLC. Esta app es una app no oficial que usa la API y el reproductor oficiales; no está avalada por Google o YouTube ni afiliada a ellos.',
  },
  notFound: { title: 'Página no encontrada', body: 'La página que buscabas no está aquí.', cta: 'Ir al inicio' },
};

const de = {
  meta: {
    title: 'Channel Timeline Viewer — einen YouTube-Kanal chronologisch ansehen',
    description:
      'iOS-Begleit-App, die die Uploads eines Kanals nach Datum sortiert (älteste zuerst), deinen Fortschritt festhält und sekundengenau fortsetzt. Die Wiedergabe nutzt den offiziellen eingebetteten YouTube-Player.',
  },
  nav: { features: 'Funktionen', how: 'So funktioniert’s', faq: 'FAQ', support: 'Support', privacy: 'Datenschutz' },
  hero: {
    badge: 'iOS 17+ · 7 Sprachen',
    title: 'Einen Kanal beim allerersten Video beginnen.',
    subtitle:
      'Channel Timeline Viewer sortiert die Uploads eines Kanals nach Veröffentlichungsdatum – die ältesten zuerst – und merkt sich, wie weit du gekommen bist. Ideal für Archive, Vorlesungsreihen und lange Serien.',
    cta: 'Im App Store laden',
    ctaPending: 'Bald im App Store',
    ctaNote: 'Keine Werbung. Keine Abos. Keine In-App-Käufe.',
  },
  problem: {
    title: 'YouTube zeigt Neues zuerst. Serien beginnen am Anfang.',
    body:
      'Einen Kanal mit Hunderten Videos nachzuholen heißt: bis ganz nach unten scrollen, sich merken, wo man aufgehört hat, und es morgen wieder suchen. Channel Timeline Viewer macht daraus eine Liste, die du einfach abarbeitest.',
  },
  featuresTitle: 'Was die App macht',
  features: [
    { title: 'Älteste zuerst', body: 'Kanal-URL eingeben – alle Uploads erscheinen nach Datum sortiert. Umschalten auf „neueste zuerst“ jederzeit möglich.' },
    { title: 'Sichtbarer Fortschritt', body: 'Gesehene Videos, Prozentwert und Fortschrittsbalken pro Kanal – wie ein Kurs, den du durcharbeitest.' },
    { title: 'Sekundengenau fortsetzen', body: 'Mitten im Video aufgehört? Beim nächsten Mal geht es genau dort weiter.' },
    { title: 'Gesehen und übersprungen', body: 'Videos als gesehen oder übersprungen markieren, Liste filtern und nur Ungesehenes abspielen.' },
    { title: 'Wiederholen und Autoplay', body: 'Ein Video oder die ganze Liste wiederholen. Autoplay zum nächsten Video ist optional und standardmäßig aus.' },
    { title: 'Aus YouTube teilen', body: 'Kanal oder Video aus der YouTube-App oder aus Safari teilen und die Timeline sofort öffnen.' },
    { title: 'Notizen pro Video', body: 'Kurze Notiz zu jedem Video – praktisch für Vorlesungen, Tutorials und lange Serien.' },
    { title: 'Sofort wieder da', body: 'Bereits geöffnete Kanäle erscheinen sofort aus einer gespeicherten Liste; neue Uploads werden danach geprüft.' },
  ],
  howTitle: 'Drei Schritte',
  how: [
    { title: 'Kanal-URL einfügen oder teilen', body: 'Eintippen oder das Teilen-Menü der YouTube-App bzw. von Safari nutzen.' },
    { title: 'Bei Video 1 beginnen', body: 'Die Uploads stehen von alt nach neu. Mit „Als Nächstes“ kehrst du jederzeit zurück.' },
    { title: 'Deinen Platz behalten', body: 'Gesehen-Markierungen, Fortschritt und Wiedergabepositionen bleiben auf deinem Gerät.' },
  ],
  faqTitle: 'Häufige Fragen',
  faq: [
    { q: 'Ist das die offizielle YouTube-App?', a: 'Nein. Es ist eine eigenständige Begleit-App, die die offizielle YouTube-API und den offiziellen eingebetteten Player nutzt. Sie wird von YouTube oder Google weder unterstützt noch ist sie mit ihnen verbunden.' },
    { q: 'Kann sie Videos herunterladen?', a: 'Nein. Es gibt keinerlei Download oder Offline-Speicherung und keine Werbeblockierung.' },
    { q: 'Spielt sie im Hintergrund?', a: 'Nein. Beim Verlassen der App stoppt die Wiedergabe. Während der Wiedergabe bleibt lediglich der Bildschirm an, damit er nicht abdunkelt.' },
    { q: 'Muss ich mich anmelden?', a: 'Kein Konto, keine Anmeldung. Die App liest nur öffentliche Informationen über die YouTube Data API v3.' },
    { q: 'Wo wird mein Fortschritt gespeichert?', a: 'Nur auf deinem Gerät. Verlauf, Fortschritt, Notizen und Positionen verlassen das Telefon nie und werden mit der App gelöscht.' },
    { q: 'Gibt es Werbung oder Abos?', a: 'Nein. Keine Werbung, keine Abos, keine In-App-Käufe und keine Funktionsunterschiede zwischen Nutzenden.' },
  ],
  notesTitle: 'Was die App bewusst nicht tut',
  notes: [
    'Kein Download, keine Offline-Speicherung',
    'Kein eigener Player – nur der offizielle eingebettete Player',
    'Keine Werbeblockierung, kein Umgehen von Wiedergabesperren',
    'Kein Scraping – die Liste stammt aus der YouTube Data API v3',
    'Keine Hintergrundwiedergabe',
  ],
  footer: {
    tagline: 'Eine Begleit-App, um Kanäle der Reihe nach anzusehen.',
    trademark: 'YouTube ist eine Marke von Google LLC. Diese App ist eine inoffizielle App, die die offizielle API und den offiziellen Player nutzt; sie wird von Google oder YouTube weder unterstützt noch ist sie mit ihnen verbunden.',
    language: 'Sprache',
    source: 'Quellcode',
  },
  support: {
    title: 'Support',
    description: 'So bekommst du Hilfe zu Channel Timeline Viewer.',
    intro: 'Wenn etwas nicht wie erwartet funktioniert, schreib uns – mit iOS-Version, App-Version und dem, was du gerade gemacht hast.',
    contactTitle: 'Kontakt',
    contactBody: 'E-Mail:',
    faqTitle: 'Vorab',
    faq: [
      { q: 'Die Kanal-URL wird nicht akzeptiert', a: 'Nutze die URL der Kanalseite (z. B. youtube.com/@handle oder youtube.com/channel/UC…). Eine Video-URL geht auch – die App findet den veröffentlichenden Kanal.' },
      { q: 'Die Liste bricht ab oder zeigt einen Fehler', a: 'Sehr große Kanäle brauchen beim ersten Laden Zeit. Nennt der Fehler ein Kontingent (Quota), versuche es später erneut – die YouTube Data API hat ein Tageslimit.' },
      { q: 'Ein Video lässt sich nicht abspielen', a: 'Manche Videos sind vom Uploader außerhalb von YouTube gesperrt. Nutze dann „In YouTube öffnen“.' },
      { q: 'Teilen öffnet die App nicht', a: 'iOS erlaubt es nicht, aus dem Teilen-Menü direkt eine App zu starten. Erlaube Mitteilungen und tippe auf die Mitteilung direkt nach dem Teilen – oder öffne die App und nutze „Geteilten Link öffnen“.' },
    ],
    responseTitle: 'Antwortzeit',
    responseBody: 'Meist innerhalb weniger Werktage.',
  },
  privacy: {
    title: 'Datenschutzerklärung',
    description: 'Was Channel Timeline Viewer speichert – und was nicht.',
    updated: 'Zuletzt aktualisiert: 18. August 2026',
    sections: [
      { title: '1. Kurzfassung', body: ['Channel Timeline Viewer speichert deine Daten auf deinem Gerät. Es gibt kein Konto, keine Analyse in der App und keinen von uns betriebenen Server, der deine Informationen erhält.'] },
      { title: '2. Was auf dem Gerät gespeichert wird', body: [
        'Folgendes wird lokal gespeichert (iOS UserDefaults / App-Cache) und nie an uns gesendet:',
        '• Kennungen der als gesehen oder übersprungen markierten Videos samt Zeitstempel',
        '• Fortschritt pro Kanal (Gesamtzahl, gesehene Anzahl, zuletzt geöffnetes Video)',
        '• Zuletzt genutzte Kanäle (Kanal-ID, Name, Vorschaubild-URL, letzte Nutzung)',
        '• Deine Notizen zu einem Video',
        '• Die Wiedergabeposition (in Sekunden) je Video',
        '• Eine zwischengespeicherte Kopie der Videoliste geöffneter Kanäle',
        'Beim Löschen der App verschwindet all das.'] },
      { title: '3. YouTube und Google', body: [
        'Die App nutzt zwei offizielle Dienste von YouTube (Google LLC):',
        '• YouTube Data API v3 – zum Abrufen der öffentlichen Uploadliste des eingegebenen Kanals.',
        '• YouTube IFrame Player – der offizielle eingebettete Player für die Wiedergabe. Während der Wiedergabe können YouTube und Google nach ihren eigenen Richtlinien Informationen erheben und verarbeiten.',
        'Die App lädt keine Videos herunter, blockiert keine Werbung, betreibt kein Scraping, spielt nicht im Hintergrund und nutzt keinen eigenen Player.',
        'Google-Datenschutzerklärung: https://policies.google.com/privacy',
        'YouTube-Nutzungsbedingungen: https://www.youtube.com/t/terms'] },
      { title: '4. Die Zwischenseite für die Wiedergabe', body: [
        'Damit der offizielle eingebettete Player korrekt dargestellt wird, lädt der Player-Bildschirm eine kleine statische Seite, die wir auf GitHub Pages veröffentlichen (https://kataming.github.io/ChannelTimelineViewer/player.html), und bettet den offiziellen Player darin ein. Diese Seite zeigt nur den Player; sie enthält keine Analyse und kein Tracking. Wie bei jedem Webaufruf kann GitHub übliche Verbindungsdaten (etwa die IP-Adresse) protokollieren.'] },
      { title: '5. Teilen aus anderen Apps', body: [
        'Die Teilen-Erweiterung erhält ausschließlich die geteilte URL (oder den Text, der sie enthält). Sie wird auf dem Gerät ausgewertet und nur für die Abfrage des Kanals über die offizielle API verwendet. Sie wird nirgendwo anders hingesendet. Nicht-YouTube-URLs werden ignoriert.'] },
      { title: '6. Mitteilungen', body: [
        'iOS erlaubt es nicht, aus dem Teilen-Menü direkt eine App zu starten. Nur wenn du Mitteilungen erlaubst, sendet die App direkt nach dem Teilen eine lokale Mitteilung, die du antippen kannst, um den Kanal zu öffnen. Sie enthält nur die geteilte YouTube-URL und wird auf dem Gerät verarbeitet. Werbe-, Reaktivierungs- oder Server-Push-Mitteilungen werden nie gesendet.'] },
      { title: '7. Tracking', body: ['Die App nutzt weder den Werbe-Identifier (IDFA) noch App Tracking Transparency, weil sie dich nicht trackt.'] },
      { title: '8. Kinder', body: ['Die App erhebt wissentlich keine personenbezogenen Daten von Kindern.'] },
      { title: '9. Diese Website', body: ['Diese Website besteht aus statischen Seiten. Sie setzt keine Cookies und nutzt keine Analyse.'] },
      { title: '10. Änderungen', body: ['Diese Erklärung kann aktualisiert werden. Wesentliche Änderungen werden mit einem App-Update mitgeteilt.'] },
      { title: '11. Kontakt', body: ['E-Mail:'] },
    ],
    trademark: 'YouTube ist eine Marke von Google LLC. Diese App ist eine inoffizielle App, die die offizielle API und den offiziellen Player nutzt; sie wird von Google oder YouTube weder unterstützt noch ist sie mit ihnen verbunden.',
  },
  notFound: { title: 'Seite nicht gefunden', body: 'Die gesuchte Seite gibt es hier nicht.', cta: 'Zur Startseite' },
};

const fr = {
  meta: {
    title: 'Channel Timeline Viewer — regarder une chaîne YouTube dans l’ordre chronologique',
    description:
      'App compagnon iOS qui classe les vidéos d’une chaîne de la plus ancienne à la plus récente, suit votre progression et reprend à la seconde près. La lecture utilise le lecteur intégré officiel de YouTube.',
  },
  nav: { features: 'Fonctions', how: 'Comment ça marche', faq: 'FAQ', support: 'Assistance', privacy: 'Confidentialité' },
  hero: {
    badge: 'iOS 17+ · 7 langues',
    title: 'Regardez une chaîne depuis sa toute première vidéo.',
    subtitle:
      'Channel Timeline Viewer classe les vidéos d’une chaîne par date de publication — de la plus ancienne à la plus récente — et retient où vous vous êtes arrêté. Idéal pour les archives, les cours et les séries au long cours.',
    cta: 'Télécharger sur l’App Store',
    ctaPending: 'Bientôt sur l’App Store',
    ctaNote: 'Sans publicité. Sans abonnement. Sans achat intégré.',
  },
  problem: {
    title: 'YouTube affiche le plus récent. Une série se regarde depuis le début.',
    body:
      'Rattraper une chaîne de plusieurs centaines de vidéos, c’est descendre jusqu’en bas, se souvenir où l’on s’est arrêté, puis la retrouver le lendemain. Channel Timeline Viewer transforme tout cela en une liste que l’on parcourt simplement.',
  },
  featuresTitle: 'Ce que fait l’app',
  features: [
    { title: 'Ordre chronologique', body: 'Collez l’URL d’une chaîne : toutes les vidéos apparaissent par date. Basculez en « plus récentes d’abord » quand vous voulez.' },
    { title: 'Progression visible', body: 'Nombre de vidéos vues, pourcentage et barre de progression par chaîne, comme un cours que l’on avance.' },
    { title: 'Reprise à la seconde', body: 'Arrêtez-vous au milieu d’une vidéo : la prochaine fois, la lecture reprend exactement là.' },
    { title: 'Vues et ignorées', body: 'Marquez les vidéos comme regardées ou ignorées, filtrez la liste et ne lisez que ce qu’il vous reste.' },
    { title: 'Répétition et lecture auto', body: 'Répétez une vidéo ou toute la liste. La lecture automatique est facultative et désactivée par défaut.' },
    { title: 'Partage depuis YouTube', body: 'Partagez une chaîne ou une vidéo depuis l’app YouTube ou Safari et ouvrez sa chronologie aussitôt.' },
    { title: 'Notes par vidéo', body: 'Gardez une note courte sur chaque vidéo : pratique pour les cours, tutoriels et longues séries.' },
    { title: 'Réouverture immédiate', body: 'Les chaînes déjà ouvertes s’affichent instantanément depuis une liste enregistrée, puis les nouveautés sont vérifiées.' },
  ],
  howTitle: 'Trois étapes',
  how: [
    { title: 'Collez ou partagez l’URL', body: 'Saisissez-la, ou utilisez la feuille de partage de l’app YouTube ou de Safari.' },
    { title: 'Commencez par la vidéo n° 1', body: 'Les vidéos s’affichent de la plus ancienne à la plus récente. « À suivre » vous y ramène à tout moment.' },
    { title: 'Gardez votre place', body: 'Marques de visionnage, progression et positions de lecture restent sur votre appareil.' },
  ],
  faqTitle: 'Questions fréquentes',
  faq: [
    { q: 'Est-ce l’app officielle YouTube ?', a: 'Non. C’est une app compagnon indépendante qui utilise l’API officielle de YouTube et son lecteur intégré officiel. Elle n’est ni approuvée par YouTube ou Google, ni affiliée à eux.' },
    { q: 'Peut-elle télécharger des vidéos ?', a: 'Non. Aucun téléchargement ni enregistrement hors ligne, et aucun blocage de publicité.' },
    { q: 'Lit-elle en arrière-plan ?', a: 'Non. La lecture s’arrête dès que vous quittez l’app. Pendant la lecture, l’écran reste simplement allumé pour ne pas s’assombrir.' },
    { q: 'Faut-il se connecter ?', a: 'Aucun compte requis. L’app ne lit que des informations publiques via l’API YouTube Data v3.' },
    { q: 'Où est enregistrée ma progression ?', a: 'Uniquement sur votre appareil. Historique, progression, notes et positions ne quittent jamais le téléphone et disparaissent avec l’app.' },
    { q: 'Y a-t-il de la publicité ou des abonnements ?', a: 'Aucun. Ni publicité, ni abonnement, ni achat intégré, et aucune différence de fonctions entre utilisateurs.' },
  ],
  notesTitle: 'Ce que l’app ne fait volontairement pas',
  notes: [
    'Aucun téléchargement ni enregistrement hors ligne',
    'Aucun lecteur maison — uniquement le lecteur intégré officiel',
    'Aucun blocage de publicité ni contournement des restrictions de lecture',
    'Aucun scraping — la liste provient de l’API YouTube Data v3',
    'Aucune lecture en arrière-plan',
  ],
  footer: {
    tagline: 'Une app compagnon pour regarder les chaînes dans l’ordre.',
    trademark: 'YouTube est une marque de Google LLC. Cette app est une app non officielle qui utilise l’API et le lecteur officiels ; elle n’est ni approuvée par Google ou YouTube, ni affiliée à eux.',
    language: 'Langue',
    source: 'Code source',
  },
  support: {
    title: 'Assistance',
    description: 'Comment obtenir de l’aide pour Channel Timeline Viewer.',
    intro: 'Si quelque chose ne fonctionne pas comme prévu, écrivez-nous en précisant votre version d’iOS, la version de l’app et ce que vous faisiez.',
    contactTitle: 'Contact',
    contactBody: 'E-mail :',
    faqTitle: 'Avant d’écrire',
    faq: [
      { q: 'L’URL de la chaîne est refusée', a: 'Utilisez l’URL de la page de la chaîne (par exemple youtube.com/@handle ou youtube.com/channel/UC…). Une URL de vidéo convient aussi : l’app retrouve la chaîne qui l’a publiée.' },
      { q: 'La liste s’arrête ou affiche une erreur', a: 'Les très grandes chaînes prennent du temps au premier chargement. Si l’erreur mentionne un quota, réessayez plus tard : l’API YouTube Data a une limite quotidienne.' },
      { q: 'Une vidéo ne se lit pas', a: 'Certaines vidéos sont bloquées hors de YouTube par leur auteur. Utilisez alors « Ouvrir dans YouTube ».' },
      { q: 'Le partage n’ouvre pas l’app', a: 'iOS ne permet pas à une feuille de partage de lancer une app directement. Autorisez les notifications et touchez celle qui apparaît juste après le partage, ou ouvrez l’app et utilisez « Ouvrir le lien partagé ».' },
    ],
    responseTitle: 'Délai de réponse',
    responseBody: 'Généralement sous quelques jours ouvrés.',
  },
  privacy: {
    title: 'Politique de confidentialité',
    description: 'Ce que Channel Timeline Viewer enregistre, et ce qu’il ne fait pas.',
    updated: 'Dernière mise à jour : 18 août 2026',
    sections: [
      { title: '1. En bref', body: ['Channel Timeline Viewer conserve vos données sur votre appareil. Il n’y a pas de compte, pas d’analytique dans l’app, et aucun serveur exploité par nous ne reçoit vos informations.'] },
      { title: '2. Ce qui est enregistré sur votre appareil', body: [
        'Les éléments suivants sont enregistrés localement (UserDefaults iOS / cache de l’app) et ne nous sont jamais transmis :',
        '• Identifiants des vidéos marquées comme regardées ou ignorées, avec l’horodatage',
        '• Progression par chaîne (nombre total, nombre de vidéos vues, dernière vidéo ouverte)',
        '• Chaînes récemment utilisées (identifiant, nom, URL de miniature, dernière utilisation)',
        '• Les notes que vous écrivez pour une vidéo',
        '• La position de lecture (en secondes) de chaque vidéo',
        '• Une copie en cache de la liste des vidéos des chaînes ouvertes',
        'La suppression de l’app efface l’ensemble.'] },
      { title: '3. YouTube et Google', body: [
        'L’app utilise deux services officiels de YouTube (Google LLC) :',
        '• API YouTube Data v3 — pour récupérer la liste publique des vidéos de la chaîne saisie.',
        '• YouTube IFrame Player — le lecteur intégré officiel utilisé pour la lecture. Pendant la lecture, YouTube et Google peuvent collecter et traiter des informations selon leurs propres politiques.',
        'L’app ne télécharge pas de vidéos, ne bloque pas la publicité, ne fait pas de scraping, ne lit pas en arrière-plan et n’utilise pas de lecteur maison.',
        'Politique de confidentialité de Google : https://policies.google.com/privacy',
        'Conditions d’utilisation de YouTube : https://www.youtube.com/t/terms'] },
      { title: '4. La page relais utilisée pour la lecture', body: [
        'Pour afficher correctement le lecteur intégré officiel, l’écran de lecture charge une petite page statique que nous publions sur GitHub Pages (https://kataming.github.io/ChannelTimelineViewer/player.html) et y intègre le lecteur officiel. Cette page ne fait qu’afficher le lecteur ; elle ne contient ni analytique ni traceur. Comme pour toute requête web, GitHub peut journaliser des informations de connexion habituelles (adresse IP, par exemple).'] },
      { title: '5. Partage depuis d’autres apps', body: [
        'L’extension de partage ne reçoit que l’URL (ou le texte la contenant) que vous partagez. Elle est analysée sur l’appareil et sert uniquement à interroger la chaîne via l’API officielle. Elle n’est envoyée nulle part ailleurs. Les URL non YouTube sont ignorées.'] },
      { title: '6. Notifications', body: [
        'iOS ne permet pas à une feuille de partage de lancer une app directement. Uniquement si vous autorisez les notifications, l’app envoie une notification locale juste après le partage afin que vous puissiez la toucher pour ouvrir la chaîne. Elle ne contient que l’URL YouTube partagée et est traitée sur l’appareil. Aucune notification promotionnelle, de relance ou push depuis un serveur n’est jamais envoyée.'] },
      { title: '7. Suivi', body: ['L’app n’utilise pas l’identifiant publicitaire (IDFA) ni App Tracking Transparency, car elle ne vous suit pas.'] },
      { title: '8. Enfants', body: ['L’app ne collecte pas sciemment de données personnelles auprès d’enfants.'] },
      { title: '9. Ce site web', body: ['Ce site est constitué de pages statiques. Il ne dépose pas de cookies et n’utilise pas d’analytique.'] },
      { title: '10. Modifications', body: ['Cette politique peut être mise à jour. Les changements importants seront annoncés avec une mise à jour de l’app.'] },
      { title: '11. Contact', body: ['E-mail :'] },
    ],
    trademark: 'YouTube est une marque de Google LLC. Cette app est une app non officielle qui utilise l’API et le lecteur officiels ; elle n’est ni approuvée par Google ou YouTube, ni affiliée à eux.',
  },
  notFound: { title: 'Page introuvable', body: 'La page que vous cherchiez n’est pas ici.', cta: 'Aller à l’accueil' },
};

const ko = {
  meta: {
    title: 'Channel Timeline Viewer — YouTube 채널을 오래된 순으로 보기',
    description:
      '채널의 업로드 동영상을 게시일순(오래된 순)으로 정리하고, 어디까지 봤는지 관리하며, 멈춘 초부터 이어서 재생하는 iOS 시청 보조 앱. 재생에는 YouTube 공식 임베드 플레이어를 사용합니다.',
  },
  nav: { features: '기능', how: '사용 방법', faq: '자주 묻는 질문', support: '지원', privacy: '개인정보' },
  hero: {
    badge: 'iOS 17+ · 7개 언어',
    title: '채널을 첫 영상부터.',
    subtitle:
      'Channel Timeline Viewer는 채널의 업로드 동영상을 게시일순(오래된 순)으로 정리하고 어디까지 봤는지 기억합니다. 과거 영상 정주행, 강의, 장기 시리즈에 잘 맞습니다.',
    cta: 'App Store에서 다운로드',
    ctaPending: 'App Store 출시 준비 중',
    ctaNote: '광고 없음. 구독 없음. 인앱 결제 없음.',
  },
  problem: {
    title: 'YouTube는 최신순, 시리즈는 처음부터.',
    body:
      '영상이 수백 개인 채널을 따라잡으려면 맨 아래까지 스크롤하고, 어디서 멈췄는지 기억하고, 다음 날 다시 찾아야 합니다. Channel Timeline Viewer는 그것을 위에서부터 차례로 지워 가는 목록으로 바꿔 줍니다.',
  },
  featuresTitle: '주요 기능',
  features: [
    { title: '오래된 순 정렬', body: '채널 URL만 넣으면 업로드 동영상이 게시일순으로 정렬됩니다. 최신 순으로 전환도 자유롭습니다.' },
    { title: '보이는 진행률', body: '채널마다 시청 수·백분율·진행 바를 표시합니다. 교재처럼 진도를 알 수 있습니다.' },
    { title: '초 단위 이어 보기', body: '도중에 멈춰도 다음에 열면 멈춘 초부터 재생합니다.' },
    { title: '시청함과 건너뛰기', body: '시청함·건너뛰기를 기록하고, 목록을 걸러 안 본 것만 재생할 수 있습니다.' },
    { title: '반복과 자동 재생', body: '한 편 반복과 전체 반복을 지원합니다. 다음 동영상 자동 재생은 선택 사항이며 기본은 꺼짐입니다.' },
    { title: 'YouTube에서 공유', body: 'YouTube 앱이나 Safari의 공유 시트에서 채널·동영상을 바로 열 수 있습니다.' },
    { title: '동영상별 메모', body: '각 동영상에 짧은 메모를 남길 수 있어 강의·튜토리얼·장편 시리즈에 유용합니다.' },
    { title: '즉시 다시 열기', body: '한 번 연 채널은 저장된 목록에서 바로 표시되고, 새 동영상은 그 뒤에 확인합니다.' },
  ],
  howTitle: '세 단계',
  how: [
    { title: '채널 URL 입력 또는 공유', body: '직접 입력하거나 YouTube 앱·Safari의 공유 시트를 사용하세요.' },
    { title: '1번째 영상부터 시청', body: '업로드 동영상이 오래된 순으로 표시됩니다. ‘다음 시청’으로 언제든 돌아올 수 있습니다.' },
    { title: '내 위치 유지', body: '시청 표시, 진행률, 재생 위치는 모두 기기에 저장됩니다.' },
  ],
  faqTitle: '자주 묻는 질문',
  faq: [
    { q: 'YouTube 공식 앱인가요?', a: '아닙니다. YouTube 공식 API와 공식 임베드 플레이어를 사용하는 독립 시청 보조 앱이며, YouTube·Google의 승인이나 제휴를 나타내지 않습니다.' },
    { q: '동영상을 다운로드할 수 있나요?', a: '아니요. 다운로드나 오프라인 저장은 전혀 하지 않으며 광고 차단도 하지 않습니다.' },
    { q: '백그라운드 재생이 되나요?', a: '되지 않습니다. 앱을 벗어나면 재생이 멈춥니다. 재생 중에는 화면이 어두워지지 않도록만 유지합니다.' },
    { q: '로그인이 필요한가요?', a: '계정이나 로그인은 필요 없습니다. YouTube Data API v3를 통해 공개 정보만 읽습니다.' },
    { q: '진행률은 어디에 저장되나요?', a: '기기에만 저장됩니다. 시청 기록·진행률·메모·재생 위치는 휴대폰을 벗어나지 않으며 앱을 삭제하면 함께 지워집니다.' },
    { q: '광고나 구독이 있나요?', a: '없습니다. 광고·구독·인앱 결제가 없고 사용자 간 기능 차이도 없습니다.' },
  ],
  notesTitle: '의도적으로 하지 않는 것',
  notes: [
    '다운로드·오프라인 저장을 하지 않음',
    '자체 플레이어로 재생하지 않음(공식 임베드 플레이어만 사용)',
    '광고 차단·재생 제한 우회를 하지 않음',
    '스크래핑을 하지 않음(목록은 YouTube Data API v3)',
    '백그라운드 재생을 하지 않음',
  ],
  footer: {
    tagline: '채널을 순서대로 보기 위한 시청 보조 앱.',
    trademark: 'YouTube는 Google LLC의 상표입니다. 이 앱은 공식 API와 공식 플레이어를 사용하는 비공식 앱이며 Google·YouTube의 승인이나 제휴를 나타내지 않습니다.',
    language: '언어',
    source: '소스 코드',
  },
  support: {
    title: '지원',
    description: 'Channel Timeline Viewer 도움말과 문의 방법.',
    intro: '예상대로 동작하지 않으면 연락 주세요. iOS 버전, 앱 버전, 당시 조작 내용을 함께 알려 주시면 도움이 됩니다.',
    contactTitle: '문의',
    contactBody: '이메일:',
    faqTitle: '문의 전에',
    faq: [
      { q: '채널 URL이 인식되지 않습니다', a: '채널 페이지 URL(예: youtube.com/@handle, youtube.com/channel/UC…)을 사용하세요. 동영상 URL도 괜찮습니다. 앱이 게시한 채널을 찾아 줍니다.' },
      { q: '목록이 중간에 멈추거나 오류가 납니다', a: '동영상이 아주 많은 채널은 첫 로딩에 시간이 걸립니다. 오류에 할당량(quota)이 언급되면 잠시 후 다시 시도하세요. YouTube Data API에는 하루 한도가 있습니다.' },
      { q: '동영상이 재생되지 않습니다', a: '게시자가 YouTube 외부 재생을 제한한 동영상이 있습니다. 그럴 때는 ‘YouTube에서 열기’를 사용하세요.' },
      { q: '공유해도 앱이 열리지 않습니다', a: 'iOS 사양상 공유 시트에서 앱을 직접 실행할 수 없습니다. 알림을 허용하고 공유 직후 표시되는 알림을 탭하거나, 앱을 열어 ‘공유된 URL 열기’를 사용하세요.' },
    ],
    responseTitle: '답변 시간',
    responseBody: '보통 영업일 기준 며칠 이내에 답변드립니다.',
  },
  privacy: {
    title: '개인정보 처리방침',
    description: 'Channel Timeline Viewer가 저장하는 것과 하지 않는 것.',
    updated: '최종 업데이트: 2026년 8월 18일',
    sections: [
      { title: '1. 요약', body: ['Channel Timeline Viewer는 데이터를 기기에 저장합니다. 계정이 없고, 앱 내 분석 도구도 없으며, 이용자의 정보를 받는 자체 서버도 없습니다.'] },
      { title: '2. 기기에 저장하는 정보', body: [
        '다음 정보는 기기에만 저장되며(iOS UserDefaults·앱 캐시) 저희에게 전송되지 않습니다.',
        '• 시청함·건너뛰기로 표시한 동영상 식별자와 시각',
        '• 채널별 진행률(전체 수, 시청 수, 마지막으로 연 동영상)',
        '• 최근 사용한 채널(채널 ID, 이름, 썸네일 URL, 마지막 사용 시각)',
        '• 동영상에 작성한 메모',
        '• 동영상별 재생 위치(초)',
        '• 열어 본 채널의 동영상 목록 캐시',
        '앱을 삭제하면 모두 지워집니다.'] },
      { title: '3. YouTube와 Google', body: [
        '이 앱은 YouTube(Google LLC)의 공식 서비스 두 가지를 사용합니다.',
        '• YouTube Data API v3 — 입력한 채널의 공개된 업로드 목록을 가져옵니다.',
        '• YouTube IFrame Player — 재생에 사용하는 공식 임베드 플레이어입니다. 재생 중 YouTube와 Google이 자체 정책에 따라 정보를 수집·처리할 수 있습니다.',
        '이 앱은 동영상 다운로드, 광고 차단, 스크래핑, 백그라운드 재생, 자체 플레이어 재생을 일절 하지 않습니다.',
        'Google 개인정보처리방침: https://policies.google.com/privacy',
        'YouTube 서비스 약관: https://www.youtube.com/t/terms'] },
      { title: '4. 재생 시 불러오는 중계 페이지', body: [
        '공식 임베드 플레이어를 올바르게 표시하기 위해, 재생 화면은 저희가 GitHub Pages에 게시한 작은 정적 페이지(https://kataming.github.io/ChannelTimelineViewer/player.html)를 불러와 그 안에 공식 플레이어를 임베드합니다. 이 페이지는 플레이어를 표시할 뿐 분석이나 추적 코드를 포함하지 않습니다. 일반적인 웹 요청과 마찬가지로 배포처인 GitHub에 통신 기록(IP 주소 등)이 남을 수 있습니다.'] },
      { title: '5. 다른 앱에서의 공유', body: [
        '공유 확장은 공유한 URL(또는 URL이 포함된 텍스트)만 받습니다. 기기에서 해석해 공식 API로 채널을 조회하는 데에만 사용하며 다른 곳으로 보내지 않습니다. YouTube가 아닌 URL은 무시합니다.'] },
      { title: '6. 알림', body: [
        'iOS 사양상 공유 시트에서 앱을 직접 실행할 수 없습니다. 알림을 허용한 경우에 한해, 공유 직후 탭하여 열 수 있는 로컬 알림을 한 건만 표시합니다. 내용은 공유된 YouTube URL뿐이며 기기에서 처리합니다. 홍보·재방문 유도 알림이나 서버 푸시 알림은 보내지 않습니다.'] },
      { title: '7. 추적', body: ['이 앱은 광고 식별자(IDFA)를 사용하지 않으며, 추적을 하지 않으므로 App Tracking Transparency도 사용하지 않습니다.'] },
      { title: '8. 아동의 개인정보', body: ['이 앱은 아동으로부터 개인정보를 의도적으로 수집하지 않습니다.'] },
      { title: '9. 이 웹사이트', body: ['이 사이트는 정적 페이지로만 구성되어 있으며 쿠키를 설정하거나 접속 분석을 하지 않습니다.'] },
      { title: '10. 변경', body: ['이 방침은 필요에 따라 업데이트될 수 있습니다. 중요한 변경은 앱 업데이트로 안내합니다.'] },
      { title: '11. 문의', body: ['이메일:'] },
    ],
    trademark: 'YouTube는 Google LLC의 상표입니다. 이 앱은 공식 API와 공식 플레이어를 사용하는 비공식 앱이며 Google·YouTube의 승인이나 제휴를 나타내지 않습니다.',
  },
  notFound: { title: '페이지를 찾을 수 없습니다', body: '찾으시는 페이지가 없습니다.', cta: '홈으로' },
};

export const dict = { en, ja, zh, es, de, fr, ko };
export default dict;
