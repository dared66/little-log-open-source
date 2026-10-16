# Live elapsed icon study

## Current app behavior

Quick Log uses the regular 26-point icons in both modes. Customize quick log
has a device-local **Show time since last activity** switch. When enabled, the
activity name moves beside the icon, with elapsed time beneath the name for
Bottle, Nursing, Diaper, Sleep, Pumping and Solids. Missing history shows a dash;
values over one day use `>1 day ago`. The activity picker, history and
customization keep their regular icons without elapsed labels.

## Archived seam-lettering study

`lib/widgets/seam_elapsed_glyph.dart` is retained for the design study and is no
longer used by Quick Log.

The text and surviving outline use one measured contour, with a shared baseline
and tangent. Bottle and pumping lettering is vertical; moon and plate lettering
follows circular arcs. Missing history leaves a complete contour. Values over
one day use `>1d` as a text cutoff only. The archived implementation uses the platform theme font;
the local study fonts below are not bundled into the app.

Focused app checks are in `test/elapsed_icon_preference_test.dart`. The combined
synthetic native suite also covers voice history questions and platform-specific
Settings Help:

```sh
python3 scripts/run_native_tests.py android branch_validation --device emulator-5580
python3 scripts/run_native_tests.py ios branch_validation --device <simulator-udid>
```

The current development version is build56. Study renders are synthetic widget
captures, distinct from simulator/emulator tests and physical-phone validation.

## Structural redo

The original study below was rejected by the user: its five results were mostly
cosmetic variations of one construction. The current study changes how time
forms part of the object. Its entry point is `structural_main.dart`:

```sh
flutter run -d macos -t tool/elapsed_study/structural_main.dart --dart-define=STRUCTURAL_DIRECTION=1
flutter test --no-pub tool/elapsed_study/structural_final_test.dart tool/elapsed_icon_mockup_test.dart
flutter test --no-pub tool/elapsed_study/structural_motion_test.dart
```

Directions1–5 are Seam lettering, Carved apertures, Wide objects, Numeral bodies,
and Folded surfaces. Add `--dart-define=MOCK_LIGHT=true` for light appearance.
The independent reviewer rejected a fill-only prototype, box-like folds,
disconnected numerals, missing artwork, and cropped cutoff punctuation before
accepting these five as distinct design mockups. This is not a celebrity review
or an assertion of expert-level equivalence.

`../../../output/elapsed-study/structural-reviews.md` records that review cycle.
The `structural-five-*` images show all five together. Per-direction Quick Log
and picker renders are named `structural-<construction>-<appearance>*.png`.

Live timestamps update minute labels and reset synthetic state. A180ms type
registration transition honors reduced motion. Numeral bodies use a literal
`0m` for a fresh log and return a recognizable contour when history is missing.
All other formatting preserves literal elapsed time and the `>1d` cutoff.
No shape, fill level or category color encodes a care target.

Wide objects is clearest; Numeral bodies deliberately trades some instant
recognition for numeric construction. At64px, long seam strings and folded
plate-rim text remain small. These are prototype tradeoffs, not equivalent
production readiness. Native state QA checks every activity and construction
for missing, now,59m,1h,23h59m and older history; visual review separately checks
complete characters, since nonblank pixels alone cannot prove legibility.

## Archived first study

Five final directions developed in ten independently reviewed Dart rounds.
The review brief was inspired by Alan Dye's design approach; Alan Dye did not
participate. The review records and native Flutter renders are saved under
`../../../output/elapsed-study/`.

| Direction | Typography | Outline / material |
| --- | --- | --- |
| 1 · Lunar script | Compact semibold, lettering follows a fixed lunar curve | Medium round strokes; wider lower lunar body |
| 2 · Soft bold | Rounded bold, stacked time | Soft, confident strokes; strongest everyday readability |
| 3 · Tall narrow | Compact semibold, selectively condensed | Slender bottles; natural plate and figures |
| 4 · Continuous inscription | Sans semibold, spaced single-line units | Wider diaper front; stacked fallback for long values |
| 5 · Sculpted | Rounded bold, slightly broader type | Stronger outline with a fixed translucent body wash |

All six activities use their accepted category colors from `lib/design.dart`.
Elapsed values only change the lettering. Shapes and decorative washes never
fill, deplete, or encode a care target. Labels retain full accessible elapsed
descriptions. Missing history is a horizontal dash; time beyond24hours is
`>1d`. A220ms registration transition affects type only, with reduced-motion
support. The live entry point updates from timestamps, refreshes when a minute
or unit changes, and resets synthetic state when a mock action is tapped.

## Preview and reproduce

From the repository root:

```sh
flutter run -d macos -t tool/elapsed_study/main.dart --dart-define=ICON_DIRECTION=1
# Add --dart-define=MOCK_LIGHT=true for light appearance; directions are1–5.
flutter test --no-pub tool/elapsed_study/render_test.dart --dart-define=STUDY_ROUND=1
# STUDY_ROUND=1–10 reproduces exploration / refinement boards.
flutter test --no-pub tool/elapsed_study/final_test.dart tool/elapsed_icon_mockup_test.dart
flutter test --no-pub tool/elapsed_study/motion_test.dart
```

Review typography loads SF Sans, SF Compact, and SF Rounded from the local
macOS font installation without copying or distributing the font files.
Other platforms use their fallback fonts; these font choices remain a local
typographic study until a portable production font decision is made.

The final renders include all five directions together, Quick Log and activity
picker screens for every direction in light/dark mode, long values at96/68px,
and an original-footprint comparison. Picker artwork is64logical pixels inside
a76px badge, larger than the reference's approximately32px artwork/44px badge.
The original-size mock demonstrates that embedded elapsed lettering is tiny;
the64px proposal is the readability compromise. Accessibility reflows and
scrolling were checked on a320px phone at1.8× text scale.

The GIF is assembled solely from native Flutter frames, showing59m→1h→1h1m→now
and the actual type registration transition for all five directions.

This is isolated mock code with synthetic data, based on build54 / source
`19a638e` on `design/elapsed-activity-icons`. It is not wired into production
logging. No development build55, phone installation, or release was prepared.
