/// Dates as words, with `intl`'s `DateFormat` and the locale's CLDR data
/// (owner's decision 24, 2026-11-08). A moment is formatted as its clock
/// face in its own zone; a date or a time as written — `DateFormat` is
/// handed a UTC `DateTime` of those fields, where nothing can shift.
///
/// Formats are ICU skeletons (`yMMMMd`, `MMMd`, `jm`, `EEEE`…): the locale
/// orders the fields and adds its words. The wording may differ slightly
/// from a browser's `Intl.DateTimeFormat` (another copy of CLDR).
library;

import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/date_symbol_data_local.dart' as data;
import 'package:intl/date_time_patterns.dart' as patterns;
import 'package:intl/intl.dart';

import '../calendars/hijri.dart';
import '../time/plain.dart';
import '../zone/zoned.dart';
import 'week_data.g.dart';

/// Every locale `intl` carries, read once (`dateTimeSymbolMap` builds the map on each call).
final _symbols = data.dateTimeSymbolMap();
final _patterns = patterns.dateTimePatternMap();

bool _loaded(String locale) {
  try {
    return DateFormat.localeExists(locale);
  } catch (_) {
    return false; // intl's maps not made yet
  }
}

/// [locale]'s data added to `intl`'s global maps when they lack it — and
/// only then: data already there (Flutter's `flutter_localizations` loads
/// its own) is never replaced, so the order the two load in does not matter.
/// A locale both carry formats with the data loaded first (Flutter's, in an
/// app: its `ar` writes Arabic-Indic digits).
void _ensure(String locale) {
  if (_loaded(locale)) return;
  final sym = _symbols[locale];
  final pat = _patterns[locale];
  if (sym == null || pat == null) return;
  initializeDateFormattingCustom(locale: locale, symbols: sym, patterns: pat);
}

/// The locale `intl` formats [locale] with: the tag itself (`ar_DZ`), else
/// its language (`fr_MA` → `fr`), else English — the last said by
/// [formatLocale] as a guess.
String _verified(String locale) => formatLocale(locale).used;

final _cachedLocales = <String, ({String used, bool exact})>{};

/// Which of `intl`'s locales formats [locale], and whether it is the tag or
/// its language ([exact]: false when nothing of it is known and English is
/// used — a guess the kernel reports).
({String used, bool exact}) formatLocale(String locale) => _cachedLocales[locale] ??= () {
  final parts = locale.replaceAll('-', '_').split('_');
  final lang = parts.first.toLowerCase();
  final region = parts.skip(1).where((p) => _region.hasMatch(p)).map((p) => p.toUpperCase()).firstOrNull;
  for (final c in [?(region == null ? null : '${lang}_$region'), lang]) {
    if (_symbols.containsKey(c)) {
      _ensure(c);
      return (used: c, exact: true);
    }
  }
  _ensure('en');
  return (used: 'en', exact: false);
}();

/// The skeletons `intl` knows (`yMMMMd`, `MMMd`, `jm`, `EEEE`…): anything
/// else would be read as a literal pattern ("EEEd" → "dim.15").
Set<String> get dateSkeletons => _patterns['en']!.keys.toSet();

/// Throws an [ArgumentError] when [skeleton] is not one of [dateSkeletons]
/// (configuration: said when given).
void checkSkeleton(String skeleton) {
  if (!_patterns['en']!.containsKey(skeleton)) {
    throw ArgumentError.value(skeleton, 'skeleton', 'not one of intl\'s date skeletons (${dateSkeletons.join(', ')})');
  }
}

final _formats = <String, DateFormat>{};

DateFormat _format(String skeleton, String locale) {
  final loc = _verified(locale);
  final key = '$loc|$skeleton';
  final f = _formats[key];
  if (f != null) return f;
  if (_formats.length > 500) _formats.clear();
  return _formats[key] = DateFormat(skeleton, loc);
}

/// The fields to print, as a UTC `DateTime`.
DateTime _fields(Object v) {
  final PlainDateTime w = switch (v) {
    ZonedDateTime() => v.plainDateTime,
    PlainDateTime() => v,
    PlainDate() => PlainDateTime(v, PlainTime.midnight),
    PlainTime() => PlainDateTime(PlainDate(1970, 1, 1), v),
    _ => throw ArgumentError.value(v, 'v', 'a ZonedDateTime, PlainDateTime, PlainDate or PlainTime'),
  };
  final d = w.date;
  final t = w.time;
  return DateTime.utc(d.year, d.month, d.day, t.hour, t.minute, t.second, t.millisecond);
}

