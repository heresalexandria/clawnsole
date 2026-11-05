// Published APIPod catalog pricing dimensions, checked 2026-11-05.
// Source: https://www.apipod.ai/models and https://www.apipod.ai/pricing.md.
const apipodPricingDimensions = <String, Map<String, Object?>>{
  "gemini-omni-flash-1.1-lite-r2v": {
    "base_price": 0.3,
    "linear_dimensions": {},
    "discrete_dimensions": {
      "resolution": {"720P": 1, "720p": 1, "1080P": 1.5, "1080p": 1.5},
    },
  },
  "gemini-omni-flash-1.1-lite-i2v": {
    "base_price": 0.3,
    "linear_dimensions": {},
    "discrete_dimensions": {
      "resolution": {"720P": 1, "720p": 1, "1080P": 1.5, "1080p": 1.5},
    },
  },
  "gemini-omni-flash-1.1-lite-t2v": {
    "base_price": 0.3,
    "linear_dimensions": {},
    "discrete_dimensions": {
      "resolution": {"720P": 1, "720p": 1, "1080P": 1.5, "1080p": 1.5},
    },
  },
  "muse-video-r2v": {
    "base_price": 1,
    "linear_dimensions": {},
    "discrete_dimensions": {
      "duration": {
        "5": 0.15,
        "10": 0.2,
        "20": 0.3,
        "30": 0.3,
        "40": 0.4,
        "50": 0.5,
        "60": 0.6,
      },
    },
  },
  "muse-video-i2v": {
    "base_price": 1,
    "linear_dimensions": {},
    "discrete_dimensions": {
      "duration": {
        "5": 0.15,
        "10": 0.2,
        "20": 0.3,
        "30": 0.3,
        "40": 0.4,
        "50": 0.5,
        "60": 0.6,
      },
    },
  },
  "muse-video-t2v": {
    "base_price": 1,
    "linear_dimensions": {},
    "discrete_dimensions": {
      "duration": {
        "5": 0.15,
        "10": 0.2,
        "20": 0.3,
        "30": 0.3,
        "40": 0.4,
        "50": 0.5,
        "60": 0.6,
      },
    },
  },
  "minimax-h3-lite-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.04},
    "discrete_dimensions": {
      "resolution": {"2K": 1.55, "768P": 1},
    },
  },
  "kling-4.0-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.085},
    "discrete_dimensions": {
      "price_tier": {
        "720p-basic": 1.68,
        "1080p-basic": 2.5,
        "720p-enhanced": 1,
        "1080p-enhanced": 1.5,
      },
    },
  },
  "kling-4.0-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.145},
    "discrete_dimensions": {
      "resolution": {"720p": 1, "1080p": 1.5},
    },
  },
  "kling-4.0-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.145},
    "discrete_dimensions": {
      "resolution": {"720p": 1, "1080p": 1.5},
    },
  },
  "kling-3.0-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.08},
    "discrete_dimensions": {
      "price_tier": {
        "4k": 5,
        "720p-audio": 1.5,
        "1080p-audio": 2,
        "720p-silent": 1,
        "1080p-silent": 1.5,
      },
    },
  },
  "kling-3.0-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.08},
    "discrete_dimensions": {
      "price_tier": {
        "4k": 5,
        "720p-audio": 1.5,
        "1080p-audio": 2,
        "720p-silent": 1,
        "1080p-silent": 1.5,
      },
    },
  },
  "wan3.0-prime-spicy-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-prime-spicy-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-prime-spicy-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-pro-spicy-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.2},
    "discrete_dimensions": {
      "resolution": {
        "2K": 1.2,
        "2k": 1.2,
        "4K": 1.5,
        "4k": 1.5,
        "1080P": 1,
        "1080p": 1,
      },
    },
  },
  "wan3.0-pro-spicy-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.2},
    "discrete_dimensions": {
      "resolution": {
        "2K": 1.2,
        "2k": 1.2,
        "4K": 1.5,
        "4k": 1.5,
        "1080P": 1,
        "1080p": 1,
      },
    },
  },
  "wan3.0-pro-spicy-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.2},
    "discrete_dimensions": {
      "resolution": {
        "2K": 1.2,
        "2k": 1.2,
        "4K": 1.5,
        "4k": 1.5,
        "1080P": 1,
        "1080p": 1,
      },
    },
  },
  "wan3.0-spicy-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.06},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-spicy-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.06},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-spicy-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.06},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "seedance-2.0-x-t2v": {"base_price": 0.75},
  "seedance-2.0-x-r2v": {"base_price": 0.75},
  "seedance-2.5-draft": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.098},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "seedance-2.0-spicy-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.065},
    "discrete_dimensions": {
      "resolution": {"4k": 11.5, "480p": 1, "720p": 2, "1080p": 5},
      "video_count": {"1": 0.6, "2": 0.6, "3": 0.6},
    },
  },
  "seedance-2.5-spicy-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
    },
  },
  "seedance-2.5-spicy-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
    },
  },
  "seedance-2.5-spicy-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "seedance-2.5-spicy-edit": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "seedance-2.5-spicy-extend": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "gemini-omni-flash-1.1-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.06},
    "discrete_dimensions": {
      "resolution": {"4k": 2, "360p": 1, "720p": 1, "1080p": 1},
    },
  },
  "gemini-omni-flash-1.1-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.06},
    "discrete_dimensions": {
      "resolution": {"4k": 2, "480p": 1, "720p": 1, "1080p": 1},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "gemini-omni-flash-1.1-extend": {
    "base_price": 0.8,
    "discrete_dimensions": {
      "resolution": {"4k": 1.5, "360p": 1, "720p": 1, "1080p": 1},
    },
  },
  "seedance-2.5-edit": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.098},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "seedance-2.5-extend": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.098},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "minimax-h3-max-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.05},
    "discrete_dimensions": {
      "resolution": {"480P": 1, "480p": 1, "768P": 1.6, "768p": 1.6},
    },
  },
  "minimax-h3-max-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.05},
    "discrete_dimensions": {
      "resolution": {"480P": 1, "480p": 1, "768P": 1.6, "768p": 1.6},
    },
  },
  "wan3.0-prime-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.07},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-prime-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.07},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-prime-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.07},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "seedance-2.5-lite-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.15},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "seedance-2.5-lite-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.15},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
    },
  },
  "seedance-2.5-lite-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.15},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
    },
  },
  "seedance-2.0-mini-lite-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.02},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
      "video_count": {"1": 0.6, "2": 0.6, "3": 0.6},
    },
  },
  "seedance-2.0-mini-lite-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.02},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
    },
  },
  "seedance-2.0-mini-lite-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.02},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
    },
  },
  "seedance-2.0-fast-lite-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.07},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
      "video_count": {"1": 0.6, "2": 0.6, "3": 0.6},
    },
  },
  "seedance-2.0-fast-lite-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.07},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
    },
  },
  "seedance-2.0-fast-lite-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.07},
    "discrete_dimensions": {
      "resolution": {"720p": 1},
    },
  },
  "seedance-2.5-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.098},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
      "video_count": {
        "1": 0.6,
        "2": 0.6,
        "3": 0.6,
        "4": 0.6,
        "5": 0.6,
        "6": 0.6,
        "7": 0.6,
        "8": 0.6,
        "9": 0.6,
        "10": 0.6,
      },
    },
  },
  "seedance-2.5-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.098},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
    },
  },
  "seedance-2.5-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.098},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2.25, "1080p": 5.53},
    },
  },
  "seedance-2.0-lite-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.085},
    "discrete_dimensions": {
      "resolution": {"720p": 1, "1080p": 2},
      "video_count": {"1": 0.6, "2": 0.6, "3": 0.6},
    },
  },
  "seedance-2.0-lite-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.085},
    "discrete_dimensions": {
      "resolution": {"720p": 1, "1080p": 2},
    },
  },
  "seedance-2.0-lite-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.085},
    "discrete_dimensions": {
      "resolution": {"720p": 1, "1080p": 2},
    },
  },
  "minimax-h3-lite-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.04},
    "discrete_dimensions": {
      "resolution": {"2K": 1.55, "768P": 1},
    },
  },
  "minimax-h3-lite-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.04},
    "discrete_dimensions": {
      "resolution": {"2K": 1.55, "768P": 1},
    },
  },
  "wan3.0-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.045},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.045},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "wan3.0-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.045},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 4,
        "1080p": 4,
      },
    },
  },
  "minimax-h3-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.09},
    "discrete_dimensions": {
      "resolution": {"2K": 1.55, "768P": 1},
    },
  },
  "minimax-h3-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.09},
    "discrete_dimensions": {
      "resolution": {"2K": 1.55, "768P": 1},
    },
  },
  "minimax-h3-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.09},
    "discrete_dimensions": {
      "resolution": {"2K": 1.55, "768P": 1},
    },
  },
  "grok-imagine-1.5-vip": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.055},
    "discrete_dimensions": {
      "resolution": {
        "480P": 1,
        "480p": 1,
        "720P": 2,
        "720p": 2,
        "1080P": 3.2,
        "1080p": 3.2,
      },
    },
  },
  "grok-imagine-1.5-fast": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.018},
    "discrete_dimensions": {},
  },
  "seedance-2.0-mini-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.025},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
      "video_count": {"1": 0.6, "2": 0.6, "3": 0.6},
    },
  },
  "seedance-2.0-mini-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.025},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
    },
  },
  "seedance-2.0-mini-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.025},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
    },
  },
  "gemini-omni-r2v": {"base_price": 0.25},
  "gemini-omni-extend": {"base_price": 0.25},
  "grok-imagine-1.5-preview": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.02},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
    },
  },
  "gemini-omni-i2v": {"base_price": 0.25},
  "seedance-2.0-fast-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.045},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
      "video_count": {"1": 0.6, "2": 0.6, "3": 0.6},
    },
  },
  "seedance-2.0-fast-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.045},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
    },
  },
  "seedance-2.0-fast-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.045},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
    },
  },
  "veo3-1-lite-4k": {"base_price": 0.4},
  "veo3-1-lite": {
    "base_price": 0.08,
    "discrete_dimensions": {
      "resolution": {"720p": 1, "1080p": 1.5},
    },
  },
  "wan2.7-videoedit": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {"720P": 1, "1080P": 1.5},
    },
  },
  "wan2.7-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {"720P": 1, "1080P": 1.5},
    },
  },
  "wan2.7-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.1},
    "discrete_dimensions": {
      "resolution": {"720P": 1, "1080P": 1.5},
    },
  },
  "seedance-2.0-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.063},
    "discrete_dimensions": {
      "resolution": {"4k": 11.5, "480p": 1, "720p": 2, "1080p": 5},
    },
  },
  "seedance-2.0-r2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.063},
    "discrete_dimensions": {
      "resolution": {"4k": 11.5, "480p": 1, "720p": 2, "1080p": 5},
      "video_count": {"1": 0.6, "2": 0.6, "3": 0.6},
    },
  },
  "seedance-2.0-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.063},
    "discrete_dimensions": {
      "resolution": {"4k": 11.5, "480p": 1, "720p": 2, "1080p": 5},
    },
  },
  "kling-2.6-motion-control": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.07},
    "discrete_dimensions": {
      "quality": {"pro": 1.5, "std": 1},
    },
  },
  "grok-imagine-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.018},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
    },
  },
  "grok-imagine-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.018},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2},
    },
  },
  "seedance-1.0-lite-i2v-ref": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.02},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 3, "1080p": 6},
    },
  },
  "motion-control-m1": {"base_price": 1},
  "seedance-1.0-lite-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.02},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 3, "1080p": 6},
    },
  },
  "seedance-1.0-lite-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.02},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 3, "1080p": 6},
    },
  },
  "seedance-1.0-pro-fast-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.012},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2, "1080p": 4},
    },
  },
  "seedance-1.0-pro-fast-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.012},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2, "1080p": 4},
    },
  },
  "seedance-1.0-pro-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.03},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2, "1080p": 4},
    },
  },
  "seedance-1.0-pro-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.03},
    "discrete_dimensions": {
      "resolution": {"480p": 1, "720p": 2, "1080p": 4},
    },
  },
  "veo3-1-quality-4k": {"base_price": 1.2},
  "veo3-1-fast-4k": {
    "base_price": 0.54,
    "linear_dimensions": {},
    "discrete_dimensions": {},
  },
  "veo3-1-fast-ref": {
    "base_price": 0.18,
    "discrete_dimensions": {
      "resolution": {"4k": 3, "720p": 1, "1080p": 1.25},
    },
  },
  "veo3-1-quality": {
    "base_price": 0.8,
    "discrete_dimensions": {
      "resolution": {"4k": 1.5, "720p": 1, "1080p": 1.25},
    },
  },
  "veo3-1-fast": {
    "base_price": 0.18,
    "discrete_dimensions": {
      "resolution": {"4k": 3, "720p": 1, "1080p": 1.25},
    },
  },
  "seedance-2.0-spicy-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.065},
    "discrete_dimensions": {
      "resolution": {"4k": 11.5, "480p": 1, "720p": 2, "1080p": 5},
    },
  },
  "seedance-2.0-spicy-i2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.065},
    "discrete_dimensions": {
      "resolution": {"4k": 11.5, "480p": 1, "720p": 2, "1080p": 5},
    },
  },
  "gemini-omni-flash-1.1-t2v": {
    "base_price": 0,
    "linear_dimensions": {"duration": 0.06},
    "discrete_dimensions": {
      "resolution": {"4k": 2, "360p": 1, "720p": 1, "1080p": 1},
    },
  },
  "gemini-omni-t2v": {"base_price": 0.25},
};
