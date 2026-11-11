import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The calendar's style, as a [ThemeExtension] (owner's decision 32,
/// 2026-11-09). Every field is optional: what is not set comes from the
/// app's [ColorScheme] and [TextTheme], so light and dark follow the app.
///
/// ```dart
/// ThemeData(extensions: [DzCalendarTheme(hourHeight: 64, eventColor: Colors.teal)])
/// ```
@immutable
class DzCalendarTheme extends ThemeExtension<DzCalendarTheme> {
  const DzCalendarTheme({
    this.eventColor,
    this.onEventColor,
    this.backgroundEventColor,
    this.todayColor,
    this.onTodayColor,
    this.gridLineColor,
    this.outsideDayColor,
    this.offHoursColor,
    this.nowColor,
    this.gapBandColor,
    this.repeatBandColor,
    this.slotColor,
    this.onSlotColor,
    this.selectionColor,
    this.headerStyle,
    this.dayNumberStyle,
    this.secondaryDateStyle,
    this.timeLabelStyle,
    this.eventStyle,
    this.titleStyle,
    this.hourHeight,
    this.minColumnWidth,
    this.barHeight,
    this.eventRadius,
    this.gutterWidth,
    this.timelineSlotWidth,
    this.timelineDayWidth,
    this.laneHeight,
    this.resourceAreaWidth,
    this.tones,
  });

  /// Named colors for events: an event's `tone` (`blue`, `brand`…) picks one.
  final Map<String, Color>? tones;

  /// Events without a tone (or with one the theme does not name).
  final Color? eventColor;
  final Color? onEventColor;

  /// `display: background` events.
  final Color? backgroundEventColor;

  /// Today's date mark.
  final Color? todayColor;
  final Color? onTodayColor;
  final Color? gridLineColor;

  /// Day numbers outside the month shown.
  final Color? outsideDayColor;

  /// Outside business hours.
  final Color? offHoursColor;

  /// The now line.
  final Color? nowColor;

  /// A band of wall times that never happen (spring forward).
  final Color? gapBandColor;

  /// A band of wall times that happen twice (fall back).
  final Color? repeatBandColor;

  /// Bookable slots (the time grid's and the slot picker's).
  final Color? slotColor;
  final Color? onSlotColor;
  final Color? selectionColor;

  /// Day and resource heads.
  final TextStyle? headerStyle;
  final TextStyle? dayNumberStyle;

  /// The secondary calendar's date beside a day's number (Hijri).
  final TextStyle? secondaryDateStyle;

  /// The time grid's hours.
  final TextStyle? timeLabelStyle;
  final TextStyle? eventStyle;

  /// The header's title.
  final TextStyle? titleStyle;

  /// Height of an hour of the time grid, in logical pixels.
  final double? hourHeight;

  /// Below it, a time grid's columns scroll sideways.
  final double? minColumnWidth;

  /// An event bar in a month (and the all-day row).
  final double? barHeight;
  final double? eventRadius;

  /// The time grid's hours column.
  final double? gutterWidth;

  /// A timeline's slot on a scale of minutes (unless `timeline.span` sets it). Default 44.
  final double? timelineSlotWidth;

  /// A timeline's day on a scale of days. Default 36.
  final double? timelineDayWidth;

  /// A timeline's lane: room for one bar (at least 24 px tall, a target's size). Default 26.
  final double? laneHeight;

  /// A timeline's resource area on tablets and desktops (a phone's is narrow). Default 160.
  final double? resourceAreaWidth;

