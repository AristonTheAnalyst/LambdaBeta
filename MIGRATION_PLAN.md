# Lambda → Flutter Migration Plan

> Source: `D:\Repositories\Lambda\lambda` (Expo + Expo Router, TypeScript)
> Destination: `D:\Repositories\Lambda In Flutter\lambda` (Flutter + Dart)
>
> **Strategy: online-only.** All reads/writes go directly to Supabase.
> Offline-first (PowerSync) will be layered on later — no SQLite, no mutation queue, no sync engine in this phase.

---

## 1. What exists in each codebase

### React Native source (complete app)

| Area | Technology |
|---|---|
| Framework | Expo SDK 54, Expo Router v6 (file-based) |
| Language | TypeScript |
| Navigation | Expo Router — Stack + 6-tab bottom nav |
| UI library | Tamagui (XStack, YStack, Text, Separator, Spinner) |
| Backend | Supabase (auth + database) |
| Auth methods | Email/password, Google OAuth, Apple Sign-In |
| Animations | react-native-reanimated (squash press), SlidePages transitions |
| Gestures | react-native-gesture-handler, react-native-draggable-flatlist |
| Validation | Zod |
| Icons | Expo Vector Icons (Ionicons, FontAwesome), Lucide React Native |
| Date picker | @react-native-community/datetimepicker |

### Flutter destination (current state — partial)

| Area | Status |
|---|---|
| Auth screens (login, signup, forgot password) | Done |
| Onboarding screen | Done |
| Home placeholder screen | Done (stub — will be replaced by tab shell) |
| GoRouter navigation + auth guard | Done |
| Supabase auth repository | Done |
| User profile repository + model | Done |
| AuthViewModel (ValueNotifier pattern) | Done |
| Design system (AppColors, AppTextStyles, AppTheme dark) | Done |
| Shared widgets (LambdaButton, LambdaInput) | Done |
| Validators utility | Done |

---

## 2. Screen inventory and mapping

| RN route | Screen name | Flutter target path | Complexity |
|---|---|---|---|
| `(auth)/login` | Login | `features/auth/view/login_screen.dart` | Done |
| `(auth)/signup` | Sign Up | `features/auth/view/signup_screen.dart` | Done |
| `(auth)/forgot-password` | Forgot Password | `features/auth/view/forgot_password_screen.dart` | Done |
| `(auth)/reset-password` | Reset Password | `features/auth/view/reset_password_screen.dart` | Low |
| `(onboarding)/` | Onboarding | `features/onboarding/view/onboarding_screen.dart` | Done |
| `(tabs)/` → redirects to `/three` | — | GoRouter redirect | Trivial |
| `(tabs)/one` | Profile Hub | `features/profile/view/profile_hub_screen.dart` | Low |
| `(tabs)/one/profile` | Profile Detail | `features/profile/view/profile_detail_screen.dart` | Medium |
| `(tabs)/two` | Exercise Config Hub | `features/exercises/view/exercise_hub_screen.dart` | Low |
| `(tabs)/two/library` | Exercise Library | `features/exercises/view/exercise_library_screen.dart` | High |
| `(tabs)/two/guide` | User Guide | `features/exercises/view/guide_screen.dart` | Low |
| `(tabs)/two/programs` | Programs | `features/exercises/view/programs_screen.dart` | Low |
| `(tabs)/three` | Workout Session | `features/session/view/session_screen.dart` | **Critical** |
| `(tabs)/four` | Training Logs | `features/logs/view/logs_screen.dart` | High |
| `(tabs)/four/[id]` | Workout Detail | `features/logs/view/workout_detail_screen.dart` | High |
| `(tabs)/five` | Statistics | `features/statistics/view/statistics_screen.dart` | Low (placeholder) |
| `(tabs)/six` | Dev Tools | `features/dev/view/dev_screen.dart` | Low |

---

## 3. Dependency mapping — RN → Flutter

