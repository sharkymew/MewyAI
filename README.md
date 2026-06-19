# AI Client

AI Client is the Xcode project for the MewyAI app.

## Project facts

- Xcode project: `AI Client.xcodeproj`
- Main scheme: `AI Client`
- App target / module: `MewyAI`
- Test target: `MewyAITests`
- Swift version: `5.0`
- Default actor isolation: `MainActor`
- Minimum iOS deployment target: `17.0`

The project uses Xcode's file-system-synchronized groups, so new Swift files under
`AI Client/` and `MewyAITests/` are picked up without manually editing
`project.pbxproj`.

## Local verification

Build the app for a generic iOS device:

```sh
xcodebuild -project 'AI Client.xcodeproj' -scheme 'AI Client' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Build the app and test bundle without launching a simulator:

```sh
xcodebuild build-for-testing -project 'AI Client.xcodeproj' -scheme 'AI Client' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Running tests requires an explicit device or simulator destination. Codex
verification should default to the generic iOS commands above unless a simulator
run is explicitly requested.

## Architecture notes

- Keep view state and business flow out of `ContentView.swift` when practical.
- Put chat-session generation state in `ChatSessionViewModel`.
- Keep auxiliary LLM work in lightweight services such as `ChatAuxiliaryAIService`
  when it does not need the main chat service state.
- `AIService` owns request/streaming behavior. Prefer pure builders and parser
  helpers for provider-specific request and response details so they can be tested
  without UI state.

## Git hygiene

Build products, DerivedData, local editor files, and `.DS_Store` should stay out of
source control. Do not commit secrets, API keys, cookies, or local credentials.
