import '../event/types.dart';

/// `single` an event, `occurrence` one of a series' occurrences, `override`
/// an occurrence changed on its own.
enum InstanceOrigin { single, occurrence, override }

/// One thing a view shows: an event, or one occurrence of a series.
final class EventInstance {
  const EventInstance(this.key, this.event, this.origin);

  /// The event id, or `seriesId@recurrenceKey` for an occurrence.
  final String key;
  final CalEvent event;
  final InstanceOrigin origin;
}