/// [v] (a [ZonedDateTime], [PlainDateTime], [PlainDate], [PlainTime] or
/// [HijriDate]) in [locale], by an ICU [skeleton]. Throws an
/// [ArgumentError] for any other value (the caller's).
String formatTemporal(Object v, String skeleton, String locale) =>
    v is HijriDate ? _formatHijri(v, skeleton, locale) : _format(skeleton, locale).format(_fields(v));

// ——— the Hijri calendar (owner's decision 53) ———

/// The months' names, CLDR's (`islamic` calendar, format forms), for the
/// languages the widgets speak; any other language gets the English ones.
const _hijriMonths = <String, List<List<String>>>{
  'en': [
    [
      'Muharram', 'Safar', 'Rabiʻ I', 'Rabiʻ II', 'Jumada I', 'Jumada II', //
      'Rajab', 'Shaʻban', 'Ramadan', 'Shawwal', 'Dhuʻl-Qiʻdah', 'Dhuʻl-Hijjah',
    ],
    [
      'Muh.', 'Saf.', 'Rab. I', 'Rab. II', 'Jum. I', 'Jum. II', //
      'Raj.', 'Sha.', 'Ram.', 'Shaw.', 'Dhuʻl-Q.', 'Dhuʻl-H.',
    ],
  ],
  'fr': [
    [
      'mouharram', 'safar', 'rabia al awal', 'rabia ath-thani', 'joumada al oula', 'joumada ath-thania', //
      'rajab', 'chaabane', 'ramadan', 'chawwal', 'dhou al qi`da', 'dhou al-hijja',
    ],
    [
      'mouh.', 'saf.', 'rab. aw.', 'rab. th.', 'joum. oul.', 'joum. tha.', //
      'raj.', 'chaa.', 'ram.', 'chaw.', 'dhou. q.', 'dhou. h.',
    ],
  ],
  'ar': [
    [
      'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', //
      'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
    ],
    [
      'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', //
      'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
    ],
  ],
};

/// The era after a year: "1447 AH", "١٤٤٧ هـ".
const _hijriEra = {'en': 'AH', 'fr': 'AH', 'ar': 'هـ'};

String _language(String locale) => locale.split(RegExp('[-_]')).first.toLowerCase();

/// The Hijri month names of [locale] (English for a language without them).
List<String> hijriMonthNames(String locale, {bool short = false}) {
  final names = _hijriMonths[_language(_verified(locale))] ?? _hijriMonths['en']!;
  return names[short ? 1 : 0];
}

final _zeros = <String, int>{};
final _digit = RegExp(r'\p{Nd}', unicode: true);

/// [n] in [locale]'s digits (Arabic-Indic where its dates use them).
String _digits(int n, String locale, {int width = 1}) {
  final loc = _verified(locale);
  // The 0 of "10" as the locale writes the 10th ("10", "١٠", "10日").
  final zero = _zeros[loc] ??= () {
    final ten = _format('d', loc).format(DateTime.utc(2024, 1, 10));
    final digits = _digit.allMatches(ten).toList();
    return digits.length < 2 ? 0x30 : digits[1][0]!.runes.first;
  }();
  final text = n.toString().padLeft(width, '0');
  if (zero == 0x30) return text;
  return String.fromCharCodes([for (final c in text.runes) c >= 0x30 && c <= 0x39 ? zero + c - 0x30 : c]);
}

final _patternRun = RegExp(r"'(?:[^']|'')*'|([A-Za-z])\1*|[^'A-Za-z]+");

/// A pattern's runs, read once per locale and skeleton: a field (its
/// letter) or literal text.
final _runs = <String, List<({String text, String? letter})>>{};

/// [v] by [skeleton] in [locale]: the locale's pattern for the skeleton (its
/// order and words), the year, month and day fields Hijri, the weekday and
/// the time the Gregorian day's; the era after the year.
String _formatHijri(HijriDate v, String skeleton, String locale) {
  final loc = _verified(locale);
  final runs = _runs['$loc|$skeleton'] ??= () {
    if (_runs.length > 500) _runs.clear();
    final pattern = _format(skeleton, locale).pattern ?? skeleton;
    return [
      for (final m in _patternRun.allMatches(pattern))
        if (m[0]!.startsWith("'"))
          (text: m[0]!.length == 2 ? "'" : m[0]!.substring(1, m[0]!.length - 1).replaceAll("''", "'"), letter: null)
        else
          (text: m[0]!, letter: m[1]),
    ];
  }();
  final lang = _language(loc);
  final hasEra = runs.any((r) => r.letter == 'G');
  final era = _hijriEra[lang] ?? _hijriEra['en']!;
  final greg = _fields(v.date);
  final out = StringBuffer();
  var eraDue = false;
  for (final r in runs) {
    final run = r.text;
    final letter = r.letter;
    // The era after the year and what is glued to it ("1447年 AH", not "1447 AH年").
    if (eraDue && (letter != null || run.startsWith(RegExp(r'\s')))) {
      out.write(' $era');
      eraDue = false;
    }
    if (letter == null) {
      out.write(run);
      continue;
    }
    final n = run.length;
    switch (letter) {
      case 'y' || 'Y' || 'u':
        out.write(_digits(v.year, loc, width: n == 2 ? 2 : 1));
        eraDue = !hasEra;
      case 'G':
        out.write(era);
      case 'M' || 'L':
        out.write(switch (n) {
          1 || 2 => _digits(v.month, loc, width: n),
          3 => hijriMonthNames(loc, short: true)[v.month - 1],
          5 => hijriMonthNames(loc)[v.month - 1].characters1,
          _ => hijriMonthNames(loc)[v.month - 1],
        });
      case 'd':
        out.write(_digits(v.day, loc, width: n));
      default:
        // The weekday: the Gregorian day's own (a Hijri date has no time).
        out.write(_format(run, loc).format(greg));
    }
  }
  if (eraDue) out.write(' $era');
  return out.toString();
}

