import 'dart:async';

import '../event/types.dart';
import '../source/chunks.dart';
import '../source/json_source.dart';
import '../source/source.dart';
import 'parse.dart';

/// An iCalendar feed as an event source: fetched whole (iCal has no
/// ranges), read by [parseICal]; what reading it found wrong comes with the
/// events. Given a [url], the application's [request] fetches it (decision
/// 55: its own client) and answers the text; or the [text] itself. A
/// `webcal://` link is the same feed over HTTPS.
EventSourceSpec icalSource(
  String id, {
  String? url,
  Future<String> Function(SourceHttpRequest request)? request,
  FutureOr<String> Function()? text,
  Map<String, String> headers = const {},
  EventInput? defaults,
  String? defaultZone,
  FutureOr<void> Function(SaveRequest request)? save,
  Duration? staleAfter,
  RetryPolicy? retry,
  Object? key,
}) => EventSourceSpec(
  id: id,
  chunk: ChunkPolicy.none,
  defaults: defaults,
  save: save,
  staleAfter: staleAfter,
  retry: retry,
  key: key,
  fetch: (r) async {
    final String body;
    if (text != null) {
      body = await text();
    } else {
      if (url == null || request == null) throw ArgumentError('icalSource needs a url and a request, or text');
      body = await request(
        SourceHttpRequest(
          url: url.replaceFirst(RegExp('^webcals?://', caseSensitive: false), 'https://'),
          path: url.replaceFirst(RegExp('^webcals?://', caseSensitive: false), 'https://'),
          queryParameters: const {},
          method: 'GET',
          headers: {'accept': 'text/calendar', ...headers},
          cancel: r.cancel,
        ),
      );
    }
    final parsed = parseICal(body, defaultZone: defaultZone);
    return SourceAnswer(parsed.events, problems: parsed.problems);
  },
);
