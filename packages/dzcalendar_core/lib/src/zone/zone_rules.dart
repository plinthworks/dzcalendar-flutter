import '../time/civil.dart';
import 'posix_rule.dart';
import 'tzdata.g.dart';

/// An IANA zone identifier ("Europe/Paris", "UTC"), or a fixed offset
/// ("+02:00") — never anything else.
typedef ZoneId = String;

/// A zone's offsets over time: which offset holds at an instant, and when it
/// next changes. Everything about zones is built on these two questions, the
/// way the TypeScript core builds on Temporal's `getTimeZoneTransition`.
sealed class ZoneRules {
  const ZoneRules();

  /// The rules for [zone], or null when it names no zone. IANA names and
  /// their links (case aside, as Temporal), "UTC", and fixed offsets of whole
  /// minutes ("+02:00", "+0200", "+02").
  static ZoneRules? of(ZoneId zone) {
    final cached = _cache[zone];
    if (cached != null || _cache.containsKey(zone)) return cached;
    final rules = _lookup(zone);
    if (_cache.length > 512) _cache.clear();
    return _cache[zone] = rules;
  }

  /// [zone] as Temporal names it: an IANA name in its own case
  /// ("europe/paris" → "Europe/Paris"; a link stays a link, "Asia/Calcutta"),
  /// an offset in its extended form ("+0200" → "+02:00"). Null when [zone]
  /// names no zone.
  static ZoneId? normalize(ZoneId zone) {
    if (of(zone) == null) return null;
    if (zone.startsWith('+') || zone.startsWith('-')) return offsetText(parseOffsetMs(zone)!);
    if (tzdataZones.containsKey(zone) || tzdataLinks.containsKey(zone)) return zone;
    return _lower[zone.toLowerCase()];
  }

  /// [zone]'s identity: a link resolved to its zone ("Asia/Calcutta" →
  /// "Asia/Kolkata"), an offset in its extended form. What `ZonedDateTime ==`
  /// compares (owner, 2026-11-08: as Temporal's `equals`). Null for no zone.
  static ZoneId? canonical(ZoneId zone) {
    final name = normalize(zone);
    if (name == null) return null;
    return tzdataLinks[name] ?? name;
  }

  /// The IANA release the bundled rules come from ("2026f").
  static String get dataVersion => tzdataVersion;

  /// Milliseconds east of UTC at [epochMs].
  int offsetAt(int epochMs);

  /// The first instant after [epochMs] (strictly) where the offset changes,
  /// or null when it never does again.
  int? nextTransition(int epochMs);
}

final _cache = <String, ZoneRules?>{};
Map<String, String>? _lowerNames;

/// Every name and link, by its lower case: built on the first unusual spelling.
Map<String, String> get _lower => _lowerNames ??= {
  for (final n in [...tzdataZones.keys, ...tzdataLinks.keys]) n.toLowerCase(): n,
};

ZoneRules? _lookup(String zone) {
  if (zone.startsWith('+') || zone.startsWith('-')) {
    // Whole minutes only: Temporal refuses "+01:00:30" as a zone.
    if (!RegExp(r'^[+-]\d{2}(?::?\d{2})?$').hasMatch(zone)) return null;
    final ms = parseOffsetMs(zone);
    return ms == null ? null : FixedOffset(ms);
  }
  var name = zone;
  if (!tzdataZones.containsKey(name) && !tzdataLinks.containsKey(name)) {
    final lower = _lower;
    final found = lower[zone.toLowerCase()];
    if (found == null) return null;
    name = found;
  }
  final canonical = tzdataLinks[name] ?? name;
  return _byCanonical[canonical] ??= TzdbRules._decode(tzdataZones[canonical]!);
}

final _byCanonical = <String, TzdbRules>{};

/// One offset for ever: "+02:00", or a zone that never changed.
final class FixedOffset extends ZoneRules {
  const FixedOffset(this.offsetMs);
  final int offsetMs;

  @override
  int offsetAt(int epochMs) => offsetMs;

  @override
  int? nextTransition(int epochMs) => null;
}

/// A zone of the bundled IANA data: its listed transitions, then its POSIX
/// rule for the years after the last one.
final class TzdbRules extends ZoneRules {
  TzdbRules._(this._initial, this._times, this._offsets, this._ruleFrom, this._rule);

  /// See `tool/encode_tzdata.dart` for the format.
  factory TzdbRules._decode(String data) {
    final [list, from, footer] = data.split('|');
    final parts = list.split(';');
    final initial = int.parse(parts[0], radix: 36) * msPerSecond;
    final times = <int>[];
    final offsets = <int>[];
    var t = 0;
    for (var i = 1; i < parts.length; i++) {
      final comma = parts[i].indexOf(',');
      t += int.parse(parts[i].substring(0, comma), radix: 36);
      times.add(t * msPerSecond);
      offsets.add(int.parse(parts[i].substring(comma + 1), radix: 36) * msPerSecond);
    }
    final ruleFrom = from.isEmpty ? null : int.parse(from, radix: 36) * msPerSecond;
    return TzdbRules._(initial, times, offsets, ruleFrom, PosixRule.tryParse(footer));
  }

  final int _initial;
  final List<int> _times;
  final List<int> _offsets;

  /// The file's last transition, whether or not it changed the offset: the
  /// rule governs from there (RFC 8536 §3.3). Null: the rule governs always.
  final int? _ruleFrom;
  final PosixRule? _rule;

  /// The index of the last listed transition at or before [epochMs], or -1.
  int _indexAt(int epochMs) {
    var lo = 0;
    var hi = _times.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] <= epochMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - 1;
  }

  bool _ruleHolds(int epochMs) => _rule != null && (_ruleFrom == null || epochMs >= _ruleFrom);

  @override
  int offsetAt(int epochMs) {
    if (_ruleHolds(epochMs)) return _ruleOffsetAt(epochMs);
    final i = _indexAt(epochMs);
    return i < 0 ? _initial : _offsets[i];
  }

  @override
  int? nextTransition(int epochMs) {
    final i = _indexAt(epochMs) + 1;
    if (i < _times.length) return _times[i];
    if (_rule == null) return null;
    // Past the list: the rule's changes, skipping any that leave the offset
    // as it was (a rule's end and next start can meet: daylight all year).
    final from = _ruleFrom;
    var after = from == null || epochMs > from ? epochMs : from;
    for (var guard = 0; guard < 8; guard++) {
      final next = _ruleNext(after);
      if (next == null) return null;
      if (offsetAt(next) != offsetAt(next - 1)) return next;
      after = next;
    }
    return null;
  }

  /// The rule's changes around [epochMs]'s year, in order; equal instants keep
  /// the year's order (an end meeting the next year's start leaves daylight on).
  List<(int, int)> _ruleChanges(int epochMs) {
    final (year, _, _) = civilOf(floorDiv(epochMs, msPerDay));
    return [for (var y = year - 1; y <= year + 1; y++) ..._rule!.changesIn(y)];
  }

  int _ruleOffsetAt(int epochMs) {
    final rule = _rule!;
    if (rule.dstOffsetMs == null) return rule.stdOffsetMs;
    var offset = rule.stdOffsetMs;
    for (final (at, after) in _ruleChanges(epochMs)) {
      if (at > epochMs) break;
      offset = after;
    }
    return offset;
  }

  int? _ruleNext(int epochMs) {
    if (_rule!.dstOffsetMs == null) return null;
    for (final (at, _) in _ruleChanges(epochMs)) {
      if (at > epochMs) return at;
    }
    return null;
  }
}
