# Zen performance and Hyper verification

KeyRow 0.1.1 keeps labels for browser tabs, the address bar, toolbar buttons, and menus. Fast mode removes duplicate labels on decorative text and container elements. It also combines nearby links to the same destination.

## YouTube in Zen

The final check opened a new YouTube tab and measured 20 shortcut activations after video links appeared and stopped moving. Every sample included browser menu, address-bar, tab, button, and link labels.

| Measurement | Result |
| --- | --- |
| Median activation | 21.5 ms |
| 95th percentile | 59.7 ms |
| Maximum | 221.1 ms |
| Labels | 144 |
| Prepared results reused | 19 of 20 |

The first activation detected a changed page-control set and performed a fresh scan. It took 221.1 ms. The other 19 activations took 11.0 to 59.7 ms. This meets the repeat-activation median below 50 ms and p95 below 100 ms check, but fresh scans can still exceed 100 ms.

The earlier YouTube scan produced about 470 labels and took 530 to 600 ms. The final fresh scan took 189 ms, and the background scans used during this run took 100 to 136 ms. Label counts depend on the page, browser layout, and open tabs.

Activation timing starts when KeyRow handles the shortcut and ends after it submits the overlay draw. It includes queued work, validation, visibility filtering, and rendering. It excludes test-driver startup and display refresh. These are measurements on the verification Mac, not a latency guarantee for every website or app. Scrolling mode still performs a separate scan to discover nested scroll areas.

KeyRow prepares controls in the background. Before reusing them, it re-queries the browser's semantic controls and checks stored control bounds, availability, and visibility. Input, scrolling, navigation, and window changes invalidate prepared results. Layout and element-destruction notifications can retain a candidate for validation, since those events also describe decorative page content.

The interface checks added and removed a button through the local fixture server without keyboard or mouse input. The new button received a usable label, and the removed button disappeared from the labels. Scrolling and navigation also produced the correct controls. Separate checks used labels to navigate through Zen's address bar and switch tabs.

## Caps Lock and Hyper

The earlier HID destination was F14 while the event handler expected F18. The corrected mapping uses the SDK's F18 constant. KeyRow updates each physical and virtual keyboard separately, polls for newly connected devices, and preserves unrelated mappings. A conflicting Caps Lock mapping produces an error.

A physical Caps Lock hold and release increased the diagnostic press count to one and left `hyper_held` false. The final build also read back the correct mapping on three connected keyboard services. In Zen, Chrome, and Safari, F19 sent during the Hyper trigger reached the fixture with Control, Option, Shift, and Command. F19 sent after release reached it with no modifiers. No stuck modifiers were observed.

Injected-device unit checks passed for separate mappings, legacy migration, hot-plug handling, restoration, unrelated edits, conflicts, and partial-failure rollback. A real keyboard disconnect and reconnect was not tested. Hyper remains enabled for normal use on the verification Mac.

## Environment and artifact

The final executable SHA-256 is `246f49403526cb3d7da7d8b98a02e05b673e0feec0bbe380c1bd2d31f37f9803`.

Verification ran on 15 October 2026 on Apple Silicon, macOS 27.0.1, one display, and Zen 1.23.1b. [The interface-check guide](../Tests/README.md) documents the repeatable checks. Raw observations and timing samples remain local and ignored by Git.

## Reconnect fix in 0.1.2

The 16 October patch opens fresh HID client connections on each mapping poll. The real external-keyboard reconnect and physical Caps Lock check passed without restarting KeyRow. The earlier timing measurements above belong to 0.1.1. See [the current verification report](verification.md) for patch results.
