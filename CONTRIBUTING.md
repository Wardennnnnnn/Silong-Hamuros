# Group workflow

## Start a change

Pull the latest `main`, then create a branch for your task:

```bash
git switch main
git pull --ff-only
git switch -c ui/dashboard-spacing
```

Use a short branch name that describes the work, such as `ui/settings-layout` or `fix/chart-labels`. Coordinate before editing the same screen: most layouts currently share `lib/main.dart`, so overlapping edits can conflict.

## Before opening a pull request

- Run `dart format` on the Dart files you changed, then `flutter analyze` and `flutter test`.
- Run the app on an Android phone or emulator. Check navigation, scrolling, small-screen layouts, and text readability.
- Keep unavailable readings visibly unavailable. UI changes should preserve offline/stale-data guards and command acknowledgment behavior.
- Include screenshots for visual changes and a short description of what changed and how you checked it.
- Keep unrelated edits out of the branch. Commit `pubspec.lock` when dependencies change.

```bash
git add lib/main.dart
git commit -m "Adjust dashboard spacing"
git push -u origin ui/dashboard-spacing
```

Open a pull request into `main` and ask a groupmate to review it before merging. For UI-only work, a disconnected app is sufficient to review layouts; weather still needs internet. Device controls and populated sensor charts need real integration data.

## Local files

Do not commit `build/`, `.dart_tool/`, `android/local.properties`, `.env` files, access tokens, keystores, or local backend storage. Each person configures their own SDK, emulator, and optional server connection.
