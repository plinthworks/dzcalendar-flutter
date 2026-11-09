import 'package:dzcalendar_core/dzcalendar_core.dart' show PlainTime, formatTemporal;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Every word the calendar adds, in the app's language (owner's decision 31,
/// 2026-11-09). Month and weekday names are not here: `intl` knows them
/// through the calendar's locale.
///
/// French, English and Arabic are shipped. Add the delegate:
///
/// ```dart
/// MaterialApp(localizationsDelegates: [
///   DzCalendarLocalizations.delegate,
///   ...GlobalMaterialLocalizations.delegates,
/// ])
/// ```
///
/// To change a word, extend the language's class and hand it to a
/// [DzCalendarLocalizationsDelegate]'s `customize`. Another language: extend
/// [DzCalendarLocalizations] (or the English one) the same way.
abstract class DzCalendarLocalizations {
  const DzCalendarLocalizations(this.localeName);

  /// The locale the words are for (numbers in counts are written in it).
  final String localeName;

  /// The shipped delegate: French, English, Arabic.
  static const LocalizationsDelegate<DzCalendarLocalizations> delegate = DzCalendarLocalizationsDelegate();

  /// The languages shipped.
  static const supportedLanguages = {'en', 'fr', 'ar'};

  /// The words for [context]. Without the delegate (or for a language it
  /// does not have), English — never a throw.
  static DzCalendarLocalizations of(BuildContext context) =>
      Localizations.of<DzCalendarLocalizations>(context, DzCalendarLocalizations) ??
      DzCalendarLocalizationsEn(Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en');

  /// The shipped words for [locale]'s language, English for another.
  static DzCalendarLocalizations forLocale(Locale locale) {
    final tag = locale.toLanguageTag();
    return switch (locale.languageCode) {
      'fr' => DzCalendarLocalizationsFr(tag),
      'ar' => DzCalendarLocalizationsAr(tag),
      _ => DzCalendarLocalizationsEn(tag),
    };
  }

  /// A count in the digits the calendar's dates use for this locale (`ar`:
  /// Arabic-Indic, as `intl` writes its dates), so "week ٤٦" matches "٩".
  String number(int n) {
    // A locale `intl` has no number data for (an app's own language): English
    // numbers rather than a throw.
    final known = Intl.verifiedLocale(localeName, NumberFormat.localeExists, onFailure: (_) => 'en');
    final latin = NumberFormat.decimalPattern(known).format(n);
    final zero = _zeroOf(localeName);
    if (zero == 0x30) return latin;
    return String.fromCharCodes([for (final c in latin.codeUnits) c >= 0x30 && c <= 0x39 ? zero + c - 0x30 : c]);
  }

  static final _zeros = <String, int>{};

  /// The zero digit `intl`'s dates use in [locale].
  static int _zeroOf(String locale) => _zeros[locale] ??= formatTemporal(PlainTime(0), 'm', locale).codeUnitAt(0);

  String get today;
  String get previous;
  String get next;
  String get allDay;

  /// Where a running event's end would be written: "14:32 – running".
  String get ongoing;

  /// The column of a day the zone skipped entirely (Apia, 30 December 2011).
  String get dayDoesNotExist;

  /// Across a band of wall times that never happen: "02:00–03:00 does not exist".
  String gapBand(String from, String to);

  /// Across a band of wall times that happen twice.
  String repeatBand(String from, String to);

  /// The mark after a time read on the second pass of a repeated hour ("02:30*").
  String get secondPassMark;

  /// An event whose drawn height is not its real length: "2 h real".
  String realDuration(String duration);

  /// A length: "2 h", "2 h 30", "45 min".
  String duration(int minutes);

  /// A screen reader's name for an event.
  String eventLabel(String title, String time);
  String get untitled;
  String get now;

  /// What a crowded day cannot show: "+3 more".
  String moreLink(int count);

  /// Its spoken name: "3 more events, Wednesday 21 October".
  String moreLabel(int count, String date);
  String get close;

  /// The view switcher's name for a view type (`dayGridMonth`…); the type itself for one it does not know.
  String viewName(String type);
  String get viewSwitcher;

  /// A day's spoken name: "Wednesday 21 October 2026, 3 events".
  String dayLabel(String date, int count);
  String newEventAt(String time);
  String newEventOn(String date);
  String get goToDay;
  String get openEvent;
  String get deleteEvent;
  String get moveEvent;
  String get resizeEvent;

  /// The menu asking how far a delete of an occurrence reaches.
  String get deleteWhich;
  String get scopeThis;
  String get scopeFollowing;
  String get scopeAll;

  /// Under "New event at 03:00" when the press was in an hour that does not exist.
  String get skippedHour;

  /// The context menu's accessible name.
  String get actions;

  /// A bookable slot: its time range, as its button says it.
  String freeSlot(String time);

  /// Seats still free in a bookable slot.
  String seatsLeft(int count);

  /// In a resource view, whose column or cell: "Dr Ali, Wednesday 21 October".
  String ofResource(String resource, String place);

  /// From one moment or day to another.
  String range(String from, String to);

  /// A list view with nothing in its period.
  String get noEvents;

  /// A resource view without any resource.
  String get noResources;

  /// The column of events on no known resource.
  String get unassigned;

  /// A week number, short (in a cell) and spoken.
  String weekShort(int week);
  String weekLabel(int week);

  /// A month of a multi-month view: its title is a button to that month.
  String get goToMonth;

  /// The slot picker on a day without any.
  String get noSlots;

  /// The slot picker's day: how many slots it has.
  String slotCount(int count);

  /// The time grid's slot: "Tuesday 20 October, 09:30".
  String cursorSlot(String date, String time);
}

/// English.
class DzCalendarLocalizationsEn extends DzCalendarLocalizations {
  const DzCalendarLocalizationsEn([super.localeName = 'en']);

