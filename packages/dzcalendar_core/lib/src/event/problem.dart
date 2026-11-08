/// Why an input was refused or bent. A code and raw detail only: sentences
/// belong to the widgets' messages, translated, never to the core.
///
/// Each code's [code] is the TypeScript core's, so a problem reads the same
/// on every platform and in the conformance cases.
enum ProblemCode {
  invalidEvent('invalid-event'),
  missingStart('missing-start'),
  invalidStart('invalid-start'),
  invalidEnd('invalid-end'),
  invalidDuration('invalid-duration'),
  endBeforeStart('end-before-start'),
  invalidId('invalid-id'),
  duplicateId('duplicate-id'),
  unknownEvent('unknown-event'),
  unknownZone('unknown-zone'),
  zoneDefaulted('zone-defaulted'),
  offsetOnly('offset-only'),
  offsetMismatch('offset-mismatch'),
  wallTimeSkipped('wall-time-skipped'),
  wallTimeAmbiguous('wall-time-ambiguous'),

  /// A `DateTime` given where a moment is expected (owner, 2026-11-08: as the
  /// web refuses `Date`, K.15): it names no zone; the detail says what to write.
  dateObjectRejected('date-object-rejected'),
  alldayWithTime('allday-with-time'),
  alldayZoneIgnored('allday-zone-ignored'),

  /// A marker is a moment: on a date alone, refused.
  markerAllDay('marker-all-day'),

  /// A marker's end or duration: it has none, ignored.
  markerLengthIgnored('marker-length-ignored'),

  /// Still running is said of a timed event: on a date alone, or with a rule, refused.
  ongoingNotTimed('ongoing-not-timed'),
  unknownResource('unknown-resource'),
  invalidRrule('invalid-rrule'),
  invalidExdate('invalid-exdate'),
  invalidRdate('invalid-rdate'),
  tooManyOccurrences('too-many-occurrences'),
  unknownOccurrence('unknown-occurrence'),
  invalidEdit('invalid-edit'),
  invalidRecurrenceId('invalid-recurrence-id'),
  orphanOverride('orphan-override'),
  icalSyntax('ical-syntax'),
  icalUnsupported('ical-unsupported'),
  zoneGuessed('zone-guessed'),
  zoneFixedOffset('zone-fixed-offset'),
  invalidResource('invalid-resource'),
  resourceCycle('resource-cycle'),
  invalidAvailability('invalid-availability'),
  invalidSlotQuery('invalid-slot-query'),
  invalidExport('invalid-export'),
  invalidOption('invalid-option'),

  /// A moment or a length written below the millisecond: kept to the
  /// millisecond (decision 1), said (owner, 2026-11-08: decision 9). No
  /// TypeScript counterpart yet — brought back to the main repository.
  precisionTruncated('precision-truncated');

  const ProblemCode(this.code);

  /// "end-before-start": the TypeScript core's spelling.
  final String code;
}

enum Severity {
  /// Rejects the input.
  error,

  /// Accompanies an accepted input: something was guessed or bent.
  warning,
}

final class Problem {
  const Problem(this.code, this.severity, this.path, [this.detail]) : sourceId = null;
  const Problem._(this.code, this.severity, this.path, this.detail, this.sourceId);

  final ProblemCode code;
  final Severity severity;

  /// Where in the input: `events[12].start`.
  final String path;

  /// Raw, untranslated: the value or what went wrong with it.
  final String? detail;
  final String? sourceId;

  bool get isError => severity == Severity.error;

  Problem withSource(String source) => Problem._(code, severity, path, detail, source);

  @override
  bool operator ==(Object other) =>
      other is Problem &&
      other.code == code &&
      other.severity == severity &&
      other.path == path &&
      other.detail == detail &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(code, severity, path, detail, sourceId);

  @override
  String toString() => '${code.code} (${severity.name}) at $path${detail == null ? '' : ': $detail'}';
}
