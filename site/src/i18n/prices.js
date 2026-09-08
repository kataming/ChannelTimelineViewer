// Pro（買い切り）の各国の価格。**自動生成なので手で書かない。**
//   python scripts/fetch_store_prices.py
// で App Store Connect / Google Play の現在の価格を読み直して作り直す。
//
// 形は { 言語: { ios: {currency, amount}, android: {currency, amount} } }。
// 金額の書式は表示側（Intl.NumberFormat）で各言語に合わせて作る。
// 中国本土は Google Play が提供されていないため、zh には android が入らない。

export const proPrices = {
  "en": {
    "ios": {
      "currency": "USD",
      "amount": 4.99
    },
    "android": {
      "currency": "USD",
      "amount": 4.99
    }
  },
  "ja": {
    "ios": {
      "currency": "JPY",
      "amount": 800.0
    },
    "android": {
      "currency": "JPY",
      "amount": 800.0
    }
  },
  "zh": {
    "ios": {
      "currency": "CNY",
      "amount": 38.0
    }
  },
  "es": {
    "ios": {
      "currency": "EUR",
      "amount": 5.99
    },
    "android": {
      "currency": "EUR",
      "amount": 4.99
    }
  },
  "de": {
    "ios": {
      "currency": "EUR",
      "amount": 5.99
    },
    "android": {
      "currency": "EUR",
      "amount": 4.99
    }
  },
  "fr": {
    "ios": {
      "currency": "EUR",
      "amount": 5.99
    },
    "android": {
      "currency": "EUR",
      "amount": 4.99
    }
  },
  "ko": {
    "ios": {
      "currency": "KRW",
      "amount": 7700.0
    },
    "android": {
      "currency": "KRW",
      "amount": 7500.0
    }
  }
};

/** その言語で出す価格。両ストアが同じ金額なら1つ、違えば両方返す。 */
export function priceFor(code) {
  // その言語の国の価格が無ければ何も出さない（別の国の金額は出さない）。
  const entry = proPrices[code];
  if (!entry) return null;
  const { ios, android } = entry;
  if (ios && android && ios.currency === android.currency && ios.amount === android.amount) {
    return { same: ios };
  }
  return { ios: ios || null, android: android || null };
}

export default proPrices;
