/// Coarse classification of a printer's Chinese character ROM, derived from
/// the GS I 0x45 ("font of language") query response. The raw string lives on
/// [DeviceInfo.language]; this enum is what business logic should branch on
/// when choosing text vs image print path.
enum ChineseRom {
  /// Traditional Chinese (HK/TW market). Caller can send Big5-encoded text.
  traditional,

  /// Simplified Chinese (mainland market). Caller can send GBK/GB18030 text.
  simplified,

  /// Anything else — printer didn't implement GS I 0x45, responded with
  /// empty string, or reported a non-Chinese ROM (JIS, KSC, etc). Caller
  /// must fall back to image printing to be safe.
  unknown,
}

/// Classify a raw GS I 0x45 response into a [ChineseRom] bucket.
///
/// Matching rules (case-insensitive, evaluated in order):
///   1. contains 'BIG5'  → traditional
///   2. contains 'GB'    → simplified
///   3. anything else (null, empty, non-Chinese ROMs) → unknown
ChineseRom classifyLanguage(String? raw) {
  if (raw == null) return ChineseRom.unknown;
  final upper = raw.toUpperCase();
  if (upper.contains('BIG5')) return ChineseRom.traditional;
  if (upper.contains('GB')) return ChineseRom.simplified;
  return ChineseRom.unknown;
}
