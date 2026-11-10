import 'dart:async';

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'env.dart';
import 'interaction.dart';
import 'l10n/localizations.dart';

/// Where a view says a stepped hit may stand.
sealed class KeyFit {
  const KeyFit();
}

/// Here (kept inside what the view draws: a slot clamped to its column's hours).
final class FitAt extends KeyFit {
  const FitAt(this.hit);
  final Hit hit;
}

/// Its day is before or after the period: the keyboard changes period.
final class FitOff extends KeyFit {
  const FitOff({required this.next});
  final bool next;
}

/// What a view gives the keyboard (owner's decision 41, the TS's
/// `KeyboardSurface`): where the cursor may stand, its lines, its events.
/// Moving the cursor, selecting from it and holding an event are the same
/// code for every view ([CalendarKeyboard]). The view draws the cursor from
/// [CalendarKeyboard.cursor]. Read from the controller's current model, so
/// a period the keyboard just went to is known before it is built.
abstract interface class KeySurface {
  KeyGrid get keyGrid;

  /// Where the cursor stands when the calendar first takes the focus: today
  /// if shown (the slot of now when in view), else the first day.
  Hit? home();

  /// [hit] kept inside what is drawn; [FitOff] when its day is not in the
  /// period; null on a day that has no time (skipped by its zone, hidden).
  KeyFit? fit(Hit hit);

  /// The first or last place of the cursor's line: a week row, a day's hours.
  Hit lineEdge(Hit hit, Edge edge);

  /// The events Enter walks into from [hit] (a month's day; none in a time grid).
  List<EventInstance> itemsAt(Hit hit);

  /// The events in view, in reading order (Tab).
  List<EventInstance> items();

  /// The events next to [instance], its day's, in reading order.
  List<EventInstance> itemsAround(EventInstance instance);

  /// The cursor's place for an event (Escape from it).
  Hit? cursorFor(EventInstance instance);

  /// A time grid with an all-day row: up from the first slot goes there.
  bool get allDayRow;

  /// The top slot in view on a day (down from the all-day row).
  Hit? firstSlot(PlainDate date, ResourceId? resourceId);

  /// A resource view (Alt+arrows go across resources).
  bool get resourceView;

  /// The same day and time in the next or previous resource's column; null: none that way.
  Hit? stepAcross(Hit hit, int delta);

  /// Scrolls so that [hit] is in view.
  void reveal(Hit hit);
}

/// What the held event's semantics say and do while the keyboard or a
/// screen reader holds it.
@immutable
final class GrabInfo {
  const GrabInfo({
    required this.key,
    required this.value,
    required this.increased,
    required this.decreased,
    required this.grid,
  });
  final String key;

  /// Where it would go now, in words.
  final String value;

  /// Where a swipe up or down would take it (what an adjustable node says it becomes).
  final String increased;
  final String decreased;
  final KeyGrid grid;

  @override
  bool operator ==(Object other) =>
      other is GrabInfo &&
      other.key == key &&
      other.value == value &&
      other.increased == increased &&
      other.decreased == decreased &&
      other.grid == grid;

  @override
  int get hashCode => Object.hash(key, value, increased, decreased, grid);
}

class _Grab {
  _Grab({required this.instance, required this.mode, required this.resourceId}) : event = instance.event;
  final EventInstance instance;

  /// The event as the last step left it.
  CalEvent event;
  Proposal? proposal;

  /// What Enter puts down: the last thing done (a move, or a resize).
  GrabKind kind = GrabKind.move;
  Edge edge = Edge.end;

  /// How it was taken: to move it (M, "Move…") or to change its length.
  final GrabKind mode;

  /// In a resource view, the column it is in now.
  ResourceId? resourceId;

  /// The calendar had the focus while it was held: losing it lets go.
  var focused = false;
}

