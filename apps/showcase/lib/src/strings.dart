import 'package:flutter/widgets.dart';

/// The showcase's own words (the calendar's come from the library), in the
/// three languages the library speaks. A small table, not a generator: the
/// app has few words.
class S {
  const S._(this._t, this.languageCode);

  final Map<String, String> _t;
  final String languageCode;

  static S of(BuildContext context) => forLocale(Localizations.localeOf(context));

  static S forLocale(Locale locale) => switch (locale.languageCode) {
    'ar' => const S._(_ar, 'ar'),
    'en' => const S._(_en, 'en'),
    _ => const S._(_fr, 'fr'),
  };

  String _(String key) => _t[key] ?? _fr[key] ?? key;

  String get appTitle => _('appTitle');
  String get calendars => _('calendars');
  String get today => _('today');
  String get previous => _('previous');
  String get next => _('next');
  String get day => _('day');
  String get week => _('week');
  String get month => _('month');
  String get year => _('year');
  String get agenda => _('agenda');
  String get search => _('search');
  String get noResults => _('noResults');
  String get newEvent => _('newEvent');
  String get editEvent => _('editEvent');
  String get title => _('title');
  String get untitled => _('untitled');
  String get place => _('place');
  String get allDay => _('allDay');
  String get starts => _('starts');
  String get ends => _('ends');
  String get calendar => _('calendar');
  String get repeat => _('repeat');
  String get repeatNever => _('repeatNever');
  String get repeatDaily => _('repeatDaily');
  String get repeatWeekly => _('repeatWeekly');
  String get repeatMonthly => _('repeatMonthly');
  String get repeatYearly => _('repeatYearly');
  String get repeatCustom => _('repeatCustom');
  String get notes => _('notes');
  String get save => _('save');
  String get cancel => _('cancel');
  String get delete => _('delete');
  String get deleteSeries => _('deleteSeries');
  String get readOnly => _('readOnly');
  String get endBeforeStart => _('endBeforeStart');
  String get importIcs => _('importIcs');
  String get exportIcs => _('exportIcs');
  String get copied => _('copied');
  String get copy => _('copy');
  String get close => _('close');
  String get undo => _('undo');
  String get redo => _('redo');
  String get language => _('language');
  String get timeZone => _('timeZone');
  String get appearance => _('appearance');
  String get system => _('system');
  String get light => _('light');
  String get dark => _('dark');
  String get hijri => _('hijri');
  String get hijriOff => _('hijriOff');
  String get hijriBeside => _('hijriBeside');
  String get hijriMain => _('hijriMain');
  String get settings => _('settings');
  String get refused => _('refused');
  String get changeWhich => _('changeWhich');
  String get scopeThis => _('scopeThis');
  String get scopeFollowing => _('scopeFollowing');
  String get scopeAll => _('scopeAll');
  String get repeatOnlyAll => _('repeatOnlyAll');
  String imported(int n, String name) => _('imported').replaceAll('{n}', '$n').replaceAll('{name}', name);
  String importProblems(int n) => _('importProblems').replaceAll('{n}', '$n');
  String get importFailed => _('importFailed');
  String get nothingToExport => _('nothingToExport');
  String get calendarWork => _('calendarWork');
  String get calendarHome => _('calendarHome');
  String get calendarHolidays => _('calendarHolidays');
  String get calendarSport => _('calendarSport');
  String get showCalendars => _('showCalendars');
}

