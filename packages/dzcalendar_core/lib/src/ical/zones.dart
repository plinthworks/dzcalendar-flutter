import '../rrule/iterate.dart';
import '../rrule/rule.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../util/js.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';

/// Windows zone names (Outlook, Exchange) → IANA, from CLDR's windowsZones
/// (territory 001). `*` stands for " Standard Time". The web's table, as is.
const _windowsTable =
    'Dateline*|Etc/GMT+12;UTC-11|Etc/GMT+11;Aleutian*|America/Adak;Hawaiian*|Pacific/Honolulu;'
    'Marquesas*|Pacific/Marquesas;Alaskan*|America/Anchorage;UTC-09|Etc/GMT+9;'
    'Pacific* (Mexico)|America/Tijuana;UTC-08|Etc/GMT+8;Pacific*|America/Los_Angeles;'
    'US Mountain*|America/Phoenix;Mountain* (Mexico)|America/Mazatlan;Mountain*|America/Denver;'
    'Yukon*|America/Whitehorse;Central America*|America/Guatemala;Central*|America/Chicago;'
    'Easter Island*|Pacific/Easter;Central* (Mexico)|America/Mexico_City;Mexico*|America/Mexico_City;'
    'Canada Central*|America/Regina;SA Pacific*|America/Bogota;Eastern* (Mexico)|America/Cancun;'
    'Eastern*|America/New_York;Haiti*|America/Port-au-Prince;Cuba*|America/Havana;'
    'US Eastern*|America/Indiana/Indianapolis;Turks And Caicos*|America/Grand_Turk;'
    'Paraguay*|America/Asuncion;Atlantic*|America/Halifax;Venezuela*|America/Caracas;'
    'Central Brazilian*|America/Cuiaba;SA Western*|America/La_Paz;Pacific SA*|America/Santiago;'
    'Newfoundland*|America/St_Johns;Tocantins*|America/Araguaina;E. South America*|America/Sao_Paulo;'
    'SA Eastern*|America/Cayenne;Argentina*|America/Argentina/Buenos_Aires;Greenland*|America/Nuuk;'
    'Montevideo*|America/Montevideo;Magallanes*|America/Punta_Arenas;Saint Pierre*|America/Miquelon;'
    'Bahia*|America/Bahia;UTC-02|Etc/GMT+2;Mid-Atlantic*|Etc/GMT+2;Azores*|Atlantic/Azores;'
    'Cape Verde*|Atlantic/Cape_Verde;UTC|Etc/UTC;GMT*|Europe/London;Greenwich*|Atlantic/Reykjavik;'
    'Sao Tome*|Africa/Sao_Tome;Morocco*|Africa/Casablanca;W. Europe*|Europe/Berlin;'
    'Central Europe*|Europe/Budapest;Romance*|Europe/Paris;Central European*|Europe/Warsaw;'
    'W. Central Africa*|Africa/Lagos;Jordan*|Asia/Amman;GTB*|Europe/Bucharest;Middle East*|Asia/Beirut;'
    'Egypt*|Africa/Cairo;E. Europe*|Europe/Chisinau;Syria*|Asia/Damascus;West Bank*|Asia/Hebron;'
    'South Africa*|Africa/Johannesburg;FLE*|Europe/Kiev;Israel*|Asia/Jerusalem;South Sudan*|Africa/Juba;'
    'Kaliningrad*|Europe/Kaliningrad;Sudan*|Africa/Khartoum;Libya*|Africa/Tripoli;'
    'Namibia*|Africa/Windhoek;Arabic*|Asia/Baghdad;Turkey*|Europe/Istanbul;Arab*|Asia/Riyadh;'
    'Belarus*|Europe/Minsk;Russian*|Europe/Moscow;E. Africa*|Africa/Nairobi;Volgograd*|Europe/Volgograd;'
    'Iran*|Asia/Tehran;Arabian*|Asia/Dubai;Astrakhan*|Europe/Astrakhan;Azerbaijan*|Asia/Baku;'
    'Russia Time Zone 3|Europe/Samara;Mauritius*|Indian/Mauritius;Saratov*|Europe/Saratov;'
    'Georgian*|Asia/Tbilisi;Caucasus*|Asia/Yerevan;Armenian*|Asia/Yerevan;Afghanistan*|Asia/Kabul;'
    'West Asia*|Asia/Tashkent;Ekaterinburg*|Asia/Yekaterinburg;Pakistan*|Asia/Karachi;'
    'Qyzylorda*|Asia/Qyzylorda;India*|Asia/Kolkata;Sri Lanka*|Asia/Colombo;Nepal*|Asia/Kathmandu;'
    'Central Asia*|Asia/Almaty;Bangladesh*|Asia/Dhaka;Omsk*|Asia/Omsk;Myanmar*|Asia/Yangon;'
    'SE Asia*|Asia/Bangkok;Altai*|Asia/Barnaul;W. Mongolia*|Asia/Hovd;North Asia*|Asia/Krasnoyarsk;'
    'N. Central Asia*|Asia/Novosibirsk;Tomsk*|Asia/Tomsk;China*|Asia/Shanghai;'
    'North Asia East*|Asia/Irkutsk;Singapore*|Asia/Singapore;W. Australia*|Australia/Perth;'
    'Taipei*|Asia/Taipei;Ulaanbaatar*|Asia/Ulaanbaatar;Aus Central W.*|Australia/Eucla;'
    'Transbaikal*|Asia/Chita;Tokyo*|Asia/Tokyo;North Korea*|Asia/Pyongyang;Korea*|Asia/Seoul;'
    'Yakutsk*|Asia/Yakutsk;Cen. Australia*|Australia/Adelaide;AUS Central*|Australia/Darwin;'
    'E. Australia*|Australia/Brisbane;AUS Eastern*|Australia/Sydney;West Pacific*|Pacific/Port_Moresby;'
    'Tasmania*|Australia/Hobart;Vladivostok*|Asia/Vladivostok;Lord Howe*|Australia/Lord_Howe;'
    'Bougainville*|Pacific/Bougainville;Russia Time Zone 10|Asia/Srednekolymsk;Magadan*|Asia/Magadan;'
    'Norfolk*|Pacific/Norfolk;Sakhalin*|Asia/Sakhalin;Central Pacific*|Pacific/Guadalcanal;'
    'Russia Time Zone 11|Asia/Kamchatka;Kamchatka*|Asia/Kamchatka;New Zealand*|Pacific/Auckland;'
    'UTC+12|Etc/GMT-12;Fiji*|Pacific/Fiji;Chatham Islands*|Pacific/Chatham;UTC+13|Etc/GMT-13;'
    'Tonga*|Pacific/Tongatapu;Samoa*|Pacific/Apia;Line Islands*|Pacific/Kiritimati';

