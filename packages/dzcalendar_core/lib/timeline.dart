/// The timeline without a screen: its elapsed axis, its views and its model (owner's
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
export 'src/kernel.dart' show TimelineSettings, TimelineViewModel;
export 'src/timeline/model.dart'
    show
        TimelineAllRow,
        TimelineBar,
        TimelineGroupRow,
        TimelineModel,
        TimelineMore,
        TimelineOptions,
        TimelineResourceRow,
        TimelineRow,
        TimelineRowBody,
        TimelineSpan,
        buildTimelineModel,
        timelineHitAt,
        timelineNow,
        updateTimelineModel;
