/// DzCalendar's Flutter widgets over `dzcalendar_core`: [DzCalendar] (month,
/// week, day, list, year), [CalendarHeader], [MiniMonth] and [SlotPicker],
/// driven by a [CalendarController]. Words through [DzCalendarLocalizations]
/// (French, English, Arabic), style through [DzCalendarTheme].
///
/// What an application uses with the widgets is exported here (owner's
/// decision 34, 2026-11-09): events, time, commands, menus, selections,
/// slots. The whole core — models, layout, recurrence, iCal — is
/// `package:dzcalendar_core`.
library;

export 'package:dzcalendar_core/dzcalendar_core.dart'
    show
        // The calendar and its settings.
        CalendarKernel,
        KernelOptions,
        KernelState,
        KernelEvent,
        KernelStateEvent,
        KernelStoreEvent,
        StateCause,
        StateDirection,
        ModelOptions,
        TimeGridSettings,
        DayGridSettings,
        AxisMode,
        CalendarRules,
        TitleFormat,
        TitleSkeleton,
        TitleBuilder,
        TitleFormatArg,
        ViewModel,
        ViewSpec,
        Segment,
        TimedSegment,
        AllDaySegment,
        AvailableSlot,
        // Events and what loading them says.
        EventInput,
        CalEvent,
        TimedEvent,
        AllDayEvent,
        EventInstance,
        EventId,
        EventDisplay,
        EventStatus,
        EventRef,
        NormalizationReport,
        Problem,
        ProblemCode,
        Severity,
        // Edits.
        Command,
        CreateEvent,
        UpdateEvent,
        MoveEvent,
        ResizeEvent,
        DeleteEvent,
        EventPatch,
        EditScope,
        RunResult,
        CommandResult,
        Violation,
        Series,
        History,
        // Time.
        Instant,
        PlainDate,
        PlainTime,
        PlainDateTime,
        ZonedDateTime,
        ZoneId,
        IsoDuration,
        WallTime,
        isValidZone,
        // Resources and rules.
        ResourceInput,
        Resource,
        unassignedId,
        BusinessHours,
        BusinessHoursRule,
        ConstraintSpec,
        BusinessHoursConstraint,
        GroupConstraint,
        SpansConstraint,
        Placement,
        ValidRange,
        // Taps, selections, menus.
        Hit,
        SlotHit,
        DayHit,
        CalendarSelection,
        DaySelection,
        TimeSelection,
        ActionTarget,
        SlotTarget,
        DayTarget,
        EventTarget,
        ActionItem,
        CreateRequest,
        CreateAt,
        CreateOn;
export 'package:dzcalendar_core/slots.dart'
    show
        Availability,
        Busy,
        BusyKind,
        DateException,
        Slot,
        SlotAccepted,
        SlotCheck,
        SlotRefused,
        SlotRules,
        SlotsResult,
        WeeklyWindow,
        Window,
        busyFromEvents,
        checkSlot,
        findSlots;

export 'src/calendar.dart' show CalendarHeader, DzCalendar;
export 'src/controller.dart' show CalendarController, ChangedItem, EventChange, EventChangeCause;
export 'src/env.dart' show ActionsBuilder, EventBuilder, EventColor, EventInfo;
export 'src/l10n/localizations.dart'
    show
        DzCalendarLocalizations,
        DzCalendarLocalizationsAr,
        DzCalendarLocalizationsDelegate,
        DzCalendarLocalizationsEn,
        DzCalendarLocalizationsFr;
export 'src/mini_month.dart' show MiniMonth;
export 'src/slot_picker.dart' show SlotPicker;
export 'src/theme.dart' show DzCalendarStyle, DzCalendarTheme;