| React Native package | Flutter equivalent | pub.dev package |
|---|---|---|
| `@supabase/supabase-js` | Supabase client | `supabase_flutter: ^2.8.4` (already added) |
| `zustand` + `@tanstack/react-query` | Riverpod async providers | `flutter_riverpod: ^2.6.1` |
| `expo-router` (tabs) | GoRouter ShellRoute | `go_router: ^14.6.3` (already added) |
| `react-navigation/bottom-tabs` | Custom bottom nav widget | Custom |
| `tamagui` (XStack/YStack) | Row / Column / Expanded | Flutter built-ins |
| `tamagui` (Text, Spinner, Separator) | Text, CircularProgressIndicator, Divider | Flutter built-ins |
| `react-native-reanimated` (squash press) | AnimationController + ScaleTransition | `flutter_animate: ^4.5.0` |
| `react-native-reanimated` (SlidePages) | PageView | Flutter built-in |
| `react-native-gesture-handler` | GestureDetector | Flutter built-in |
| `react-native-draggable-flatlist` | ReorderableListView | Flutter built-in |
| `@expo/vector-icons` (Ionicons) | Icons.* (Material) — map per icon | Flutter built-in |
| `@expo/vector-icons` (FontAwesome) | FontAwesome icons | `font_awesome_flutter: ^10.7.0` (already added) |
| `@react-native-community/datetimepicker` | `showDatePicker()` | Flutter built-in |
| `@react-native-picker/picker` | Custom bottom sheet list | Flutter built-in |
| `zod` (validation) | Dart validators (existing `validators.dart`) | Custom |
| `expo-apple-authentication` | Apple Sign-In | `sign_in_with_apple: ^6.1.4` (already added) |
| `expo-linking` | Deep link handling | `app_links: ^6.4.0` (already added) |

**Add to pubspec.yaml:**
```yaml
dependencies:
  flutter_riverpod: ^2.6.1
  flutter_animate: ^4.5.0
  intl: ^0.20.2
```

That's it — no sqflite, no uuid, no connectivity_plus. Supabase Flutter handles auth token storage internally.

---

## 4. Architecture decisions

### State management: Riverpod

The RN app mixes Zustand + React Context + React Query. In Flutter, **Riverpod** covers all three cleanly:

- `AsyncNotifierProvider` → data fetched from Supabase (replaces React Query)
- `NotifierProvider` / `StateNotifierProvider` → local UI state (replaces Zustand)
- `StreamProvider` → auth state stream (replaces AuthContext)
- `Provider` → simple computed values

The existing `ValueNotifier`/`ChangeNotifier` pattern in auth stays as-is. All new features use Riverpod.

### Data layer: Supabase repositories

All CRUD goes through repository classes in `data/repositories/`. No local cache. Each operation calls Supabase directly and returns the result. Riverpod providers call the repositories and hold the resulting state.

For the Session screen, this means:
- `createWorkout` → `supabase.from('fact_user_workout').insert(...)`
- `insertSet` → `supabase.from('fact_workout_set').insert(...)`
- `updateSet` → `supabase.from('fact_workout_set').update(...).eq(...)`
- etc.

### Navigation: GoRouter ShellRoute for tabs

Replace the Expo Router `(tabs)` group with a GoRouter `ShellRoute`. The custom bottom nav bar sits outside the routed content, identical to how the RN app renders `ExternalBottomNav` outside `<Tabs>`.

---