  /// Every field filled: this extension of [context]'s theme over the
  /// values taken from its color scheme and text theme.
  static DzCalendarStyle of(BuildContext context) {
    final theme = Theme.of(context);
    final ext = theme.extension<DzCalendarTheme>();
    final s = theme.colorScheme;
    final t = theme.textTheme;
    return DzCalendarStyle(
      eventColor: ext?.eventColor ?? s.primaryContainer,
      onEventColor: ext?.onEventColor ?? s.onPrimaryContainer,
      backgroundEventColor: ext?.backgroundEventColor ?? s.tertiaryContainer.withValues(alpha: 0.45),
      todayColor: ext?.todayColor ?? s.primary,
      onTodayColor: ext?.onTodayColor ?? s.onPrimary,
      gridLineColor: ext?.gridLineColor ?? s.outlineVariant,
      outsideDayColor: ext?.outsideDayColor ?? s.onSurface.withValues(alpha: 0.38),
      offHoursColor: ext?.offHoursColor ?? s.onSurface.withValues(alpha: 0.05),
      nowColor: ext?.nowColor ?? s.error,
      gapBandColor: ext?.gapBandColor ?? s.errorContainer.withValues(alpha: 0.6),
      repeatBandColor: ext?.repeatBandColor ?? s.secondaryContainer.withValues(alpha: 0.6),
      slotColor: ext?.slotColor ?? s.secondaryContainer,
      onSlotColor: ext?.onSlotColor ?? s.onSecondaryContainer,
      selectionColor: ext?.selectionColor ?? s.primary.withValues(alpha: 0.18),
      headerStyle: (t.labelMedium ?? const TextStyle(fontSize: 12)).merge(ext?.headerStyle),
      dayNumberStyle: (t.bodySmall ?? const TextStyle(fontSize: 12)).merge(ext?.dayNumberStyle),
      secondaryDateStyle: (t.labelSmall ?? const TextStyle(fontSize: 10))
          .copyWith(color: s.onSurfaceVariant)
          .merge(ext?.secondaryDateStyle),
      timeLabelStyle: (t.labelSmall ?? const TextStyle(fontSize: 11))
          .copyWith(color: s.onSurfaceVariant)
          .merge(ext?.timeLabelStyle),
      eventStyle: (t.labelSmall ?? const TextStyle(fontSize: 11)).merge(ext?.eventStyle),
      titleStyle: (t.titleMedium ?? const TextStyle(fontSize: 16)).merge(ext?.titleStyle),
      hourHeight: ext?.hourHeight ?? 48,
      minColumnWidth: ext?.minColumnWidth ?? 44,
      barHeight: ext?.barHeight ?? 18,
      eventRadius: ext?.eventRadius ?? 4,
      gutterWidth: ext?.gutterWidth ?? 48,
      timelineSlotWidth: ext?.timelineSlotWidth ?? 44,
      timelineDayWidth: ext?.timelineDayWidth ?? 36,
      laneHeight: ext?.laneHeight ?? 26,
      resourceAreaWidth: ext?.resourceAreaWidth ?? 160,
      tones: ext?.tones ?? const {},
    );
  }

  @override
  DzCalendarTheme copyWith({
    Color? eventColor,
    Color? onEventColor,
    Color? backgroundEventColor,
    Color? todayColor,
    Color? onTodayColor,
    Color? gridLineColor,
    Color? outsideDayColor,
    Color? offHoursColor,
    Color? nowColor,
    Color? gapBandColor,
    Color? repeatBandColor,
    Color? slotColor,
    Color? onSlotColor,
    Color? selectionColor,
    TextStyle? headerStyle,
    TextStyle? dayNumberStyle,
    TextStyle? secondaryDateStyle,
    TextStyle? timeLabelStyle,
    TextStyle? eventStyle,
    TextStyle? titleStyle,
    double? hourHeight,
    double? minColumnWidth,
    double? barHeight,
    double? eventRadius,
    double? gutterWidth,
    double? timelineSlotWidth,
    double? timelineDayWidth,
    double? laneHeight,
    double? resourceAreaWidth,
    Map<String, Color>? tones,
  }) => DzCalendarTheme(
    eventColor: eventColor ?? this.eventColor,
    onEventColor: onEventColor ?? this.onEventColor,
    backgroundEventColor: backgroundEventColor ?? this.backgroundEventColor,
    todayColor: todayColor ?? this.todayColor,
    onTodayColor: onTodayColor ?? this.onTodayColor,
    gridLineColor: gridLineColor ?? this.gridLineColor,
    outsideDayColor: outsideDayColor ?? this.outsideDayColor,
    offHoursColor: offHoursColor ?? this.offHoursColor,
    nowColor: nowColor ?? this.nowColor,
    gapBandColor: gapBandColor ?? this.gapBandColor,
    repeatBandColor: repeatBandColor ?? this.repeatBandColor,
    slotColor: slotColor ?? this.slotColor,
    onSlotColor: onSlotColor ?? this.onSlotColor,
    selectionColor: selectionColor ?? this.selectionColor,
    headerStyle: headerStyle ?? this.headerStyle,
    dayNumberStyle: dayNumberStyle ?? this.dayNumberStyle,
    secondaryDateStyle: secondaryDateStyle ?? this.secondaryDateStyle,
    timeLabelStyle: timeLabelStyle ?? this.timeLabelStyle,
    eventStyle: eventStyle ?? this.eventStyle,
    titleStyle: titleStyle ?? this.titleStyle,
    hourHeight: hourHeight ?? this.hourHeight,
    minColumnWidth: minColumnWidth ?? this.minColumnWidth,
    barHeight: barHeight ?? this.barHeight,
    eventRadius: eventRadius ?? this.eventRadius,
    gutterWidth: gutterWidth ?? this.gutterWidth,
    timelineSlotWidth: timelineSlotWidth ?? this.timelineSlotWidth,
    timelineDayWidth: timelineDayWidth ?? this.timelineDayWidth,
    laneHeight: laneHeight ?? this.laneHeight,
    resourceAreaWidth: resourceAreaWidth ?? this.resourceAreaWidth,
    tones: tones ?? this.tones,
  );