extension on String {
  /// The first character (a narrow month name).
  String get characters1 => isEmpty ? this : String.fromCharCode(runes.first);
}

final _token = RegExp(r'\p{Nd}+|[\p{L}\p{M}]+|[^\p{Nd}\p{L}\p{M}]+', unicode: true);

/// "15–21 mars 2026", "Mar 30 – Apr 5, 2026", "Dec 28, 2026 – Jan 3, 2027":
/// both ends formatted, what they share at the start and the end said once.
/// Both ends Hijri ([HijriDate]) or neither (an [ArgumentError] else).
/// `intl` has no range formats (the browser's `formatRange`): the shared
/// words are found token by token, so a locale's own range pattern may
/// differ slightly.
/// Ends given the wrong way round still make a readable title.
String formatRangeTitle(Object a, Object b, String skeleton, String locale, {String separator = '–'}) {
  final String left;
  final String right;
  if (a is HijriDate || b is HijriDate) {
    if (a is! HijriDate || b is! HijriDate) throw ArgumentError('both ends Hijri, or neither');
    final (x, y) = b.compareTo(a) < 0 ? (b, a) : (a, b);
    left = _formatHijri(x, skeleton, locale);
    right = _formatHijri(y, skeleton, locale);
  } else {
    final f = _format(skeleton, locale);
    var x = _fields(a);
    var y = _fields(b);
    if (y.isBefore(x)) (x, y) = (y, x);
    left = f.format(x);
    right = f.format(y);
  }
  if (left == right) return left;
  final ta = [for (final m in _token.allMatches(left)) m[0]!];
  final tb = [for (final m in _token.allMatches(right)) m[0]!];
  var p = 0;
  while (p < ta.length && p < tb.length && ta[p] == tb[p]) {
    p++;
  }
  var s = 0;
  while (s < ta.length - p && s < tb.length - p && ta[ta.length - 1 - s] == tb[tb.length - 1 - s]) {
    s++;
  }
  // A shared end starting with the point of an abbreviation ("janv." and
  // "févr." share ".") gives the point back: each keeps its own.
  while (s > 0 && ta.length - s > p && ta[ta.length - s].startsWith('.') && _isWord(ta[ta.length - s - 1])) {
    s--;
  }
  // A shared stretch must hold a word or a number: separators alone are not shared.
  bool meaningful(Iterable<String> ts) => ts.any((t) => _isWord(t));
  if (!meaningful(ta.take(p))) p = 0;
  if (!meaningful(ta.skip(ta.length - s))) s = 0;
  final prefix = ta.take(p).join();
  final suffix = ta.skip(ta.length - s).join();
  final midA = ta.sublist(p, ta.length - s).join();
  final midB = tb.sublist(p, tb.length - s).join();
  // One field on each side ("15–21"): a bare dash; whole dates: spaced.
  final short = !midA.trim().contains(' ') && !midB.trim().contains(' ');
  final dash = short ? separator : ' $separator ';
  // The dash replaces the space either side of it; the space before what is shared stays.
  return '$prefix${midA.trimRight()}$dash${midB.trimLeft()}$suffix';
}

bool _isWord(String t) => RegExp(r'[\p{Nd}\p{L}]', unicode: true).hasMatch(t);

enum NameWidth { narrow, short, long }

/// Monday 1 January 2024: a known Monday.
final _monday = PlainDate(2024, 1, 1);

/// The weekdays' names from [firstDay] (ISO 1–7), standalone forms.
List<String> weekdayNames(String locale, NameWidth width, int firstDay) {
  final skeleton = switch (width) {
    NameWidth.narrow => 'ccccc',
    NameWidth.short => 'ccc',
    NameWidth.long => 'cccc',
  };
  return [for (var i = 0; i < 7; i++) formatTemporal(_monday.addDays((firstDay - 1 + i) % 7), skeleton, locale)];
}