  String _events(int c) => c == 1 ? '1 event' : '${number(c)} events';

  @override
  String get today => 'Today';
  @override
  String get previous => 'Previous';
  @override
  String get next => 'Next';
  @override
  String get allDay => 'All day';
  @override
  String get ongoing => 'running';
  @override
  String get dayDoesNotExist => 'This day does not exist in this time zone';
  @override
  String gapBand(String from, String to) => '$from–$to does not exist';
  @override
  String repeatBand(String from, String to) => '$from–$to happens twice';
  @override
  String get secondPassMark => '*';
  @override
  String duration(int minutes) => _hm(this, minutes, 'h', 'min');
  @override
  String realDuration(String duration) => '$duration real';
  @override
  String eventLabel(String title, String time) => '$title, $time';
  @override
  String get untitled => '(no title)';
  @override
  String get now => 'Now';
  @override
  String moreLink(int count) => '+${number(count)} more';
  @override
  String moreLabel(int count, String date) => '${number(count)} more ${count == 1 ? 'event' : 'events'}, $date';
  @override
  String get close => 'Close';
  @override
  String viewName(String type) => switch (_viewKind(type)) {
    _ViewKind.month => 'Month',
    _ViewKind.week => 'Week',
    _ViewKind.day => 'Day',
    _ViewKind.list => 'List',
    _ViewKind.year => 'Year',
    null => type,
  };
  @override
  String get viewSwitcher => 'View';
  @override
  String dayLabel(String date, int count) => count == 0 ? date : '$date, ${_events(count)}';
  @override
  String newEventAt(String time) => 'New event at $time';
  @override
  String newEventOn(String date) => 'New all-day event on $date';
  @override
  String get goToDay => 'Go to this day';
  @override
  String get openEvent => 'Open';
  @override
  String get deleteEvent => 'Delete';
  @override
  String get moveEvent => 'Move…';
  @override
  String get resizeEvent => 'Change duration…';
  @override
  String get deleteWhich => 'Delete which events?';
  @override
  String get scopeThis => 'This event';
  @override
  String get scopeFollowing => 'This and following events';
  @override
  String get scopeAll => 'All events';
  @override
  String get skippedHour => 'This hour does not exist today; the event starts when it ends';
  @override
  String get actions => 'Actions';
  @override
  String freeSlot(String time) => 'Free slot, $time';
  @override
  String seatsLeft(int count) => count == 1 ? '1 seat' : '${number(count)} seats';
  @override
  String ofResource(String resource, String place) => '$resource, $place';
  @override
  String range(String from, String to) => '$from to $to';
  @override
  String get noEvents => 'No events to display';
  @override
  String get noResources => 'No resources to display';
  @override
  String get unassigned => 'Unassigned';
  @override
  String weekShort(int week) => 'W${number(week)}';
  @override
  String weekLabel(int week) => 'Week ${number(week)}';
  @override
  String get goToMonth => 'Go to this month';
  @override
  String get noSlots => 'No free slots';
  @override
  String slotCount(int count) => count == 1 ? '1 slot' : '${number(count)} slots';
  @override
  String cursorSlot(String date, String time) => '$date, $time';
}

/// French.
class DzCalendarLocalizationsFr extends DzCalendarLocalizations {
  const DzCalendarLocalizationsFr([super.localeName = 'fr']);

