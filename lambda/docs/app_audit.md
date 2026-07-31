# Lambda — App Audit (as of 31 July 2026)

A review of everything a user can currently do in the app, feature by feature, plus a
long-term roadmap for features that are on the radar but not yet built.

---

## The user journey

### 1. Sign up / authentication — ✅ complete
- Email/password signup and login with validation + error banners
- **Google** and **Apple** (iOS only) social login
- Forgot / reset password flow
- Deep-link password recovery handling

### 2. Onboarding — ✅ complete
- 4-slide welcome deck after first sign-in: *Track Your Workouts*, *Plan with
  Programs*, *Set PRs & Review*, *Stay Consistent*
- Skip button + Get Started; router gates unboarded users to onboarding and
  sends onboarded users straight in

### 3. Shown around the app — ✅ partial
- A **User Guide** exists under Exercise Configuration → `/exercises/guide`
  (content depth needs a manual check)

---

## The core training loop

### Log training sessions — ✅ fully featured
- **Start page**: planned-workout banner, 1–5 pre-workout feeling picker,
  pre-workout notes, Start button
- **Active session**:
  - Exercise tabs (long-press reorderable, superset hexagon icons, per-exercise
    set counts)
  - 4-tile stats bar: SETS / PRS / EXERCISES / AVG REST (PR tile tappable → PR modal)
  - Rest timer with presets + custom input + circular countdown
  - Hold-to-finish End Workout button (1.5s hold) → post-notes + feeling
  - Inline set editing with auto-commit on blur, numeric-only inputs
  - **PR row highlighting** (compares against past workouts + earlier sets in
    the same session; first-ever lift counts as a PR)
  - Supersets, variations (with create-new + "did you mean?" dedup), notes
  - **Survives hot restart** — DB restore + static ViewModel cache

### Plan training sessions — ✅ fully featured
- Full-screen planner mirroring the session UX: tabs, inline target-set grid,
  add exercise, add set, swipe duplicate/delete
- Day-of-week picker for calendar-mode programs
- Unsaved-changes confirmation on back; explicit Save button + auto-commit

### Write programs — ✅ solid
- Program library: create, **set as current**, duplicate, archive
- Program detail: name / goal / length / **Sequential vs Calendar** progression,
  drag-reorder planned workouts
- **Gap**: no explicit week/phase assignment on planned workouts — "Week N" is
  inferred from program-run days, not assigned per workout

### Monitor PRs — ✅ rich
- **PR library** (replaces the old empty Statistics tab): All PRs / By Exercise /
  Timeline
- Per-exercise **rep-max curve** (tracked rep counts 1–10, 12, 15, 20, 25, 30)
  and **weight-max** (most reps at a weight)
- Tap a rep-max or weight-max → axis history sheet (every PR ever for that
  axis) → tap through to the originating past session
- **Cascade-on-delete**: deleting a source set deletes its PRs (with a warning
  showing the count) and recomputes, promoting the next-best
- PR snapshots persisted in `fact_pr`; live in-session highlight matches the
  persisted logic
- **Gaps**: no general statistics (volume, frequency, charts); no bodyweight /
  weight-tracking UI

### Review past workouts & sets — ✅ good
- **Logs screen**: Workouts + Sets tabs, filters (exercise / variation / date
  range), pull-to-refresh, planned-workout badge on cards
- **Past-session viewer**: tabbed exercise layout, read-only view + edit mode,
  PR row highlighting, Lessons/History, Pre/Post notes buttons
- **Gap**: rest-period history and pre/post-feeling are captured but **not
  displayed** in past-session review

### Configure exercises & variations — ✅ complete
- Exercise library: create / edit / archive exercises and variations
- Assign variations to exercises (multi-select), search, archive
- Per-exercise **Lessons** (pinnable cue cards) and **History** reference

---

## Secondary surfaces

| Surface | State |
|---|---|
| **Profile** | View/edit name, DOB, gender, height, weight |
| **Dev area** | Gallery, experimental screen, PR catalog drill-down, delete-account edge function |
| **Onboarding** | 4-slide deck |
| **Update gate** | App-store version check + required-update / nudge banners |

---

## What's NOT there yet (enhancement layer, not blockers)

1. **Analytics / statistics** beyond PRs — volume, frequency, progression charts
2. **Rest / feeling surfaced in past sessions** (data exists, UI doesn't show it)
3. **Bodyweight tracking UI** (`fact_bodyweight` table exists, no screen)
4. **Program weeks/phases** assignable to planned workouts
5. **No social / sharing / competition**
6. **No workout templates** outside programs

---

# Long-term roadmap (on the radar, not to be worked on now)

We're still refining the core features. These are directional — captured here so
the current architecture (especially the PR engine) is designed with them in mind.

### 1. PR history export / report
Export your PR history as a report. No other fitness app allows this. The
`fact_pr` snapshot table is the natural source for a clean, structured export.

### 2. Coaching system
Users coach each other. The PR engine is load-bearing here: it's the stats
engine that demonstrates coaching value — *"while coached by X, this athlete
achieved this much growth (rep-max curve moved from A to B, weight-max at N
improved, N PRs set)."* A coach needs a read-only view of a coachee's PR
progression and session history. This argues for keeping PR data queryable per
exercise/axis/date.

### 3. Gamification of achievement
Highlighting PRs is the first step. To make the app feel genuinely good to use:
- Show **PR count at the top of the live session** (already the PRS tile — can
  be made more prominent/celebratory)
- Achievement moments, streaks, milestone callouts
- Progress "level-ups" against rep-max/weight-max goals

### 4. Payment processing
The app will eventually be paid, or freemium: free tier vs paid tier, where the
paid tier unlocks full statistics. Keep the PR/analytics engine separate from
the paywall so gating can be layered on later without rework.