/// The keyboard on a calendar (owner's decisions 41–43; ARCHITECTURE D.3,
/// D.6). The calendar is one focus point; the cursor is a [Hit] moved by
/// the core's `stepHit`; Shift extends a selection from where it started
/// (`selectionBetween`, as a finger's drag); Tab goes through the events;
/// on an event, M or Alt+Enter holds it: each arrow is a `grabStep` (the
/// finger's proposals), Enter puts it down through
/// [CalendarInteraction.commit] — refusal, scope, history, announcement —
/// exactly as a drop. A screen reader holds an event from its "Move…"
/// action: swiping up or down steps it, a double tap puts it down. Every
/// step is said.
class CalendarKeyboard {
  CalendarKeyboard(this._x) {
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  final CalendarInteraction _x;
  CalendarEnv get _env => _x.env;
  DzCalendarLocalizations get _l => _env.l10n;

  /// The calendar's one focus point.
  final node = FocusNode(debugLabel: 'DzCalendar');

  KeySurface? _surface;
  Hit? _cursor;
  EventInstance? _event;

  /// Where Shift started: the selection runs from here to the cursor.
  Hit? _anchor;

  /// The selection last given to `onSelect` from the keyboard.
  CalendarSelection? _handed;
  _Grab? _grab;
  var _committing = false;
  var _ownNavs = 0;
  var _disposed = false;

  /// The cursor, drawn by the view (null: not shown — no keyboard focus).
  final cursor = ValueNotifier<Hit?>(null);

  /// The event the keyboard is on, outlined (its instance key).
  final focused = ValueNotifier<String?>(null);

  /// The event held by the keyboard or a screen reader.
  final held = ValueNotifier<GrabInfo?>(null);

  bool get grabbing => _grab != null;

  /// Held to change its length: no day actions for a reader.
  bool get grabbingLength => _grab?.mode == GrabKind.resize;

  /// The view now on screen offers itself; the one that leaves takes itself back.
  void attach(KeySurface s) => _surface = s;

  void detach(KeySurface s) {
    if (identical(_surface, s)) _surface = null;
  }

  ZoneId get _zone => _env.zone;
  int get _snap => _env.config.snapMinutes;
  InteractionContext _ctx() => _env.controller.kernel.interactionContext(snapMinutes: _snap);

  // ——— focus ———

  bool get _visible => node.hasFocus && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  void _redraw() {
    if (_disposed) return;
    cursor.value = _visible && _event == null && _grab == null ? _cursor : null;
    focused.value = _visible && _grab == null ? _event?.key : null;
  }

  void _modeChanged(FocusHighlightMode _) => _redraw();

  /// The calendar took or lost the focus: the cursor takes its place (today,
  /// at the hour in view); the focus gone, a held event is let go.
  void focusChanged(bool has) {
    final g = _grab;
    if (has) {
      g?.focused = true;
      if (_cursor == null && _event == null) _cursor = _surface?.home();
    } else if (g != null && g.focused && !_committing) {
      _letGo(said: true);
    }
    _redraw();
  }

  /// A tap on a day or a slot: the keyboard goes on from there.
  void tapped(Hit hit) {
    // The slot the tap is in, not the moment under the finger.
    final start = hit is SlotHit ? hit.slotStart : null;
    _cursor = hit is SlotHit && start != null
        ? SlotHit(date: hit.date, instant: start, resourceId: hit.resourceId)
        : hit;
    _event = null;
    _anchor = null;
    node.requestFocus();
    _redraw();
  }

  /// The events shown changed (a filter, a deletion, an undo): the cursor
  /// on one no longer drawn, or holding it, goes back to its day; a held
  /// one is let go — Enter or Delete never reach an event out of sight.
  void dropGone() {
    final s = _surface;
    if (s == null || _committing) return;
    final keys = {for (final i in s.items()) i.key};
    final g = _grab;
    if (g != null && !keys.contains(g.instance.key)) _letGo(said: true);
    final held = _x.held.value;
    if (held != null && !keys.contains(held)) _x.release();
    final e = _event;
    if (e == null || keys.contains(e.key)) return;
    _event = null;
    _cursor ??= s.home();
    _redraw();
  }

  /// A tap on an event: the keyboard goes on from it.
  void tappedEvent(EventInstance i) {
    _event = i;
    _anchor = null;
    node.requestFocus();
    _redraw();
  }

  /// Another period, view or zone, not the keyboard's doing: a held event is
  /// let go; the cursor is placed again at the next key.
  void periodChanged() {
    if (_ownNavs > 0) {
      _ownNavs = 0;
      // Drawn again once the new period is built.
      if (_grab != null) SchedulerBinding.instance.addPostFrameCallback((_) => _grab != null ? _drawGrab() : null);
      return;
    }
    if (_grab != null && !_committing) _letGo(said: true);
    _event = null;
    _anchor = null;
    _redraw();
  }

  // ——— words ———

  String _day(PlainDate d) => formatTemporal(d, 'MMMMEEEEd', _env.locale);

  String _resourceTitle(ResourceId id) =>
      id == unassignedId ? _l.unassigned : (_env.controller.kernel.resources.byId[id]?.resource.title ?? id);

  /// The cursor's place in words, its resource first ("Dr Ali, Wednesday 21 October, 09:30").
  String hitLabel(Hit hit) {
    final place = switch (hit) {
      DayHit(:final date, :final allDayRow) => allDayRow ? _l.cursorAllDay(_day(date)) : _day(date),
      SlotHit(:final date, :final instant) => _l.cursorSlot(_day(date), _x.timeWords(instant)),
    };
    final r = hit.resourceId;
    return r == null ? place : _l.ofResource(_resourceTitle(r), place);
  }

  String _moments(Instant a, Instant b) {
    final za = ZonedDateTime(a, _zone);
    final zb = ZonedDateTime(b, _zone);
    final sameDay = za.date == zb.date || (zb.time == PlainTime(0, 0) && za.date.addDays(1) == zb.date);
    return sameDay
        ? '${_day(za.date)}, ${_l.range(_x.timeWords(a), _x.timeWords(b))}'
        : _l.range('${_day(za.date)} ${_x.timeWords(a)}', '${_day(zb.date)} ${_x.timeWords(b)}');
  }

  String _days(PlainDate first, PlainDate end) {
    final last = end.addDays(-1);
    return !last.isAfter(first) ? _day(first) : _l.range(_day(first), _day(last));
  }

  /// An event's span as a selection would say it.
  static CalendarSelection _spanOf(CalEvent ev) => switch (ev) {
    TimedEvent(:final start, :final end) => TimeSelection(start: start, end: end),
    AllDayEvent(:final start, :final end) => DaySelection(start: start, end: end),
  };

  String _spanWords(CalendarSelection s) => switch (s) {
    DaySelection(:final start, :final end) => _days(start, end),
    TimeSelection(:final start, :final end) => _moments(start.instant, end.instant),
  };

  /// Where a held event would go: its time, its resources when they change,
  /// a change of kind, a skipped hour, a refusal.
  String proposalWords(Proposal p, CalEvent was) {
    final ev = p.proposed;
    var text = switch (ev) {
      TimedEvent(:final start, :final end) => _moments(start.instant, end.instant),
      AllDayEvent(:final start, :final end) => _days(start, end),
    };
    if (ev.resourceIds.join('\u0000') != was.resourceIds.join('\u0000')) {
      for (final id in ev.resourceIds.reversed) {
        text = _l.ofResource(_resourceTitle(id), text);
      }
    }
    if (ev.allDay != was.allDay) text += '. ${ev.allDay ? _l.becomesAllDay : _l.becomesTimed(_x.lengthWords(ev))}';
    if (p.skipped) text += '. ${_l.skippedHour}';
    if (!p.valid) text += '. ${_x.refusalWords(p)}';
    return text;
  }

  void _say(String text) => _x.say(text);

  // ——— keys ———

  /// A key on the calendar: the core's keymap (`intentFor`) says what it means.
  KeyEventResult onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final s = _surface;
    final k = keyLikeOf(e);
    if (s == null || k == null) return KeyEventResult.ignored;
    // Held down, only the moves repeat: not Enter, Space, M, Delete, Escape.
    if (e is KeyRepeatEvent && !_repeats.contains(k.key)) {
      return _grab != null || _event != null || _cursor != null ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final rtl = _env.textDirection == TextDirection.rtl;
    final handled = _grab != null ? _onGrab(k, s, rtl) : _onKey(k, s, rtl);
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _onKey(KeyLike k, KeySurface s, bool rtl) {
    if (k.key == 'Tab' && !k.alt && !k.ctrl && !k.meta) return _tab(s, back: k.shift);
    final ev = _event;
    final intent = intentFor(k, mode: ev != null ? KeyMode.event : KeyMode.cursor, grid: s.keyGrid, rtl: rtl);
    if (intent == null) return false;
    if (intent case CommandKeyIntent(kind: KeyCommand.undo || KeyCommand.redo)) {
      return _undo(redo: intent.kind == KeyCommand.redo);
    }
    if (ev != null) return _onEvent(intent, ev, s);
    final at = _cursor;
    final f = at == null ? null : s.fit(at);
    // No place yet, or the period changed under it (the app navigated): it starts again at home.
    if (at == null || f is! FitAt) {
      final home = s.home();
      if (home == null) return false;
      _show(home, s);
      _say(hitLabel(home));
      return true;
    }
    return _onCursor(intent, f.hit, s);
  }

  /// Ctrl+Z / ⌘Z, Shift+Ctrl+Z, Ctrl+Y: an editable calendar's (decision 43).
  bool _undo({required bool redo}) {
    final config = _env.config;
    if (!config.editable || !config.keyboardUndo) return false;
    final c = _env.controller;
    if (redo ? c.redo() : c.undo()) _say(redo ? _l.redone : _l.undone);
    return true;
  }

  // ——— the cursor ———

  void _show(Hit hit, KeySurface s) {
    _cursor = hit;
    _event = null;
    s.reveal(hit);
    _redraw();
  }

  bool _onCursor(KeyIntent intent, Hit at, KeySurface s) {
    switch (intent) {
      case MoveKeyIntent(:final step, :final extend):
        return _moveCursor(at, _land(s, at, stepHit(_zone, _snap, at, step), step), extend, s);
      case LineKeyIntent(:final edge, :final extend):
        return _moveCursor(at, s.lineEdge(at, edge), extend, s);
      case AcrossKeyIntent(:final delta):
        // Not a resource view: Alt+arrows are not the calendar's.
        if (!s.resourceView) return false;
        return _moveCursor(at, s.stepAcross(at, delta), false, s);
      case PeriodKeyIntent(:final next):
        return _period(at, next, s);
      case CommandKeyIntent(kind: KeyCommand.enter):
        // A selection being made: Enter gives it to the app, even on a day with events.
        if (_anchor != null) return _activate(at);
        final items = s.itemsAt(at);
        if (items.isNotEmpty) {
          _focusEvent(items.first, s);
          return true;
        }
        return _activate(at);
      case CommandKeyIntent(kind: KeyCommand.activate):
        return _activate(at);
      case CommandKeyIntent(kind: KeyCommand.cancel):
        final c = _env.controller;
        if (_anchor == null && c.selection == null) return false;
        final had = c.selection != null;
        _anchor = null;
        c.select(null);
        if (had) _say(_l.selectionCleared);
        return true;
      default:
        return false;
    }
  }

  bool _moveCursor(Hit from, Hit? to, bool extend, KeySurface s) {
    if (to == null || (_sameHit(from, to) && !extend)) {
      _say(_l.noFurther);
      return true;
    }
    final c = _env.controller;
    if (extend && _env.config.selectable) {
      _anchor ??= from;
    } else if (_anchor != null || c.selection != null) {
      _anchor = null;
      c.select(null);
    }
    _show(to, s);
    final a = _anchor;
    if (a != null) {
      final sel = selectionBetween(_ctx(), a, to);
      c.select(sel);
      _say(_l.selected(_spanWords(sel)));
    } else {
      _say(hitLabel(to));
    }
    return true;
  }

  /// A stepped hit, kept inside what the view draws: another period when it
  /// left this one, past a day that has no time (or a hidden one), and in a
  /// time grid between the all-day row and the hours. Null: nowhere to go.
  Hit? _land(KeySurface s, Hit from, Hit to, KeyStep step, {bool mayNavigate = true}) {
    if (s.keyGrid == KeyGrid.time && step.slots != 0 && from is DayHit) {
      return step.slots > 0 ? s.firstSlot(from.date, from.resourceId) : null;
    }
    var target = to;
    // Up to six more days: past a skipped day, or the hidden days of a week.
    for (var tries = 0; tries < 7; tries++) {
      var f = s.fit(target);
      if (f is FitOff) {
        // A fixed period does not move.
        if (!mayNavigate || _env.state.view.visibleRange != null) return null;
        _navigate(next: f.next);
        f = s.fit(target);
      }
      if (f is FitAt) {
        final h = f.hit;
        // Up from the first slot of a day: its all-day row.
        if (s.keyGrid == KeyGrid.time &&
            s.allDayRow &&
            step.slots < 0 &&
            from is SlotHit &&
            h is SlotHit &&
            h.instant.epochMilliseconds == from.instant.epochMilliseconds) {
          return DayHit(date: from.date, allDayRow: true, resourceId: from.resourceId);
        }
        return h;
      }
      if (f != null || step.days == 0) return null;
      // From where it started, one day further each time: the wall time is kept from there.
      target = stepHit(_zone, _snap, from, KeyStep(days: step.days + step.days.sign * (tries + 1), slots: step.slots));
    }
    return null;
  }

  void _navigate({required bool next}) {
    final c = _env.controller;
    final before = c.state.range.start;
    _ownNavs++;
    next ? c.next() : c.previous();
    // Nowhere to go (a valid range's end): nothing will be told, nothing to wait for.
    if (c.state.range.start == before) _ownNavs--;
  }

  /// PageUp / PageDown: the period before or after, the cursor's date moved by
  /// the view's own step (a month: the 31st becomes the 30th).
  bool _period(Hit at, bool next, KeySurface s) {
    final c = _env.controller;
    final before = c.state;
    final spec = before.view;
    if (spec.visibleRange != null) {
      _say(_l.noFurther);
      return true;
    }
    _navigate(next: next);
    final sign = next ? 1 : -1;
    final PlainDate target;
    if (spec.dayCount == null || spec.dateIncrement != null) {
      final d = spec.dateIncrement ?? spec.duration;
      target = at.date.addMonths(sign * (d.years * 12 + d.months)).addDays(sign * (d.weeks * 7 + d.days));
    } else {
      target = at.date.addDays(before.range.start.daysUntil(c.state.range.start));
    }
    final moved = stepHit(_zone, _snap, at, KeyStep(days: at.date.daysUntil(target)));
    final f = s.fit(moved);
    final to = f is FitAt ? f.hit : s.home();
    if (to == null) return true;
    _anchor = null;
    c.select(null);
    _show(to, s);
    _say(hitLabel(to));
    return true;
  }

  /// Space (Enter on a day without events): the date tap, or the selection made.
  bool _activate(Hit at) {
    final c = _env.controller;
    if (_anchor != null) {
      // Handed once: Enter again does not book it twice; the app cleared it, that Enter is spent.
      final sel = c.selection;
      if (sel != null && !identical(sel, _handed)) {
        _handed = sel;
        _env.selected(sel);
      } else if (sel == null) {
        _anchor = null;
      }
      return true;
    }
    _env.onDateTap?.call(at);
    final sel = selectionBetween(_ctx(), at, at);
    c.select(sel);
    _env.selected(sel);
    return true;
  }

  // ——— on an event ———

  void _focusEvent(EventInstance i, KeySurface s, {bool quiet = false}) {
    _event = i;
    final ev = i.event;
    s.reveal(eventHit(ev, Edge.start, displayZone: _zone, grid: s.keyGrid));
    _redraw();
    if (!quiet) _say(_l.eventLabel(_env.title(i), _env.span(i)));
  }

  /// Tab and Shift+Tab: from the cursor to the events, through them in
  /// reading order, back to the cursor; past the last, out of the calendar.
  bool _tab(KeySurface s, {required bool back}) {
    final all = s.items();
    final ev = _event;
    if (ev == null) {
      if (back || all.isEmpty) return false;
      _focusEvent(all.first, s);
      return true;
    }
    final k = all.indexWhere((x) => x.key == ev.key);
    final n = k + (back ? -1 : 1);
    if (n >= 0 && n < all.length) {
      _focusEvent(all[n], s);
      return true;
    }
    if (back) {
      _event = null;
      final at = _cursor ?? s.cursorFor(ev) ?? s.home();
      if (at != null) {
        _show(at, s);
        _say(hitLabel(at));
      }
      return true;
    }
    // Out of the calendar: coming back starts on the cursor.
    _event = null;
    _redraw();
    return false;
  }

  bool _onEvent(KeyIntent intent, EventInstance i, KeySurface s) {
    switch (intent) {
      case CommandKeyIntent(kind: KeyCommand.open):
        final open = _env.onEventTap;
        if (open != null) {
          open(i, _x.rectOfEvent(i));
        } else {
          _x.openMenu(i, _anchorOf(i));
        }
        return true;
      case CommandKeyIntent(kind: KeyCommand.grab):
        grab(i, GrabKind.move);
        return true;
      case CommandKeyIntent(kind: KeyCommand.delete):
        unawaited(_delete(i, s));
        return true;
      case CommandKeyIntent(kind: KeyCommand.cancel):
        final back = s.cursorFor(i);
        if (back == null) return false;
        _show(back, s);
        _say(hitLabel(back));
        return true;
      case ItemKeyIntent(:final delta):
        final items = s.itemsAround(i);
        final k = items.indexWhere((x) => x.key == i.key);
        final n = k + delta;
        if (k >= 0 && n >= 0 && n < items.length) _focusEvent(items[n], s);
        return true;
      default:
        return false;
    }
  }

  /// Where a menu opens for an event the keyboard is on.
  Offset _anchorOf(EventInstance i) {
    final b = _x.boxesOf(i.event);
    return b.isEmpty ? Offset.zero : b.first.rect.bottomLeft;
  }

  /// A screen reader's "Delete" on an event.
  void delete(EventInstance i) {
    final s = _surface;
    if (s != null) unawaited(_delete(i, s));
  }

  Future<void> _delete(EventInstance i, KeySurface s) async {
    if (!_x.mayDelete(i.event)) return _say(_l.notEditable);
    final ev = i.event;
    final ref = ev.ref;
    var command = DeleteEvent(ev.id);
    if (ref != null) {
      final scope = await _x.askScope(_anchorOf(i), _l.deleteWhich);
      if (scope == null || _disposed) return;
      command = DeleteEvent(ref.seriesId, key: ref.key, scope: scope);
    }
    final back = s.cursorFor(i);
    final r = _env.controller.run(command, validate: true);
    if (!r.ok) return;
    final config = _env.config;
    final undo = config.editable && config.keyboardUndo
        ? (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS
              ? '⌘Z'
              : 'Ctrl+Z')
        : '';
    _say(_l.eventDeleted(_env.title(i), undo));
    final to = back ?? s.home();
    if (to != null) _show(to, s);
  }

  // ——— grab mode: the keyboard's drag ———

  /// Holds [i] (M, Alt+Enter, the menu's "Move…" and "Change duration…", a
  /// screen reader's action): the arrows step it, Enter puts it down.
  void grab(EventInstance i, GrabKind kind) {
    final s = _surface;
    if (_grab != null || _x.busy || s == null) return;
    final ev = i.event;
    if (!_x.mayMove(ev) && !_x.mayResize(ev)) return _say(_l.notEditable);
    final resourceId = s.resourceView ? (ev.resourceIds.isEmpty ? unassignedId : ev.resourceIds.first) : null;
    // Taken from the keyboard, the calendar has the focus already: losing it lets go.
    final g = _Grab(instance: i, mode: kind, resourceId: resourceId)
      ..kind = kind
      ..focused = node.hasFocus;
    _grab = g;
    _anchor = null;
    _env.controller.select(null);
    _x.release();
    _drawGrab();
    final ctx = _x.context;
    final reader = ctx != null && ctx.mounted && (MediaQuery.maybeAccessibleNavigationOf(ctx) ?? false);
    final help = reader
        ? _l.grabHelpReader
        : kind == GrabKind.resize
        ? _l.grabHelpResize
        : _l.grabHelp;
    _say('${_l.grabbed(_env.title(i))} $help');
    // After the menu that asked for it gives the focus back.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_grab == g && !_disposed) node.requestFocus();
    });
    _redraw();
  }

