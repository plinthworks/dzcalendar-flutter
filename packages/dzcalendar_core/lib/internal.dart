/// The engine's working parts: for the Flutter package (`dzcalendar`) and
/// the tests. No semantic-versioning promise (owner's decision 12,
/// 2026-11-08): anything here may change in any release. Applications use
/// `package:dzcalendar_core/dzcalendar_core.dart`.
library;

export 'dzcalendar_core.dart';
export 'ical.dart';
export 'slots.dart';
export 'timeline.dart';
export 'src/commands/patch.dart' show lengthOf, patchEvent;
export 'src/event/normalize.dart' show hash53, withRef;
export 'src/event/parse_temporal.dart'
    show ParseResult, Parsed, ParsedDate, ParsedInstant, ParsedWall, ParsedZoned, parseTemporal, placeWall;
export 'src/intervals.dart' show intersectSpans, normalizeSpans, spanInstants, subtractSpans, unionSpans;
export 'src/recurrence/edit.dart'
    show
        EditResult,
        OccurrenceRef,
        deleteOccurrence,
        deleteSeries,
        editOccurrence,
        editedOccurrence,
        firstKey,
        isOccurrence,
        startOfKey;
export 'src/slots/engine.dart' show maxCandidates, maxSlots, openSpans;
export 'src/slots/json.dart' show readMomentExact;
export 'src/rules/validate.dart' show Neighbours, validateWith;
export 'src/kernel.dart' show kernelFamilies;
export 'src/layout/column.dart' show ColItem, ColPlacement, ColumnLayoutMode, layoutColumn;
export 'src/layout/rows.dart' show OverflowPiece, OverflowResult, Packed, RowItem, computeOverflow, packLanes;
export 'src/layout/virtual.dart' show PrefixSums, Sizes, UniformSizes, VRange, VariableSizes, visible2D, visibleRange;
export 'src/project/segment.dart' show DateIndex, segmentAllDay, segmentTimed, splitByWeek;
export 'src/views/daygrid.dart'
    show cutDayGridModel, groupHeadsOf, isBackground, updateDayGridModel, updateMultiMonthModel;
export 'src/views/timegrid.dart' show buildTimeGridColumn, updateTimeGridModel;
export 'src/util/js.dart' show jsRound, jsText;
export 'src/recurrence/series.dart'
    show defaultOccurrenceLimit, forever, keyOf, occurrenceSpan, seriesEquals, seriesSpan, setEquals;
export 'src/rrule/edit.dart'
    show
        ImplicitPart,
        Start,
        countBefore,
        explicitRule,
        implicitRule,
        indexOfStart,
        iterateUnion,
        nthStart,
        rebaseRule,
        sameStart,
        splitRule,
        startBefore;
export 'src/rrule/expand.dart' show defaultExpandLimit, firstStartDate, firstStartZoned, lastStartDate, lastStartZoned;
export 'src/rrule/iterate.dart' show IterationState, iterateDates, iterateZoned, plainSubDaily, weekOf;
export 'src/store/persistent.dart' show PersistentIntervalTree, PersistentOrderedMap;
export 'src/store/store.dart' show sourceOf, spanOf, stamp;
export 'src/zone/zone_rules.dart' show FixedOffset, TzdbRules, ZoneRules;
