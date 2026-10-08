// AdMob の日ごとの推移の整形（画面とテストで共用）。

/** AdMob はデータの無い日を返さないので、集計期間（from〜to）の抜けた日を 0 で埋める（推移を日付どおりに並べるため）。 */
export function fillDailyGaps(daily, from, to) {
  if (!daily.length) return daily;
  const byDate = new Map(daily.map((d) => [d.date, d]));
  const start = new Date(`${from || daily[0].date}T00:00:00Z`);
  const end = new Date(`${to || daily[daily.length - 1].date}T00:00:00Z`);
  if (!(start <= end) || (end - start) / 86400000 > 400) return daily;
  const out = [];
  for (let t = start; t <= end; t = new Date(t.getTime() + 86400000)) {
    const date = t.toISOString().slice(0, 10);
    out.push(byDate.get(date) ?? { date, earningsJPY: 0, impressions: 0, clicks: 0, adRequests: 0, matchedRequests: 0, byPlatform: {} });
  }
  return out;
}
