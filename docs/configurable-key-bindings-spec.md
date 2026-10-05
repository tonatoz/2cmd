## Problem Statement

2cmd assigns one input source to the left Command key and another to the right Command key. Users who need a third input source cannot assign it a dedicated key. Users whose keyboards lack a right Command key cannot replace that binding.

Users who need only two Command keys should not need extra setup. An update must preserve their selected input sources and existing shortcut behavior.

## Solution

Keep two default bindings: left Command and right Command. Add a configuration window that lets users replace their keys and configure up to five bindings.

The first two binding rows remain mandatory. Users can change their keys and input sources. They can add and delete up to three additional rows.

Each binding selects a specific macOS input source. A binding identifies a physical key by its key code, not by the character it produces.

Supported assignments include left and right Command, Option, and Control, plus ordinary character, function, navigation, and editing keys. Fn/Globe, Caps Lock, and multimedia keys are explicitly outside this feature.

The menu continues to offer quick input-source selection. The configuration window edits a draft with Apply and Cancel. Standard users can ignore the window.

## User Stories

1. As an existing 2cmd user, I want left and right Command to keep working after an update, so that I do not need to reconfigure the app.
2. As an existing 2cmd user, I want my selected input sources to survive an update, so that the app does not replace my preferred layouts.
3. As a new 2cmd user, I want two useful default bindings, so that I can start without opening configuration.
4. As a user who needs only two input sources, I want the ordinary menu to stay simple, so that additional functionality does not complicate daily use.
5. As a user with three input sources, I want a third dedicated key, so that one press selects the source I need.
6. As a multilingual user, I want up to five bindings, so that I can assign keys to the input sources I use.
7. As a user without a right Command key, I want to replace its assignment, so that both mandatory bindings remain usable.
8. As a user with a custom keyboard, I want to assign an ordinary key, so that I can use a dedicated language key.
9. As a user, I want each key to select a specific input source, so that I do not need to remember a cycling order.
10. As a user, I want bindings to identify physical keys, so that changing the active input source does not move the switch key.
11. As a user, I want to distinguish left and right modifiers, so that I can assign them independently.
12. As a user, I want to choose a specific input source rather than a language name, so that I can retain my preferred layout variant.
13. As a user, I want a configuration entry in the menu, so that I can find keyboard settings without another application.
14. As a user, I want one window listing keys beside input sources, so that I can inspect all assignments together.
15. As a user, I want the first two rows to remain present, so that configuration always contains the two mandatory bindings.
16. As a user, I want to add an optional binding, so that I can enable another dedicated switch key.
17. As a user, I want to delete an optional binding, so that an unused key returns to its ordinary role.
18. As a user, I want the app to prevent a sixth binding, so that the five-binding limit is clear.
19. As a user, I want to record a key by pressing it, so that I do not need to identify it in a long list.
20. As a user, I want a separate button to cancel key recording, so that Escape remains available for assignment.
21. As a user, I want recorded presses to stay inside key recording, so that they do not type into another application or switch input sources.
22. As a user, I want the app to reject a key already assigned to another row, so that one press has one unambiguous binding.
23. As a user, I want a conflict message to identify the existing assignment, so that I know which row to edit.
24. As a user, I want different keys to be able to select the same input source, so that I can use whichever key is convenient.
25. As a user, I want unsupported key categories to be stated explicitly, so that the app does not promise assignments it cannot support.
26. As a user assigning an ordinary key, I want an inline warning about its lost ordinary action, so that I understand the effect before applying.
27. As a user assigning Command, I want to avoid unnecessary warnings, so that the standard configuration remains uncomplicated.
28. As a user, I want a draft configuration, so that unfinished edits do not affect my working bindings.
29. As a user, I want Apply to activate and save the complete configuration, so that the displayed settings and active behavior agree.
30. As a user, I want Cancel to discard edits, so that I can inspect alternatives without changing my configuration.
31. As a user, I want closing the configuration window to discard unapplied edits, so that closing it does not silently activate changes.
32. As a user, I want quick input-source selection in the menu to save immediately, so that the existing workflow remains available.
33. As a user, I want the menu to show only configured bindings, so that empty optional slots do not add clutter.
34. As a user, I want a bound ordinary key to switch on key down without performing its ordinary action, so that a dedicated switch does not insert text or execute another command.
35. As a user, I want holding a bound ordinary key to avoid repeated switches, so that auto-repeat does not retrigger the binding.
36. As a user, I want a bound modifier to switch only after a solo press and release, so that shortcuts retain their normal behavior.
37. As a user, I want typing, mouse clicks, and scrolling during a modifier gesture to cancel switching, so that combined actions do not change my input source.
38. As a user, I want modifier-first shortcuts using a bound ordinary key to remain available, so that assigning A does not disable Command-A.
39. As a user, I want my configuration to survive an app restart, so that I do not need to recreate bindings.
40. As a user, I want restoring standard keys to preserve my first two input sources, so that restoring keys does not replace my languages.
41. As a user, I want restoring standard keys to remove optional bindings only when I apply the draft, so that I can cancel the reset.
42. As a user whose input source becomes unavailable, I want the app to retain and mark the binding, so that my selection is not silently replaced.
43. As a user whose input source becomes unavailable, I want the key to perform its ordinary action, so that an inactive binding does not consume useful input.
44. As a user who enables the same input source again, I want its retained binding to resume working, so that I do not need to recreate it.
45. As a user, I want disabling 2cmd to stop switching and key suppression, so that the existing Enabled control remains a complete off switch.

