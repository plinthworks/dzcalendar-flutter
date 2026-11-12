import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'book.dart';
import 'draft.dart';
import 'strings.dart';

/// Wider than this, the sidebar stays beside the calendar and the
/// inspector is a popover (macOS, tablets); narrower, a drawer and a sheet.
const wideFrom = 800.0;

/// Opens the inspector (owner's decision 47): on wide screens a popover
/// beside [anchor] (global; centered without), a sheet on phones. It runs
/// its commands itself, validated, so each save is one step of the history.
Future<void> showInspector(
  BuildContext context, {
  required CalendarBook book,
  required Draft draft,
  EventInstance? instance,
  Rect? anchor,
}) {
  final narrow = MediaQuery.sizeOf(context).width < wideFrom;
  final inspector = EventInspector(book: book, draft: draft, instance: instance, sheet: narrow);
  if (narrow) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => inspector,
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black12,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (context, _, _) => SafeArea(
      child: CustomSingleChildLayout(
        // The layout is inside the safe area: the anchor moved by its padding.
        delegate: _Popover(anchor?.shift(-MediaQuery.paddingOf(context).topLeft), Directionality.of(context)),
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: inspector,
        ),
      ),
    ),
  );
}

/// Beside the box: after it in the reading direction when there is room,
/// else before it, its top near the box's; centered when there is no box or
/// none fits (the box as wide as the screen).
class _Popover extends SingleChildLayoutDelegate {
  _Popover(this.anchor, this.direction);

  final Rect? anchor;
  final TextDirection direction;
  static const width = 380.0;
  static const gap = 14.0;
  static const margin = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints(maxWidth: width.clamp(0, c.maxWidth - 2 * margin), maxHeight: c.maxHeight - 2 * margin);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = anchor;
    // No box (nothing laid out yet): centered, not in a corner.
    if (a == null || a.isEmpty) return Offset((size.width - child.width) / 2, (size.height - child.height) / 3);
    final after = a.right + gap;
    final before = a.left - gap - child.width;
    final fitsAfter = after + child.width <= size.width - margin;
    final fitsBefore = before >= margin;
    final ltr = direction == TextDirection.ltr;
    final double x;
    if (ltr ? fitsAfter : !fitsBefore && fitsAfter) {
      x = after;
    } else if (fitsBefore) {
      x = before;
    } else {
      return Offset((size.width - child.width) / 2, (size.height - child.height) / 3);
    }
    final y = (a.top - 40).clamp(margin, (size.height - child.height - margin).clamp(margin, double.infinity));
    return Offset(x, y.toDouble());
  }

  @override
  bool shouldRelayout(_Popover old) => old.anchor != anchor || old.direction != direction;
}

class EventInspector extends StatefulWidget {
  const EventInspector({super.key, required this.book, required this.draft, this.instance, this.sheet = false});

  final CalendarBook book;
  final Draft draft;

  /// The event edited; null for a new one.
  final EventInstance? instance;

  /// In a bottom sheet (its own padding for the keyboard).
  final bool sheet;

  @override
  State<EventInspector> createState() => _EventInspectorState();
}

class _EventInspectorState extends State<EventInspector> {
  late final Draft _before = widget.draft;
  late final Draft _d = widget.draft.copy();
  late final _title = TextEditingController(text: _d.title);
  late final _place = TextEditingController(text: _d.place);
  late final _notes = TextEditingController(text: _d.notes);
  String? _error;

  CalendarBook get _book => widget.book;
  CalendarController get _controller => _book.controller;
  bool get _isNew => widget.instance == null;
  bool get _readOnly => _book.byId(_d.calendarId)?.readOnly ?? false;
  bool get _occurrence => widget.instance?.event.ref != null;

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _sync() {
    _d
      ..title = _title.text
      ..place = _place.text
      ..notes = _notes.text;
  }