  bool get _readerOn => SemanticsBinding.instance.semanticsEnabled;

  void _drawGrab() {
    final g = _grab;
    final s = _surface;
    if (g == null || _disposed) return;
    final p = g.proposal;
    _x.showHeld(g.instance, g.event, valid: p?.valid ?? true);
    if (s == null) return;
    held.value = GrabInfo(
      key: g.instance.key,
      value: p == null ? _spanWords(_spanOf(g.event)) : proposalWords(p, g.instance.event),
      // What a swipe would do, worked out only for a screen reader.
      increased: _readerOn ? _readerPreview(g, s, 1) : _l.noFurther,
      decreased: _readerOn ? _readerPreview(g, s, -1) : _l.noFurther,
      grid: s.keyGrid,
    );
    final edge = eventHit(
      g.event,
      g.kind == GrabKind.resize ? g.edge : Edge.start,
      displayZone: _zone,
      grid: s.keyGrid,
    );
    final r = g.resourceId;
    s.reveal(
      r == null
          ? edge
          : switch (edge) {
              SlotHit() => SlotHit(date: edge.date, instant: edge.instant, gap: edge.gap, resourceId: r),
              DayHit() => DayHit(date: edge.date, allDayRow: edge.allDayRow, resourceId: r),
            },
    );
  }