## Implementation Decisions

### Existing modules and cutover

- Extend the existing pure gesture-recognition module in TwoCmdCore to handle configurable bindings and ordinary-key event decisions. Reuse its existing testable seam rather than creating a second command-only detector.
- Update KeyTapMonitor to consume the generalized recognition decisions. Its event callback must support passing or suppressing ordinary-key events instead of always returning every event unchanged.
- Update Settings to load and save the ordered binding configuration and migrate previous selections.
- Update StatusItemController to render configured rows, preserve quick input-source selection, and open the configuration window.
- Add a focused AppKit configuration-window module. It owns the editable draft and key-recording presentation, not a second persistent settings store.
- Update AppDelegate to select an input source from a resolved binding instead of selecting by CommandSide.
- Continue using InputSourceManager for system input-source identifiers, names, availability, and selection.
- Migrate all callers away from the two-side configuration contract. Remove obsolete command-only interfaces and storage after the cutover.
- Preserve the existing main-thread execution model and Accessibility activation flow. This feature does not introduce background event processing or another permission flow.

### Binding model and persistence

- Store an ordered list of bindings in UserDefaults. Each binding contains a physical key code and a macOS input-source identifier.
- Use the first two list entries as the mandatory rows. The remaining entries are optional. Committed configurations contain two to five rows.
- Serialize the binding list through a Codable representation. Keep encoding, decoding, migration, and persistence inside Settings.
- Store identifiers rather than localized display names or language codes. Display names come from the available system input sources.
- Keep Enabled as an independent existing preference.
- If the new configuration is present, load it without reseeding removed optional rows or replacing user selections.
- Otherwise, migrate leftSourceID and rightSourceID into the two default Command bindings. Preserve existing identifiers exactly.
- For a new installation or a missing previous selection, reuse the current default input-source selection rules: English for left Command and Russian for right Command.
- Do not invent an available source if the existing default selection rules produce none. Show an unconfigured mandatory row until the user selects a source.
- Persist the migrated configuration and retire the previous source-selection keys. Subsequent launches must use the new configuration as the source of truth.

### Configuration window and menu

- Opening the configuration window creates a draft from the committed configuration. Ordinary switching continues to use committed settings outside key recording.
- Apply validates, activates, and saves the complete draft. Cancel and closing the window discard unapplied edits.
- A newly added row is draft-only until it has a supported key and an input source. An incomplete draft cannot be applied.
- The two mandatory rows have no delete action. Optional rows can be deleted. Disable adding a row when the draft already contains five rows.
- Recording starts only after the user explicitly requests it. Temporarily suspend binding activation while recording and suppress the press being recorded.
- Cancel recording with a separate control, so Escape can be recorded as a key. Restore normal committed behavior after recording ends or is cancelled.
- Reject unsupported assignments. A key already assigned to another row is also rejected, with the conflicting row identified. Do not swap keys or modify another row automatically.
- Allow multiple distinct keys to select the same input-source identifier.
- Show an inline warning for ordinary keys whose normal action will be suppressed. Do not require an extra confirmation dialog before Apply.
- The ordinary menu shows configured bindings in their saved order and one configuration entry. Do not show empty optional slots.
- Quick input-source changes made directly in the menu remain immediate and persistent. The draft and any concurrent menu change must not silently overwrite each other. The configuration interaction must keep one authoritative edit state.
- Preserve the current English UI convention. Russian labels discussed during design describe the intended controls, not a new localization requirement.

### Event behavior

- Ordinary assigned keys activate on the first non-repeat key-down event when no held modifier precedes them. Suppress their ordinary action for that press, including repeat events and its corresponding release.
- Auto-repeat never causes additional activation for the same press.
- When a modifier is already held before an ordinary assigned key is pressed, pass the key through and do not activate its binding.
- Do not promise restoration of a shortcut when the assigned ordinary key was pressed and suppressed before Command or another modifier.
- Command, Option, and Control bindings activate after a solo release. Other keyboard activity, another held modifier, a mouse action, or scrolling cancels the pending solo gesture.
- Preserve separate left and right modifier identities. A latched Caps Lock state must not count as a physically held modifier or break ordinary solo switching.
- Gesture state must not leak across disabling, recording transitions, or committed configuration changes. Keep each already-started press consistent through its release.
- When interception is disabled, neither switch input sources nor suppress ordinary input. Preserve the existing behavior when Accessibility access or event-tap activation is unavailable.

### Reset and unavailable input sources

- Restore Standard Keys changes the draft to left Command and right Command, keeps the input sources of the first two rows, and removes optional rows.
- Reset has no effect on active behavior or persistence until Apply. It can be cancelled like any other draft edit.
- If a stored source is unavailable, retain its identifier and binding position and display an unavailable-source warning.
- An unavailable binding does not switch input sources and does not suppress the ordinary action of a newly started key press.
- If the same source becomes available again, reactivate the retained binding without replacing its identifier or requiring reconfiguration.

