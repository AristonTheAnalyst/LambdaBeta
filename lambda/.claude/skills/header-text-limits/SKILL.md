---
name: header-text-limits
description: >
  The character budget for anything drawn in a header bar. Use whenever a
  screen title is authored, a user-created name is drawn in a PageHeader (or
  in an inline header rename field), or a header is being laid out — so no
  title ever has to be cut in the bar that frames the screen.
---

# Header text limits — one line, twenty characters

A header is the frame. Text that does not fit it is not "long"; it is wrong.
The rule comes from a measured surface, not a preference: `PageHeader` centres
its title between two 88pt bands (`left: 88, right: 88` — a 44pt control plus
16pt at each edge), which leaves the title **217–226pt** on the phones this
design targets (393–402pt wide). At the header's type — `AppFonts.ui`, 18,
w600 — that is:

| Input | Fits in 226pt |
|---|---|
| average lowercase (`a`) | ~22 characters |
| wide uppercase (`W`) | ~13 characters |
| `Legs & Core Strength` (20) | 182pt — comfortable |

So the budget is **20 characters**, every time, for every header. It is a
ceiling, not a target. (A 375pt screen is one character tighter; the ellipsis
is the backstop there, never the plan.)

## The rule

1. **Authored titles stay at or under 20 characters.** Short nouns and
   phrases only — `Sessions`, `Pre-Evaluation`, `Session Reflection`,
   `Reviews`. Never a sentence, a count, or a verb phrase (`Start a new
   workout` belongs in the body, not the bar).
2. **A user-created name drawn in a header rides its kind's cap**, and every
   kind's cap is 20 (`lib/core/utils/name_limit.dart`: workout, program,
   block, goal text, review title — see the frontend-design skill's
   "User-created names"). A name whose cap would let it exceed 20 must never
   be drawn in a header.
3. **Never compose a title from parts that can each spend the full budget.**
   `'$program — $workout'` sums two budgets and overruns both. A composition
   is acceptable only when the part that must always read whole comes
   **first** and fits the band alone, and the part **last** is
   supplementary — the ellipsis lands on the supplement, so the screen still
   makes sense cut. The exercise detail's `name · variation` pill is the
   reference shape: the exercise (≤ 20) leads, the variation yields. If an
   authored prefix is essential (`Review: …`), the prefix spends the same 20.
   The idle Training page's header carries **one** value — the session
   template's name, or `Freestyle Session` (authored, 16) — so it spends one
   budget; the selector pill is a header selector (frontend-design §5), not
   a composition.
4. **Inline rename fields get the same budget.** `titleWidget` (the program
   and workout name `TextField`s) scrolls instead of ellipsizing, so the
   field's `maxLength` is the only thing holding it in the slot. The planner's
   hand-rolled header band is `left: 88, right: 88` for the same reason and
   gets the same 20.
5. **One line, nothing else.** A header has no subtitle, badge count or
   second row. If the information is worth more than 20 characters, it is
   body content.
6. **Do not widen the title by shrinking the band ad hoc.** The 88pt gutters
   are what keep a 44pt control's target intact; if a header genuinely needs
   a different band, measure it against the type size first, state the new
   budget in a comment, and keep the reading centred on the screen.

`PageHeader` draws `maxLines: 1, overflow: ellipsis` as the last resort. A
cut title is a bug in the name or the budget — never in the bar.

## How the numbers were measured (2026-10-20)

Real fonts, not guesses: `TextPainter` over `assets/fonts/Manrope-600.ttf`
at 18px, `maxWidth` 226, walking a run of a single glyph until
`didExceedMaxLines`. Re-run this if the header type, the gutters or the
target phone width ever change — the cap is derived from the band, and the
`name_limit_test.dart` pins must move with it.

Why this skill exists: a 30-character workout name elided in the session
header it was named for. The display fix (`UserNameText`) kept it from
breaking the layout; the limit is what stops the user creating a name no
header can show.

## Checklist

- [ ] Every title authored for a header is ≤ 20 characters
- [ ] Every user-created name shown in a header is capped at 20 with a counter
      on its field
- [ ] No title assembled from parts that can sum past the budget
- [ ] Inline header fields carry `maxLength` at the cap
- [ ] One line; no subtitle, count or second row has crept in
- [ ] Any hand-rolled header reuses the 88pt bands and states its own budget