  /// The proposal against the event as it was taken (what `isUnchanged`,
  /// `commandFor` and the words compare with), not the last step's.
  Proposal _fromStart(_Grab g, Proposal p) => Proposal(
    placement: Placement(event: g.instance.event, proposed: p.proposed, external: p.placement.external),
    violations: p.violations,
    ambiguity: p.ambiguity,
    skipped: p.skipped,
  );

  bool _onGrab(KeyLike k, KeySurface s, bool rtl) {
    if (_committing) return false;
    final intent = intentFor(k, mode: KeyMode.grab, grid: s.keyGrid, rtl: rtl);
    if (intent == null) {
      // No undo while an event is held (the history would move under it).
      final key = k.key.toLowerCase();
      return ((k.ctrl || k.meta) && (key == 'z' || key == 'y')) || (k.alt && k.key.startsWith('Arrow'));
    }
    final g = _grab!;
    if (k.key == 'Tab') {
      // Tab lets go, and still moves the focus on.
      _letGo(said: true);
      return false;
    }
    switch (intent) {
      case MoveKeyIntent(:final step):
        g.mode == GrabKind.resize ? _step(GrabKind.resize, Edge.end, step) : _step(GrabKind.move, Edge.start, step);
      case ResizeKeyIntent(:final edge, :final step):
        _step(GrabKind.resize, edge, step);
      case AcrossKeyIntent(:final delta):
        _across(delta);
      case CommandKeyIntent(kind: KeyCommand.commit):
        unawaited(_commit());
      case CommandKeyIntent(kind: KeyCommand.cancel):
        _letGo(said: true);
      default:
        return false;
    }
    return true;
  }

