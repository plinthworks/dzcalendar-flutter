import 'package:dzcalendar_core/internal.dart';
import 'package:flutter/material.dart';

import 'l10n/localizations.dart';
import 'theme.dart';

/// Bookable slots to pick from: a strip of the days that have some, then
/// the chosen day's times (owner's decisions 30 and 36). Used alone, without
/// a calendar, on the app's own slot objects — [startOf] and [endOf] say
/// when each one is; [SlotPicker.fromSlots] takes `findSlots`' [Slot]s.
///
/// Days and times are read in [displayZone]; two slots at the same clock
/// time on a fall-back day are told apart by their offset.
///
/// In a scrolling parent it is as tall as its content; given a bounded height,
/// the days stay on top and the times scroll under them.
class SlotPicker<T> extends StatefulWidget {
  const SlotPicker({
    super.key,
    required this.items,
    required this.startOf,
    required this.endOf,
    required this.displayZone,
    this.selected,
    this.onSelected,
    this.enabledOf,
    this.seatsOf,
    this.initialDay,
    this.enabled = true,
    this.locale,
    this.empty,
  });

  final List<T> items;
  final Instant Function(T item) startOf;
  final Instant Function(T item) endOf;

  /// The zone days and times are read in (the provider's, usually). One
  /// that is none reads in UTC.
  final ZoneId displayZone;

  /// Compared with `==`.
  final T? selected;
  final ValueChanged<T>? onSelected;

  /// A slot shown but not bookable (default: all are).
  final bool Function(T item)? enabledOf;

  /// Seats still free, said with the time (default: none said).
  final int? Function(T item)? seatsOf;

  /// The day shown first (default: the first with slots).
  final PlainDate? initialDay;

  /// False while a booking is being sent: no time can be tapped.
  final bool enabled;

  /// Default: the app's locale.
  final String? locale;

  /// Shown when there is no slot at all (default: "No free slots").
  final Widget? empty;

  /// `findSlots`' slots, read in [displayZone] (default: the first slot's zone).
  static SlotPicker<Slot> fromSlots({
    Key? key,
    required List<Slot> slots,
    ZoneId? displayZone,
    Slot? selected,
    ValueChanged<Slot>? onSelected,
    PlainDate? initialDay,
    bool enabled = true,
    String? locale,
    Widget? empty,
  }) => SlotPicker<Slot>(
    key: key,
    items: slots,
    startOf: (s) => s.start.instant,
    endOf: (s) => s.end.instant,
    displayZone: displayZone ?? (slots.isEmpty ? 'UTC' : slots.first.start.zone),
    selected: selected,
    onSelected: onSelected,
    initialDay: initialDay,
    enabled: enabled,
    locale: locale,
    empty: empty,
  );

  @override
  State<SlotPicker<T>> createState() => _SlotPickerState<T>();
}

class _SlotPickerState<T> extends State<SlotPicker<T>> {
  PlainDate? _day;

  ZoneId get _zone => isValidZone(widget.displayZone) ? widget.displayZone : 'UTC';

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final l10n = DzCalendarLocalizations.of(context);
    final style = DzCalendarTheme.of(context);
    final locale = w.locale ?? Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en';
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final zone = _zone;
    final byDay = <PlainDate, List<T>>{};
    for (final s in w.items) {
      byDay.putIfAbsent(ZonedDateTime(w.startOf(s), zone).date, () => []).add(s);
    }
    if (byDay.isEmpty) {
      return w.empty ?? Center(child: Text(l10n.noSlots, style: Theme.of(context).textTheme.bodyMedium));
    }
    final days = byDay.keys.toList()..sort();
    final wanted = _day ?? w.initialDay;
    final day = wanted != null && byDay.containsKey(wanted) ? wanted : days.first;
    final times = [...byDay[day]!]
      ..sort((a, b) => w.startOf(a).epochMilliseconds.compareTo(w.startOf(b).epochMilliseconds));
    String clock(Instant i) => formatTemporal(ZonedDateTime(i, zone), use24 ? 'Hm' : 'jm', locale);
    // A clock time read twice that day (the repeated hour): say each one's offset.
    final seen = <String, int>{};
    for (final s in times) {
      final k = clock(w.startOf(s));
      seen[k] = (seen[k] ?? 0) + 1;
    }
    final scheme = Theme.of(context).colorScheme;