## 5. Folder structure (target)

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── styles/
│   │   ├── app_colors.dart          (done)
│   │   ├── app_text_styles.dart     (done)
│   │   └── app_theme.dart           (done)
│   └── utils/
│       ├── validators.dart          (done)
│       └── workout_format.dart      (new — port of workoutSetFormat.ts)
├── data/
│   ├── models/
│   │   ├── user_profile.dart        (done)
│   │   ├── workout.dart             (new)
│   │   ├── workout_set.dart         (new)
│   │   ├── custom_exercise.dart     (new)
│   │   ├── custom_variation.dart    (new)
│   │   └── exercise_detail.dart     (new — exercise + assigned variations)
│   └── repositories/
│       ├── auth_repository.dart     (done)
│       ├── user_repository.dart     (done)
│       ├── exercise_repository.dart (new)
│       └── workout_repository.dart  (new)
├── features/
│   ├── auth/
│   │   ├── view/
│   │   │   ├── login_screen.dart              (done)
│   │   │   ├── signup_screen.dart             (done)
│   │   │   ├── forgot_password_screen.dart    (done)
│   │   │   └── reset_password_screen.dart     (new)
│   │   └── viewmodel/
│   │       └── auth_viewmodel.dart            (done)
│   ├── onboarding/
│   │   └── view/
│   │       └── onboarding_screen.dart         (done)
│   ├── profile/
│   │   ├── view/
│   │   │   ├── profile_hub_screen.dart        (new)
│   │   │   └── profile_detail_screen.dart     (new)
│   │   └── viewmodel/
│   │       └── profile_viewmodel.dart         (new)
│   ├── exercises/
│   │   ├── view/
│   │   │   ├── exercise_hub_screen.dart       (new)
│   │   │   ├── exercise_library_screen.dart   (new)
│   │   │   ├── guide_screen.dart              (new)
│   │   │   └── programs_screen.dart           (new)
│   │   └── viewmodel/
│   │       └── exercise_viewmodel.dart        (new)
│   ├── session/
│   │   ├── view/
│   │   │   └── session_screen.dart            (new)
│   │   └── viewmodel/
│   │       └── session_viewmodel.dart         (new)
│   ├── logs/
│   │   ├── view/
│   │   │   ├── logs_screen.dart               (new)
│   │   │   └── workout_detail_screen.dart     (new)
│   │   └── viewmodel/
│   │       └── logs_viewmodel.dart            (new)
│   ├── statistics/
│   │   └── view/
│   │       └── statistics_screen.dart         (new — placeholder)
│   └── dev/
│       └── view/
│           └── dev_screen.dart                (new)
└── shared/
    ├── providers/
    │   └── exercise_data_provider.dart        (new — Riverpod, replaces ExerciseDataContext)
    ├── router/
    │   ├── app_router.dart                    (update — ShellRoute + all routes)
    │   └── auth_notifier.dart                 (done)
    └── widgets/
        ├── lambda_button.dart                 (done)
        ├── lambda_input.dart                  (done)
        ├── bottom_nav_bar.dart                (new)
        ├── page_header.dart                   (new)
        ├── slide_up_modal.dart                (new)
        ├── dropdown_select.dart               (new)
        ├── segmented_control.dart             (new)
        ├── slide_pages.dart                   (new)
        ├── slide_tab_bar.dart                 (new)
        ├── slide_tab_view.dart                (new)
        └── press_squash.dart                  (new)
