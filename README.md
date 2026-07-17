# MewyAI

MewyAI is an independently developed BYOK (bring your own key) AI client for
iPhone and iPad. It was built to explore multi-provider model integration,
streaming responses, local conversation storage, tool calling, and the
architecture of a native iOS AI client.

This repository contains the cleaned public release of a project originally developed privately.

## Project status

MewyAI is in maintenance mode. A version of the app completed App Store review
and release during private development; this repository does not claim current
App Store availability and does not change any production App Store version.
The public release is intended for technical review, portfolio use, and limited
maintenance rather than active commercial development.

Current project facts:

- App version: 1.1.0 (build 7)
- Minimum deployment target: iOS 17.0
- Language: Swift 6
- UI: SwiftUI with selected UIKit integrations
- Project: `AI Client.xcodeproj`
- Scheme: `AI Client`
- App target/module: `MewyAI`
- Test target: `MewyAITests`

## Features

- Streaming chat with multiple conversations and provider configurations
- OpenAI Chat Completions, OpenAI Responses, Anthropic Messages, and Google
  Vertex AI Express protocol adapters
- OpenAI-compatible provider support, including built-in presets for services
  such as DeepSeek and OpenRouter
- Multiple API keys per provider with local failover state
- Markdown, syntax highlighting, tables, and LaTeX rendering
- Image and document attachments, camera capture, and speech input
- Message editing, conversation branches, search, export, and usage estimates
- Local SQLite conversation persistence and local knowledge-base indexing
- Model tool calling, Skills/MCP integration, App Intents, and background
  completion notifications

Provider and model behavior varies by API implementation. A listed preset does
not imply endorsement, affiliation, or guaranteed compatibility with every
model exposed by that provider.

## Architecture

The app is organized around a few explicit boundaries:

- `App` and `Chat` contain SwiftUI presentation and chat-session state.
- `AIService` builds provider requests and parses streaming responses.
- `Configuration` owns provider/model metadata and credential references.
- `Persistence` stores conversations locally in SQLite.
- `Agent` and `MCP` coordinate tool capabilities.
- `KnowledgeBase` handles local document processing and retrieval.
- `AppIntents` and shared services contain Apple-platform integrations.

See [Docs/architecture.md](Docs/architecture.md) for the data flow and security
boundaries.

## Model protocols

| Protocol | Typical use |
| --- | --- |
| OpenAI Chat Completions | OpenAI and OpenAI-compatible chat APIs |
| OpenAI Responses | OpenAI Responses-compatible APIs |
| Anthropic Messages | Claude-compatible message APIs |
| Vertex AI Express | Gemini model access through the Vertex Express API |

Custom base URLs and headers are supported. Treat a custom endpoint as a
separate trust boundary: prompts, attachments, and recalled context are sent to
the endpoint selected for that request.

## Build locally

Requirements:

- macOS with an Xcode version that supports Swift 6 and the iOS 17 SDK
- Internet access for the first Swift Package Manager dependency resolution
- Your own Apple development team only when installing on a physical device

Clone the repository, then open `AI Client.xcodeproj`. Xcode restores the pinned
Swift packages from `Package.resolved`.

To build without code signing:

```sh
xcodebuild -project 'AI Client.xcodeproj' \
  -scheme 'AI Client' \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

To build the app and test bundle without launching a simulator:

```sh
xcodebuild build-for-testing \
  -project 'AI Client.xcodeproj' \
  -scheme 'AI Client' \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

For device installation, select your own development team and use a bundle
identifier that belongs to you. The public project intentionally contains no
Apple Developer Team ID. [`Secrets.example.xcconfig`](Secrets.example.xcconfig)
shows invalid signing placeholders for reference; it is not loaded by the
project automatically.

Before redistributing a build, replace the deliberately invalid
`support@example.invalid` address in
`AI Client/App/Onboarding/OnboardingConsentView.swift` with a monitored public
support address.

## Add your API key

No provider key is required at build time:

1. Launch the app and open the provider configuration screen.
2. Add or select a provider and verify its base URL and protocol.
3. Enter your own API key and, if required, sensitive custom headers.
4. Add or fetch model identifiers and test the configuration.

Provider API keys, agent secrets, and sensitive custom-header values are stored
as generic-password items in the iOS Keychain with
`WhenUnlockedThisDeviceOnly` accessibility. Non-secret configuration metadata
is stored separately. Do not place provider keys in source files, `.xcconfig`
files, tests, screenshots, or issue reports.

## Privacy

Conversations and knowledge-base data are stored locally in the app's
Application Support directory. Content is transmitted to the provider or
custom endpoint selected by the user when a request requires it. The app does
not make a local database equivalent to Keychain protection, and users should
not treat the device as a zero-trust storage environment.

Read [Docs/privacy.md](Docs/privacy.md) for the detailed data inventory and
network boundaries.

## Screenshots

Reviewed public screenshots have not been committed yet. The sanitization and
capture checklist is in [Docs/screenshots/README.md](Docs/screenshots/README.md).
No synthetic screenshots or private test conversations are used as substitutes.

## Known limitations

- BYOK APIs can change independently of this maintenance repository.
- Vertex AI Express model discovery is not automatic; model IDs are added
  manually.
- Tool calling, reasoning fields, usage reporting, and image support depend on
  the selected provider and model.
- Local conversation and knowledge-base files are not application-level
  end-to-end encrypted.
- App Store binaries may differ from the latest public source snapshot.
- The project has no guaranteed response time or commercial support commitment.

## Security and contributing

- Security guidance: [SECURITY.md](SECURITY.md)
- Contribution policy: [CONTRIBUTING.md](CONTRIBUTING.md)
- Change history: [CHANGELOG.md](CHANGELOG.md)
- Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## License and author

MewyAI is developed by **SharkyMew**. Commit authorship and dates are preserved
in the cleaned Git history.

The MewyAI source is made available under an **all rights reserved** license;
it is not an open-source license. See [LICENSE](LICENSE). Bundled dependencies
remain under their respective licenses.