    Widget dayChip(PlainDate d) {
      final chosen = d == day;
      final count = byDay[d]!.length;
      final fg = chosen ? scheme.onPrimary : scheme.onSurface;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Semantics(
          button: true,
          selected: chosen,
          label: '${l10n.dayLabel(formatTemporal(d, 'yMMMMEEEEd', locale), 0)}, ${l10n.slotCount(count)}',
          // `excludeSemantics` drops the InkWell's tap with its words: the action is
          // given back here, or a screen reader reads the day and cannot choose it.
          onTap: () => setState(() => _day = d),
          excludeSemantics: true,
          child: Material(
            color: chosen ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _day = d),
              // A minimum width, not a fixed one: "14 créneaux" or an Arabic count
              // does not fit 64 points once the text is enlarged.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weekdayNames(locale, NameWidth.short, 1)[d.dayOfWeek - 1],
                        style: style.headerStyle.copyWith(color: fg),
                      ),
                      Text(
                        formatTemporal(d, 'd', locale),
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700, height: 1.1),
                      ),
                      Text(l10n.slotCount(count), style: style.timeLabelStyle.copyWith(color: fg, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // No fixed height: a strip of 88 overflowed from a text ×1.35 on, and Arabic
    // lines are taller too. The strip takes its content's height; IntrinsicHeight
    // makes every day as tall as the tallest. Built at once rather than lazily: a
    // few weeks of days cost nothing.
    final strip = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final d in days) dayChip(d)]),
      ),
    );
    final chosenDay = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(formatTemporal(day, 'yMMMMEEEEd', locale), style: style.titleStyle),
    );
    final grid = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: [for (final s in times) _button(s, seen, clock, l10n, style)]),
    );
    // In a scrolling parent, as tall as its content: a loose Flexible in a
    // Column of unbounded height takes its child's height. Given a bounded
    // height (a screen's body, a sheet), the days stay on top and the times
    // scroll under them, rather than overflowing at a large text or with many
    // times (owner's decision 72). No LayoutBuilder: a dialog asks its content
    // for an intrinsic width.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        strip,
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [chosenDay, grid],
            ),
          ),
        ),
      ],
    );
  }

  Widget _button(
    T s,
    Map<String, int> seen,
    String Function(Instant) clock,
    DzCalendarLocalizations l10n,
    DzCalendarStyle style,
  ) {
    final w = widget;
    final start = w.startOf(s);
    final t = clock(start);
    final time = (seen[t] ?? 0) > 1 ? '$t (UTC${ZonedDateTime(start, _zone).offset})' : t;
    final seats = w.seatsOf?.call(s);
    final label = seats == null ? time : '$time · ${l10n.seatsLeft(seats)}';
    final chosen = w.selected == s;
    final on = w.enabled && (w.enabledOf?.call(s) ?? true);
    final tap = on && w.onSelected != null ? () => w.onSelected!(s) : null;
    return Semantics(
      button: true,
      selected: chosen,
      enabled: on,
      label:
          '${l10n.freeSlot(l10n.range(time, clock(w.endOf(s))))}${seats == null ? '' : ', ${l10n.seatsLeft(seats)}'}',
      // Same as a day: the button's own tap is excluded with its label. Null while
      // disabled, so a screen reader cannot book what a finger cannot.
      onTap: tap,
      excludeSemantics: true,
      child: chosen
          ? FilledButton(onPressed: tap, child: Text(label))
          : OutlinedButton(
              onPressed: tap,
              style: OutlinedButton.styleFrom(foregroundColor: style.onSlotColor),
              child: Text(label),
            ),
    );
  }
}