```

---

## 6. Phased implementation plan

### Phase 0 — Dependency setup (half day)
1. Add `flutter_riverpod`, `flutter_animate`, `intl` to `pubspec.yaml`.
2. Run `flutter pub get`.
3. Wrap `main()` with `ProviderScope`.

### Phase 1 — Data models (1 day)
Dart model classes with `fromMap`/`toJson` serialization matching Supabase column names exactly.

- `Workout` — maps to `fact_user_workout`
- `WorkoutSet` — maps to `fact_workout_set`
  - `workoutSetReps` and `workoutSetDurationSeconds` are stored as Supabase arrays — deserialize as `List<num>`
- `CustomExercise` — maps to `user_custom_exercise`
- `CustomVariation` — maps to `user_custom_variation`
- `ExerciseDetail` — derived model: `CustomExercise` + `List<CustomVariation>` (assigned). Used everywhere exercises are displayed.

Also port `workoutSetFormat.ts` → `workout_format.dart`:
- `parseValues(String input)` — parses `"10,8,6"` → `[10, 8, 6]`
- `toProperCase(String s)` — title-cases a string

### Phase 2 — Supabase repositories (1 day)

**`ExerciseRepository`**
```dart
Future<List<CustomExercise>> fetchExercises(String userId);
Future<List<CustomVariation>> fetchVariations(String userId);
Future<List<ExerciseBridgeRow>> fetchBridges(String userId);
Future<CustomExercise> createExercise(String userId, String name, String volumeType);
Future<void> reactivateExercise(String exerciseId, String volumeType);
Future<CustomVariation> createVariation(String userId, String name);
Future<void> reactivateVariation(String variationId);
Future<void> addBridge(String userId, String exerciseId, String variationId);
```

**`WorkoutRepository`**
```dart
Future<String> createWorkout(String userId, String? preNotes);
Future<void> endWorkout(String workoutId, String? postNotes);
Future<void> cancelWorkout(String workoutId);       // hard delete
Future<String?> getActiveWorkoutId(String userId);
Future<WorkoutSet> insertSet({...});
Future<void> updateSet(String setId, {...});
Future<void> deleteSet(String setId);
Future<List<WorkoutSet>> loadSetsForWorkout(String workoutId);
Future<void> reorderSets(String workoutId, List<String> orderedIds);
Future<List<WorkoutWithSets>> loadWorkoutsWithSets(String userId);
Future<List<PastSetRow>> loadPastSetsTimeline(String userId);
```

> `getActiveWorkoutId` queries Supabase for a workout with `is_active = true` for the current user. In the offline-first RN app this was a local SQLite query; here it's a lightweight Supabase call.

### Phase 3 — ExerciseData provider (half day)
Central Riverpod provider that caches exercise + variation data for the session. Multiple screens read from this instead of each hitting Supabase independently.

```dart
// shared/providers/exercise_data_provider.dart
final exerciseDataProvider = AsyncNotifierProvider<ExerciseDataNotifier, ExerciseDataState>(...);