  Future<void> _save() async {
    _sync();
    final s = S.of(context);
    if (_d.title.trim().isEmpty) _d.title = s.untitled;
    if (!_d.inOrder) return setState(() => _error = s.endBeforeStart);
    final Command? command;
    final instance = widget.instance;
    if (instance == null) {
      command = createCommand(_d, _book);
    } else {
      EditScope? scope;
      if (asksScope(instance, _before, _d)) {
        scope = await _askScope(s.changeWhich);
        if (scope == null || !mounted) return;
      }
      command = editCommand(instance, _before, _d, _book, scope: scope);
    }
    // Into an unticked calendar: ticked first (as macOS Calendar), so what is
    // shown is always what the ticked calendars hold.
    final target = _book.byId(_d.calendarId);
    if (command != null && target != null && !target.visible) _book.setVisible(target, true);
    if (command != null && !_controller.run(command, validate: true).ok) {
      return setState(() => _error = s.refused);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final instance = widget.instance;
    if (instance == null) return;
    var scope = EditScope.single;
    if (_occurrence) {
      final chosen = await _askScope(S.of(context).delete);
      if (chosen == null || !mounted) return;
      scope = chosen;
    }
    if (!_controller.run(deleteCommand(instance, scope: scope), validate: true).ok) {
      return setState(() => _error = S.of(context).refused);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<EditScope?> _askScope(String header) {
    final s = S.of(context);
    return showDialog<EditScope>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(header),
        children: [
          for (final (scope, label) in [
            (EditScope.single, s.scopeThis),
            (EditScope.following, s.scopeFollowing),
            (EditScope.all, s.scopeAll),
          ])
            SimpleDialogOption(onPressed: () => Navigator.pop(context, scope), child: Text(label)),
        ],
      ),
    );
  }

  // --- Dates and times ---------------------------------------------------------------

  int get _lengthMs => PlainDateTime(_d.endDate, _d.endTime).wallMs - PlainDateTime(_d.startDate, _d.startTime).wallMs;

  /// A new start keeps the length, as macOS Calendar does.
  void _setStart(PlainDate date, PlainTime time) {
    final length = _lengthMs;
    final days = _d.startDate.daysUntil(_d.endDate);
    setState(() {
      _d
        ..startDate = date
        ..startTime = time;
      if (_d.allDay) {
        _d.endDate = date.addDays(days < 0 ? 0 : days);
      } else {
        final end = PlainDateTime(date, time).addMs(length > 0 ? length : 3600000);
        _d
          ..endDate = end.date
          ..endTime = end.time;
      }
      _error = null;
    });
  }

  Future<PlainDate?> _pickDate(PlainDate at) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(at.year, at.month, at.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    return picked == null ? null : PlainDate(picked.year, picked.month, picked.day);
  }

  Future<PlainTime?> _pickTime(PlainTime at) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: at.hour, minute: at.minute),
    );
    return picked == null ? null : PlainTime(picked.hour, picked.minute);
  }

  Widget _when(String label, {required bool start}) {
    final date = start ? _d.startDate : _d.endDate;
    final time = start ? _d.startTime : _d.endTime;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateText = DateFormat.yMMMEd(locale).format(DateTime(date.year, date.month, date.day));
    final timeText = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: time.hour, minute: time.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final enabled = !_readOnly;
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label)),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: !enabled
                  ? null
                  : () async {
                      final d = await _pickDate(date);
                      if (d == null) return;
                      if (start) {
                        _setStart(d, _d.startTime);
                      } else {
                        setState(() {
                          _d.endDate = d;
                          _error = null;
                        });
                      }
                    },
              child: Text(dateText),
            ),
          ),
        ),
        if (!_d.allDay)
          TextButton(
            onPressed: !enabled
                ? null
                : () async {
                    final t = await _pickTime(time);
                    if (t == null) return;
                    if (start) {
                      _setStart(_d.startDate, t);
                    } else {
                      setState(() {
                        _d.endTime = t;
                        _error = null;
                      });
                    }
                  },
            child: Text(timeText),
          ),
      ],
    );
  }

  // --- The form ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final enabled = !_readOnly;
    final calendar = _book.byId(_d.calendarId);
    final choices = [..._book.writable, if (calendar != null && calendar.readOnly) calendar];
    final repeatChoices = [
      for (final p in RepeatPreset.values) (p, _presetName(s, p)),
      if (_d.repeat == null) (null, s.repeatCustom),
    ];

    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          enabled: enabled,
          autofocus: _isNew,
          style: theme.textTheme.titleMedium,
          decoration: InputDecoration(hintText: s.title, border: InputBorder.none),
          onSubmitted: (_) => _save(),
        ),
        TextField(
          controller: _place,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: s.place,
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.place_outlined, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 28),
          ),
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(s.allDay),
          value: _d.allDay,
          onChanged: !enabled ? null : (v) => setState(() => _d.allDay = v),
        ),
        _when(s.starts, start: true),
        _when(s.ends, start: false),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const Divider(),
        Row(
          children: [
            SizedBox(width: 96, child: Text(s.calendar)),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                underline: const SizedBox.shrink(),
                value: _d.calendarId,
                onChanged: !enabled ? null : (v) => setState(() => _d.calendarId = v ?? _d.calendarId),
                items: [
                  for (final c in choices)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: c.color),
                          const SizedBox(width: 8),
                          Expanded(child: Text(c.name(context), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(width: 96, child: Text(s.repeat)),
            Expanded(
              child: DropdownButton<RepeatPreset?>(
                isExpanded: true,
                underline: const SizedBox.shrink(),
                value: _d.repeat,
                onChanged: !enabled ? null : (v) => setState(() => _d.repeat = v),
                items: [for (final (p, name) in repeatChoices) DropdownMenuItem(value: p, child: Text(name))],
              ),
            ),
          ],
        ),
        if (_occurrence && _d.repeat != _before.repeat)
          Text(s.repeatOnlyAll, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        const Divider(),
        TextField(
          controller: _notes,
          enabled: enabled,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(hintText: s.notes, border: InputBorder.none),
        ),
        if (_readOnly)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(s.readOnly, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (!_isNew && enabled)
              IconButton(
                tooltip: s.delete,
                color: theme.colorScheme.error,
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            Expanded(
              // Larger text: the buttons go one under the other rather than overflow.
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 4,
                children: [
                  if (enabled) ...[
                    TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
                    FilledButton(onPressed: _save, child: Text(s.save)),
                  ] else
                    FilledButton.tonal(onPressed: () => Navigator.pop(context), child: Text(s.close)),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        widget.sheet ? 0 : 16,
        20,
        16 + (widget.sheet ? MediaQuery.viewInsetsOf(context).bottom : 0),
      ),
      child: form,
    );
  }

  static String _presetName(S s, RepeatPreset p) => switch (p) {
    RepeatPreset.never => s.repeatNever,
    RepeatPreset.daily => s.repeatDaily,
    RepeatPreset.weekly => s.repeatWeekly,
    RepeatPreset.monthly => s.repeatMonthly,
    RepeatPreset.yearly => s.repeatYearly,
  };
}
