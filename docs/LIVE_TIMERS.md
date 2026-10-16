# Live timer lifecycle

Nursing and pumping follow Running → Paused → Finished. Active controls show
Pause; paused controls show Resume and Finish. Sleep has no paused state and
finishes directly. The same rules apply in the app, iOS Live Activities and
Android timer notifications. Voice finish requests also require paused nursing
or pumping sessions.

Paused sessions remain visible, freeze their displayed durations and survive
app restart. Resuming excludes the break. Nursing keeps the totals for each
side. Pumping stores accumulated active milliseconds independently of its wall
clock start/end; completed records retain activeSeconds internally.
Finish records the last pause as the timed session’s end.

Build 54 is the last externally distributed build and the public compatibility
baseline. Builds 55 and later are internal. Shared logs remain compatible with
build 54. Pumping active seconds travel
in the existing v6 source envelope's `littleLogTimer` extension, leaving pumping
CSV details empty. Existing Nara provenance, actual start/end, amount, note and
record identity are preserved. Older clients can read, edit and delete these
records and retain the extension on export. They display their existing duration
presentation; current clients restore the precise active duration. Timer metadata
is bound to the original start/end: if an older client changes those times,
current clients honor the edit instead of applying stale active seconds.

Build-56 rows that put activeSeconds in CSV details still load. Sync conditionally
rewrites that representation into the compatible envelope, including tombstones,
even with no pending local entries. Repair uses the existing ETag conflict retries
and verification; it never clears history or modifies the caregiver's entries.
The committed compatibility tests use the exact frozen reader from released
build 54, including old-client edit/delete round trips. Those source blobs are
also identical in builds 52, 53 and internal build 55. Additional internal-build
checks do not replace validation against the released build-54 reader.

Finishing pumping opens amount entry. Dismissing that form retains the finished
session with Add amount; it cannot resume. Saving or confirming Discard removes
it from live surfaces. Nursing/sleep disappear once finished. Active and paused
sessions can be discarded from their controls, always with confirmation.
Saved activity edit pages have a separate confirmed Delete entry action. Discarding
a resumed nursing session preserves its previously saved portion.

On iOS 17+, Lock Screen and expanded Dynamic Island controls offer Pause or
Resume/Finish. Compact/minimal views keep their category icon and a frozen
counter while paused. Earlier iOS versions display the state but require the app
for actions. On Android, ongoing notifications offer the same controls;
Android 16+ requests native Live Update/status-chip promotion. System settings
and manufacturer support determine promotion. Notification permission is
requested on Android 13+ when the first live session is shown. Dismissing a notification hides
its presentation without discarding the session.

Native actions are journaled before changing the display. A cold/suspended
Flutter engine processes them when available. Each action carries the session
ID, baby ID and expected revision; replayed or stale controls cannot finish a
resumed or replacement session. Pending actions are overlaid on new snapshots
so an older app update cannot briefly unpause a native display. iOS also retains
accepted state while ActivityKit publishes an update asynchronously. Paused sessions
for other babies stay visible when the selected baby changes.

Native tests run only on disposable QA devices, never the shared review devices.
