import '../event/types.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'types.dart';

/// The busy time of calendar events (those with `busy`, the default unless
/// cancelled): a timed event is a booking, an all-day one blocks its whole
/// dates in the provider's [zone].
List<Busy> busyFromEvents(Iterable<CalEvent> events, ZoneId zone) => [
  for (final e in events)
    if (e.busy)
      switch (e) {
        TimedEvent(:final start, :final end) => Busy(start: start.instant, end: end.instant),
        AllDayEvent(:final start, :final end) => Busy(
          start: start.startOfDayIn(zone),
          end: end.startOfDayIn(zone),
          kind: BusyKind.block,
        ),
      },
];