class ExerciseDataState {
  final List<CustomExercise> exercises;
  final List<CustomVariation> variations;
  final Map<String, ExerciseDetail> exerciseDetailMap;
}
```

Call `ref.invalidate(exerciseDataProvider)` after any create/reactivate operation to force a refresh.

### Phase 4 — Navigation shell (1 day)
1. Update `app_router.dart` to use a `ShellRoute` wrapping all tab destinations.
2. `bottom_nav_bar.dart` — mirrors the RN `BottomNav` exactly: 6 items in the same order (Statistics → Logs → Session → Exercises → Profile → Dev), with Ionicons equivalent Material icons.
3. `page_header.dart` — top bar with title + optional left/right widget slots.
4. `TabShell` widget — composes `PageHeader` + routed child + `BottomNavBar`.

**GoRouter tab routes:**
```
/session      → SessionScreen     (default tab, mirrors /three redirect)
/logs         → LogsScreen
/logs/:id     → WorkoutDetailScreen
/exercises    → ExerciseHubScreen
/exercises/library   → ExerciseLibraryScreen
/exercises/guide     → GuideScreen
/exercises/programs  → ProgramsScreen
/profile      → ProfileHubScreen
/profile/detail → ProfileDetailScreen
/statistics   → StatisticsScreen
/dev          → DevScreen
```

### Phase 5 — Shared UI components (1–2 days)
Build before the screens that depend on them.

**`press_squash.dart`**
On press-down, scales to ~0.96 with a spring. Use `flutter_animate`'s `.scale()` effect triggered by a `GestureDetector` or `InkWell` with a custom splash. This replaces `PressSquash.tsx` / `SquashPressable`.

**`slide_up_modal.dart`**
Thin wrapper around `showModalBottomSheet`. Parameters:
- `fitContent: bool` → `isScrollControlled: true` + `useSafeArea: true`
- `keyboardAware: bool` → set `Scaffold` with `resizeToAvoidBottomInset` or wrap content in `Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom))`
- For stacked modals (Session screen), call with `useRootNavigator: true` so each sheet is pushed on the root navigator stack.

**`dropdown_select.dart`**
Custom bottom sheet option picker. Parameters: `options`, `value`, `onChange`, `placeholder`, `searchable`, `onCreateNew`, `createNewLabel`. Mirrors `DropdownSelect` from `FormControls.tsx`. Not a material `DropdownButton`.

**`segmented_control.dart`**
Horizontal row of tappable chips. Mirrors `SegmentedControl` from `FormControls.tsx`.

**`slide_pages.dart`**
A `PageView` with a controller class (`SlidePagesController`) exposing `slideIn()`, `slideOut()`, `resetToPage(int)`. Mirrors `SlidePages.tsx` + `useSlidePages.ts`.

**`slide_tab_bar.dart`** + **`slide_tab_view.dart`**
Tab indicator bar + synced `PageView`. Used by the Logs screen. Mirrors `SlideTabBar.tsx` + `SlideTabView.tsx`.

### Phase 6 — Auth reset-password screen (half day)
Triggered by a `PASSWORD_RECOVERY` deep link. Show new-password + confirm form. On submit: `supabase.auth.updateUser(data: {'password': newPassword})`.

In `AuthNotifier`, listen to `supabase.client.auth.onAuthStateChange` and emit a `passwordRecovery` state when the event type is `AuthChangeEvent.passwordRecovery`. GoRouter redirect picks this up and routes to `/reset-password`.

### Phase 7 — Profile screens (1 day)
1. `ProfileHubScreen` — list of section cards. Port of `one/index.tsx`. Read source before implementing.
2. `ProfileDetailScreen` — view/edit `UserProfile` (name, DOB, gender, height, weight). Port of `one/profile.tsx`. Read source before implementing. Writes to Supabase `dim_user` table via `UserRepository`.

### Phase 8 — Exercise screens (2 days)
Build in order:

1. `ExerciseHubScreen` — hub card list (Library, Guide, Programs). Port of `two/index.tsx`.
2. `GuideScreen` — static content. Port of `two/guide.tsx`.
3. `ProgramsScreen` — placeholder. Port of `two/programs.tsx`.
4. `ExerciseLibraryScreen` — full exercise + variation management. Port of `two/library.tsx`. Read source before implementing. All CRUD goes through `ExerciseRepository`, then call `ref.invalidate(exerciseDataProvider)`.

### Phase 9 — Training Logs screens (2 days)
1. `LogsScreen` — tab view (Workouts | Sets). Reads from Supabase via `WorkoutRepository`. Pull-to-refresh triggers a new fetch. Uses `SlideTabBar` + `SlideTabView`. Port of `four/index.tsx`.
2. `WorkoutDetailScreen` — one workout + its sets. Allows editing sets. Port of `four/[id].tsx`. Read source before implementing.

### Phase 10 — Session screen (3–4 days)
**The most complex screen.** `three.tsx` is 825 lines with 10+ modals and significant form state. Break into sub-tasks:

1. **`SessionViewModel`** — `ChangeNotifier` (or Riverpod `Notifier`) holding: `currentWorkoutId`, `sets`, all modal-open booleans, all form field values, `viewMode`. Every mutation calls `WorkoutRepository` and then calls `notifyListeners()` / `state = state.copyWith(...)`.
2. **`WorkoutSetsList` widget** — grouped or chronological set list. Drag-to-reorder via `ReorderableListView`. On reorder, calls `WorkoutRepository.reorderSets()`.
3. **`WorkoutLogStickyFooter` widget** — "Log Set" button pinned to bottom.
4. **`SlidePages` integration** — Page 0 (start/pre-workout), Page 1 (active session).
5. **Log Set modal** — exercise dropdown, optional variation dropdown, weight field, reps/duration field, notes field.
6. **Edit Set modal** — same fields + delete button.
7. **End Workout modal** — post-workout notes + confirm.
8. **New Exercise modal** — name + `SegmentedControl` (Reps / Duration).
9. **Assign Variations sheet** — multiselect existing variations + "New Variation" shortcut.
10. **New Variation modal** — name input.

**Key behaviours to preserve (online-only simplification):**
- Exercise defaults (last weight + last variation) — fetch from Supabase `exercise_defaults` on exercise selection, or derive from the last logged set.
- `InteractionManager.runAfterInteractions` pattern → `WidgetsBinding.instance.addPostFrameCallback`.
- Drag reorder updates `workout_set_number` for all affected rows in a single batch update.
- Duplicate exercise/variation names: check via Supabase query before creating (`findExerciseByName` / `findVariationByName` equivalent in `ExerciseRepository`).
- `parseValues` (from `workout_format.dart`) to parse user's reps/duration input string.

### Phase 11 — Statistics screen (half day)
Placeholder only. "Coming soon." text centered on screen.

### Phase 12 — Dev screen (half day)
Simple dev tooling screen. The SQL inspector from the RN app is irrelevant (no local DB). Replace with a Supabase query inspector or basic diagnostic info (current user, session info, env). Low priority.

### Phase 13 — Polish (1–2 days)
- Squash press on all interactive cards.
- SlidePages animation.
- Dark theme consistency pass.
- Safe area insets on all screens.
- Keyboard avoid behaviour on all input-heavy screens.
- Update Supabase OAuth redirect URL from `com.example.lambda://` to the real bundle ID.
- Move Supabase URL + anon key out of `main.dart` into compile-time `--dart-define` constants or `flutter_dotenv`.

