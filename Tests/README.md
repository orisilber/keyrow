# Repeat the interface checks

The native driver sends system keyboard and mouse events through KeyRow's global listener, then reads actual Accessibility results. It changes test controls and navigates public pages. Run one scenario at a time because the foreground app is shared. Use a test browser window and avoid interacting with the Mac during a run.

## Prepare a diagnostic build

Run these commands from the repository root. The default workspace is `.verification`, which Git ignores. Set `KEYROW_TEST_WORKSPACE` to use a different absolute path.

```sh
export KEYROW_TEST_WORKSPACE="$PWD/.verification"
mkdir -p "$KEYROW_TEST_WORKSPACE/work" "$KEYROW_TEST_WORKSPACE/outputs"
./build.sh "$KEYROW_TEST_WORKSPACE/outputs/KeyRow.app"
/usr/libexec/PlistBuddy -c "Add :KeyRowVerificationOutput string $KEYROW_TEST_WORKSPACE/work/navigation-state.json" "$KEYROW_TEST_WORKSPACE/outputs/KeyRow.app/Contents/Info.plist"
codesign --force --sign - --identifier local.keyrow.app --requirements '=designated => identifier "local.keyrow.app"' "$KEYROW_TEST_WORKSPACE/outputs/KeyRow.app"
open "$KEYROW_TEST_WORKSPACE/outputs/KeyRow.app"
```

Quit any other KeyRow instance first. Enable KeyRow's Accessibility permission in System Settings and confirm the global shortcut works. Keep the diagnostic app at the same path while testing. In another terminal, serve the fixture from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Tests
```

## Run scenarios

```sh
python3 Tests/verify.py --browser com.google.Chrome --name 'Google Chrome'
python3 Tests/verify.py --browser com.apple.Safari --name Safari
python3 Tests/verify.py --browser app.zen-browser.zen --name Zen
python3 Tests/verify_additional.py --scenario native
python3 Tests/verify_additional.py --scenario live --browser com.google.Chrome --name 'Google Chrome'
```

The native scenario uses Calculator, a generated Finder fixture, and System Settings. The live scenario checks Wikipedia, GitHub, and Apple. Repeat it with the browser identifiers above. These checks expect English control names.

Open KeyRow's practice window before running `python3 Tests/verify_additional.py --scenario practice`. Enable automatic Mission Control activation and leave the practice window open before running `--scenario mission`.

Set preferences through KeyRow's settings before running these mode checks:

| Command | Required preferences |
| --- | --- |
| `python3 Tests/verify_modes.py manual` | Automatic click off |
| `python3 Tests/verify_modes.py chain` | Automatic click and Chain clicks on |
| `python3 Tests/verify_modes.py ignored` | Chrome in Ignored Apps |
| `python3 Tests/verify_modes.py scrolling` | Chrome allowed, default scrolling preferences |
| `python3 Tests/verify_modes.py typing` | Chrome allowed, Automatic click on, Chain clicks off |

Restore preferences after each scenario. Reports append to the workspace's `outputs/verification.json` and include the executable SHA-256. Raw observations stay in `work/verification-driver`; the overlay PNG contains KeyRow's labels and outlines. These generated files can contain information about open apps and must stay local.

## Check click-through and covering windows

Open KeyRow's practice window, then run:

```sh
xcrun swiftc -target arm64-apple-macosx13.0 Tests/occlusion-fixture.swift -o "$KEYROW_TEST_WORKSPACE/occlusion-fixture" -framework AppKit
python3 Tests/verify_visibility.py --cover "$KEYROW_TEST_WORKSPACE/occlusion-fixture"
```

The check clicks a visible practice button using its label, covers that button with a real floating window, confirms its label disappears, and confirms it returns when the window closes. The fixture closes even if an assertion fails. To reproduce the original failure, run while macOS has a transparent Notification Center host in its window list. The fixture does not dismiss that system window.

## Clean up

Quit the diagnostic app and stop the fixture server. Close test windows and restore KeyRow preferences. Rebuild with `./build.sh` and launch `build/KeyRow.app` for normal use, with diagnostics disabled.

## Hyper, browser controls, and latency

Enable Hyper in KeyRow's General settings before running the delivery check. If Hyper itself opens navigation, temporarily turn on Pause navigation for `verify_hyper.py`, then restore it afterward. The modifier-delivery check focuses the fixture with native Tab presses so it works while navigation is paused. These tests use the same local fixture server and diagnostic app as the other scenarios.

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 Sources/Hyper.swift Tests/hyper-tests.swift -o "$KEYROW_TEST_WORKSPACE/hyper-tests" -framework AppKit -framework IOKit
"$KEYROW_TEST_WORKSPACE/hyper-tests"
python3 Tests/verify_hyper.py
python3 Tests/verify_browser_controls.py
python3 Tests/verify_cache.py
python3 Tests/verify_zen_performance.py --samples 20
```

The Hyper unit checks cover independent device mappings, legacy F14 migration, a newly connected device, restoration, unrelated mapping edits, conflicts, and rollback after a partial failure. The browser check reads each connected keyboard's mapping, sends F19 while the F18 Hyper trigger is held, and sends F19 again after release. The page must receive all four modifiers on the first key and none on the second.

A physical Caps Lock press requires a person. With diagnostics enabled, compare `hyper_presses` before and after holding and releasing Caps Lock. `hyper_enabled` must be true, the press count must increase, and `hyper_held` must return to false. A synthesized F18 event alone cannot prove the HID mapping.

The browser-controls check uses labels to navigate through Zen's address bar and switch to a generated Wikipedia tab. It clicks Reload and checks that the fixture counter resets, opens File and checks its menu-item labels, and asserts that toolbar and menu labels remain present. The cache check adds and removes a control asynchronously, scrolls the page, navigates, and checks the resulting controls through their actual labels.

The latency check opens YouTube in Zen and verifies that menu, address bar, tab, button, and link labels are included in every sample. It records activation-to-draw timing and checks median below 50 ms and p95 below 100 ms. The maximum remains in the report, including a potentially slower initial cold activation. `source_scan_ms` describes the underlying scan, which may have run in the background; `ready_ms` is the activation time. Timing ends after overlay drawing is submitted and excludes display refresh latency.

Mode checks also accept `--browser app.zen-browser.zen --name Zen`. Use those arguments to run manual confirmation, chaining, scrolling, typing, and ignored-app scenarios in Zen. Restore Automatic click on, Chain clicks off, and the ignored-app list after testing.

## Verify keyboard reconnect recovery

The native connection check reads and releases 1,000 fresh HID snapshots without changing mappings. Keep keyboards connected while it runs.

```sh
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 Sources/Hyper.swift Tests/hyper-device-tests.swift -o "$KEYROW_TEST_WORKSPACE/hyper-device-tests" -framework AppKit -framework IOKit
"$KEYROW_TEST_WORKSPACE/hyper-device-tests"
python3 Tests/verify_hyper_reconnect.py
```

For the reconnect check, leave the diagnostic KeyRow app running with Hyper enabled. After the check prints READY, turn the external keyboard off for three seconds and back on. Hold physical Caps Lock for two seconds, then release it. Do not send synthesized F18 events during this check.

The watcher requires an observed device departure or new service, all connected keyboards mapped to F18 again, a physical press-count increase, release of the held state, and no Hyper error. It times out after three minutes. Restarting KeyRow during the check does not establish reconnect recovery.
