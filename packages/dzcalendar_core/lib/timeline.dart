/// The timeline without a screen: its elapsed axis and its views (owner's
/// decisions 14 and 17, 2026-11-08). Pure Dart, no Flutter.
library;

export 'src/timeline/axis.dart'
    show
        DayScale,
        MinuteScale,
        TimelineAxis,
        TimelineGroup,
        TimelineScale,
        TimelineSlot,
        TimelineUnit,
        buildTimelineAxis,
        defaultScale,
        timelineViews;