/// The months' names, standalone forms (`LLLL`: "janvier", not "de janvier").
List<String> monthNames(String locale, NameWidth width) {
  final skeleton = switch (width) {
    NameWidth.narrow => 'LLLLL',
    NameWidth.short => 'LLL',
    NameWidth.long => 'LLLL',
  };
  return [for (var m = 1; m <= 12; m++) formatTemporal(PlainDate(2024, m, 1), skeleton, locale)];
}

/// A locale's week: its first day (ISO 1–7) and the days of the new year a
/// week needs to be week 1 (4 under ISO, 1 in the US).
final class WeekRules {
  const WeekRules({required this.firstDay, required this.minimalDays});
  final int firstDay;
  final int minimalDays;

  static const iso = WeekRules(firstDay: 1, minimalDays: 4);

  @override
  bool operator ==(Object other) =>
      other is WeekRules && other.firstDay == firstDay && other.minimalDays == minimalDays;

  @override
  int get hashCode => Object.hash(firstDay, minimalDays);

  @override
  String toString() => 'WeekRules(first $firstDay, $minimalDays days)';
}

/// Regions whose week 1 needs four days of the new year (CLDR `minDays`
/// 4); everywhere else, the week holding 1 January is week 1. The web's own
/// list (its engine leaves `minimalDays` out).
const _fourDayRegions = {
  'AD', 'AN', 'AT', 'AX', 'BE', 'BG', 'CH', 'CZ', 'DE', 'DK', 'EE', 'ES', 'FI', 'FJ', 'FO', 'FR', 'GB', //
  'GF', 'GG', 'GI', 'GP', 'GR', 'HU', 'IE', 'IM', 'IS', 'IT', 'JE', 'LI', 'LT', 'LU', 'MC', 'MQ', 'NL', //
  'NO', 'PL', 'PT', 'RE', 'RU', 'SE', 'SJ', 'SK', 'SM', 'VA',
};

final _region = RegExp(r'^[A-Za-z]{2}$|^\d{3}$');
final _script = RegExp(r'^[A-Za-z]{4}$');

/// The region a tag names (`ar-SA` → SA), else its language's likely one
/// (`ar` → EG, `zh-Hant` → TW), as CLDR's likely subtags say; null when
/// neither is known.
String? _regionOf(String locale) {
  final parts = locale.replaceAll('_', '-').split('-');
  if (parts.isEmpty || parts.first.isEmpty) return null;
  final lang = parts.first.toLowerCase();
  String? script;
  for (final p in parts.skip(1)) {
    if (_region.hasMatch(p)) return p.toUpperCase();
    if (_script.hasMatch(p)) script ??= '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}';
  }
  return (script == null ? null : likelyRegion['$lang-$script']) ?? likelyRegion[lang];
}

/// The locale's week rules, from CLDR as the web reads them (its engine's
/// week info and likely subtags): the first day of the region the tag names,
/// or of its language's likely region — `ar-SA` starts on Sunday, `ar-DZ` on
/// Saturday, `fr` on Monday; week 1 by the region's rule. An unknown region:
/// Monday, and the week holding 1 January.
WeekRules weekRulesFor(String locale) {
  final region = _regionOf(locale);
  if (region == null) return const WeekRules(firstDay: 1, minimalDays: 1);
  return WeekRules(firstDay: weekFirstDay[region] ?? 1, minimalDays: _fourDayRegions.contains(region) ? 4 : 1);
}

PlainDate _startOfWeek(PlainDate d, int firstDay) => d.addDays(-((d.dayOfWeek - firstDay + 7) % 7));

/// The first day of week 1 of [year] under these rules.
PlainDate _week1Start(int year, WeekRules r) {
  final jan1 = PlainDate(year, 1, 1);
  final start = _startOfWeek(jan1, r.firstDay);
  final daysInYear = 7 - start.daysUntil(jan1);
  return daysInYear >= r.minimalDays ? start : start.addDays(7);
}

/// The week number of a date under a locale's rules: ISO (Monday, 4 days),
/// the US (Sunday, 1 day) and every other combination. A date before week 1
/// belongs to the previous year's last week; one on or after next year's
/// week 1 is week 1.
int weekNumber(PlainDate date, WeekRules r) {
  final next = _week1Start(date.year + 1, r);
  if (!date.isBefore(next)) return 1;
  var start = _week1Start(date.year, r);
  if (date.isBefore(start)) start = _week1Start(date.year - 1, r);
  return start.daysUntil(date) ~/ 7 + 1;
}