## Testing Decisions

### Primary seam

- The primary automated seam is the existing pure gesture-recognition interface in TwoCmdCore, generalized to configurable bindings.
- Feed that interface committed effective bindings and physical keyboard or gesture events. Observe which input-source identifier it selects and whether the event should pass through or be suppressed.
- Test consumer-visible results across complete press sequences. Do not assert private state, enum layout, callback forwarding, source text, or incidental UI wording.
- Keep AppKit, a live event tap, Accessibility permissions, and actual system input-source switching outside these deterministic recognition tests.
- This seam is a design recommendation synthesized from the repository. No separate user approval of the test seam was obtained because the specification request explicitly prohibited another interview.

### Recognition coverage

- Preserve regression coverage for default left and right Command taps, shortcuts, overlapping modifiers, mouse cancellation, and Caps Lock being latched.
- Exercise configured left and right Option and Control independently.
- Exercise ordinary assigned keys with key down, auto-repeat, and key up. Assert one activation and suppression of the whole intercepted press.
- Exercise modifier-first shortcuts and assert no activation with normal event propagation.
- Exercise an ordinary key followed by a modifier and assert the documented non-restoration behavior without producing an unmatched release.
- Exercise disabled interception, unavailable sources, and recording transitions. Assert that switching and suppression follow their respective contracts.
- Exercise a configuration change during an existing press. Assert that gesture state does not activate a stale binding or mix suppression decisions within that press.

### Persistence seam

- Use the existing Settings interface with an isolated UserDefaults domain for persistence tests. This existing seam is necessary to verify restart and migration behavior independently of the system keyboard.
- Recreate Settings against the same isolated domain and assert that the ordered two-to-five binding configuration and Enabled state survive.
- Seed previous leftSourceID and rightSourceID selections, migrate, and assert that the same identifiers remain assigned to the default keys.
- Assert that a subsequent load does not resurrect deleted optional bindings or replace user-selected keys and sources.
- Assert that cancelling a draft leaves the committed configuration unchanged and applying a valid draft changes the complete configuration.
- Assert the two-row minimum, five-row maximum, unique key codes, and allowance for repeated source identifiers at the configuration validation interface.

### Prior art and runtime proof

- Follow the existing standalone Swift test-runner convention used for SoloTapDetector and ActivationCoordinator. The project intentionally supports Command Line Tools without requiring XCTest or full Xcode.
- Extend the existing make test workflow rather than introducing another test framework.
- Use isolated deterministic tests for uncertain event transitions, migration, and configuration boundaries. Do not add tests that only check wiring or copies of settings values.
- During implementation, launch the actual app and inspect the menu and configuration window. Verify recording, Apply, Cancel, optional-row deletion, and reset on the real surface.
- Exercise switching in a separate text application. Verify default Command shortcuts, assigned ordinary-key suppression, auto-repeat, modifier-first shortcuts, and disabled interception.
- Remove and re-enable a configured system input source. Observe both the warning and the return and restoration of the key's ordinary and assigned behaviors.
- Restart the app and observe persisted assignments. Validate migration using an isolated previous-format configuration before replacing real user preferences.
- Update user documentation to describe supported keys, ordinary-action suppression, configuration controls, and the unavailable-source behavior.

## Out of Scope

- Fn/Globe, Caps Lock, and multimedia-key assignments.
- More than five bindings or fewer than two mandatory rows.
- Assigning multi-key shortcuts, double taps, long presses, or layout-cycling gestures.
- Automatic keyboard-firmware remapping or integration with an external remapping tool. A custom keycap alone does not establish the key code it sends.
- Different configurations for individual applications or keyboards.
- Cloud synchronization, configuration import/export, and a separate settings database.
- Automatic replacement of an unavailable input source.
- Removal of ordinary-action suppression for active ordinary-key bindings.
- Reconstruction or replay of a key already suppressed before a later modifier press.
- A new localization system, renaming 2cmd, or changing unrelated login, update, permission, and release behavior.

## Further Notes

- The design derives from the user's choices in Q1–Q13. Q13 narrows the earlier request for arbitrary keys to the supported categories stated above.
- The request to produce this specification replaces the pending final interview confirmation. It does not authorize implementation.
- The first two rows are mandatory binding slots, not permanently reserved Command assignments. Their input sources are the ones retained when restoring standard keys.
- The highest end-to-end verification surface is the running macOS app together with an ordinary text application. Pure recognition tests and Settings tests support that verification but do not replace it.
- The intended issue tracker is GitHub for tonatoz/2cmd. Issues are enabled, but the current label vocabulary does not contain ready-for-agent.
- Publication is blocked until the tracker setup provides ready-for-agent. Run /setup-matt-pocock-skills before publishing this specification with that label. Do not silently substitute enhancement or create a different triage workflow.
- This document is a specification, not an implementation or a verification report. No feature behavior or proposed tests have been executed.
