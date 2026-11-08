/// When can this provider be booked? Weekly hours and dated exceptions in
/// the provider's own zone, minus what is busy, cut into slots, with
/// buffers, notice, horizon and a daily cap. Pure Dart, no clock read: the
/// same answer on the phone, on the server and on the web (owner's
/// decisions 14, 15 and 18–21, 2026-11-08).
library;

export 'src/slots/busy.dart' show busyFromEvents;
export 'src/slots/engine.dart' show checkSlot, findSlots;
export 'src/slots/json.dart' show readMoment;
export 'src/slots/types.dart'
    show
        Availability,
        Busy,
        BusyKind,
        DateException,
        RuleWindow,
        Slot,
        SlotAccepted,
        SlotCheck,
        SlotRefusal,
        SlotRefused,
        SlotRequest,
        SlotRules,
        SlotsResult,
        WeeklyWindow,
        Window;
export 'src/time/wall_time.dart' show WallTime;
