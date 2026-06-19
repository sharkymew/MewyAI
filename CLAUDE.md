# CLAUDE.md

This repository contains the MewyAI iOS app.

## Essentials

- Project: `AI Client.xcodeproj`
- Scheme: `AI Client`
- App target and module: `MewyAI`
- Test target: `MewyAITests`
- Default actor isolation is `MainActor`.
- Swift version is currently `5.0`.

## Working rules

- Read the current implementation before editing.
- Prefer minimal, targeted changes.
- Do not move unrelated code while fixing a bug.
- Do not add dependencies without explicit confirmation.
- Keep secrets and local credentials out of logs, diffs, and tests.
- New Swift files under `AI Client/` or `MewyAITests/` are included through
  Xcode file-system-synchronized groups.

## Verification commands

```sh
xcodebuild -project 'AI Client.xcodeproj' -scheme 'AI Client' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

```sh
xcodebuild build-for-testing -project 'AI Client.xcodeproj' -scheme 'AI Client' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Do not launch simulators during default Codex validation. Run tests only when an
explicit device or simulator destination is requested.

## Architecture guidance

- Avoid adding more responsibilities to `ContentView.swift`.
- Chat generation state belongs in `ChatSessionViewModel`.
- Provider request-body construction and stream parsing should stay in small,
  testable helpers where possible.
- Keep UI side effects in views and pure request/parser behavior outside views.
