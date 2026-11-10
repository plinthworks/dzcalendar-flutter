import 'dart:async';

import '../event/problem.dart';
import '../event/types.dart';
import 'chunks.dart';
import 'source.dart';

/// A request a source wants made (owner's decision 55): the application
/// makes it with its own client (dio, http) and answers the body — the
/// decoded JSON for [jsonSource], the text for `icalSource`. A failure (an
/// HTTP error, the network) is thrown: the source's fetch fails, retried
/// by its policy. [cancel]: tie it to the client's own cancelling.
final class SourceHttpRequest {
  const SourceHttpRequest({
    required this.url,
    required this.path,
    required this.queryParameters,
    required this.method,
    required this.headers,
    required this.cancel,
    this.body,
  });

  /// The whole URL, its query written in ([path] + [queryParameters]).
  final String url;

  /// The URL as given, and the parameters apart (dio's `baseUrl` and
  /// `queryParameters`, an interceptor's cache key).
  final String path;
  final Map<String, String> queryParameters;

  /// `GET` or `POST`.
  final String method;
  final Map<String, String> headers;

  /// A form (`application/x-www-form-urlencoded`) for a `POST`.
  final String? body;
  final CancelToken cancel;
}

/// Makes a request for a JSON source: the decoded body.
typedef JsonRequester = Future<Object?> Function(SourceHttpRequest request);

String _query(Map<String, String> params) => [
  for (final MapEntry(:key, :value) in params.entries) '${Uri.encodeComponent(key)}=${Uri.encodeComponent(value)}',
].join('&');

/// The default reading of a JSON answer: a list of the web's event objects;
/// an item that is not one is a problem at `answer[i]`.
SourceAnswer readEventList(Object? json) {
  if (json is! List) {
    final text = '$json';
    throw FormatException('expected a list of events', text.length > 200 ? '${text.substring(0, 200)}…' : text);
  }
  final events = <EventInput>[];
  final problems = <Problem>[];
  for (var i = 0; i < json.length; i++) {
    final x = json[i];
    if (x is Map) {
      events.add(EventInput.fromJson(x));
    } else {
      // The answer's own place: the events read are numbered without it.
      problems.add(Problem(ProblemCode.invalidEvent, Severity.error, 'answer[$i]', 'not an object'));
    }
  }
  return SourceAnswer(events, problems: problems);
}

/// Events from a URL answering JSON. Each request names its stretch as
/// instants (`start=2026-09-30T10:00:00Z&end=…`, wide enough for every zone)
/// and the calendar's zone; a chunked request is one stretch of whole
/// chunks. A parameter's name null leaves it out. Told the zone (and cut),
/// it is asked again when the zone changes ([EventSourceSpec.zoneDependent]).
EventSourceSpec jsonSource(
  String id, {
  required String url,
  required JsonRequester request,
  String? startParam = 'start',
  String? endParam = 'end',
  String? zoneParam = 'timeZone',
  Map<String, String> params = const {},
  String method = 'GET',
  Map<String, String> headers = const {},
  SourceAnswer Function(Object? json) map = readEventList,
  ChunkPolicy chunk = ChunkPolicy.month,
  Duration? staleAfter,
  RetryPolicy? retry,
  bool? zoneDependent,
  EventInput? defaults,
  FutureOr<void> Function(SaveRequest request)? save,
  Object? key,
  bool createsHere = false,
}) {
  assert(method == 'GET' || method == 'POST');
  Future<SourceAnswer> fetch(FetchRequest r) async {
    final q = <String, String>{...params};
    final w = r.window;
    if (w != null) {
      if (startParam != null) q[startParam] = '${w.start}';
      if (endParam != null) q[endParam] = '${w.end}';
      if (zoneParam != null) q[zoneParam] = w.displayZone;
    }
    final query = _query(q);
    final post = method == 'POST';
    final raw = await request(
      SourceHttpRequest(
        url: post || query.isEmpty ? url : '$url${url.contains('?') ? '&' : '?'}$query',
        path: url,
        queryParameters: post ? const {} : q,
        method: method,
        headers: {
          'accept': 'application/json',
          if (post) 'content-type': 'application/x-www-form-urlencoded',
          ...headers,
        },
        body: post ? query : null,
        cancel: r.cancel,
      ),
    );
    return map(raw);
  }

  // The zone sent (a whole feed is sent none): the server may answer by it, asked again when it changes.
  return EventSourceSpec(
    id: id,
    fetch: fetch,
    chunk: chunk,
    staleAfter: staleAfter,
    retry: retry,
    zoneDependent: zoneDependent ?? (zoneParam != null && chunk.unit != ChunkUnit.none),
    defaults: defaults,
    save: save,
    key: key,
    createsHere: createsHere,
  );
}
