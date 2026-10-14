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
xcrun swiftc Tests/occlusion-fixture.swift -o "$KEYROW_TEST_WORKSPACE/occlusion-fixture" -framework AppKit
python3 Tests/verify_visibility.py --cover "$KEYROW_TEST_WORKSPACE/occlusion-fixture"
```

The check clicks a visible practice button using its label, covers that button with a real floating window, confirms its label disappears, and confirms it returns when the window closes. The fixture closes even if an assertion fails. To reproduce the original failure, run while macOS has a transparent Notification Center host in its window list. The fixture does not dismiss that system window.

## Clean up

Quit the diagnostic app and stop the fixture server. Close test windows and restore KeyRow preferences. Rebuild with `./build.sh` and launch `build/KeyRow.app` for normal use, with diagnostics disabled.

The earlier Hyper check also inspected the HID Caps Lock mapping, recorded a modifier-only shortcut, activated it through the mapped F18 trigger, clicked a browser control, disabled Hyper, and confirmed removal of the temporary mapping. It was a supervised check and is not an automated scenario in these scripts.