  // French: 0 and 1 take the singular.
  String _events(int c) => c <= 1 ? '${number(c)} événement' : '${number(c)} événements';

  @override
  String get today => "Aujourd'hui";
  @override
  String get previous => 'Précédent';
  @override
  String get next => 'Suivant';
  @override
  String get allDay => 'Toute la journée';
  @override
  String get ongoing => 'en cours';
  @override
  String get dayDoesNotExist => "Ce jour n'existe pas dans ce fuseau horaire";
  @override
  String gapBand(String from, String to) => "$from–$to n'existe pas";
  @override
  String repeatBand(String from, String to) => '$from–$to a lieu deux fois';
  @override
  String get secondPassMark => '*';
  @override
  String duration(int minutes) => _hm(this, minutes, 'h', 'min');
  @override
  String realDuration(String duration) => '$duration réelles';
  @override
  String eventLabel(String title, String time) => '$title, $time';
  @override
  String get untitled => '(sans titre)';
  @override
  String get now => 'Maintenant';
  @override
  String moreLink(int count) => '+${number(count)} autres';
  @override
  String moreLabel(int count, String date) =>
      count <= 1 ? '${number(count)} autre événement, $date' : '${number(count)} autres événements, $date';
  @override
  String get close => 'Fermer';
  @override
  String viewName(String type) => switch (_viewKind(type)) {
    _ViewKind.month => 'Mois',
    _ViewKind.week => 'Semaine',
    _ViewKind.day => 'Jour',
    _ViewKind.list => 'Liste',
    _ViewKind.year => 'Année',
    null => type,
  };
  @override
  String get viewSwitcher => 'Affichage';
  @override
  String dayLabel(String date, int count) => count == 0 ? date : '$date, ${_events(count)}';
  @override
  String newEventAt(String time) => 'Nouvel événement à $time';
  @override
  String newEventOn(String date) => 'Nouvel événement sur la journée du $date';
  @override
  String get goToDay => 'Aller à ce jour';
  @override
  String get openEvent => 'Ouvrir';
  @override
  String get deleteEvent => 'Supprimer';
  @override
  String get moveEvent => 'Déplacer…';
  @override
  String get resizeEvent => 'Changer la durée…';
  @override
  String get deleteWhich => 'Supprimer quels événements ?';
  @override
  String get scopeThis => 'Cet événement';
  @override
  String get scopeFollowing => 'Cet événement et les suivants';
  @override
  String get scopeAll => 'Tous les événements';
  @override
  String get skippedHour => "Cette heure n'existe pas aujourd'hui ; l'événement commence à sa fin";
  @override
  String get actions => 'Actions';
  @override
  String freeSlot(String time) => 'Créneau libre, $time';
  @override
  String seatsLeft(int count) => count <= 1 ? '${number(count)} place' : '${number(count)} places';
  @override
  String ofResource(String resource, String place) => '$resource, $place';
  @override
  String range(String from, String to) => 'de $from à $to';
  @override
  String get noEvents => 'Aucun événement à afficher';
  @override
  String get noResources => 'Aucune ressource à afficher';
  @override
  String get unassigned => 'Non attribué';
  @override
  String weekShort(int week) => 'S${number(week)}';
  @override
  String weekLabel(int week) => 'Semaine ${number(week)}';
  @override
  String get goToMonth => 'Aller à ce mois';
  @override
  String get noSlots => 'Aucun créneau libre';
  @override
  String slotCount(int count) => count <= 1 ? '${number(count)} créneau' : '${number(count)} créneaux';
  @override
  String cursorSlot(String date, String time) => '$date, $time';
}

/// Arabic. Times and offsets inside a sentence are isolated (FSI … PDI) so
/// they keep their own direction; counts follow Arabic's six plural forms.
class DzCalendarLocalizationsAr extends DzCalendarLocalizations {
  const DzCalendarLocalizationsAr([super.localeName = 'ar']);

