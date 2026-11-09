// Only the package's own entry, next to Material: every name it exports is
// usable without a `hide` (owner's decision 34). An ambiguous name would not compile.
import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the exported names do not collide with material.dart', () {
    final types = <Type>[
      CalendarKernel, KernelOptions, KernelState, KernelEvent, KernelStateEvent, KernelStoreEvent, StateCause,
      StateDirection, ModelOptions, TimeGridSettings, DayGridSettings, AxisMode, CalendarRules, TitleFormat,
      TitleSkeleton,
      TitleBuilder,
      TitleFormatArg,
      ViewModel,
      ViewSpec,
      Segment,
      TimedSegment,
      AllDaySegment,
      AvailableSlot,
      EventInput,
      CalEvent,
      TimedEvent, AllDayEvent, EventInstance, EventDisplay, EventStatus, EventRef, NormalizationReport, Problem,
      ProblemCode, Severity, Command, CreateEvent, UpdateEvent, MoveEvent, ResizeEvent, DeleteEvent, EventPatch,
      EditScope,
      RunResult,
      CommandResult,
      Violation,
      Series,
      History,
      Instant,
      PlainDate,
      PlainTime,
      PlainDateTime,
      ZonedDateTime,
      IsoDuration,
      WallTime, ResourceInput, Resource, BusinessHours, BusinessHoursRule, ConstraintSpec, BusinessHoursConstraint,
      GroupConstraint, SpansConstraint, Placement, ValidRange, Hit, SlotHit, DayHit, CalendarSelection, DaySelection,
      TimeSelection, ActionTarget, SlotTarget, DayTarget, EventTarget, ActionItem, CreateRequest, CreateAt, CreateOn,
      Availability, Busy, BusyKind, DateException, Slot, SlotAccepted, SlotCheck, SlotRefused, SlotRules,
      SlotsResult,
      WeeklyWindow,
      Window,
      CalendarHeader,
      DzCalendar,
      CalendarController,
      EventChange,
      EventChangeCause,
      ChangedItem,
      EventInfo,
      DzCalendarLocalizations,
      DzCalendarLocalizationsAr, DzCalendarLocalizationsDelegate, DzCalendarLocalizationsEn,
      DzCalendarLocalizationsFr, MiniMonth, SlotPicker, DzCalendarStyle, DzCalendarTheme,
      // Material's own, in the same file.
      Scaffold, Material,
    ];
    expect(types, hasLength(109));
    expect([isValidZone, busyFromEvents, checkSlot, findSlots, unassignedId], hasLength(5));
    const ZoneId zone = 'Europe/Paris';
    const EventId id = 'a';
    expect(isValidZone(zone) && id.isNotEmpty, isTrue);
  });
}
