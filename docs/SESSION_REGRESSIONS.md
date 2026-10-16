# Regression coverage for the build 46 UI changes

The ordinary suite runs these assertions without screenshot flags. Summary geometry uses real SDK fonts, including the 320px / 180% text scenario. Screenshots alone are review evidence, not a pass condition.

| Requirement | Automated protection |
| --- | --- |
| Drive owner label beside Refresh, outside the baby header | `invitation_harness_test.dart`: footer ordering and distance, normal and large text, Today and History |
| Tight activity titles across the app | `entry_labels_test.dart`: all ten add/edit headings; `care_entry_test.dart`: actual Bottle/Nursing navigation |
| New bottles default to breast milk | `care_entry_test.dart`: selected milk default, saved breast milk volume and zero formula |
| Entry units follow Settings; an entry override does not change the default | `care_entry_test.dart`: settings persistence and reopening Bottle |
| oz/ml pill uses muted palette, stays compact, and centers beside Amount | `volume_test.dart`: selected fill, no checkmarks, relative position, height <=40px, vertical centers, small-screen validation |
| Switching oz/ml preserves the precise amount | `volume_test.dart`: five round trips, CSV/storage reopening and mixed-unit totals |
| Every option chip uses the shared style without checkmarks | `selection_chip_test.dart` and `support/selection_chip_expectations.dart`: selection/disabled semantics, callbacks, shared-component ancestry, fill, typography and borders; invoked on baby backgrounds and multi-option diaper choices |
| Units and non-diaper boolean choices share the compact Bottle pill; Settings scope note is above controls | `toggle_pill_test.dart`: selection, disabled semantics, muted fill, compact size, normal/180% text; `care_entry_test.dart`: scope note order, unit persistence, independent Wet/Dirty chips, same-row compact geometry, original rash/blowout switches and saves |
| Diaper multiselect retains independent choices | `format_upgrade_widget_test.dart`: selecting two colors and deselecting one without clearing the other |
| Saved diaper flags show check/X without redundant Yes/No text | `care_entry_test.dart`: actual icons and visible labels; screen-reader labels preserve Yes/No |
| Nursing Finish saves directly; Pause/Resume and reopening show the actual state | `nursing_controls_test.dart`: both starts, running/paused finishes, persisted counts, restart, explicit Start-other-side, save lock, dismissal, failed-save retry, paused-time exclusion; native release/control harnesses include these tests |
| New nursing requires recorded side time | `care_entry_test.dart`: rejected empty save and saved left-only time; `long_timer_edit_test.dart`: controller rejection of missing sides, preservation of legacy note-only edits |
| Today and History use identical nursing totals and side details | `today_page_test.dart`: navigate both screens, short and hour-long totals, normal and large text |
| Nursing is as compact as the other cells | `today_page_test.dart`: heights across both rows, aligned values/labels, no L/R-label overlap, readable side font; `history_summary_layout_test.dart`: peer alignment and long totals |
| “No side” never appears in nursing summaries | `today_page_test.dart` and `history_summary_layout_test.dart`: legacy minutes still count in the total, absent visible label |
| A beta cannot omit fixes already merged into main | `scripts/test_release_preflight.py`: real temporary Git history accepts main/descendants and rejects a stale branch with the missing fix named |
| Current devicectl schema detects the paired phone | `scripts/test_ios_phone_dev.py`: correct, wrong, unpaired, shut down, missing and incomplete device listings |

## Full harness

```sh
flutter test --reporter expanded
python3 -m unittest discover -s scripts -p 'test_*.py'
flutter analyze
flutter test integration_test/full_harness_test.dart -d IPHONE_SIMULATOR_ID --dart-define-from-file=config/google.local.json --reporter expanded
```

`integration_test/control_regression_test.dart` is the focused native harness for unit preferences, Bottle conversions and boolean entry controls.

The full native harness combines the synthetic navigation, storage/recovery, onboarding, editing, sharing and build-46 regression cases with a 10,000-record native-storage probe. `release_regression_test.dart` also includes the recent UI cases. CI runs every unit/widget and Python test on each main push and PR.

Native and widget harness data are synthetic. Live Google-account probes are separately opt-in. Passing these tests does not constitute visual verification of the user's physical phone, an OS force-kill test, or a performance benchmark. The app's build number remains `1.0.0+46`; changing only the test harness does not require a phone rebuild.
