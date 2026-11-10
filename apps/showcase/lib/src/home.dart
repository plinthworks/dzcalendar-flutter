import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dzcalendar/dzcalendar.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'app.dart';
import 'book.dart';
import 'demo.dart';
import 'draft.dart';
import 'inspector.dart';
import 'shots.dart';
import 'strings.dart';

/// The views of the switcher, in macOS Calendar's order.
const _views = {'timeGridDay': 0, 'timeGridWeek': 1, 'dayGridMonth': 2, 'multiMonthYear': 3};

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings, this.today, this.view, this.shot});

  final Settings settings;
  final PlainDate? today;

  /// The view at start (default: a week, a day on phones).
  final String? view;

  /// A gesture played at start, for screenshots (see [playShot]).
  final String? shot;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final CalendarController _controller;
  late final CalendarBook _book;

  /// For tests.
  @visibleForTesting
  CalendarBook get book => _book;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scaffold = GlobalKey<ScaffoldState>();

  /// Where the last finger or pointer went down: the inspector opens beside it.
  Offset? _anchor;
  late ZoneId _zone = widget.settings.zone;

  @override
  void initState() {
    super.initState();
    final frozen = widget.today;
    final zone = widget.settings.zone;
    final now = frozen == null ? null : ZonedDateTime.fromWall(PlainDateTime(frozen, PlainTime(10, 20)), zone)!.instant;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final narrow = view.physicalSize.width / view.devicePixelRatio < 600;
    _controller = CalendarController(
      KernelOptions(
        timeZone: zone,
        locale: widget.settings.locale.toLanguageTag(),
        initialDate: frozen,
        initialView: widget.view ?? (narrow ? 'timeGridDay' : 'timeGridWeek'),
        now: now == null ? null : () => now,
        options: ModelOptions(
          timeGrid: const TimeGridSettings(slotMinutes: 30),
          businessHours: BusinessHours([
            BusinessHoursRule(daysOfWeek: const [7, 1, 2, 3, 4], from: const WallTime(8), to: const WallTime(17)),
          ]),
        ),
      ),
      onCommandRefused: (_, _) => _say(S.of(context).refused),
    );
    _book = CalendarBook(_controller);
    loadDemo(_book, frozen ?? _controller.state.today);
    widget.settings.addListener(_settingsChanged);
    _search.addListener(() => setState(() {}));
    final shot = widget.shot;
    if (shot != null && shot.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => playShot(context, shot, search: _search));
    }
  }

  void _settingsChanged() {
    if (widget.settings.zone != _zone) {
      _zone = widget.settings.zone;
      _controller.setTimeZone(_zone);
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_settingsChanged);
    _search.dispose();
    _searchFocus.dispose();
    _book.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, width: _wide ? 420 : null));
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= wideFrom;

  // --- Opening the inspector -------------------------------------------------

  Future<void> _open(Draft draft, {EventInstance? instance}) async {
    // A pointer's place serves once: a later open from the keyboard or a
    // screen reader is centered, not beside an old click.
    final anchor = _wide ? _anchor : null;
    _anchor = null;
    await showInspector(context, book: _book, draft: draft, instance: instance, anchor: anchor);
    if (mounted) _controller.select(null);
  }

  void _openEvent(EventInstance instance) =>
      _open(Draft.of(instance, _book, _controller.state.timeZone), instance: instance);

  String? get _calendarForNew {
    final shown = _book.writable.where((c) => c.visible);
    return (shown.isNotEmpty ? shown.first : _book.writable.firstOrNull)?.id;
  }

  void _newAt(ZonedDateTime start, [ZonedDateTime? end]) {
    final calendar = _calendarForNew;
    if (calendar == null) return;
    _open(
      Draft.fresh(
        calendarId: calendar,
        title: S.of(context).untitled,
        start: start,
        end: end ?? ZonedDateTime(start.instant.add(const Duration(hours: 1)), start.zone),
      ),
    );
  }

  void _newOn(PlainDate first, [PlainDate? last]) {
    final calendar = _calendarForNew;
    if (calendar == null) return;
    _open(
      Draft.freshDays(
        calendarId: calendar,
        title: S.of(context).untitled,
        first: first,
        last: last ?? first,
        hour: PlainTime(9),
      ),
    );
  }

  /// The toolbar's "+": the next whole hour of the day shown.
  void _newEvent() {
    _anchor = null;
    final s = _controller.state;
    final now = ZonedDateTime(_controller.now(), s.timeZone);
    final hour = s.date == now.date ? (now.time.hour + 1).clamp(0, 23) : 9;
    _newAt(ZonedDateTime.fromWall(PlainDateTime(s.date, PlainTime(hour)), s.timeZone)!);
  }

  void _onSelect(CalendarSelection selection) => switch (selection) {
    TimeSelection(:final start, :final end) => _newAt(start, end),
    DaySelection(:final start, :final end) => _newOn(start, end.addDays(-1)),
  };

  void _onCreate(CreateRequest request) => switch (request) {
    CreateAt(:final start) => _newAt(ZonedDateTime(start, _controller.state.timeZone)),
    CreateOn(:final date) => _newOn(date),
  };

  void _onDateTap(Hit hit) {
    // In the year, a day opens it.
    if (_controller.state.view.type != 'multiMonthYear') return;
    if (hit case DayHit(:final date)) _controller.setView('timeGridDay', date);
  }

  // --- Search, import, export ----------------------------------------------------

  void _reveal(Found found) {
    final type = _controller.state.view.type;
    if (type == 'multiMonthYear') {
      _controller.setView('timeGridDay', found.date);
    } else {
      _controller.goTo(found.date);
    }
  }

  Future<void> _searchOnPhone() async {
    final found = await Navigator.of(context).push<Found>(
      MaterialPageRoute(
        builder: (_) => _SearchPage(book: _book, today: _controller.state.today),
      ),
    );
    if (found != null) _reveal(found);
  }

  Future<void> _import() async {
    final s = S.of(context);
    const group = XTypeGroup(
      label: 'iCalendar',
      extensions: ['ics'],
      mimeTypes: ['text/calendar'],
      uniformTypeIdentifiers: ['com.apple.ical.ics'],
    );
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [group]);
    } on PlatformException {
      _say(s.importFailed);
      return;
    }
    if (file == null) return;
    String text;
    try {
      text = await file.readAsString();
    } on Object {
      _say(s.importFailed);
      return;
    }
    if (!mounted) return;
    final name = file.name.replaceAll(RegExp(r'\.ics$', caseSensitive: false), '');
    final r = _book.importIcs(text, fallbackName: name);
    if (r == null) return _say(s.importFailed);
    final problems = r.problems.isEmpty ? '' : ' · ${s.importProblems(r.problems.length)}';
    if (!mounted) return;
    _say('${s.imported(r.count, r.calendar.name(context))}$problems');
  }

  Future<void> _export() async {
    final s = S.of(context);
    final text = _book.exportIcs(s.appTitle);
    if (text == null) return _say(s.nothingToExport);
    if (!kIsWeb && Platform.isMacOS) {
      final where = await getSaveLocation(
        suggestedName: 'dzcalendar.ics',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'iCalendar', extensions: ['ics']),
        ],
      );
      if (where == null) return;
      await XFile.fromData(utf8.encode(text), mimeType: 'text/calendar').saveTo(where.path);
      return;
    }
    if (!mounted) return;
    // Phones save no file without a share sheet: the text, to copy.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.exportIcs.replaceAll('…', '')),
        content: SizedBox(
          width: 520,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              _say(s.copied);
            },
            child: Text(s.copy),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.close)),
        ],
      ),
    );
  }

  Future<void> _settingsDialog() => showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(settings: widget.settings),
  );

  // --- Layout -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final wide = _wide;
    final s = S.of(context);
    final calendar = Listener(
      onPointerDown: (e) => _anchor = e.position,
      child: DzCalendar(
        controller: _controller,
        showHeader: false,
        views: _views.keys.toList(),
        editable: true,
        selectable: true,
        swipeToNavigate: !wide,
        eventColor: (i) => _book.calendarOf(i.event)?.color,
        onEventTap: _openEvent,
        onSelect: _onSelect,
        onCreateRequest: _onCreate,
        onDateTap: _onDateTap,
      ),
    );
    final searching = wide && _search.text.trim().isNotEmpty;
    final main = Column(
      children: [
        _Toolbar(
          controller: _controller,
          wide: wide,
          search: _search,
          searchFocus: _searchFocus,
          onMenu: () => _scaffold.currentState?.openDrawer(),
          onSearch: _searchOnPhone,
          onAdd: _newEvent,
          onImport: _import,
          onExport: _export,
          onSettings: _settingsDialog,
        ),
        const Divider(),
        Expanded(
          child: Row(
            children: [
              Expanded(child: calendar),
              if (searching) ...[
                const VerticalDivider(),
                SizedBox(
                  width: 300,
                  // Again on every change: a calendar unticked, an event edited or deleted.
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_book, _controller]),
                    builder: (context, _) => _SearchResults(
                      book: _book,
                      query: _search.text,
                      today: _controller.state.today,
                      onPick: _reveal,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final sidebar = _Sidebar(
      controller: _controller,
      book: _book,
      onImport: _import,
      onExport: _export,
      onDate: wide ? null : (_) => Navigator.of(context).maybePop(),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newEvent,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newEvent,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true): _controller.today,
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): _controller.today,
      },
      child: Scaffold(
        key: _scaffold,
        drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
        body: SafeArea(
          bottom: false,
          child: wide
              ? Row(
                  children: [
                    SizedBox(width: 252, child: sidebar),
                    const VerticalDivider(),
                    Expanded(child: main),
                  ],
                )
              : main,
        ),
        floatingActionButton: wide
            ? null
            : FloatingActionButton(onPressed: _newEvent, tooltip: s.newEvent, child: const Icon(Icons.add)),
      ),
    );
  }
}

// --- The toolbar ------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.wide,
    required this.search,
    required this.searchFocus,
    required this.onMenu,
    required this.onSearch,
    required this.onAdd,
    required this.onImport,
    required this.onExport,
    required this.onSettings,
  });

  final CalendarController controller;
  final bool wide;
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onMenu, onSearch, onAdd, onImport, onExport, onSettings;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final title = Text(
          state.title,
          style: (wide ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        );
        final views = SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(value: 'timeGridDay', label: Text(s.day)),
            ButtonSegment(value: 'timeGridWeek', label: Text(s.week)),
            ButtonSegment(value: 'dayGridMonth', label: Text(s.month)),
            ButtonSegment(value: 'multiMonthYear', label: Text(s.year)),
          ],
          selected: {state.view.type},
          onSelectionChanged: (v) => controller.setView(v.first),
        );
        final more = _MoreMenu(controller: controller, onImport: onImport, onExport: onExport, onSettings: onSettings);
        if (wide) {
          final field = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200, maxHeight: 36),
            child: TextField(
              controller: search,
              focusNode: searchFocus,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: s.search,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close, size: 16), onPressed: search.clear),
              ),
            ),
          );
          return LayoutBuilder(
            builder: (context, box) {
              // One line when the views fit beside the title; else the views below.
              final roomy = box.maxWidth >= 1000;
              final line = Row(
                children: [
                  Flexible(
                    child: OutlinedButton(
                      onPressed: controller.today,
                      child: Text(s.today, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(tooltip: s.previous, onPressed: controller.previous, icon: const Icon(Icons.chevron_left)),
                  IconButton(tooltip: s.next, onPressed: controller.next, icon: const Icon(Icons.chevron_right)),
                  const SizedBox(width: 8),
                  Expanded(child: title),
                  // Larger text (accessibility sizes) shrinks the switcher rather than overflow.
                  if (roomy) ...[
                    Flexible(
                      flex: 2,
                      child: FittedBox(fit: BoxFit.scaleDown, child: views),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Flexible(child: field),
                  IconButton(tooltip: s.newEvent, onPressed: onAdd, icon: const Icon(Icons.add)),
                  more,
                ],
              );
              return Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
                child: roomy
                    ? line
                    : Column(
                        children: [
                          line,
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: SizedBox(width: double.infinity, child: views),
                          ),
                        ],
                      ),
              );
            },
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(tooltip: s.showCalendars, onPressed: onMenu, icon: const Icon(Icons.menu)),
                  Expanded(child: title),
                  IconButton(tooltip: s.search, onPressed: onSearch, icon: const Icon(Icons.search)),
                  IconButton(tooltip: s.today, onPressed: controller.today, icon: const Icon(Icons.today)),
                  more,
                ],
              ),
              SizedBox(width: double.infinity, child: views),
            ],
          ),
        );
      },
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.controller, required this.onImport, required this.onExport, required this.onSettings});

  final CalendarController controller;
  final VoidCallback onImport, onExport, onSettings;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.undo),
          onPressed: controller.history.canUndo ? controller.undo : null,
          child: Text(s.undo),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.redo),
          onPressed: controller.history.canRedo ? controller.redo : null,
          child: Text(s.redo),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.file_open_outlined),
          onPressed: onImport,
          child: Text(s.importIcs),
        ),
        MenuItemButton(leadingIcon: const Icon(Icons.ios_share), onPressed: onExport, child: Text(s.exportIcs)),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined),
          onPressed: onSettings,
          child: Text(s.settings),
        ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.more_vert),
      ),
    );
  }
}

