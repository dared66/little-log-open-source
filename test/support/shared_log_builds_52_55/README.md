# Frozen shared-log readers

Exact, unmodified reader source from `testflight-build54`, the last externally distributed build and public compatibility baseline. All six blobs are identical in builds 52, 53, 54 and internal build 55. Builds 55 and later are internal; their tags do not establish a public release. Keep these sources frozen: compatibility tests must exercise the released build-54 reader, not a reimplementation.

| Source | Git blob |
| --- | --- |
| `lib/models.dart` | `596da33a46b4fdf03ed4b53b96b4cb4d56d08174` |
| `lib/activity_details.dart` | `4af8f93d55ea92b55370de0f6273728fbf174b95` |
| `lib/record_validation.dart` | `5fe34744f9634b79030e5a8cdc5cd543d1ac033f` |
| `lib/diaper_details.dart` | `0404eb201a4e3c3ee3c1559535d6544732748b70` |
| `lib/volume.dart` | `5f947ce9e24b3c9f982bd501f407f79662e51b37` |
| `lib/services/family_csv.dart` | `12e9ce48bddcd8e2fa454dd7be28db562cc10f33` |

The synthetic history in `../build54_history_fixture.dart` was encoded by this exact build-54 writer. It includes all ten activities, profile metadata, existing deletions and CSV schemas 1–6, plus old pumping and paused-nursing JSON. The CI gate `python3 scripts/check_build54_compatibility.py` pins these six source blobs and that history fixture, then runs both compatibility suites. Altering or removing the frozen files fails the gate. The tests also run inside the complete Android/iOS harness.