const _fr = {
  'appTitle': 'Calendrier DzCalendar',
  'calendars': 'Calendriers',
  'today': "Aujourd'hui",
  'previous': 'Précédent',
  'next': 'Suivant',
  'day': 'Jour',
  'week': 'Semaine',
  'month': 'Mois',
  'year': 'Année',
  'agenda': 'Agenda',
  'search': 'Rechercher',
  'noResults': 'Aucun événement trouvé',
  'newEvent': 'Nouvel événement',
  'editEvent': "Modifier l'événement",
  'title': 'Titre',
  'untitled': 'Nouvel événement',
  'place': 'Lieu',
  'allDay': 'Toute la journée',
  'starts': 'Début',
  'ends': 'Fin',
  'calendar': 'Calendrier',
  'repeat': 'Répétition',
  'repeatNever': 'Jamais',
  'repeatDaily': 'Chaque jour',
  'repeatWeekly': 'Chaque semaine',
  'repeatMonthly': 'Chaque mois',
  'repeatYearly': 'Chaque année',
  'repeatCustom': 'Personnalisée',
  'notes': 'Notes',
  'save': 'Enregistrer',
  'cancel': 'Annuler',
  'delete': "Supprimer l'événement",
  'deleteSeries': 'Supprimer toute la série',
  'readOnly': 'Ce calendrier est en lecture seule.',
  'endBeforeStart': 'La fin doit venir après le début.',
  'importIcs': 'Importer un fichier .ics…',
  'exportIcs': 'Exporter en .ics…',
  'copied': 'Copié dans le presse-papiers',
  'copy': 'Copier',
  'close': 'Fermer',
  'undo': 'Annuler',
  'redo': 'Rétablir',
  'language': 'Langue',
  'timeZone': 'Fuseau horaire',
  'appearance': 'Apparence',
  'system': 'Système',
  'light': 'Clair',
  'dark': 'Sombre',
  'hijri': 'Calendrier hégirien',
  'hijriOff': 'Non',
  'hijriBeside': 'À côté',
  'hijriMain': 'Principal',
  'settings': 'Réglages',
  'refused': 'Modification refusée',
  'changeWhich': 'Modifier quelles occurrences ?',
  'scopeThis': 'Celle-ci seulement',
  'scopeFollowing': 'Celle-ci et les suivantes',
  'scopeAll': 'Toutes',
  'repeatOnlyAll': 'La répétition change pour toute la série.',
  'imported': '{n} événement(s) importé(s) dans « {name} »',
  'importProblems': '{n} problème(s) signalé(s) à la lecture',
  'importFailed': "Ce fichier n'a pas pu être lu.",
  'nothingToExport': 'Aucun événement à exporter',
  'calendarWork': 'Cabinet',
  'calendarHome': 'Maison',
  'calendarHolidays': 'Jours fériés (Algérie)',
  'calendarSport': 'Sport',
  'showCalendars': 'Afficher les calendriers',
};

const _en = {
  'appTitle': 'DzCalendar Calendar',
  'calendars': 'Calendars',
  'today': 'Today',
  'previous': 'Previous',
  'next': 'Next',
  'day': 'Day',
  'week': 'Week',
  'month': 'Month',
  'year': 'Year',
  'agenda': 'Agenda',
  'search': 'Search',
  'noResults': 'No events found',
  'newEvent': 'New event',
  'editEvent': 'Edit event',
  'title': 'Title',
  'untitled': 'New event',
  'place': 'Location',
  'allDay': 'All day',
  'starts': 'Starts',
  'ends': 'Ends',
  'calendar': 'Calendar',
  'repeat': 'Repeat',
  'repeatNever': 'Never',
  'repeatDaily': 'Every day',
  'repeatWeekly': 'Every week',
  'repeatMonthly': 'Every month',
  'repeatYearly': 'Every year',
  'repeatCustom': 'Custom',
  'notes': 'Notes',
  'save': 'Save',
  'cancel': 'Cancel',
  'delete': 'Delete event',
  'deleteSeries': 'Delete the whole series',
  'readOnly': 'This calendar is read-only.',
  'endBeforeStart': 'The end must come after the start.',
  'importIcs': 'Import an .ics file…',
  'exportIcs': 'Export as .ics…',
  'copied': 'Copied to the clipboard',
  'copy': 'Copy',
  'close': 'Close',
  'undo': 'Undo',
  'redo': 'Redo',
  'language': 'Language',
  'timeZone': 'Time zone',
  'appearance': 'Appearance',
  'system': 'System',
  'light': 'Light',
  'dark': 'Dark',
  'hijri': 'Hijri calendar',
  'hijriOff': 'Off',
  'hijriBeside': 'Beside',
  'hijriMain': 'Main',
  'settings': 'Settings',
  'refused': 'Change refused',
  'changeWhich': 'Change which occurrences?',
  'scopeThis': 'This one only',
  'scopeFollowing': 'This and following',
  'scopeAll': 'All',
  'repeatOnlyAll': 'The repeat changes for the whole series.',
  'imported': '{n} event(s) imported into “{name}”',
  'importProblems': '{n} problem(s) reported while reading',
  'importFailed': 'This file could not be read.',
  'nothingToExport': 'No events to export',
  'calendarWork': 'Practice',
  'calendarHome': 'Home',
  'calendarHolidays': 'Public holidays (Algeria)',
  'calendarSport': 'Sport',
  'showCalendars': 'Show calendars',
};

