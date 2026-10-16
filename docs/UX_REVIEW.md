> Superseded by the build 2 flow redesign and navigation-driven review in `output/flow-redesign/REVIEW.md`. The earlier captures below did not prove complete user journeys.

# Three-pass UX review — September 18, 2026

This is a historical design review. Referenced review captures were local
working artifacts and are not included in this repository.

## Loop 1 — task flow and navigation

Review: the original home stacked all entry controls ahead of the timeline. History was buried inside an activity card, and a feeding-only floating button competed with the rest of the UI.

Fix: persistent Today, History, and Family destinations; a four-action quick-log area; a single chooser for all ten categories; contextual nursing, sleep, and pumping flows; active timers appear on Today; recent activity is separated from full history. Entries share recognizable activity icons and date formatting.

Verification: actual widget captures saved in `../output/ux-review/loop-1/`. Updated the existing feeding/diaper/nursing tests for the new entry points.

## Loop 2 — visual hierarchy and form consistency

Review: inconsistent button shapes, decorative subtitles, character counters, and long technical sharing instructions created unnecessary scanning. Save scrolled away with the form. The onboarding sign-in path still used a modal despite the known Google web-button issue.

Fix: restrained green palette, consistent typography, rectangular rounded controls, white sheets, explicit close buttons, and shared form/time components. Save stays below the scrolling fields and above keyboard space. Sharing prioritizes account connection and caregiver invitations; restore and data tools expand on demand. Onboarding joins open a full page. History has clear totals, matching activity rows, filters and empty states.

Verification: existing form tests pass for every activity type. Actual widget captures saved in `../output/ux-review/loop-2/`.

## Loop 3 — state, feedback and accessibility

Review: switching destinations discarded history selection; blank feeding fields hid units; successful saves were silent; invitation errors appeared far below their input; timer-start sheets needed live busy/error updates.

Fix: preserve visited tab state; show units in field labels; confirm completed saves; prevent repeated save submissions; disable fields during save; show invitation errors inline; add live error semantics and observable timer-sheet state. Match history and home formatting and sort recent entries explicitly.

Verification: 47 automated tests pass, including a 320 × 640 phone at 180% text scale, all form categories, keyboard-space handling, persistent history day/filter selection, and access to all ten logging categories. Static analysis is clean. Configured web build and unsigned iPhone build pass. Actual widget captures saved in `../output/ux-review/loop-3/`.

## Review artifact and limits

The updated fillable PDF is `../output/pdf/little-log-refined-screen-review.pdf`: 58 screen views, clickable overview, per-screen notes, keep-as-is checkboxes, cross-screen references, and global change instructions. Screens use sample data; connected-account states are simulated. The original review PDF is retained.

Live browser inspection was blocked by the unavailable administrator-policy check. No browser-policy workaround was used. No device installation, real Google invitation, live cloud verification, or real baby-data change was performed. Google-owned sign-in/consent/Picker contents and the operating-system keyboard are outside these widget captures.
