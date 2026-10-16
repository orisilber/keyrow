# KeyRow verification

## 0.1.2 keyboard reconnect fix, 16 October 2026

The installed 0.1.1 app showed the Caps Lock mapping warning, and `verify_hyper.py` failed because two of three current keyboard services had no Caps Lock mapping. Their registry IDs had changed. Restarting the unchanged app restored the mappings.

Version 0.1.2 opens fresh HID connections on every mapping poll instead of keeping one client for the app's lifetime. Each snapshot keeps its client alive until all of its services are released. Existing mapping ownership, conflict checks, and restoration behavior are unchanged.

With the updated app left running, a real external keyboard power cycle produced a device departure and a new service. KeyRow restored F18 mappings on all three services without restarting. The physical Caps Lock hold increased the press count, release cleared the held state, and the warning cleared in both diagnostics and Settings.

The Hyper delivery check passed in Zen, Chrome, and Safari. Each page received all four modifiers during the trigger and none after release. Navigation was temporarily paused for this check because the user's Hyper key is also the navigation shortcut. It was restored afterward, with the user's shortcut preserved.

The configured Caps navigation shortcut opened labels and clicked the browser counter. Zen's address bar, tab switching, Reload, and File-menu label checks also passed. A normal launch with diagnostics disabled accepted the same shortcut and clicked the counter again. The diagnostic file stopped updating, and strict signature verification passed.

The existing Hyper unit checks passed. A new native check read and released 1,000 fresh keyboard snapshots without changing mappings or crashing. The build's label and shortcut self-tests, Python parsing, plist validation, and build-script syntax checks passed.

The patch executable SHA-256 is `a82fc60ebf9a3c9986ae8765edb0a1ec914c92296794ff833479f326efedc558`. The device test covered an actual external-keyboard reconnect. Sleep and wake were not separately exercised during this patch verification. The browser performance and full navigation sweep below belong to 0.1.1.

## 0.1.1 full navigation sweep, 15 October 2026

KeyRow 0.1.1 passed 30 distinct interface scenarios on 15 October 2026. The checks drove the actual global keyboard listener in Zen, Chrome, Safari, and native macOS apps. Search is omitted.

The tested executable SHA-256 is `246f49403526cb3d7da7d8b98a02e05b673e0feec0bbe380c1bd2d31f37f9803`. Verification used Apple Silicon, macOS 27.0.1 build 26A434, one display, and Colemak DH ANSI. Browser versions were Zen 1.23.1b, Chrome 155.0.8059.41, and Safari 27.0.1.

### Browser navigation

| Check | Zen | Chrome | Safari |
| --- | --- | --- | --- |
| Button and double-click counters | PASS | PASS | PASS |
| Shadow DOM and iframe controls | PASS | PASS | PASS |
| Disabled and offscreen control filtering | PASS | PASS | PASS |
| Page, nested vertical, and horizontal scrolling | PASS | PASS | PASS |
| Fixture console errors | 0 | 0 | 0 |
| Hyper delivery and release | PASS | PASS | PASS |
| Wikipedia to English main page | PASS | PASS | PASS |
| GitHub to README file | PASS | PASS | PASS |
| Apple to Support | PASS | PASS | PASS |

Public-site checks asserted the resulting document URL. They waited for the actual document and a stable control position before selecting a label. Fixture checks asserted actual counters and scroll positions.

Zen's browser-control check used labels to focus the address bar, navigate to Wikipedia, and switch tabs. A labelled Reload button reset the fixture counter. A labelled File menu opened and exposed labelled menu items. Browser toolbar and menu controls remained included in fast mode.

The prepared-label check added and removed a button through the local server without a keyboard or mouse event. It clicked the added button, confirmed the removed control lost its label, and checked controls again after scrolling and navigation.

### Native apps and interaction modes

| App or mode | Verified result |
| --- | --- |
| Calculator | A label clicked 7 and the display became 7. |
| Finder | A label selected the generated fixture file in list view. |
| System Settings | A label opened Appearance without changing an appearance setting. |
| Native practice window | Labels clicked a button, toggled a checkbox, focused and edited text, and scrolled a native area. |
| Mission Control | Labels appeared automatically, selected KeyRow Practice, closed Mission Control, and brought KeyRow forward. |
| Window visibility | A visible practice button remained usable beneath the transparent system host. A real covering window removed its label; closing that window restored it. |
| Zen manual confirmation | Selection, Tab and Shift-Tab, Control-N and Control-P, Backspace, right-click, and Command-click into a new tab passed. |
| Zen chain clicks | A click refreshed the labels, and selecting a text input ended the chain. |
| Zen immediate typing | Space and Return reached the newly focused input. |
| Zen scrolling commands | Half-page up and down, top and bottom, and Shift dash changed the intended nested area's scroll position. |
| Zen ignored-app setting | Both navigation shortcuts passed through while Zen was ignored. |

Automatic click was restored on, Chain clicks off, and the ignored-app list empty. Hyper remains enabled. Launch on login remained enabled.

### Hyper and timing

The physical Caps Lock hold and release reached the corrected F18 handler. The press count increased, and the held state returned to false. Automated checks on the final build confirmed the mapping on three connected keyboard services. All four modifiers reached the fixture during Hyper, and no modifiers remained after release in each browser.

The final 20-activation YouTube run in Zen had 144 labels, a 21.5 ms median, a 59.7 ms 95th percentile, and a 221.1 ms maximum. The first activation needed a fresh scan after the page controls changed. The other 19 took less than 60 ms. Browser controls were included in every sample. [Performance and Hyper details](performance.md) describe the timing boundary and remaining cold-scan limit.

### Production app and source checks

A clean launch with diagnostics disabled accepted the global shortcut. Typing the visible practice-button label incremented its actual counter. The diagnostic file stopped updating. The local app signature passed strict verification.

The build passed label uniqueness and prefix checks through 4,000 targets and shortcut-modifier matching. Hyper unit checks passed for independent device mappings, legacy migration, hot-plug handling, restoration, unrelated edits, conflicts, and partial-failure rollback. Python test files parsed, the app plist passed validation, and the build script passed its syntax check.

### Scope

The initial release's synthesized Hyper test missed a mismatch between the F14 HID destination and the F18 event handler. Version 0.1.1 corrects that mapping and adds the physical check described above. The transparent Notification Center visibility regression also remains covered.

These checks cover the listed cases on one Mac. They do not establish compatibility with every website, custom control, macOS version, or display setup. A real keyboard disconnect and reconnect, login at startup, Intel, and multiple displays were not exercised. Fresh scans and scrolling scans can exceed 100 ms.

[Repeat the interface checks](../Tests/README.md). Logs, raw Accessibility observations, screenshots, runtime JSON, build products, and credentials remain local and excluded from Git.