final Map<String, String> _windows = {
  for (final e in _windowsTable.split(';'))
    e.split('|')[0].replaceFirst('*', ' Standard Time').toLowerCase(): e.split('|')[1],
};

/// The IANA names in [_windowsTable], in order: which of several zones that
/// agree is preferred (Europe/Berlin rather than Africa/Ceuta).
final List<String> _known = [for (final e in _windowsTable.split(';')) e.split('|')[1]];

/// The IANA zone for a Windows zone name, case-insensitive.
String? windowsZone(String name) => _windows[name.trim().toLowerCase()];

/// One STANDARD or DAYLIGHT block of a VTIMEZONE: from when, from which
/// offset to which (seconds).
final class Observance {
  const Observance({
    required this.start,
    required this.from,
    required this.to,
    required this.rdates,
    required this.standard,
    this.rrule,
  });
  final PlainDateTime start;
  final int from;
  final int to;
  final String? rrule;
  final List<PlainDateTime> rdates;
  final bool standard;
}

final _offsetRe = RegExp(r'^([+-])(\d{2})(\d{2})(\d{2})?$');

/// `+0100`, `-0330`, `+013015` → seconds; null when malformed.
int? offsetSeconds(String v) {
  final m = _offsetRe.firstMatch(v.trim());
  if (m == null) return null;
  final s = int.parse(m[2]!) * 3600 + int.parse(m[3]!) * 60 + int.parse(m[4] ?? '0');
  return m[1] == '-' ? -s : s;
}

String _p2(int n) => n.toString().padLeft(2, '0');

/// Seconds → `+0100` (`+013015` when it has seconds).
String formatOffset(int seconds) {
  final a = seconds.abs();
  final s = a % 60;
  return '${seconds < 0 ? '-' : '+'}${_p2(a ~/ 3600)}${_p2(a ~/ 60 % 60)}${s != 0 ? _p2(s) : ''}';
}

int _utcMs(PlainDateTime wall) => wall.wallMs;

