import 'package:dzcalendar_core/dzcalendar_core.dart' show PlainTime, ViolationCode, formatTemporal;
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
///
/// A word added in a later minor version comes with a body (its English
/// text), so a class extending this one keeps compiling (owner's decision
/// 69); extending [DzCalendarLocalizationsEn] gets every new word in English
/// until it is translated.
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

  /// Asked when an occurrence of a series was moved or resized.
  String get changeWhich;

  /// A held event's menu button.
  String get moreOptions;
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

  /// A timeline's resource area, over its rows.
  String get resources;

  /// A resource's or a group's row: show what is under it, or hide it.
  String showRows(String name);
  String hideRows(String name);

  /// A phone's resource area: names in full, or initials only.
  String get widenResources;
  String get narrowResources;

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

  // ——— the keyboard and screen readers (19e-2b-2) ———

  /// The cursor on a day's all-day row, or on a day.
  String cursorAllDay(String date);

  /// The keyboard's selection, said as it grows.
  String selected(String span);
  String get selectionCleared;

  /// A step that has nowhere to go (a fixed period's end, past the hours).
  String get noFurther;
  String get notEditable;
  String get cannotMove;
  String get cannotResize;

  /// Grab mode starts (M, Alt+Enter, "Move…").
  String grabbed(String title);

  /// What the keys do while an event is held.
  String get grabHelp;

  /// Held from "Change duration…": the arrows pull its end.
  String get grabHelpResize;

  /// What a screen reader's gestures do while an event is held.
  String get grabHelpReader;
  String get grabCancelled;

  /// A place the calendar's rules refuse, with why when known.
  String get dropRefused;
  String dropRefusedFor(String reasons);

  /// Why a place is refused, in a few words.
  String violation(ViolationCode code);

  /// Said once an event is put down.
  String eventMoved(String title, String time);
  String eventResized(String title, String time);
  String movedIntoGap(String time);
  String get becomesAllDay;
  String becomesTimed(String length);

  /// Said after Delete; [undo] is the shortcut, empty when there is none.
  String eventDeleted(String title, String undo);
  String get undone;
  String get redone;

  /// A held event's actions for screen readers.
  String get previousDay;
  String get nextDay;
  String get previousWeek;
  String get nextWeek;

  /// A resource view's held event: to the row (or column) before or after.
  String get previousResource;
  String get nextResource;
  String get putDown;
  String get cancelMove;
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
  }.timeline(type, (k) => 'Timeline ($k)', lower: true);
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
  String get changeWhich => 'Change which events?';
  @override
  String get moreOptions => 'More options';
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
  String get resources => 'Resources';
  @override
  String showRows(String name) => 'Show under $name';
  @override
  String hideRows(String name) => 'Hide under $name';
  @override
  String get widenResources => 'Show names';
  @override
  String get narrowResources => 'Initials only';
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

  @override
  String cursorAllDay(String date) => '$date, all day';
  @override
  String selected(String span) => 'Selected: $span';
  @override
  String get selectionCleared => 'Selection cleared';
  @override
  String get noFurther => 'Cannot go further';
  @override
  String get notEditable => 'This event cannot be changed';
  @override
  String get cannotMove => 'This event cannot be moved';
  @override
  String get cannotResize => 'This length cannot be changed here';
  @override
  String grabbed(String title) => '$title grabbed.';
  @override
  String get grabHelp =>
      'Arrows move it, Page Up and Page Down by a week, Shift with arrows changes its end, Enter puts it down, Escape cancels.';
  @override
  String get grabHelpResize => 'Arrows change its end, Enter puts it down, Escape cancels.';
  @override
  String get grabHelpReader => 'Swipe up or down to move it, double tap to put it down.';
  @override
  String get grabCancelled => 'Move cancelled';
  @override
  String get dropRefused => 'Not allowed here';
  @override
  String dropRefusedFor(String reasons) => 'Not allowed here: $reasons';
  @override
  String violation(ViolationCode code) => switch (code) {
    ViolationCode.constraint => 'outside the allowed hours',
    ViolationCode.overlap => 'overlaps another event',
    ViolationCode.allow => 'refused by the application',
    ViolationCode.validRange => 'outside the dates shown',
    ViolationCode.notEditable => 'cannot be changed',
  };
  @override
  String eventMoved(String title, String time) => '$title moved to $time';
  @override
  String eventResized(String title, String time) => '$title now ends at $time';
  @override
  String movedIntoGap(String time) => 'That time does not exist that day; moved to $time';
  @override
  String get becomesAllDay => 'It becomes an all-day event';
  @override
  String becomesTimed(String length) => 'It becomes a timed event of $length';
  @override
  String eventDeleted(String title, String undo) => undo.isEmpty ? '$title deleted.' : '$title deleted. $undo to undo.';
  @override
  String get undone => 'Undone';
  @override
  String get redone => 'Redone';
  @override
  String get previousDay => 'Previous day';
  @override
  String get nextDay => 'Next day';
  @override
  String get previousWeek => 'Previous week';
  @override
  String get nextWeek => 'Next week';
  @override
  String get previousResource => 'Previous resource';
  @override
  String get nextResource => 'Next resource';
  @override
  String get putDown => 'Put down';
  @override
  String get cancelMove => 'Cancel the move';
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
  }.timeline(type, (k) => 'Chronologie ($k)', lower: true);
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
  String get changeWhich => 'Modifier quels événements ?';
  @override
  String get moreOptions => 'Plus d’options';
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
  String get resources => 'Ressources';
  @override
  String showRows(String name) => 'Déplier $name';
  @override
  String hideRows(String name) => 'Replier $name';
  @override
  String get widenResources => 'Afficher les noms';
  @override
  String get narrowResources => 'Initiales seulement';
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

  @override
  String cursorAllDay(String date) => '$date, journée';
  @override
  String selected(String span) => 'Sélection : $span';
  @override
  String get selectionCleared => 'Sélection effacée';
  @override
  String get noFurther => 'Impossible d’aller plus loin';
  @override
  String get notEditable => 'Cet événement ne peut pas être modifié';
  @override
  String get cannotMove => 'Cet événement ne peut pas être déplacé';
  @override
  String get cannotResize => 'Cette durée ne peut pas être changée ici';
  @override
  String grabbed(String title) => '« $title » saisi.';
  @override
  String get grabHelp =>
      'Flèches pour le déplacer, Page précédente et suivante d’une semaine, Maj et flèches pour sa fin, Entrée pour le poser, Échap pour annuler.';
  @override
  String get grabHelpResize => 'Flèches pour sa fin, Entrée pour le poser, Échap pour annuler.';
  @override
  String get grabHelpReader => 'Balayez vers le haut ou le bas pour le déplacer, touchez deux fois pour le poser.';
  @override
  String get grabCancelled => 'Déplacement annulé';
  @override
  String get dropRefused => 'Impossible ici';
  @override
  String dropRefusedFor(String reasons) => 'Impossible ici : $reasons';
  @override
  String violation(ViolationCode code) => switch (code) {
    ViolationCode.constraint => 'en dehors des heures permises',
    ViolationCode.overlap => 'chevauche un autre événement',
    ViolationCode.allow => "refusé par l'application",
    ViolationCode.validRange => 'en dehors des dates affichables',
    ViolationCode.notEditable => 'non modifiable',
  };
  @override
  String eventMoved(String title, String time) => '« $title » déplacé à $time';
  @override
  String eventResized(String title, String time) => '« $title » finit maintenant à $time';
  @override
  String movedIntoGap(String time) => 'Cette heure n’existe pas ce jour-là : déplacé à $time';
  @override
  String get becomesAllDay => 'Il devient un événement sur la journée';
  @override
  String becomesTimed(String length) => 'Il devient un événement horaire de $length';
  @override
  String eventDeleted(String title, String undo) =>
      undo.isEmpty ? '« $title » supprimé.' : '« $title » supprimé. $undo pour annuler.';
  @override
  String get undone => 'Annulé';
  @override
  String get redone => 'Rétabli';
  @override
  String get previousDay => 'Jour précédent';
  @override
  String get nextDay => 'Jour suivant';
  @override
  String get previousWeek => 'Semaine précédente';
  @override
  String get nextWeek => 'Semaine suivante';
  @override
  String get previousResource => 'Ressource précédente';
  @override
  String get nextResource => 'Ressource suivante';
  @override
  String get putDown => 'Poser';
  @override
  String get cancelMove => 'Annuler le déplacement';
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
  }.timeline(type, (k) => 'خط زمني ($k)');
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
  String get changeWhich => 'ما الأحداث التي تريد تعديلها؟';
  @override
  String get moreOptions => 'خيارات أخرى';
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
  String get resources => 'الموارد';
  @override
  String showRows(String name) => 'إظهار ما تحت $name';
  @override
  String hideRows(String name) => 'إخفاء ما تحت $name';
  @override
  String get widenResources => 'إظهار الأسماء';
  @override
  String get narrowResources => 'الأحرف الأولى فقط';
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

  @override
  String cursorAllDay(String date) => '$date، طوال اليوم';
  @override
  String selected(String span) => 'تم التحديد: $span';
  @override
  String get selectionCleared => 'تم إلغاء التحديد';
  @override
  String get noFurther => 'لا يمكن التقدم أكثر';
  @override
  String get notEditable => 'لا يمكن تغيير هذا الحدث';
  @override
  String get cannotMove => 'لا يمكن نقل هذا الحدث';
  @override
  String get cannotResize => 'لا يمكن تغيير هذه المدة هنا';
  @override
  String grabbed(String title) => 'تم التقاط «$title».';
  @override
  String get grabHelp =>
      'الأسهم لنقله، و${_iso('Page Up')} و${_iso('Page Down')} بأسبوع، و${_iso('Shift')} مع الأسهم لتغيير نهايته، و${_iso('Enter')} لوضعه، و${_iso('Escape')} للإلغاء.';
  @override
  String get grabHelpResize => 'الأسهم لتغيير نهايته، و${_iso('Enter')} لوضعه، و${_iso('Escape')} للإلغاء.';
  @override
  String get grabHelpReader => 'اسحب لأعلى أو لأسفل لنقله، وانقر مرتين لوضعه.';
  @override
  String get grabCancelled => 'تم إلغاء النقل';
  @override
  String get dropRefused => 'غير مسموح هنا';
  @override
  String dropRefusedFor(String reasons) => 'غير مسموح هنا: $reasons';
  @override
  String violation(ViolationCode code) => switch (code) {
    ViolationCode.constraint => 'خارج الساعات المسموح بها',
    ViolationCode.overlap => 'يتداخل مع حدث آخر',
    ViolationCode.allow => 'رفضه التطبيق',
    ViolationCode.validRange => 'خارج التواريخ المعروضة',
    ViolationCode.notEditable => 'لا يمكن تغييره',
  };
  @override
  String eventMoved(String title, String time) => 'تم نقل «$title» إلى ${_iso(time)}';
  @override
  String eventResized(String title, String time) => 'ينتهي «$title» الآن في ${_iso(time)}';
  @override
  String movedIntoGap(String time) => 'هذا الوقت غير موجود في ذلك اليوم؛ تم النقل إلى ${_iso(time)}';
  @override
  String get becomesAllDay => 'يصبح حدثًا طوال اليوم';
  @override
  String becomesTimed(String length) => 'يصبح حدثًا مدته $length';
  @override
  String eventDeleted(String title, String undo) =>
      undo.isEmpty ? 'تم حذف «$title».' : 'تم حذف «$title». ${_iso(undo)} للتراجع.';
  @override
  String get undone => 'تم التراجع';
  @override
  String get redone => 'تمت الإعادة';
  @override
  String get previousDay => 'اليوم السابق';
  @override
  String get nextDay => 'اليوم التالي';
  @override
  String get previousWeek => 'الأسبوع السابق';
  @override
  String get nextWeek => 'الأسبوع التالي';
  @override
  String get previousResource => 'المورد السابق';
  @override
  String get nextResource => 'المورد التالي';
  @override
  String get putDown => 'وضع';
  @override
  String get cancelMove => 'إلغاء النقل';
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
extension on String {
  /// A timeline view's name: its span's ("Day") inside the timeline's own.
  String timeline(String type, String Function(String kind) name, {bool lower = false}) =>
      type.contains('imeline') && _viewKind(type) != null ? name(lower ? toLowerCase() : this) : this;
}

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