  void _step(GrabKind kind, Edge edge, KeyStep by, {bool mayNavigate = true}) {
    final g = _grab;
    final s = _surface;
    if (g == null || s == null) return;
    final ev = g.instance.event;
    if (kind == GrabKind.move && !_x.mayMove(ev)) return _say(_l.cannotMove);
    // Its end only (no resizing from the start yet); a timed event in a month only moves.
    if (kind == GrabKind.resize && (!_x.mayResize(ev) || edge != Edge.end)) return _say(_l.cannotResize);
    final r = _propose(g, s, kind, edge, by, mayNavigate: mayNavigate);
    if (r == null) return _say(_l.noFurther);
    final landed = r.landed;
    if (kind == GrabKind.move && landed?.resourceId != null) g.resourceId = landed!.resourceId;
    _held(g, r.p, kind, edge);
  }

  /// Where one step would take the held event, nothing changed yet.
  ({Proposal p, Hit? landed})? _propose(
    _Grab g,
    KeySurface s,
    GrabKind kind,
    Edge edge,
    KeyStep by, {
    required bool mayNavigate,
  }) {
    Hit? landed;
    final p = grabStep(
      _ctx(),
      s.keyGrid,
      g.event,
      by,
      edge: kind == GrabKind.resize ? edge : null,
      fit: (to, from) => landed = _land(s, from, to, by, mayNavigate: mayNavigate),
      resourceId: g.resourceId,
    );
    return p == null ? null : (p: p, landed: landed);
  }

