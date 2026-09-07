// 入力（チャンネルURL / @ハンドル / チャンネルID / 動画URL）の解析。
// アプリ側の Services/ChannelResolver.swift と同じ規則にしてある（挙動を揃えるため）。
// ネットワークに触らない純粋関数なので、scripts/test-trial.mjs でそのまま試せる。

/** UC で始まる24文字のチャンネルIDか。 */
export function isChannelId(s) {
  return typeof s === 'string' && s.length === 24 && s.startsWith('UC') && /^[A-Za-z0-9_-]+$/.test(s);
}

/** YouTube の動画ID（11文字）か。 */
export function isVideoId(s) {
  return typeof s === 'string' && s.length === 11 && /^[A-Za-z0-9_-]+$/.test(s);
}

/**
 * 入力を識別子に変換する。
 * @returns {{kind:'channelId'|'handle'|'username'|'name'|'video', value:string}|null}
 *          解析できなければ null（＝チャンネルURLとして認識できない）。
 */
export function parseInput(raw) {
  const input = String(raw || '').trim();
  if (!input) return null;

  // 1) @ハンドル単体
  if (input.startsWith('@')) {
    const handle = input.slice(1).trim();
    return handle && /^[A-Za-z0-9_.\-]+$/.test(handle) ? { kind: 'handle', value: handle } : null;
  }

  // 2) チャンネルID単体
  if (isChannelId(input)) return { kind: 'channelId', value: input };

  // 3) URLとして解析（スキーム省略も許容）
  let url;
  try {
    url = new URL(input.includes('://') ? input : `https://${input}`);
  } catch {
    return null;
  }

  const host = url.hostname.toLowerCase();
  if (!(host === 'youtu.be' || host.endsWith('.youtu.be') || host === 'youtube.com' || host.endsWith('.youtube.com'))) {
    return null;
  }

  const segments = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);

  // 短縮URL（youtu.be/VIDEOID）は常に動画。
  if (host === 'youtu.be' || host.endsWith('.youtu.be')) {
    const id = segments[0];
    return isVideoId(id) ? { kind: 'video', value: id } : null;
  }

  const first = segments[0];
  if (!first) return null;

  switch (first.toLowerCase()) {
    case 'watch': {
      const v = url.searchParams.get('v');
      return isVideoId(v) ? { kind: 'video', value: v } : null;
    }
    case 'shorts':
    case 'live':
    case 'embed':
    case 'v': {
      const id = segments[1];
      return isVideoId(id) ? { kind: 'video', value: id } : null;
    }
    case 'channel': {
      const id = segments[1];
      return isChannelId(id) ? { kind: 'channelId', value: id } : null;
    }
    case 'user': {
      const name = segments[1];
      return name ? { kind: 'username', value: name } : null;
    }
    case 'c': {
      const name = segments[1];
      return name ? { kind: 'name', value: name } : null;
    }
    default:
      if (first.startsWith('@')) {
        const handle = first.slice(1);
        return handle ? { kind: 'handle', value: handle } : null;
      }
      // youtube.com/SomeName のような古いカスタムURL
      return { kind: 'name', value: first };
  }
}