/// The moments a VTIMEZONE changes offset within the years asked, with the
/// offset before and after (seconds); `at` in epoch ms.
List<({int at, int from, int to})> _transitions(List<Observance> obs, int fromYear, int toYear) {
  final out = <({int at, int from, int to})>[];
  final until = _utcMs(PlainDateTime(PlainDate(toYear + 1, 1, 1), PlainTime.midnight));
  final since = _utcMs(PlainDateTime(PlainDate(fromYear, 1, 1), PlainTime.midnight));
  for (final o in obs) {
    // Wall times stepped as if in UTC: pure wall-clock arithmetic.
    final onsets = <PlainDateTime>[o.start, ...o.rdates];
    final text = o.rrule;
    final rule = text == null ? null : parseRRule(text).rule;
    if (rule != null) {
      var n = 0;
      for (final z in iterateZoned(ZonedDateTime(Instant.fromEpochMilliseconds(_utcMs(o.start)), 'UTC'), rule)) {
        if (z.date.year > toYear || ++n > 2000) break;
        onsets.add(z.plainDateTime);
      }
    }
    for (final wall in onsets) {
      final at = _utcMs(wall) - o.from * 1000;
      if (at < until && at >= since) out.add((at: at, from: o.from, to: o.to));
    }
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}

/// The offset (seconds) a VTIMEZONE's own rules give a wall time: what the
/// reader uses when no IANA zone keeps those rules. In a skipped hour, the
/// offset before the change (the wall time is read as if it had not changed
/// yet); in a repeated hour, the first pass.
int offsetIn(List<Observance> obs, PlainDateTime wall) {
  final changes = _transitions(obs, wall.date.year - 1, wall.date.year + 1);
  final std = obs.isEmpty ? 0 : (obs.where((o) => o.standard).firstOrNull ?? obs.first).to;
  int at(int ms) {
    var off = changes.isNotEmpty ? changes.first.from : std;
    for (final c in changes) {
      if (c.at <= ms) off = c.to;
    }
    return off;
  }

  final utc = _utcMs(wall);
  final offsets = {
    std,
    for (final c in changes) ...[c.from, c.to],
  }.toList();
  // Offsets under which the wall time exists; two in a repeated hour (the first pass is the larger), none in a gap.
  final fit = [
    for (final o in offsets)
      if (at(utc - o * 1000) == o) o,
  ];
  return fit.isNotEmpty ? fit.reduce((a, b) => a > b ? a : b) : offsets.reduce((a, b) => a < b ? a : b);
}

List<String>? _candidates;

/// The IANA zone that keeps the same offsets as a VTIMEZONE over the years
/// asked: equal just before and at each of its changes, and mid-January and
/// mid-July of each year. Several zones agree (Paris, Berlin, Madrid…): the
/// one Windows names first for that region wins (Europe/Berlin rather than
/// Africa/Ceuta), then the first by name.
///
/// The candidates are the IANA zones of our data; the web's are its
/// engine's (`Intl.supportedValuesOf`, CLDR's names — `Asia/Calcutta` where
/// IANA says `Asia/Kolkata`), so a tie may be broken differently there.
String? matchObservances(List<Observance> obs, List<int> years) {
  if (obs.isEmpty || years.isEmpty) return null;
  final first = years.reduce((a, b) => a < b ? a : b);
  final last = years.reduce((a, b) => a > b ? a : b);
  final changes = _transitions(obs, first, last);
  // Before any change the years see, the offset is what the earliest observance changed from.
  final latestStart = [...obs]..sort((a, b) => b.start.compareTo(a.start));
  final initial = changes.isNotEmpty ? changes.first.from : latestStart.first.to;
  final samples = <(int, int)>[];
  for (final c in changes) {
    samples
      ..add((c.at - 1000, c.from))
      ..add((c.at, c.to));
  }
  for (final y in years) {
    for (final month in const [1, 7]) {
      final at = _utcMs(PlainDateTime(PlainDate(y, month, 15), PlainTime(12)));
      var off = initial;
      for (final c in changes) {
        if (c.at <= at) off = c.to;
      }
      samples.add((at, off));
    }
  }
  final candidates = _candidates ??= [
    for (final z in ZoneRules.zoneNames)
      if (z.contains('/') && !z.startsWith('Etc/')) z,
  ];
  final fit = [
    for (final z in candidates)
      if (samples.every((s) => ZoneRules.of(z)!.offsetAt(s.$1) == s.$2 * 1000)) z,
  ];
  if (fit.isEmpty) return null;
  // The table names some zones by an older link (Europe/Kiev): compared as canonical names.
  final known = [for (final k in _known) ZoneRules.canonical(k) ?? k];
  int rank(String z) {
    final i = known.indexOf(z);
    return i >= 0 ? -i : -999;
  }

  return fit.reduce((best, z) => rank(z) > rank(best) ? z : best);
}

/// A fixed-offset zone id (`+05:30`) for an offset in seconds, to the minute.
String fixedZone(int seconds) {
  final t = formatOffset(jsRound(seconds / 60) * 60);
  return '${t.substring(0, t.length - 2)}:${t.substring(t.length - 2)}';
}

final _offsetZone = RegExp(r'^[+-]\d');

/// An IANA zone hidden in a TZID: as is, or the longest valid tail of a path
/// (`/mozilla.org/…/Europe/Paris`), or a Windows name.
String? ianaIn(String tzid) {
  final t = tzid.trim();
  if (isValidZone(t) && !_offsetZone.hasMatch(t)) return t;
  final parts = t.split('/').where((p) => p.isNotEmpty).toList();
  for (var i = 0; i < parts.length - 1; i++) {
    final z = parts.sublist(i).join('/');
    if (z.contains('/') && isValidZone(z)) return z;
  }
  return isValidZone(t) ? t : windowsZone(t);
}

/// The zone's offset in seconds at an instant.
int offsetSecondsAt(ZoneId zone, Instant at) => rulesFor(zone).offsetAt(at.epochMilliseconds) ~/ 1000;