  /// A left-to-right fragment (a time, an offset) kept whole inside right-to-left text.
  static String _iso(String s) => s.isEmpty ? s : '\u2068$s\u2069';

  String _plural(
    int c, {
    required String zero,
    required String one,
    required String two,
    required String few,
    required String many,
    required String other,
  }) => Intl.pluralLogic(c, locale: 'ar', zero: zero, one: one, two: two, few: few, many: many, other: other);

  String _events(int c) => _plural(
    c,
    zero: 'لا أحداث',
    one: 'حدث واحد',
    two: 'حدثان',
    few: '${number(c)} أحداث',
    many: '${number(c)} حدثًا',
    other: '${number(c)} حدث',
  );

  String _more(int c) => _plural(
    c,
    zero: '${number(c)} حدث آخر',
    one: 'حدث آخر',
    two: 'حدثان آخران',
    few: '${number(c)} أحداث أخرى',
    many: '${number(c)} حدثًا آخر',
    other: '${number(c)} حدث آخر',
  );

  @override
  String get today => 'اليوم';
  @override
  String get previous => 'السابق';
  @override
  String get next => 'التالي';
  @override
  String get allDay => 'طوال اليوم';
  @override
  String get ongoing => 'جارٍ';
  @override
  String get dayDoesNotExist => 'هذا اليوم غير موجود في هذه المنطقة الزمنية';
  @override
  String gapBand(String from, String to) => 'الفترة ${_iso('$from–$to')} غير موجودة';
  @override
  String repeatBand(String from, String to) => 'الفترة ${_iso('$from–$to')} تتكرر مرتين';
  @override
  String get secondPassMark => '*';
  @override
  String duration(int minutes) => _hm(this, minutes, 'س', 'د');
  @override
  String realDuration(String duration) => '$duration فعليًا';
  @override
  String eventLabel(String title, String time) => '$title، ${_iso(time)}';
  @override
  String get untitled => '(بلا عنوان)';
  @override
  String get now => 'الآن';
  @override
  String moreLink(int count) => '+${number(count)} أخرى';
  @override
  String moreLabel(int count, String date) => '${_more(count)}، $date';
  @override
  String get close => 'إغلاق';
  @override
  String viewName(String type) => switch (_viewKind(type)) {
    _ViewKind.month => 'شهر',
    _ViewKind.week => 'أسبوع',
    _ViewKind.day => 'يوم',
    _ViewKind.list => 'قائمة',
    _ViewKind.year => 'سنة',
    null => type,
  };
  @override
  String get viewSwitcher => 'العرض';
  @override
  String dayLabel(String date, int count) => count == 0 ? date : '$date، ${_events(count)}';
  @override
  String newEventAt(String time) => 'حدث جديد في ${_iso(time)}';
  @override
  String newEventOn(String date) => 'حدث جديد طوال اليوم في $date';
  @override
  String get goToDay => 'الانتقال إلى هذا اليوم';
  @override
  String get openEvent => 'فتح';
  @override
  String get deleteEvent => 'حذف';
  @override
  String get moveEvent => 'نقل…';
  @override
  String get resizeEvent => 'تغيير المدة…';
  @override
  String get deleteWhich => 'ما الأحداث التي تريد حذفها؟';
  @override
  String get scopeThis => 'هذا الحدث';
  @override
  String get scopeFollowing => 'هذا الحدث والأحداث التالية';
  @override
  String get scopeAll => 'كل الأحداث';
  @override
  String get skippedHour => 'هذه الساعة غير موجودة اليوم؛ يبدأ الحدث عند نهايتها';
  @override
  String get actions => 'إجراءات';
  @override
  String freeSlot(String time) => 'موعد متاح، ${_iso(time)}';
  @override
  String seatsLeft(int count) => _plural(
    count,
    zero: '${number(count)} مقعد',
    one: 'مقعد واحد',
    two: 'مقعدان',
    few: '${number(count)} مقاعد',
    many: '${number(count)} مقعدًا',
    other: '${number(count)} مقعد',
  );
  @override
  String ofResource(String resource, String place) => '$resource، $place';
  @override
  String range(String from, String to) => 'من ${_iso(from)} إلى ${_iso(to)}';
  @override
  String get noEvents => 'لا توجد أحداث لعرضها';
  @override
  String get noResources => 'لا توجد موارد لعرضها';
  @override
  String get unassigned => 'غير مُسنَد';
  @override
  String weekShort(int week) => 'أ${number(week)}';
  @override
  String weekLabel(int week) => 'الأسبوع ${number(week)}';
  @override
  String get goToMonth => 'الانتقال إلى هذا الشهر';
  @override
  String get noSlots => 'لا توجد مواعيد متاحة';
  @override
  String slotCount(int count) => _plural(
    count,
    zero: 'لا مواعيد',
    one: 'موعد واحد',
    two: 'موعدان',
    few: '${number(count)} مواعيد',
    many: '${number(count)} موعدًا',
    other: '${number(count)} موعد',
  );
  @override
  String cursorSlot(String date, String time) => '$date، ${_iso(time)}';
}

/// "2 h", "2 h 30", "45 min", in the locale's digits.
String _hm(DzCalendarLocalizations l, int minutes, String h, String min) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${l.number(rest)} $min';
  if (rest == 0) return '${l.number(hours)} $h';
  return '${l.number(hours)} $h ${rest < 10 ? l.number(0) : ''}${l.number(rest)}';
}

