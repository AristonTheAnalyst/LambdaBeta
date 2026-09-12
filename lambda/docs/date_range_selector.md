# Date Range Selector — Plan of Record

2026-08-26. A single custom component for picking date ranges on the exercise
insights page (and any future screen that needs one): presets **or** a
calendar, with the default being custom month-to-date.

## Current state

The insights page has a `PopupMenuButton` pill showing `1M · 24 Jul – 24 Aug`;
its menu offers 1M/3M/6M/1Y/Custom, and Custom opens Flutter's full-screen
native `showDateRangePicker`. The page state is `_Preset` + `_customRange`,
with `_window`/`_windowLabel` computed inline.

## Component design

**Interaction:** tapping the date pill opens a bottom sheet (via
`showLambdaModal`, matching every other modal in the app). The sheet contains
the presets and the calendar in one place, with an explicit **Apply** button.

```
┌─────────────────────────────────┐
│ DATE RANGE                      │
│                                 │
│ [ 1M ] [ 3M ] [ 6M ] [ 1Y ]     │   ← preset chips (active highlighted)
│                                 │
│ ───────── or custom ─────────── │
│                                 │
│  ◀  August 2026  ▶              │   ← inline month calendar
│  Mo Tu We Th Fr Sa Su           │
│   1  2  3 [4] 5  6  7           │   ← tap start, tap end; range tints
│  ...                            │
│                                 │
│ 1 Aug – 24 Aug 2026             │   ← live selection label
│                                 │
│         [Cancel] [Apply]        │
└─────────────────────────────────┘
```

- **Preset chips** select (highlight + update the live label) but do not
  apply until Apply — no accidental commits.
- **Calendar**: custom inline month grid (prev/next month chevrons, weekday
  header, day cells). First tap sets the range start, second tap sets the
  end; tapping before the start restarts the selection. Future dates
  disabled; navigation capped at today's month.
- Tapping a preset while a custom range is active switches the selection to
  that preset (and vice versa: tapping any calendar day switches to custom).

## Data model (pure, shared)

`lib/core/utils/date_range.dart` — no widgets, unit-testable:

```dart
enum DateRangePreset { m1, m3, m6, y1, custom }

/// One selection: a preset, or an explicit custom range.
class DateRangeSelection {
  final DateRangePreset preset;
  final DateTimeRange? customRange; // non-null iff preset == custom
}

DateRangeSelection monthToDateDefault(DateTime today);
  // custom range: 1st of the current month → today. The page initializes
  // to this on every open — a default, not a persisted state, so it can
  // never freeze on last month's dates.

({DateTime from, DateTime to}) windowFor(DateRangeSelection s, DateTime today);
  // presets: rolling windows from today (30/90/180/365 days), to exclusive.
  // custom: the picked range, to exclusive.

String labelFor(DateRangeSelection s, DateTime today);
  // "1M · 24 Jul – 24 Aug", "Custom · 1 Aug – 24 Aug" — the pill text.
```

All date math lives here. The page and the sheet consume it; neither
computes windows itself. Rules encoded once:

- Windows are `[from, to)` with `to = today + 1` for presets / `end + 1` for
  custom — matches the existing `_window` semantics exactly.
- Range end may not exceed today; range start may not be before end.
- MTD default recomputed per page open (not persisted).

## The widget

`lib/shared/widgets/date_range_selector.dart`:

```dart
Future<DateRangeSelection?> showDateRangeSelector(
  BuildContext context, {
  required DateRangeSelection initial,
})
```

Returns the new selection, or null on Cancel. Internal state mirrors the
sheet; nothing is written until Apply. Reused later by any screen with a
date filter.

## Insights page migration

- Replace `_Preset`, `_presetDays`, `_customRange`, `_window`,
  `_windowLabel`, `_presetLabel`, `_pickCustomRange` with:
  `DateRangeSelection _selection = monthToDateDefault(now);` (set in
  initState so each open is fresh) and `_window = windowFor(_selection, now)`.
- The pill becomes a plain button showing `labelFor(...)`; its tap handler
  awaits `showDateRangeSelector` and setStates on non-null.
- All downstream consumers (`_body`, journey rows, metrics) keep using
  `_window` — zero changes below the filter layer.

## Edge cases (all in the pure module + tests)

1. Custom range end tapped before start → restart selection with the new
   date as start.
2. Preset selected, then a calendar day tapped → becomes custom (and the
   custom range starts as that single day until the second tap).
3. Month navigation stops at the current month; days after today are
   disabled.
4. Apply with a one-day range (start == end) is legal — a single-day window.
5. Cancel leaves the page state untouched (sheet is pure until Apply).

## Tests

- `windowFor`: preset windows (30/90/180/365), boundary inclusivity, custom
  ranges, single-day range.
- `monthToDateDefault`: first of month → today, across month/year
  boundaries (e.g. run on Jan 1).
- `labelFor`: preset + custom renderings.
- Widget test (optional): open sheet, tap a preset, Apply → page pill
  updates; Cancel → unchanged.

## Phasing

1. `date_range.dart` + unit tests (pure — no UI risk).
2. `date_range_selector.dart` sheet widget (presets + inline calendar +
   Apply/Cancel) with the existing design tokens (ghost/accent tones from
   `container_styles.dart`).
3. Insights page migration (delete the old `_Preset` plumbing).
4. Verify: analyzer, 29+ tests, manual pass on the sim (preset apply,
   calendar range, cancel, MTD default on first open).
