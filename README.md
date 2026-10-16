# KeyRow

KeyRow is a local macOS keyboard-navigation app based on Homerow's clicking and scrolling behavior. It has no search mode.

Build and open `KeyRow.app` using the instructions below. Its keyboard icon appears in the menu bar. Enable KeyRow under System Settings → Privacy & Security → Accessibility.

Press **⌘⇧Space**, then type the label on a control to click it. Press **⌘⇧J** to enter scrolling mode, then hold H, J, K, or L to scroll left, down, up, or right. Press Esc to exit either mode.

Use the menu-bar icon to open Settings or the practice window. You can move the app to Applications if you prefer.

## Clicking controls

| Key | Action |
| --- | --- |
| Label letters | Filter controls, then click when the label is complete |
| Tab / Shift-Tab | Focus the next / previous matching control |
| Down / Up, Control-N / Control-P | Focus the next / previous control |
| Backspace | Remove the last label letter |
| Return or Space | Click the focused control |
| Shift-Return | Right-click |
| Command-Return | Command-click, including a browser link in a new tab |
| Return immediately after a click | Complete a double-click |
| ? | Show the focused control's name and role |
| Esc | Exit |

Turn off Automatic click to select a label first and confirm with Return. Chain clicks shows fresh labels after a click. Selecting a text input ends the chain so you can type.

## Scrolling controls

| Key | Action |
| --- | --- |
| Hold H / J / K / L | Scroll left / down / up / right |
| Shift with a scroll key | Use dash speed |
| Number shown on an area | Select that area |
| Tab / Shift-Tab | Select the next / previous area |
| D / U | Scroll half an area down / up |
| gg / Shift-G | Go to the top / bottom |
| Esc | Exit |

Settings lets you change shortcuts, label characters, label size, theme, scroll keys and speeds, arrow-key behavior, sounds, and ignored apps. Shortcuts can also use modifiers alone. Mission Control can activate clicking automatically.

Hyper maps Caps Lock to Control-Option-Shift-Command while KeyRow runs. It updates physical and virtual keyboards separately, including keyboards connected later, and preserves unrelated mappings. Conflicting Caps Lock mappings show an error. It opens fresh keyboard connections on each poll so reconnecting devices do not leave it using stale handles. Quit KeyRow normally to remove the mappings it installs. To use Caps Lock alone for navigation, enable Hyper and record Caps Lock as the clicking or scrolling shortcut.

Fast labels include browser tabs, the address bar, toolbar buttons, and menus. Decorative text and container elements do not receive duplicate labels. Nearby links to the same destination share one label. KeyRow prepares controls in the background and invalidates them after input, layout changes, scrolling, and navigation.

[Performance and Hyper verification](docs/performance.md) records the measured Zen results and the physical Caps Lock check.

## Build

Requires an Apple Silicon Mac running macOS 13 or later and Xcode command-line tools. There are no third-party dependencies.

```sh
./build.sh
open build/KeyRow.app
```

The build creates an ad-hoc signed app and runs label uniqueness and prefix checks. To choose another destination, pass an absolute app path to `build.sh`.

## Verification

[Verification results](docs/verification.md) describe the browser and native-app checks completed before publication. [Repeat the interface checks](Tests/README.md) explains how to run the native test driver and browser fixtures.

Logs, raw Accessibility observations, test evidence, build products, and local credentials are excluded by `.gitignore`. Diagnostics are disabled in a normal build. The optional verification mode writes observations only to the configured local workspace.

## Compatibility

The app reads controls through macOS Accessibility. Apps and custom controls must expose usable accessibility information to receive labels. Testing covers the cases listed in the report. Runtime verification used macOS 27.0.1 and one display. Recovery after an external keyboard disconnect and reconnect was verified. Login-at-startup, other macOS releases, Intel builds, multiple displays, and additional keyboard models were not exercised.

KeyRow is an independent recreation of Homerow's navigation behavior. Branding, theme-preview artwork, and some settings details differ. Input source follows the current macOS layout rather than a separate override. Homerow's licensing and update service are not included. Search is intentionally absent.
