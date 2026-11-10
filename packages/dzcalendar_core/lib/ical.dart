/// iCalendar (RFC 5545): read with each event's real zone (IANA TZIDs as
/// they are, Windows names through CLDR's table, a custom VTIMEZONE matched
/// to the IANA zone with the same offsets), written with VTIMEZONEs from the
/// zones' real transitions (owner's decisions 14 and 16, 2026-11-08).
library;

export 'src/ical/parse.dart' show ICalCalendar, ParsedICal, parseICal;
export 'src/ical/serialize.dart' show serializeICal;
export 'src/ical/source.dart' show icalSource;
export 'src/ical/zones.dart' show windowsZone;
