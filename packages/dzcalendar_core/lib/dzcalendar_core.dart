/// DzCalendar's core in pure Dart. Every event keeps its own time zone; days
/// of 23 h, 25 h or 23 h 30 are what they are.
///
/// This library is the public API, under semantic versioning (owner's
/// decision 12, 2026-11-08). The engine's working parts are in
/// `package:dzcalendar_core/internal.dart`, for the Flutter package and the
/// tests, without that promise.
library;

export 'src/commands/apply.dart' show applyCommand;
export 'src/commands/history.dart' show History, RunResult;
export 'src/commands/types.dart'
    show
        Batch,
        ChangeRule,
        Command,
        CommandContext,
        CommandResult,
        CreateEvent,
        DeleteEvent,
        DeleteSeries,
        Edge,
        EditScope,
        EventField,
        EventPatch,
        InvalidCommand,
        MoveEvent,
        Reach,
        RepeatEvent,
        ResizeEvent,
        SplitSeries,
        UpdateEvent;
export 'src/event/normalize.dart'
    show
        IdGenerator,
        NormalizationReport,
        NormalizeContext,
        NormalizeResult,
        Normalized,
        NormalizedEvent,
        NormalizedSeries,
        createIdGenerator,
        normalizeEvent,
        normalizeMany;
export 'src/event/problem.dart' show Problem, ProblemCode, Severity;
export 'src/event/types.dart'
    show
        AllDayEvent,
        CalEvent,
        EventDisplay,
        EventId,
        EventInput,
        EventPerms,
        EventRef,
        EventStatus,
        RecurrenceKey,
        ResourceId,
        SeriesId,
        TimedEvent,
        eventEquals,
        sameValue;
export 'src/intervals.dart' show MsSpan;
export 'src/layout/column.dart' show ColItem, ColPlacement, ColumnLayoutMode, layoutColumn;
export 'src/project/segment.dart'
    show AllDaySegment, DateIndex, Segment, TimedSegment, segmentAllDay, segmentTimed, splitByWeek;
export 'src/project/time_axis.dart'
    show AxisBand, AxisMode, AxisPrefer, AxisTick, ColumnAxis, FromPosition, TickNote, buildColumnAxis;
export 'src/recurrence/series.dart'
    show
        Series,
        SeriesWindow,
        SplitFrom,
        escapeId,
        expandSeries,
        materialize,
        occurrenceKey,
        occurrenceLength,
        parseInstanceKey;
export 'src/rrule/expand.dart' show ExpandResult, expandDates, expandZoned;
export 'src/rrule/rule.dart'
    show
        ByDay,
        ExDate,
        ExDay,
        ExInstant,
        Frequency,
        ParsedRRule,
        RDate,
        RDay,
        RRule,
        RRuleProblem,
        RRuleSet,
        RZoned,
        parseRRule,
        serializeRRule;
export 'src/store/changes.dart' show ChangeCause, EventMutation, Mutation, SeriesMutation, StoreChange;
export 'src/store/instance.dart' show EventInstance, InstanceOrigin;
export 'src/store/store.dart' show EventStore, QueryOptions, StoreSnapshot, ViewWindow, datesWindow, viewWindow;
export 'src/time/duration.dart' show IsoDuration;
export 'src/time/instant.dart' show Instant;
export 'src/time/plain.dart' show PlainDate, PlainDateTime, PlainTime;
export 'src/views/views.dart'
    show
        NavContext,
        NavDirection,
        ViewAlignment,
        ViewRange,
        ViewSpec,
        VisibleRange,
        assertViewSpec,
        builtinViews,
        computeViewRange,
        navigate;
export 'src/zone/day_info.dart'
    show
        ByDisambiguation,
        DayInfo,
        DayKind,
        PreferOffset,
        ResolvedWall,
        Transition,
        TransitionKind,
        WallPolicy,
        dayInfo,
        dayInfos,
        isOffsetZone,
        isQuietDay,
        isValidZone,
        resolveWall,
        transitionsBetween;
export 'src/zone/wall.dart' show Disambiguation;
export 'src/zone/zone_rules.dart' show ZoneId, zoneDataVersion;
export 'src/zone/zoned.dart' show InstantInZone, PlainDateInZone, PlainDateTimeInZone, ZonedDateTime;