  /// What a reader's swipe ([dir]: up +1, down −1) would make the held event: its words.
  String _readerPreview(_Grab g, KeySurface s, int dir) {
    final kind = g.mode;
    if (kind == GrabKind.move ? !_x.mayMove(g.instance.event) : !_x.mayResize(g.instance.event)) {
      return kind == GrabKind.move ? _l.cannotMove : _l.cannotResize;
    }
    final step = _readerStepOf(g, s, dir);
    final r = _propose(g, s, kind, kind == GrabKind.resize ? Edge.end : Edge.start, step, mayNavigate: false);
    return r == null ? _l.noFurther : proposalWords(r.p, g.instance.event);
  }

  void _held(_Grab g, Proposal p, GrabKind kind, Edge edge) {
    g
      ..event = heldEvent(p)
      ..proposal = _fromStart(g, p)
      ..kind = kind
      ..edge = edge;
    _drawGrab();
    _say(proposalWords(p, g.instance.event));
  }

  /// Alt+Left/Right while holding: the next resource, the same day and time.
  void _across(int delta) {
    final g = _grab;
    final s = _surface;
    if (g == null || s == null) return;
    if (!_x.mayMove(g.instance.event)) return _say(_l.cannotMove);
    Hit? landed;
    final p = grabStep(
      _ctx(),
      s.keyGrid,
      g.event,
      const KeyStep(),
      fit: (_, from) => landed = s.resourceView ? s.stepAcross(from, delta) : null,
      resourceId: g.resourceId,
    );
    if (p == null) return _say(_l.noFurther);
    if (landed?.resourceId != null) g.resourceId = landed!.resourceId;
    _held(g, p, GrabKind.move, Edge.start);
  }