  @override
  DzCalendarTheme lerp(covariant DzCalendarTheme? other, double t) {
    if (other == null) return this;
    Color? c(Color? a, Color? b) => Color.lerp(a, b, t);
    TextStyle? s(TextStyle? a, TextStyle? b) => TextStyle.lerp(a, b, t);
    double? d(double? a, double? b) => a == null || b == null ? (t < 0.5 ? a : b) : lerpDouble(a, b, t);
    return DzCalendarTheme(
      eventColor: c(eventColor, other.eventColor),
      onEventColor: c(onEventColor, other.onEventColor),
      backgroundEventColor: c(backgroundEventColor, other.backgroundEventColor),
      todayColor: c(todayColor, other.todayColor),
      onTodayColor: c(onTodayColor, other.onTodayColor),
      gridLineColor: c(gridLineColor, other.gridLineColor),
      outsideDayColor: c(outsideDayColor, other.outsideDayColor),
      offHoursColor: c(offHoursColor, other.offHoursColor),
      nowColor: c(nowColor, other.nowColor),
      gapBandColor: c(gapBandColor, other.gapBandColor),
      repeatBandColor: c(repeatBandColor, other.repeatBandColor),
      slotColor: c(slotColor, other.slotColor),
      onSlotColor: c(onSlotColor, other.onSlotColor),
      selectionColor: c(selectionColor, other.selectionColor),
      headerStyle: s(headerStyle, other.headerStyle),
      dayNumberStyle: s(dayNumberStyle, other.dayNumberStyle),
      secondaryDateStyle: s(secondaryDateStyle, other.secondaryDateStyle),
      timeLabelStyle: s(timeLabelStyle, other.timeLabelStyle),
      eventStyle: s(eventStyle, other.eventStyle),
      titleStyle: s(titleStyle, other.titleStyle),
      hourHeight: d(hourHeight, other.hourHeight),
      minColumnWidth: d(minColumnWidth, other.minColumnWidth),
      barHeight: d(barHeight, other.barHeight),
      eventRadius: d(eventRadius, other.eventRadius),
      gutterWidth: d(gutterWidth, other.gutterWidth),
      timelineSlotWidth: d(timelineSlotWidth, other.timelineSlotWidth),
      timelineDayWidth: d(timelineDayWidth, other.timelineDayWidth),
      laneHeight: d(laneHeight, other.laneHeight),
      resourceAreaWidth: d(resourceAreaWidth, other.resourceAreaWidth),
      tones: t < 0.5 ? tones : other.tones,
    );
  }
}

/// [DzCalendarTheme] resolved: every value the widgets draw with.
@immutable
class DzCalendarStyle {
  const DzCalendarStyle({
    required this.eventColor,
    required this.onEventColor,
    required this.backgroundEventColor,
    required this.todayColor,
    required this.onTodayColor,
    required this.gridLineColor,
    required this.outsideDayColor,
    required this.offHoursColor,
    required this.nowColor,
    required this.gapBandColor,
    required this.repeatBandColor,
    required this.slotColor,
    required this.onSlotColor,
    required this.selectionColor,
    required this.headerStyle,
    required this.dayNumberStyle,
    required this.secondaryDateStyle,
    required this.timeLabelStyle,
    required this.eventStyle,
    required this.titleStyle,
    required this.hourHeight,
    required this.minColumnWidth,
    required this.barHeight,
    required this.eventRadius,
    required this.gutterWidth,
    required this.timelineSlotWidth,
    required this.timelineDayWidth,
    required this.laneHeight,
    required this.resourceAreaWidth,
    required this.tones,
  });
  final Map<String, Color> tones;
  final Color eventColor;
  final Color onEventColor;
  final Color backgroundEventColor;
  final Color todayColor;
  final Color onTodayColor;
  final Color gridLineColor;
  final Color outsideDayColor;
  final Color offHoursColor;
  final Color nowColor;
  final Color gapBandColor;
  final Color repeatBandColor;
  final Color slotColor;
  final Color onSlotColor;
  final Color selectionColor;
  final TextStyle headerStyle;
  final TextStyle dayNumberStyle;
  final TextStyle secondaryDateStyle;
  final TextStyle timeLabelStyle;
  final TextStyle eventStyle;
  final TextStyle titleStyle;
  final double hourHeight;
  final double minColumnWidth;
  final double barHeight;
  final double eventRadius;
  final double gutterWidth;
  final double timelineSlotWidth;
  final double timelineDayWidth;
  final double laneHeight;
  final double resourceAreaWidth;
}
