# KeyRow verification

The initial release passed 25 scenarios on the verification Mac. Those checks did not cover a transparent system window that later caused the visibility failure described below. The app was tested through its global keyboard listener in real browsers and native apps. Search is omitted.

Verified on 15 October 2026, local time, on Apple Silicon with macOS 27.0.1, build 26A434. Browser versions were Chrome 155.0.8059.41, Safari 27.0.1, and Zen 1.23.1b. The active keyboard layout was Colemak DH ANSI.

## Browsers

The fixture checks actual button click counts, double-click and context-click events, shadow DOM, iframe controls, hidden/disabled controls, page scrolling, independent nested vertical scrolling, and horizontal scrolling. The fixture's page-error, unhandled-rejection, and console-error counter remained zero. Chrome also passed checkbox and immediate text-input checks.

| Browser | Result | Scroll-mode scan | Scroll areas | Fixture console errors |
| --- | --- | --- | --- | --- |
| Google Chrome | PASS | 200 ms | 5 | 0 |
| Safari | PASS | 235 ms | 4 | 0 |
| Zen | PASS | 197 ms | 6 | 0 |

Public-site link navigation passed in every cell below. Each check asserts the resulting document URL, rather than a link URL or browser tab title. The test waits for the loaded document and a stable control position.

| Browser | Wikipedia → English main page | GitHub → README file | Apple → Support |
| --- | --- | --- | --- |
| Chrome | PASS | PASS | PASS |
| Safari | PASS | PASS | PASS |
| Zen | PASS | PASS | PASS |

## Native apps

| App | Verified result |
| --- | --- |
| Calculator | A keyboard label clicked 7 and the actual display became 7. |
| Finder | A keyboard label selected the fixture file in list view. |
| System Settings | A label opened Appearance. No appearance setting changed. |
| KeyRow practice | Labels clicked a button, toggled a checkbox, focused and edited text, and scrolled a native area. |
| Mission Control | Labels appeared automatically, selected KeyRow Practice, closed Mission Control, and brought KeyRow to the foreground. |

Mission Control support accounts for the [macOS 27 accessibility-process change](https://github.com/Hammerspoon/hammerspoon/issues/3897). Window selection also moves the pointer to the chosen thumbnail so the hovered window cannot override the selection.

## Interaction checks

Manual confirmation, Tab/Shift-Tab, Control-N/P, Backspace, right-click, Command-click into a new tab, double-click, chain refresh, ending a chain at an input, ignored apps, the literal Command-Shift-J shortcut, half-page scrolling, top/bottom commands, and Shift dash passed.

Immediate spaces and Return pass through to a focused text input. The double-click continuation uses Return outside text inputs.

The Hyper check installed the Caps Lock → F18 HID mapping, recorded the Control-Option-Shift-Command modifier-only shortcut, activated it through the mapped F18 trigger, and clicked a browser control. Hyper was disabled afterward. A final HID-property read confirmed that the temporary Caps Lock entry was removed. This checks the mapping and its event handler; it does not simulate a physical hardware Caps Lock switch.

After diagnostics were removed, a clean launch accepted the real global shortcut and clicked the browser counter through its label. The diagnostic state file stopped updating. The local app signature also passed verification. Sampled label counts through 4,000 passed the uniqueness and prefix tests during the build.

## Scope

These results cover the navigation implementation included in this repository. Publication changed the build output and test-workspace defaults to repository-local ignored directories. A fresh build and its self-tests passed after those packaging changes.

Raw Accessibility observations, logs, runtime JSON, screenshots, and app binaries are intentionally excluded from the repository. The UI checks used one Apple Silicon Mac, one display, and the versions listed above. They do not establish compatibility with every website or app. Physical Caps Lock hardware, login-at-startup, other macOS versions, Intel, multiple displays, and newly connected keyboards were not exercised.

## Visibility fix, 15 October 2026

The failure reproduced on the installed app with Accessibility permission and the global listener both active. Accessibility returned the native controls, but a full-screen, click-through Notification Center host was first in the window list. The geometry-only occlusion check removed the visible buttons.

`Tests/verify_visibility.py` failed before the fix because the visible Count click button had no label. With the fix, ambiguous window bounds fall back to Accessibility hit testing. The same check then clicked the button successfully while the system host remained present. A real floating window covered the button, removed its label, and the label returned after the covering window closed.

The fixed build also passed browser fixtures in Chrome, Safari, and Zen, including actual clicks, double-clicks, iframe and shadow controls, nested scrolling, horizontal scrolling, and zero fixture console errors. Public link navigation passed on Wikipedia, GitHub, and Apple in all three browsers. Native checks passed in Calculator, Finder, System Settings, and the KeyRow practice window.

A clean restart of the same signed app with diagnostics disabled accepted the global shortcut and clicked the practice counter. The diagnostic state file stopped updating. The build self-tests and signature verification passed. Raw logs and observations remain local and ignored.