const _ar = {
  'appTitle': 'تقويم DzCalendar',
  'calendars': 'التقويمات',
  'today': 'اليوم',
  'previous': 'السابق',
  'next': 'التالي',
  'day': 'يوم',
  'week': 'أسبوع',
  'month': 'شهر',
  'year': 'سنة',
  'agenda': 'جدول',
  'search': 'بحث',
  'noResults': 'لا توجد أحداث',
  'newEvent': 'حدث جديد',
  'editEvent': 'تعديل الحدث',
  'title': 'العنوان',
  'untitled': 'حدث جديد',
  'place': 'المكان',
  'allDay': 'طوال اليوم',
  'starts': 'البداية',
  'ends': 'النهاية',
  'calendar': 'التقويم',
  'repeat': 'التكرار',
  'repeatNever': 'أبدًا',
  'repeatDaily': 'كل يوم',
  'repeatWeekly': 'كل أسبوع',
  'repeatMonthly': 'كل شهر',
  'repeatYearly': 'كل سنة',
  'repeatCustom': 'مخصص',
  'notes': 'ملاحظات',
  'save': 'حفظ',
  'cancel': 'إلغاء',
  'delete': 'حذف الحدث',
  'deleteSeries': 'حذف السلسلة كاملة',
  'readOnly': 'هذا التقويم للقراءة فقط.',
  'endBeforeStart': 'يجب أن تأتي النهاية بعد البداية.',
  'importIcs': 'استيراد ملف ‎.ics…',
  'exportIcs': 'تصدير بصيغة ‎.ics…',
  'copied': 'نُسخ إلى الحافظة',
  'copy': 'نسخ',
  'close': 'إغلاق',
  'undo': 'تراجع',
  'redo': 'إعادة',
  'language': 'اللغة',
  'timeZone': 'المنطقة الزمنية',
  'appearance': 'المظهر',
  'system': 'النظام',
  'light': 'فاتح',
  'dark': 'داكن',
  'hijri': 'التقويم الهجري',
  'hijriOff': 'لا',
  'hijriBeside': 'بجانبه',
  'hijriMain': 'رئيسي',
  'settings': 'الإعدادات',
  'refused': 'رُفض التعديل',
  'changeWhich': 'تعديل أي تكرارات؟',
  'scopeThis': 'هذا فقط',
  'scopeFollowing': 'هذا وما يليه',
  'scopeAll': 'الكل',
  'repeatOnlyAll': 'يتغير التكرار للسلسلة كاملة.',
  'imported': 'استُورد {n} حدث في «{name}»',
  'importProblems': 'أُبلغ عن {n} مشكلة أثناء القراءة',
  'importFailed': 'تعذرت قراءة هذا الملف.',
  'nothingToExport': 'لا أحداث للتصدير',
  'calendarWork': 'العيادة',
  'calendarHome': 'المنزل',
  'calendarHolidays': 'العطل الرسمية (الجزائر)',
  'calendarSport': 'رياضة',
  'showCalendars': 'عرض التقويمات',
};
