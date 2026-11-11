/// DzCalendar's core in pure Dart. Every event keeps its own time zone; days
/// of 23 h, 25 h or 23 h 30 are what they are.
///
/// This library is the public API, under semantic versioning (owner's
/// decision 12, 2026-11-08). The engine's working parts are in
/// `package:dzcalendar_core/internal.dart`, for the Flutter package and the
/// tests, without that promise.
library;

export 'src/calendars/hijri.dart' show HijriCalendar, HijriDate, HijriMonth, HijriReckoning;
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
export 'src/format/format.dart'
    show
        NameWidth,
        WeekRules,
        checkSkeleton,
        dateSkeletons,
        formatLocale,
        formatRangeTitle,
        formatTemporal,
        hijriMonthNames,
        monthNames,
        weekNumber,
        weekRulesFor,
        weekdayNames;
export 'src/interaction/actions.dart'
    show
        ActionContext,
        ActionItem,
        ActionLabels,
        ActionTarget,
        CreateAt,
        CreateOn,
        CreateRequest,
        DayTarget,
        EventTarget,
        GrabKind,
        SlotTarget,
        actionsFor;
export 'src/interaction/hit.dart' show allDayHitAt, dayHitAt, slotHitAt, slotTargetAt;
export 'src/interaction/keymap.dart'
    show
        AcrossKeyIntent,
        KeyIntent,
        ItemKeyIntent,
        KeyGrid,
        KeyLike,
        KeyMode,
        LineKeyIntent,
        MoveKeyIntent,
        PeriodKeyIntent,
        ResizeKeyIntent,
        CommandKeyIntent,
        KeyCommand,
        KeyStep,
        eventHit,
        grabStep,
        heldEvent,
        intentFor,
        stepHit;
export 'src/interaction/propose.dart'
    show
        Ambiguity,
        DayHit,
        DaySelection,
        Hit,
        InteractionContext,
        Proposal,
        CalendarSelection,
        SlotHit,
        TimeSelection,
        commandFor,
        isUnchanged,
        proposeMove,
        proposeResize,
        selectionBetween;
export 'src/kernel.dart'
    show
        CalendarKernel,
        CalendarRules,
        DayGridSettings,
        DayGridViewModel,
        KernelEvent,
        KernelOptions,
        KernelState,
        KernelStateEvent,
        KernelSourceEvent,
        KernelStoreEvent,
        ListViewModel,
        ModelOptions,
        MultiMonthViewModel,
        StateCause,
        formatInCalendar,
        StateDirection,
        TimeGridSettings,
        TimeGridViewModel,
        TitleBuilder,
        TitleFormat,
        TitleFormatArg,
        TitleSkeleton,
        TimelineSettings,
        TimelineViewModel,
        ViewModel;
export 'src/project/segment.dart' show AllDaySegment, Segment, TimedSegment;
export 'src/project/time_axis.dart'
    show AxisBand, AxisMode, AxisPrefer, AxisTick, ColumnAxis, FromPosition, buildColumnAxis;
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
export 'src/resource/rows.dart'
    show
        ColumnResources,
        GroupRow,
        ResourceItemRow,
        ResourceRow,
        RowState,
        columnResources,
        flattenRows,
        groupValue,
        instancesOf;
export 'src/resource/tree.dart'
    show
        CompareOrder,
        FieldOrder,
        Resource,
        ResourceInput,
        ResourceNode,
        ResourceOrder,
        ResourceTree,
        buildResourceTree,
        ResourceTreeResult,
        buildResourceTreeFromJson,
        unassignedId,
        unassignedResource;
export 'src/rules/business_hours.dart' show BusinessHours, BusinessHoursRule, businessIntervals;
export 'src/rules/constraint.dart' show BusinessHoursConstraint, ConstraintSpec, GroupConstraint, SpansConstraint;
export 'src/rules/validate.dart'
    show OverlapFn, Placement, RulesContext, ValidRange, Violation, ViolationCode, validateProposal;
export 'src/source/chunks.dart' show Chunk, ChunkPolicy, ChunkUnit, chunkAt, chunksCovering;
export 'src/source/json_source.dart' show JsonRequester, SourceHttpRequest, jsonSource, readEventList;
export 'src/source/live.dart' show LiveCreate, LiveMessage, LiveRemove, LiveReset, LiveUpdate, liveSource;
export 'src/source/manager.dart'
    show
        SourceFetchFailed,
        SourceHold,
        SourceLiveFailed,
        SourceSaveFailed,
        SourceSaved,
        SourceLoading,
        SourceManager,
        SourceNotice,
        SourceProblems,
        SystemTimers,
        Timers,
        wholeChunk;
export 'src/source/source.dart'
    show
        CancelSource,
        CancelToken,
        EditKind,
        EventEdit,
        EventSourceSpec,
        FetchRequest,
        LiveConnect,
        LiveContext,
        RetryPolicy,
        SaveCause,
        SaveRequest,
        SeriesEdit,
        SourceAnswer,
        SourceEdit,
        SourceFetch,
        arraySource,
        fnSource;
export 'src/store/changes.dart' show ChangeCause, EventMutation, Mutation, SeriesMutation, StoreChange;
export 'src/commands/patch.dart' show toInput;
export 'src/store/export.dart' show eventInput, exportInputs, seriesInput;
export 'src/store/instance.dart' show EventInstance, InstanceOrigin;
export 'src/store/store.dart' show EventStore, QueryOptions, StoreSnapshot, ViewWindow, datesWindow, viewWindow;
export 'src/time/duration.dart' show IsoDuration;
export 'src/time/instant.dart' show Instant;
export 'src/time/plain.dart' show PlainDate, PlainDateTime, PlainTime;
export 'src/views/daygrid.dart'
    show
        DayGridBar,
        DayGridModel,
        DayGridOptions,
        DayGridWeek,
        MultiMonthModel,
        ResourceGroupHead,
        ResourceHead,
        buildDayGridModel,
        buildMultiMonthModel;
export 'src/views/list.dart' show ListDay, ListEntry, ListModel, ListOptions, buildListModel;
export 'src/views/timegrid.dart'
    show
        AllDayBar,
        AvailableSlot,
        MoreTimed,
        PlacedSlot,
        PlacedTimed,
        Reading,
        TimeGridAllDay,
        TimeGridColumn,
        TimeGridModel,
        TimeGridOptions,
        buildTimeGridModel,
        locateNow;
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
export 'src/time/wall_time.dart' show WallTime;
export 'src/zone/day_info.dart'
    show
        ByDisambiguation,
        DayInfo,
        DayKind,
        PreferOffset,
        ResolvedWall,
        Transition,
        TransitionKind,
        WallPass,
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
