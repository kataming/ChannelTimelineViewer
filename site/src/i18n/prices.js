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
      "amount": 500.0
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
      "amount": 5.99
    }
  },
  "de": {
    "ios": {
      "currency": "EUR",
      "amount": 5.99
    },
    "android": {
      "currency": "EUR",
      "amount": 5.99
    }
  },
  "fr": {
    "ios": {
      "currency": "EUR",
      "amount": 5.99
    },
    "android": {
      "currency": "EUR",
      "amount": 5.99
    }
  },
  "ko": {
    "ios": {
      "currency": "KRW",
      "amount": 7700.0
    },
    "android": {
      "currency": "KRW",
      "amount": 7700.0
    }
  },
  "ar": {
    "ios": {
      "currency": "SAR",
      "amount": 19.99
    },
    "android": {
      "currency": "SAR",
      "amount": 21.99
    }
  },
  "bn": {
    "ios": {
      "currency": "USD",
      "amount": 4.99
    },
    "android": {
      "currency": "BDT",
      "amount": 99.0
    }
  },
  "cs": {
    "ios": {
      "currency": "CZK",
      "amount": 129.0
    },
    "android": {
      "currency": "CZK",
      "amount": 119.99
    }
  },
  "nl": {
    "ios": {
      "currency": "EUR",
      "amount": 5.99
    },
    "android": {
      "currency": "EUR",
      "amount": 5.99
    }
  },
  "fil": {
    "ios": {
      "currency": "PHP",
      "amount": 299.0
    },
    "android": {
      "currency": "PHP",
      "amount": 345.0
    }
  },
  "el": {
    "ios": {
      "currency": "EUR",
      "amount": 5.99
    },
    "android": {
      "currency": "EUR",
      "amount": 5.99
    }
  },
  "hi": {
    "ios": {
      "currency": "INR",
      "amount": 499.0
    },
    "android": {
      "currency": "INR",
      "amount": 99.0
    }
  },
  "hu": {
    "ios": {
      "currency": "HUF",
      "amount": 1990.0
    },
    "android": {
      "currency": "HUF",
      "amount": 1990.0
    }
  },
  "id": {
    "ios": {
      "currency": "IDR",
      "amount": 99000.0
    },
    "android": {
      "currency": "IDR",
      "amount": 89000.0
    }
  },
  "it": {
    "ios": {
      "currency": "EUR",
      "amount": 5.99
    },
    "android": {
      "currency": "EUR",
      "amount": 5.99
    }
  },
  "kn": {
    "ios": {
      "currency": "INR",
      "amount": 499.0
    },
    "android": {
      "currency": "INR",
      "amount": 99.0
    }
  },
  "mr": {
    "ios": {
      "currency": "INR",
      "amount": 499.0
    },
    "android": {
      "currency": "INR",
      "amount": 99.0
    }
  },
  "pl": {
    "ios": {
      "currency": "PLN",
      "amount": 24.99
    },
    "android": {
      "currency": "PLN",
      "amount": 22.99
    }
  },
  "pt": {
    "ios": {
      "currency": "BRL",
      "amount": 29.9
    },
    "android": {
      "currency": "BRL",
      "amount": 25.99
    }
  },
  "pa": {
    "ios": {
      "currency": "INR",
      "amount": 499.0
    },
    "android": {
      "currency": "INR",
      "amount": 99.0
    }
  },
  "ro": {
    "ios": {
      "currency": "RON",
      "amount": 29.99
    },
    "android": {
      "currency": "RON",
      "amount": 26.99
    }
  },
  "ru": {
    "ios": {
      "currency": "RUB",
      "amount": 449.0
    },
    "android": {
      "currency": "RUB",
      "amount": 419.0
    }
  },
  "sv": {
    "ios": {
      "currency": "SEK",
      "amount": 69.0
    },
    "android": {
      "currency": "SEK",
      "amount": 59.0
    }
  },
  "ta": {
    "ios": {
      "currency": "INR",
      "amount": 499.0
    },
    "android": {
      "currency": "INR",
      "amount": 99.0
    }
  },
  "te": {
    "ios": {
      "currency": "INR",
      "amount": 499.0
    },
    "android": {
      "currency": "INR",
      "amount": 99.0
    }
  },
  "th": {
    "ios": {
      "currency": "THB",
      "amount": 199.0
    },
    "android": {
      "currency": "THB",
      "amount": 175.0
    }
  },
  "zhHant": {
    "ios": {
      "currency": "TWD",
      "amount": 150.0
    },
    "android": {
      "currency": "TWD",
      "amount": 170.0
    }
  },
  "tr": {
    "ios": {
      "currency": "TRY",
      "amount": 249.99
    },
    "android": {
      "currency": "TRY",
      "amount": 284.99
    }
  },
  "uk": {
    "ios": {
      "currency": "USD",
      "amount": 5.99
    },
    "android": {
      "currency": "UAH",
      "amount": 264.99
    }
  },
  "ur": {
    "ios": {
      "currency": "PKR",
      "amount": 1300.0
    },
    "android": {
      "currency": "PKR",
      "amount": 399.0
    }
  },
  "vi": {
    "ios": {
      "currency": "VND",
      "amount": 149000.0
    },
    "android": {
      "currency": "VND",
      "amount": 130000.0
    }
  },
  "ms": {
    "ios": {
      "currency": "MYR",
      "amount": 22.9
    },
    "android": {
      "currency": "MYR",
      "amount": 21.99
    }
  },
  "zu": {
    "ios": {
      "currency": "ZAR",
      "amount": 99.99
    },
    "android": {
      "currency": "ZAR",
      "amount": 49.99
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
