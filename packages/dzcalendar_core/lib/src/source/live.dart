import 'dart:async';

import '../event/types.dart';
import '../time/instant.dart';
import 'chunks.dart';
import 'source.dart';

/// What a live feed says: an event made, an event changed (its fields laid
/// over the ones it had, `extendedProps` merged; `ongoing: false` without
/// an end: it ends now), an event gone, or the whole list anew (a
/// reconnection that sends everything).
sealed class LiveMessage {
  const LiveMessage();
}

final class LiveCreate extends LiveMessage {
  const LiveCreate(this.event);
  final EventInput event;
}

final class LiveUpdate extends LiveMessage {
  const LiveUpdate(this.id, this.patch);
  final String id;
  final EventInput patch;
}

final class LiveRemove extends LiveMessage {
  const LiveRemove(this.id);
  final String id;
}

final class LiveReset extends LiveMessage {
  const LiveReset(this.events);
  final List<EventInput> events;
}

/// A source that is told, not asked (owner's decision 56): [connect] opens
/// the feed — a WebSocket, Firestore, a Riverpod provider's stream — and
/// each message changes the source's events; the calendar draws what
/// changed (messages of one turn, one redraw). Listened to while the source
/// is in the calendar, cancelled when it is removed or replaced or the
/// calendar disposed; [connect] is called again if the source is given anew.
/// [connect] makes a fresh stream each time (a single-subscription stream
/// stored once cannot be listened to twice); a stream that reconnects
/// should say [LiveReset] first. Make the spec once (a long-lived provider):
/// a spec made anew starts empty and reconnects. The stream's errors and
/// its end are told as `SourceLiveFailed` (never a crash: a phone loses its
/// network). An event without an id cannot be changed later: it is given
/// one (`<source>-<n>`). The feed is the authority: a person's edit to one
/// of its events lasts until its next message — or, with [save], is written
/// back (decision 58).
EventSourceSpec liveSource(
  String id, {
  required Stream<LiveMessage> Function() connect,
  EventInput? defaults,
  FutureOr<void> Function(SaveRequest request)? save,
}) {
  final events = <String, EventInput>{};
  var made = 0;
  Instant Function() clock = () => Instant.fromEpochMilliseconds(DateTime.now().millisecondsSinceEpoch);

  void take(LiveMessage m) {
    switch (m) {
      case LiveCreate(:final event):
        final key = event.id ?? '$id-${++made}';
        // Its own fields as given (what reading them said too), an id added.
        events[key] = event.id == null ? event.withDefaults(EventInput(id: key)) : event;
      case LiveUpdate(id: final key, :final patch):
        final was = events[key];
        if (was == null) return;
        // Finished without an end said: it ends when the feed says so — now, the calendar's.
        final ends = was.ongoing == true && patch.ongoing == false && patch.end == null && patch.duration == null;
        events[key] = EventInput.patchInput(was, patch, id: key, end: ends ? '${clock()}' : null);
      case LiveRemove(id: final key):
        events.remove(key);
      case LiveReset(events: final all):
        events.clear();
        for (final e in all) {
          take(LiveCreate(e));
        }
    }
  }

  return EventSourceSpec(
    id: id,
    chunk: ChunkPolicy.none,
    defaults: defaults,
    save: save,
    fetch: (_) => SourceAnswer([...events.values]),
    // What the calendar forgot is not kept here either: the list does not grow for as long as the app runs.
    forgot: (ids) {
      for (final x in ids) {
        events.remove(x);
      }
    },
    live: (ctx) {
      clock = ctx.now;
      var due = false;
      var open = true;
      final sub = connect().listen(
        (m) {
          take(m);
          // A burst of messages, one delivery.
          if (due) return;
          due = true;
          scheduleMicrotask(() {
            due = false;
            if (open) ctx.changed();
          });
        },
        onError: (Object e, StackTrace st) {
          if (open) ctx.failed(e, st);
        },
        onDone: () {
          if (open) ctx.failed(StateError('the feed of $id ended'), null, closed: true);
        },
      );
      return () {
        open = false;
        unawaited(sub.cancel().catchError((Object _) {}));
      };
    },
  );
}
