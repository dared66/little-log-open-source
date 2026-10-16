# Nursing timer states

Finish is the save action. There is no nursing review state or second Save button. Sleep and pumping still review their additional fields.

| Current state | Action | Next state | Durable result |
| --- | --- | --- | --- |
| No session | Start left/right | Running on chosen side | One active session |
| Running | Switch side | Running on other side | Accumulated time retained; next segment starts now |
| Running | Pause nursing | Paused on current side | Both side totals frozen |
| Paused | Resume nursing | Running on same side | Paused interval excluded |
| Paused | Start other side | Running on other side | Paused interval excluded; action explicitly starts timing |
| Running or paused | Close/reopen | Same state | Closing does not finish or discard the session |
| Running or paused | Finish nursing | Saving | End time captured at the tap; all controls disabled |
| Saving | Successful write | Saved, sheet closes | One record; active session removed atomically |
| Saving | Failed write | Previous active state with error | Active session retained; Finish can retry |
| Saving | Sheet dismissed | Save continues | Successful write still removes the active session once |
| Saved | Reopen Nursing | No session | New start choices; the finished timer cannot reappear |

The timer header names its actual state and side. Paused sessions do not show a running label. The running form accepts optional notes before Finish.

`test/nursing_controls_test.dart` checks these transitions, exact side totals, both sides, normal and enlarged text, persisted storage, controller reload, duplicate-tap prevention and save errors. `test/flow_journey_test.dart` exercises the real navigation. Both native harnesses include the nursing controls tests. Controller reload is not a physical OS force-kill test.

The prior navigation tests explicitly expected Finish to open review and leave the active session present until Save. They verified that implementation rather than the intended meaning of Finish. That expectation has been removed.
