import '../event/problem.dart';
import '../event/types.dart';
import '../store/instance.dart';
import '../store/store.dart';
import '../time/plain.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'daygrid.dart' show isBackground;
import 'views.dart';

final class ListEntry {
  const ListEntry({
    required this.key,
    required this.instance,
    required this.allDay,
    required this.startsHere,
    required this.endsHere,
    this.start,
    this.end,
  });

  /// `instance.key|date`: an event over three days is three entries.
  final String key;
  final EventInstance instance;

  /// An all-day event, or a timed one covering the whole of this day in the display zone.
  final bool allDay;
  final bool startsHere;
  final bool endsHere;

  /// The part of a timed event on this day, in the display zone.
  final ZonedDateTime? start;
  final ZonedDateTime? end;
}

final class ListDay {
  const ListDay({required this.date, required this.lengthMinutes, required this.entries});
  final PlainDate date;

  /// The day's real length in the display zone: 1500 on a fall-back Sunday, 1410 at Lord Howe.
  final double lengthMinutes;
  final List<ListEntry> entries;
}

final class ListModel {
  const ListModel({required this.version, required this.range, required this.days});
  final int version;
  final ViewRange range;
  final List<ListDay> days;
}

final class ListOptions {
  const ListOptions({required this.displayZone, this.includeEmpty = false, this.onProblem});
  final ZoneId displayZone;

  /// Where the queries' problems go (a series cut short there).
  final void Function(Problem)? onProblem;

  /// Every shown date, events or not (a custom view's days). Default: only days with events.
  final bool includeEmpty;
}

/// The events of a period, day by day in the display zone, in reading
/// order: all-day first, then by start, longer first, title. A day that
/// does not exist in the zone (Apia, 30 December 2011) has no entry and no
/// heading.
ListModel buildListModel(ViewRange range, StoreSnapshot snap, ListOptions opts) {
  final zone = opts.displayZone;
  final shown = {for (final d in range.dates) d.epochDay};
  final infos = [
    for (final d in dayInfos(range.start, range.start.daysUntil(range.end), zone))
      if (d.lengthMinutes > 0 && shown.contains(d.date.epochDay)) d,
  ];
  final buckets = [for (final _ in infos) <ListEntry>[]];
  final index = {for (var i = 0; i < infos.length; i++) infos[i].date.epochDay: i};
  final starts = [for (final d in infos) d.start.epochMilliseconds];

  for (final instance in snap.queryInstances(
    viewWindow(range.start, range.end, zone),
    QueryOptions(onProblem: opts.onProblem),
  )) {
    if (isBackground(instance.event.display)) continue;
    switch (instance.event) {
      case AllDayEvent(start: final evStart, end: final evEnd):
        final last = evEnd.addDays(-1);
        for (
          var d = evStart.isAfter(range.start) ? evStart : range.start;
          d.isBefore(evEnd) && d.isBefore(range.end);
          d = d.addDays(1)
        ) {
          final i = index[d.epochDay];
          if (i == null) continue;
          buckets[i].add(
            ListEntry(
              key: '${instance.key}|$d',
              instance: instance,
              allDay: true,
              startsHere: d == evStart,
              endsHere: d == last,
            ),
          );
        }
      case TimedEvent(start: final evStart, end: final evEnd):
        final s = evStart.epochMilliseconds;
        final e = evEnd.epochMilliseconds;
        // The last day starting at or before the event's start, then on while days begin before its end.
        var lo = 0;
        var hi = infos.length;
        while (lo < hi) {
          final mid = (lo + hi) >> 1;
          if (starts[mid] <= s) {
            lo = mid + 1;
          } else {
            hi = mid;
          }
        }
        for (var i = lo - 1 < 0 ? 0 : lo - 1; i < infos.length; i++) {
          final day = infos[i];
          final ds = day.start.epochMilliseconds;
          final de = day.end.epochMilliseconds;
          if (ds >= e && !(s == e && ds == s)) break;
          // A zero-length event shows on its day; an end at midnight does not touch the next one.
          final meets = s == e ? s >= ds && s < de : s < de && e > ds;
          if (!meets) continue;
          final startsHere = s >= ds;
          final endsHere = e <= de;
          buckets[i].add(
            ListEntry(
              key: '${instance.key}|${day.date}',
              instance: instance,
              allDay: s <= ds && e >= de,
              startsHere: startsHere,
              endsHere: endsHere,
              start: startsHere ? evStart.withTimeZone(zone) : ZonedDateTime(day.start, zone),
              end: endsHere ? evEnd.withTimeZone(zone) : ZonedDateTime(day.end, zone),
            ),
          );
        }
    }
  }

  int length(ListEntry x) => switch (x.instance.event) {
    AllDayEvent(:final start, :final end) => start.daysUntil(end) * 86400000,
    TimedEvent(:final start, :final end) => end.epochMilliseconds - start.epochMilliseconds,
  };
  int order(ListEntry a, ListEntry b) {
    var c = (b.allDay ? 1 : 0) - (a.allDay ? 1 : 0);
    if (c != 0) return c;
    c = (a.start?.epochMilliseconds ?? 0).compareTo(b.start?.epochMilliseconds ?? 0);
    if (c != 0) return c;
    c = length(b).compareTo(length(a));
    if (c != 0) return c;
    c = a.instance.event.title.compareTo(b.instance.event.title);
    return c != 0 ? c : a.key.compareTo(b.key);
  }

  final days = <ListDay>[];
  for (var i = 0; i < infos.length; i++) {
    final entries = buckets[i];
    if (entries.isEmpty && !opts.includeEmpty) continue;
    entries.sort(order);
    days.add(ListDay(date: infos[i].date, lengthMinutes: infos[i].lengthMinutes, entries: List.unmodifiable(entries)));
  }
  return ListModel(version: snap.version, range: range, days: List.unmodifiable(days));
}
