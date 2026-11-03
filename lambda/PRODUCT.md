# Lambda — Product Constitution

**Version 0.2 · 2026-10-28 · Status: draft for builder review**

This document is the source of truth for what Lambda is and is not. Architecture lives in `CLAUDE.md`; design tokens live in the skills. When they disagree about *what* Lambda is, this document wins. When they disagree about *how* it is built, the more specific document wins.

---

## 0. How to use this

- Read this before proposing, designing, or building anything.
- Run every idea through the gate in §6. A "no" sends it to the parking lot, not the build.
- Change this document only in a product review (§9): named, dated, with what changed and why.
- Rejected ideas go to `DECISIONS.md` with the reason, so they do not return every six weeks.
- The landing site is downstream. Its copy is corrected to this document, never the reverse.

## 1. What Lambda is

Lambda is a memory prosthetic for resistance training.

Notes and spreadsheets let people record training, but they cannot give it back. The squat from two months ago is buried, unfindable without the right keyword, and therefore effectively forgotten. Lambda puts structure under the writing so retrieval is one tap: tap the exercise, tap back, see the history.

The core question is always exercise-centric:

- *How was this exercise last time?*
- *How has this exercise been?*

The value is assembly, not inference: putting the pieces in one place, in a list you would never build by hand. Lambda reports what happened. It does not tell you what to do. It is prescriptive only in structure — it has an opinion about how data is entered and moved through — and descriptive in output.

The promise is confidence from evidence: *I did that shit; I can do this slightly harder thing, probably.*

**Who it is for:** beginners learning to read their training; experienced lifters diagnosing a stall; coaches and training partners; anyone who wants their training to be legible without becoming a data project.

**Who it is not for:** people who want a fixed program that tells them exactly what to lift, and people who do not want to think about their training. A template serves them better. Lambda is resistance training.

As of this version, Lambda is free.

## 2. The five features — the current surface

| Feature | What it is | What it remembers |
|---|---|---|
| **Sessions** | Dated training logs. A session contains exercises; each exercise contains its sets. | What you did. |
| **Session plans** | Reusable plans for a session: exercises and target sets, loaded at the start of a session to reduce data entry. Code: **planned session** (`dim_planned_session`). | What you intended. |
| **Goals** | A target set you plan to do or beat, per exercise × variation. A multi-set goal lists rungs, each met by a distinct set. | What you are chasing. |
| **Reviews** | Named, versioned passes over one or more session plans. You see the session plan as it was, edit it, and note per exercise what changed and why. The review lens also shows PRs and goals achieved since the last review. Direct edits to a session plan bypass version history; a review is the deliberate mode. | Why you changed. |
| **PRs** | Derived on read, never stored. A set that extends the best-ever frontier for an exercise × variation. | The best you have done. |

Five features, five kinds of memory. Anything not on this list is not in the app.

## 3. The ontology

The data model is the product. Get it wrong and every feature downstream is wrong.

- **An exercise owns its sets.** Sets do not own exercises. Competitors get this backwards; do not.
- **A set** is kg, reps, and variation. Three fields.
- **Variation** is set-level and its own axis. "No variation" is an explicit value, not null. Every key is `(exercise, variation)`.
- **A session** is a dated container of exercises.
- **A session plan** is a reusable plan of exercises and target sets for one session.
- **Naming:** the user-facing term is **session plan**; the code term is **planned session** (`dim_planned_session`). "Workout" is banned from user-facing vocabulary: it collapses the plan and the execution.
- **A goal** is a target set — or several rungs — for an exercise × variation.
- **A review** is a versioned pass over session plans. It stages its edits and applies them at Finish; the plan moves only then. A session plan edited outside a review has no version history.
- **A PR is derived on read** from set history, keyed by exercise × variation. There is no PR table. A set `(w, r)` is a PR iff no prior set has `w' ≥ w` and `r' ≥ r`. A set that beats both dimensions is **one** PR, not two. Bodyweight is weight 0. A first-ever set on a pair is a PR.
- **PR means unprecedented, not superlative.** It is a statement about the record, not a judgment of the performance.
- **Retrieval is exercise-centric.** Session and review are time windows on the same exercise history. They are not separate memories.

## 4. What Lambda is not

- **Not an analytics product.** No statistical graphs, percentages, estimated 1RMs, trendlines, or inferential claims. "Analyse" means assemble.
- **Not AI.** No generated plans, recommendations, predictions, or scores.
- **Not a coach in the product.** It informs; you decide. Coaching is a human relationship the app supports, not an algorithm.
- **Not a social network.** No feed, public profiles, follower counts, or likes. Friends are permissioned training partners and coaches. Friendship is by code, instant and mutual, never a request. Coaching is request/accept.
- **Not modes.** No coach mode / user mode. Roles are permissions on the same UI.
- **Not open-ended.** Fixed fields, one exercise visible at a time, three fields per set. Notes live on sets, exercises, sessions, and reviews, each with a job. No free-form pages.
- **Not a program that tells you what to lift.** A template does that better. A program in Lambda is a structure you own and review, not a prescription the app hands you.
- **Not feature-complete by addition.** The absence is the product.
- **Not a data-science project.** The original mistake was inference. Inference does not work for trainees; they need a simpler tool to move more weight.

## 5. Non-negotiables