// --- The sidebar --------------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.book,
    required this.onImport,
    required this.onExport,
    this.onDate,
  });

  final CalendarController controller;
  final CalendarBook book;
  final VoidCallback onImport, onExport;
  final ValueChanged<PlainDate>? onDate;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListenableBuilder(
        listenable: book,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: MiniMonth.controller(controller, onDateSelected: onDate),
            ),
            const SizedBox(height: 8),
            const Divider(),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
              child: Text(s.calendars, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline)),
            ),
            for (final c in book.calendars)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                visualDensity: VisualDensity.compact,
                value: c.visible,
                onChanged: (v) => book.setVisible(c, v ?? true),
                fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? c.color : null),
                side: BorderSide(color: c.color, width: 2),
                title: Text(c.name(context), overflow: TextOverflow.ellipsis),
                secondary: c.readOnly ? Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.outline) : null,
              ),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.file_open_outlined, size: 20),
              title: Text(s.importIcs),
              onTap: onImport,
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.ios_share, size: 20),
              title: Text(s.exportIcs),
              onTap: onExport,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Search ---------------------------------------------------------------------------

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.book, required this.query, required this.today, required this.onPick});

  final CalendarBook book;
  final String query;
  final PlainDate today;
  final ValueChanged<Found> onPick;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final found = book.search(query, today);
    if (found.isEmpty) {
      return Center(
        child: Text(s.noResults, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      );
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateFormat = DateFormat.yMMMEd(locale);
    final timeFormat = MediaQuery.alwaysUse24HourFormatOf(context) ? DateFormat.Hm(locale) : DateFormat.jm(locale);
    final zone = book.controller.state.timeZone;
    return ListView.separated(
      itemCount: found.length,
      separatorBuilder: (_, _) => const Divider(indent: 16),
      itemBuilder: (context, k) {
        final f = found[k];
        final e = f.instance.event;
        final date = dateFormat.format(DateTime(f.date.year, f.date.month, f.date.day));
        final when = switch (e) {
          TimedEvent(:final start) => () {
            final t = ZonedDateTime(start.instant, zone).time;
            return '$date · ${timeFormat.format(DateTime(2000, 1, 1, t.hour, t.minute))}';
          }(),
          AllDayEvent() => date,
        };
        return ListTile(
          dense: true,
          leading: Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(color: f.calendar.color, borderRadius: BorderRadius.circular(2)),
          ),
          title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(when),
          onTap: () => onPick(f),
        );
      },
    );
  }
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.book, required this.today});

  final CalendarBook book;
  final PlainDate today;

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: s.search, border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: _query.text.trim().isEmpty
          ? const SizedBox.shrink()
          : _SearchResults(
              book: widget.book,
              query: _query.text,
              today: widget.today,
              onPick: (f) => Navigator.pop(context, f),
            ),
    );
  }
}

// --- Settings ----------------------------------------------------------------------------

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.settings});

  final Settings settings;

  static const _languageNames = {'fr': 'Français', 'en': 'English', 'ar': 'العربية'};

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => AlertDialog(
        title: Text(s.settings),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.language, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final l in Settings.locales)
                    ButtonSegment(value: l.languageCode, label: Text(_languageNames[l.languageCode]!)),
                ],
                selected: {settings.locale.languageCode},
                onSelectionChanged: (v) => settings.update(locale: Locale(v.first)),
              ),
              const SizedBox(height: 16),
              Text(s.timeZone, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: settings.zone,
                items: [for (final z in Settings.zones) DropdownMenuItem(value: z, child: Text(z))],
                onChanged: (z) => settings.update(zone: z),
              ),
              const SizedBox(height: 16),
              Text(s.appearance, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(s.system)),
                  ButtonSegment(value: ThemeMode.light, label: Text(s.light)),
                  ButtonSegment(value: ThemeMode.dark, label: Text(s.dark)),
                ],
                selected: {settings.mode},
                onSelectionChanged: (v) => settings.update(mode: v.first),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.close))],
      ),
    );
  }
}
