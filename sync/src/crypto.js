// トークンとペアリングコードの生成・照合。
//
// 守ること:
// - 生成は暗号論的乱数のみ（Math.random は使わない）
// - サーバーに平文で保存しない（SHA-256 のハッシュだけ）。ログにも出さない
// - 比較は定数時間で行う

/** 紛らわしい文字（0/O, 1/I/L, 8/B）を除いた 8 文字。 */
const CODE_ALPHABET = 'ACDEFGHJKMNPQRTUVWXY34679';
export const CODE_LENGTH = 8;

function randomBytes(length) {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

function toHex(buffer) {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** ペアリングコード（人が読んで入力する。約 37bit のエントロピー）。 */
export function generatePairingCode() {
  const bytes = randomBytes(CODE_LENGTH);
  let code = '';
  for (const byte of bytes) code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
  return code;
}

/** 端末トークン・ポーリングトークン（URL には載せない。ヘッダーでだけ送る）。 */
export function generateToken() {
  return toHex(randomBytes(32));
}

export function generateId() {
  return crypto.randomUUID();
}

/** 入力されたコードのゆらぎ（小文字・空白・ハイフン）を吸収する。 */
export function normalizeCode(input) {
  return String(input ?? '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
}

export async function hash(value, pepper = '') {
  const data = new TextEncoder().encode(`${pepper}:${value}`);
  return toHex(await crypto.subtle.digest('SHA-256', data));
}

/** 定数時間比較（長さが違えば false）。 */
export function safeEqual(a, b) {
  const left = String(a ?? '');
  const right = String(b ?? '');
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i += 1) diff |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return diff === 0;
}
