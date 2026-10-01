// データアクセス層。画面はここ経由でしかデータに触らない。
// 保存先はローカル版なら Node のサーバー（/api/db → data/db.json）、
// 公式サイト版（/marketing/）なら Cloudflare Pages Functions（/marketing/api/db → KV）。
// どちらも同じ API なので、URL は相対パス（api/db）で書く。
import { normalize } from './domain/schema.js';

export class ConflictError extends Error {}

export class HttpRepository {
  constructor(base = 'api/db') { this.base = base; }

  async load() {
    const res = await fetch(this.base, { cache: 'no-store', credentials: 'same-origin' });
    if (res.status === 401) { location.reload(); throw new Error('ログインが切れました'); }
    if (!res.ok) throw new Error(`読み込みに失敗しました（HTTP ${res.status}）`);
    return normalize(await res.json());
  }

  /**
   * 保存。baseVersion（読み込んだときの updatedAt）を送り、サーバー側がそれより新しければ 409 を返す。
   * 別の端末・タブで先に保存された内容を、黙って上書きしないため。
   */
  async save(doc, baseVersion) {
    const res = await fetch(this.base, {
      method: 'PUT',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', ...(baseVersion ? { 'If-Match': baseVersion } : {}) },
      body: JSON.stringify(doc),
    });
    const body = await res.json().catch(() => ({}));
    if (res.status === 401) { location.reload(); throw new Error('ログインが切れました'); }
    if (res.status === 409) throw new ConflictError(body.error || '別の画面で先に保存されています');
    if (!res.ok) throw new Error(body.error || `保存に失敗しました（HTTP ${res.status}）`);
    return normalize(body);
  }
}

export class Store {
  constructor(repository) {
    this.repository = repository;
    this.doc = null;
    this.listeners = new Set();
  }

  async init() {
    this.doc = await this.repository.load();
    this.emit();
  }

  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  emit() { for (const fn of this.listeners) fn(this.doc); }

  /** 操作（doc → 新しい doc）を当てて保存する。入力エラーはそのまま投げ返す。 */
  async apply(operation) {
    const next = operation(this.doc);
    this.doc = await this.repository.save(next, this.doc.updatedAt);
    this.emit();
    return this.doc;
  }

  /** 復元。今の内容をまるごと置き換える（版の確認はしない）。 */
  async replace(doc) {
    this.doc = await this.repository.save(normalize(doc));
    this.emit();
    return this.doc;
  }
}