1. Memory over analysis.
2. Descriptive output; prescriptive structure.
3. The exercise is the atom of memory.
4. Simple for the user; complexity stays under the hood.
5. Every field has a job. There are no optional fields.
6. Five features, five memories. Surface area is a budget, not a wish list.
7. Intimate social: friend codes and granular permissions. No public surface.
8. No AI, no feed, no inference.
9. If a lifter cannot explain a feature in one sentence, it is not ready.

## 6. The gate

Every proposed feature or change must pass all five:

1. **Which of the five features does this live inside?** None → no.
2. **Does it restate and assemble logged data, or does it predict, judge, or advise?** Predict / judge / advise → no.
3. **Does it add a mode, a feed, a public surface, or a new entity?** Yes → no, unless it is a committed amendment (§7).
4. **Does it slow set entry or the exercise lookup?** Yes → no.
5. **Can a lifter find and use it without being taught?** No → no.

A sixth feature does not enter because it is small. It enters only by displacing one or by an explicit amendment to this document.

## 7. Programs — committed; semantics unsettled

**Status:** committed to return; currently out of the UI (2026-10-26) while the semantics are settled. The data layer is retained, including blocks and runs. Treat the existing structures as proposals, not decisions.

**Why it belongs:** programming is not necessary for the framework, but it is too common a training paradigm to omit. Most lifters train inside a program. Without one, Lambda is unusable for them.

**Working definition:** a program is a set of session plans done and reviewed in a structured way.

**Guardrail:** a program is a composition over session plans and reviews. It is not a new kind of memory and not a second source of truth. If it starts owning session plans, duplicating review semantics, or prescribing what you lift, it is drifting.

**Open semantics — settle these here before any program UI returns:**

1. Does a program **reference** session plans or **own copies**? What happens to the program when a session plan is edited — pin the version or follow the latest?
2. Can one session plan belong to more than one program?
3. Is a program a **sequence** (ordered session plans), a **schedule** (dates/frequency), or both?
4. Is a **run** a distinct commitment (with a start, end, and progress) or just the act of doing the session plans? Does the existing `run` concept survive?
5. Is a **block/phase** a first-class idea (e.g. accumulation → intensification) or only ordering?
6. What makes a program **done**? Does completion produce a review?
7. Do goals attach to the program, the session plan, or the exercise?
8. What does a **program-level review** cover that a review of a single session plan does not?

**Rule:** no program UI ships until every question above is answered in this section.

## 8. On the radar — not committed

- **Calendar.** Acceptable only as a *view* over existing sessions, session plans, goals, and reviews. If it adds scheduling semantics, recurrence, reminders, or new entities, it is new memory and needs an amendment. Calendar waits on programs: scheduling should be settled once, not twice.
- **Scheduled reviews by frequency.** Extends the principle of reminding you what you said you would do. A reminder, not an automation: it may prompt a review, not create one. Still inside Reviews. Candidate.

Nothing here is a promise. Items move only by product review.

## 9. The process

- **Parking lot.** `DECISIONS.md`: date, idea, gate result, reason. Capture the day it occurs to you; never build it that day.
- **Product review.** The only place this document changes. Named, dated, with what changed and why. No direct edits mid-build.
- **Feature budget.** The surface is five features. A sixth enters only by displacing one or by an explicit amendment here. "It's small" is not a displacement.
- **Review cadence.** Revisit this document at each major release, or quarterly — whichever is less frequent. The constitution is Lambda's session plan; changing it without a review is the product equivalent of editing a session plan without version history.
- **Agent instruction.** `CLAUDE.md` points here. Every agent reads this before proposing a feature, runs the gate, and writes rejections to `DECISIONS.md`.

## 10. Glossary

| Term | Meaning |
|---|---|
| **Exercise** | The atom of memory. Owns its sets. |
| **Variation** | A set-level axis and value, including "none." Part of every key. |
| **Set** | kg × reps × variation. The raw datum. |
| **Session** | A dated training log; contains exercises. |
| **Session plan** | A reusable plan of exercises and target sets for one session. Code: planned session (`dim_planned_session`). |
| **Goal** | A target set, or several rungs, you plan to do or beat. |
| **Review** | A named, versioned pass over session plans, with per-exercise rationale. The "why" record. |
| **PR** | A set that extends the best-ever frontier for an exercise × variation. Derived, not stored. |
| **Program** | A structured set of session plans and reviews. Semantics unsettled (§7). |
| **Run** | A commitment to a program. Existing data-layer concept; unsettled. |
| **Block** | An ordered phase of a program. Existing data-layer concept; unsettled. |
| **Friend code** | The only social onboarding. Instant, mutual friendship. |
| **Coach** | A permissioned relationship, not a mode. |

## 11. Known drift — the landing site

The landing site currently contains claims that do not match this document. They are parked, not approved:

- **"The training framework that learns from you."** Implies the app adapts. Lambda gives your own data back; you learn.
- **"SMART goals."** Goals are target sets, not a goal-setting framework.
- **"Estimated maxes."** No inference. PRs are literal sets.
- **"Full programs."** Programs are out of the UI.
- **"Collaborate" as a loop phase.** Collaboration is a permission layer across the loop, not a phase.
- **"Smart PR detection."** Detection is deterministic; "smart" implies something the app does not do.

The site is corrected to this document when we next touch it. These lines are not to be reused.

## 12. Change log

- **0.2 — 2026-10-28** — Renamed the user-facing template from "workout" to **session plan**; "workout" is banned from user-facing vocabulary. Code remains **planned session** (`dim_planned_session`).
- **0.1 — 2026-10-28** — Initial draft from the builder's verbal model.
