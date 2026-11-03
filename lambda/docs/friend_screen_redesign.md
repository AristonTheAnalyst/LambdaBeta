# Friend Screen redesign — working notes

Started 2026-11-02/03. Surface: **Dev → Friend Screen**
(`/dev/friend-screen`, `lib/features/dev/view/friend_screen_lab.dart`).

This is a living log. Every change the user asks for in the lab goes here,
with the date, so the direction survives the session.

## The goal (user, 2026-11-03)

- **One UI/UX for your own data and a friend's data.** Looking at a friend's
  data should feel exactly like looking at your own; the only difference is
  capability (read-only / no write doors), never a second design.
- Once each tab's screen is settled, **the lab previews replace the old
  personal Session and Library tab screens**, and the same previews become
  the **actual friend profile and its following screens**.
- The Library tabs (Exercises, Variations, Goals, Workouts, Reviews) are
  **weak / useless / half-assed** — most have never had a proper design pass.
  Fixing them is part of this work.
- Do not start the production rollout until the user says the previews are
  done.

## Where the work lives

| Piece | Path |
|---|---|
| Friend profile lab (six tabs) | `lib/features/dev/view/friend_screen_lab.dart` |
| Winning session card (ledger-chips) | `lib/features/dev/view/session_cards_screen.dart` (`LedgerChipsCard`) |
| Session screen (real viewer mirror) | `lib/features/dev/view/session_lab_screen.dart` |
| Exercise screen | `lib/features/dev/view/exercise_lab_screen.dart` |
| Placeholder detail screens | `lib/features/dev/view/friend_lab_detail_screens.dart` |
| Shared lab toolbar (search · sort · filter) | `lib/features/dev/view/lab_toolbar.dart` |
| Shared goal ledger (OPEN \| COMPLETE) | `lib/features/dev/view/lab_goal_columns.dart` |
| Dev routes | `/dev/friend-screen`, `/dev/session-cards` |

The lab is **static**: sample data, no database reads, no writes. The
production rollout will wire the same widgets to real repositories/ViewModels.

## Tab shape settled so far

Six-tab strip: **Session · Exercises · Variations · Goals · Workouts ·
Reviews** (Goals pulled forward beside Variations; 2026-11-01).

### Session
- Card: `LedgerChipsCard` — date rail (day / month / weekday), plan name in
  the session-title position, PR total, PRE/POST stars, exercise chips.
  (The design that won; 2026-10-31.)
- Rail: `WED` then the day count directly **beneath** it (`5D`), same ink,
  no "ago" (2026-11-03). Year replaces the weekday when the date is not in
  the current year.
- Whole cards tappable → the real viewer's static mirror
  (`session_lab_screen.dart`, 2026-11-03): header with back + edit pencil,
  flat exercise card with a working exercise selector, KG/REPS/VARIATION
  rows, floor with `PREVIOUSLY` date bar + mode radios, undo/redo/trash,
  ratings star (real ratings sheet), PR/goal/notes tiles. Doors that need
  real history are drawn but spent.

### Exercises
- `logged …` (not `trained …`) on the age line (2026-11-03).
- Date line: written date + `· Nd` inside the 99-day window; year when not
  the current one.
- Right-hand grid: trophy (PRs), bullseye (goals met, success ink), bullseye
  (goals open, accent), then sessions + sets on the second line.
- Names must hold the app's 20-character cap; wrap instead of ellipsis.