enum _ViewKind { month, week, day, list, year }

/// What the view switcher calls a view, from its type's name.
_ViewKind? _viewKind(String type) {
  if (type.startsWith('list')) return _ViewKind.list;
  if (type.startsWith('multiMonth') || type.endsWith('Year')) return _ViewKind.year;
  if (type.endsWith('Month')) return _ViewKind.month;
  if (type.endsWith('Week')) return _ViewKind.week;
  if (type.endsWith('Day')) return _ViewKind.day;
  return null;
}

/// Loads the calendar's words for the app's locale.
class DzCalendarLocalizationsDelegate extends LocalizationsDelegate<DzCalendarLocalizations> {
  /// [customize] receives the shipped words for a locale and returns the
  /// ones to use (a subclass changing a few, or another language's).
  const DzCalendarLocalizationsDelegate({this.customize, this.languages});

  final DzCalendarLocalizations Function(Locale locale, DzCalendarLocalizations shipped)? customize;

  /// Languages [customize] adds (an app translating to another language).
  final Set<String>? languages;

  @override
  bool isSupported(Locale locale) =>
      DzCalendarLocalizations.supportedLanguages.contains(locale.languageCode) ||
      (languages?.contains(locale.languageCode) ?? false);

  @override
  Future<DzCalendarLocalizations> load(Locale locale) {
    final shipped = DzCalendarLocalizations.forLocale(locale);
    final fn = customize;
    return SynchronousFuture(fn == null ? shipped : fn(locale, shipped));
  }

  @override
  bool shouldReload(DzCalendarLocalizationsDelegate old) => old.customize != customize || old.languages != languages;
}