---

## 7. Technical notes

### 7.1 workout_set_reps / workout_set_duration_seconds
In Supabase, these are likely stored as JSONB arrays or text[]. When reading from Supabase via `supabase_flutter`, these will come back as `List<dynamic>`. Cast to `List<num>` on deserialization. The `parseValues` Dart utility parses the user's text input (`"10,8,6"`) into this list before insert.

### 7.2 SlideUpModal stacking
The Session screen stacks up to 3 bottom sheets (Log Set → Assign Variations → New Variation). Call all `showModalBottomSheet` with `useRootNavigator: true` so each sheet is pushed on the root navigator stack and they layer correctly.

### 7.3 Auth deep link (password recovery)
`AuthContext.tsx` detects `PASSWORD_RECOVERY` from `supabase.auth.onAuthStateChange`. Port this: in `AuthNotifier`, expose an `isPasswordRecovery` flag from the auth state stream, and add a GoRouter redirect that sends to `/reset-password` when it's true.

### 7.4 ExerciseData pre-warming
The RN app pre-warms the exercise cache when Tab 2 mounts so sub-screens open instantly. In Flutter, trigger `ref.read(exerciseDataProvider.notifier).build()` (or `ref.refresh`) on `ExerciseHubScreen` mount via a `ref.listen` or `Consumer` init.

### 7.5 Active workout on app resume
`getActiveWorkoutId` must be called when the Session screen mounts so a resumed in-progress workout is restored. Query `fact_user_workout` for `is_active = true AND user_id = userId LIMIT 1`.

---

## 8. Implementation order summary

```
Phase 0   pubspec + ProviderScope
Phase 1   Data models + workout_format.dart
Phase 2   Supabase repositories (Exercise + Workout)
Phase 3   ExerciseData provider (Riverpod)
Phase 4   Navigation shell (ShellRoute + BottomNav + PageHeader)
Phase 5   Shared UI components (SlideUpModal, DropdownSelect, SlidePages, PressSquash, etc.)
Phase 6   Reset-password screen
Phase 7   Profile screens
Phase 8   Exercise screens
Phase 9   Training Logs screens
Phase 10  Session screen          ← most effort, ~3-4 days
Phase 11  Statistics screen
Phase 12  Dev screen
Phase 13  Polish + prod config
```

Estimated total: **~13–16 developer-days** — roughly 25–30% less than the offline-first version.

---

## 9. What NOT to do

- Do not add SQLite, sqflite, or any local database — that comes with PowerSync later.
- Do not port the mutation queue, sync engine, or any offline store files.
- Do not use `flutter_redux` or `get` — stick to Riverpod + the existing ValueNotifier pattern.
- Do not translate Tamagui primitives literally — `YStack` → `Column`, `XStack` → `Row`, `flex={1}` → `Expanded`. Translate intent, not syntax.
- Do not write to Supabase outside of a repository class — all DB access goes through `data/repositories/`.