  /// A tap on the calendar while an event is held: it goes there, as if
  /// dragged (WCAG 2.5.7: "Move…", then a tap). False: nothing held.
  bool putAt(Hit hit) {
    final g = _grab;
    final s = _surface;
    if (g == null || s == null) return false;
    if (_committing) return true;
    final resize = g.kind == GrabKind.resize;
    final p = grabStep(
      _ctx(),
      s.keyGrid,
      g.event,
      const KeyStep(),
      edge: resize ? g.edge : null,
      fit: (_, _) => hit,
      resourceId: g.resourceId,
    );
    if (p == null) return true;
    if (!resize && hit.resourceId != null) g.resourceId = hit.resourceId;
    g
      ..event = heldEvent(p)
      ..proposal = _fromStart(g, p);
    _drawGrab();
    unawaited(_commit());
    return true;
  }

  Future<void> _commit() async {
    final g = _grab;
    if (g == null || _committing) return;
    final p = g.proposal;
    if (p == null || isUnchanged(p)) return _letGo(said: true);
    _committing = true;
    var done = false;
    try {
      done = await _x.commit(g.instance, p, resize: g.kind == GrabKind.resize, at: _x.ghostAnchor ?? Offset.zero);
    } catch (e, st) {
      // An app's callback failed: grab mode still ends, the error is reported.
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st, library: 'dzcalendar'));
    } finally {
      _committing = false;
      if (!_disposed && identical(_grab, g)) {
        _grab = null;
        held.value = null;
      }
    }
    if (_disposed) return;
    final ev = done ? p.proposed : g.instance.event;
    _refocus(
      g.instance.event.id,
      eventHit(ev, Edge.start, displayZone: _zone, grid: _surface?.keyGrid ?? KeyGrid.time),
    );
  }

  void _letGo({required bool said}) {
    final g = _grab;
    if (g == null || _disposed) return;
    _grab = null;
    held.value = null;
    _x.showHeld(g.instance, null);
    if (said) _say(_l.grabCancelled);
    _refocus(
      g.instance.event.id,
      eventHit(g.instance.event, Edge.start, displayZone: _zone, grid: _surface?.keyGrid ?? KeyGrid.time),
    );
  }

  /// After a grab: once drawn again, the event where it is now, else the cursor there.
  void _refocus(EventId id, Hit at) {
    _event = null;
    _cursor = at;
    _redraw();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final s = _surface;
      if (_disposed || s == null || _grab != null) return;
      final found = s.items().where((x) => x.event.id == id).firstOrNull;
      final f = s.fit(at);
      if (f is FitAt) _cursor = f.hit;
      if (found != null) {
        _focusEvent(found, s, quiet: true);
      } else {
        _redraw();
      }
    });
  }

  // ——— a screen reader's actions on the held event (decision 42) ———

  /// Swipe up (+1) or down (−1): a slot later or earlier (a day in a month).
  void readerStep(int dir) {
    final g = _grab;
    final s = _surface;
    if (g == null || s == null || _committing) return;
    final step = _readerStepOf(g, s, dir);
    final kind = g.mode;
    // A step that leaves the period would take the event's node, and the reader's place, away.
    _step(kind, kind == GrabKind.resize ? Edge.end : Edge.start, step, mayNavigate: false);
  }

  /// A swipe's step: a slot in a time grid, a day for an all-day event or in a month.
  static KeyStep _readerStepOf(_Grab g, KeySurface s, int dir) =>
      s.keyGrid == KeyGrid.time && !g.event.allDay ? KeyStep(slots: dir) : KeyStep(days: dir);

  /// The day (a month: the week) before or after; held to change its length, none.
  void readerDay(int dir) {
    final g = _grab;
    final s = _surface;
    if (g == null || s == null || _committing || g.mode == GrabKind.resize) return;
    final step = KeyStep(days: s.keyGrid == KeyGrid.time ? dir : 7 * dir);
    _step(GrabKind.move, Edge.start, step, mayNavigate: false);
  }

  /// A double tap on the held event: put down.
  void readerPutDown() => unawaited(_commit());

  /// The reader's "Cancel the move".
  void readerCancel() => _letGo(said: true);

  void dispose() {
    _disposed = true;
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    node.dispose();
    cursor.dispose();
    focused.dispose();
    held.dispose();
  }
}