#### Exercise screen (2026-11-03 — built fresh, not the old detail screen)
Opens from any exercise row. Top to bottom:
1. **Header**: `{Person}'s Exercises` (Jamie's in the lab) — not the
   exercise name; the screen is a view of one person's exercise data.
2. **Exercise bar**: just the middle bar of the session selector — the
   exercise's name and a chevron, no arrows. Tapping opens a **searchable
   dropdown** listing the person's exercises **most done first**, each row
   stating `N sets in the last month`; the current one is checked.
3. **Horizontal divider**, edge to edge.
4. **Three-tab icon navigator** — the preview screens' icon strip
   (`SlideIconTabBar`), evenly split, the active tab carrying the strip's
   underline; no words (labels ride semantics only). The tabs, left to
   right: **Summary stats** (bar-chart glyph, the default/landing tab),
   **PRs** (trophy), **Goals** (bullseye) (2026-11-03).
5. **Compact toolbar**: search + sort + range filter, the same strip as the
   preview pages (`LabToolbar`, extracted to `lab_toolbar.dart`). It rides
   only the PRs and Goals tabs — a summary is not a list, so the controls
   are hidden there.
6. **Content**:
   - **Summary stats**: a `SUMMARY` eyebrow and a four-tile `StatsRow` —
     PRs (all time), Sets (last 30 days), Sessions (all time), Goals met —
     with the caption `Sets are the last 30 days; the rest are all time.`
   - **PRs**: the exercise's PR feed, newest first, each under its written
     date (`29 OCT`) and drawn with the app's shared `PrEventRow` card.
   - **Goals**: the Goals preview's two-column OPEN | COMPLETE ledger, using
     the shared `GoalLabColumns` (`lab_goal_columns.dart`) — goal icon + by/
     met date, notebook-pen + created date, success ink when met.
- Search filters the current list; sort rewrites its order; the range filter
  narrows by date. Tapping a goal opens its placeholder screen.
- The PR totals per exercise come from the Exercises tab's sample; PR events
  are generated from a prescription (newest = heaviest, walking down). The
  picker's last-month set count is the sample's lifetime sets ÷ 3 (0 when the
  exercise has not been logged in 30 days).

### Variations
- Still the pill layout (name + exercise/set pills). No date change needed.
- Name column widened to hold a 20-character name (2026-11-03); pills wrap.
- This tab is one of the "weak" ones — redesign pending.

### Goals
- Two dates stacked under the name (2026-11-03):
  - **by / met** date: the goal's bullseye icon + date (success ink when met).
  - **created** date: the notebook-pen icon + date.
- Date + `· Nd` inside 99 days; year when not current.
- No “by” / “met” / “created” words — the icon carries the meaning.
- Goal names wrap freely under a half-width column.

### Workouts
- Date line: `logged 31 oct · 3d` — "last" removed 2026-11-03.
- Right-hand metrics: sessions run (play glyph, no label), PRs (trophy,
  accent), goals hit (bullseye, success). Replaces the old "N exercises" text.
- Last-logged order (most recent first); last-year rows carry the year.
- Long names wrap; no ellipsis.

### Reviews
- Now in the **session ledger shape** (2026-11-03): same date rail as the
  Session cards, review name at the session title's position and size, PRs
  (trophy) and goals hit (bullseye) in the title row, workouts listed as
  plain stacked lines — no pills, no PRE/POST stars.
- Rail shows weekday, or the year when not current, plus the day count
  inside 99 days; date reads month-caps.
- Whole row tappable → placeholder `ReviewLabScreen` for now.

## Cross-cutting rules

- **Dates:** a written date shows the year only when it is not the current
  year. Within **99 days** (two digits max) it also carries a day count —
  `5D` in the Session rail (caps), `· 5d` in the other tabs. At 100 days the
  count disappears and the written date stands alone.
  Helper: `daysReading` / `railDaysReading` in `session_cards_screen.dart`.
- **Names:** every user-created name is capped at 20 characters. Every row in
  these tabs must render a full 20-character name — wrap to a second line
  rather than ellipsis or clip (2026-11-03).
- **Ink:** follow the existing tokens — `primary` content, `inkSecondary`
  secondary/quiet, `accent` PRs, `success` goals hit; `muted` never for text.
- **Navigation:** every card/ledger row opens its entity's screen. Session
  has the real viewer mirror and Exercise its own new screen; Variation /
  Goal / Workout / Review are still empty placeholders.

## Rollout order (when the user says go)

1. Finish settling each tab in the lab (Session done first; the rest follow).
2. Fill in the five placeholder entity screens with their real previews.
3. Extract the lab's widgets out of `lib/features/dev/` into production
   widgets; wire real data (repositories + ViewModels).
4. Replace the personal Session and Library tab screens with the new design.
5. Rebuild the real friend profile and its follow-on screens on the same
   widgets and layouts; capability (read-only, no write doors) — not a
   separate design — separates a friend's view from your own.
6. Keep the dev lab until the rollout is verified, then retire it as the
   decision record.