const _repeats = {'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'PageUp', 'PageDown'};

bool _sameHit(Hit a, Hit b) => switch ((a, b)) {
  (SlotHit a, SlotHit b) =>
    a.date == b.date && a.instant.epochMilliseconds == b.instant.epochMilliseconds && a.resourceId == b.resourceId,
  (DayHit a, DayHit b) => a.date == b.date && a.allDayRow == b.allDayRow && a.resourceId == b.resourceId,
  _ => false,
};

/// A Flutter key as the core's keymap reads it (the web's names), so the
/// keys are the same on every platform and port.
KeyLike? keyLikeOf(KeyEvent e) {
  final k = e.logicalKey;
  final name = switch (k) {
    LogicalKeyboardKey.arrowLeft => 'ArrowLeft',
    LogicalKeyboardKey.arrowRight => 'ArrowRight',
    LogicalKeyboardKey.arrowUp => 'ArrowUp',
    LogicalKeyboardKey.arrowDown => 'ArrowDown',
    LogicalKeyboardKey.home => 'Home',
    LogicalKeyboardKey.end => 'End',
    LogicalKeyboardKey.pageUp => 'PageUp',
    LogicalKeyboardKey.pageDown => 'PageDown',
    LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => 'Enter',
    LogicalKeyboardKey.space => ' ',
    LogicalKeyboardKey.escape => 'Escape',
    LogicalKeyboardKey.tab => 'Tab',
    LogicalKeyboardKey.delete => 'Delete',
    LogicalKeyboardKey.backspace => 'Backspace',
    // M, Z, Y by their place on the keyboard when the layout writes another script (Arabic).
    _ => switch (e.physicalKey) {
      PhysicalKeyboardKey.keyM => 'm',
      PhysicalKeyboardKey.keyZ => 'z',
      PhysicalKeyboardKey.keyY => 'y',
      _ => k.keyLabel.length == 1 ? k.keyLabel.toLowerCase() : null,
    },
  };
  if (name == null) return null;
  final hw = HardwareKeyboard.instance;
  return KeyLike(
    name,
    shift: hw.isShiftPressed,
    alt: hw.isAltPressed,
    ctrl: hw.isControlPressed,
    meta: hw.isMetaPressed,
  );
}
