<div align="center">
  <img src="AI%20Client/Assets.xcassets/MewyAILogo.imageset/MewyAI.png" alt="MewyAI logo" width="128">

  <h1>MewyAI</h1>

  <p>A native BYOK AI client for iPhone and iPad.</p>

  <p><a href="README.zh-CN.md">简体中文</a></p>

  <p>
    <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
    <img src="https://img.shields.io/badge/iOS-17.0%2B-000000?logo=apple&logoColor=white" alt="iOS 17.0 or later">
    <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
    <img src="https://img.shields.io/badge/version-1.1.0-2ea44f" alt="Version 1.1.0">
    <img src="https://img.shields.io/badge/license-All%20rights%20reserved-lightgrey" alt="All rights reserved">
  </p>

  <p>
    <a href="#features">Features</a> ·
    <a href="#quick-start">Quick start</a> ·
    <a href="Docs/architecture.md">Architecture</a> ·
    <a href="Docs/privacy.md">Privacy</a> ·
    <a href="CONTRIBUTING.md">Contributing</a>
  </p>
</div>

MewyAI is an independently developed, native iOS AI client built around the
bring-your-own-key (BYOK) model. It explores multi-provider model integration,
streaming responses, local conversation storage, tool calling, and the
architecture of a full-featured SwiftUI AI client.

> [!IMPORTANT]
> This repository is a cleaned public release of a project originally developed
> privately. It is in maintenance mode and is intended for technical review,
> portfolio use, and limited maintenance—not active commercial development.

## Features

| Chat experience | Providers and models |
| --- | --- |
| Streaming responses and multiple conversations | OpenAI Chat Completions and Responses |
| Markdown, syntax highlighting, tables, and LaTeX | Anthropic Messages and Vertex AI Express |
| Image and document attachments, camera, and speech input | OpenAI-compatible custom providers |
| Message editing, branching, search, and export | Multiple API keys with local failover state |

| Local data | Tools and integrations |
| --- | --- |
| SQLite conversation persistence | Model tool calling and Skills/MCP support |
| Local knowledge-base indexing and retrieval | App Intents and Apple platform integrations |
| API keys and sensitive headers stored in Keychain | Background completion notifications |
| Local usage and cost estimates | Custom base URLs and request headers |

Provider and model behavior varies by API implementation. A listed preset does
not imply endorsement, affiliation, or guaranteed compatibility with every
model exposed by that provider.

## Project status

A version of MewyAI completed App Store review and release during private
development. This repository does not claim current App Store availability and
does not change any production App Store version.

| | |
| --- | --- |
| **App version** | 1.1.0 (build 7) |
| **Minimum deployment target** | iOS 17.0 |
| **Language** | Swift 6 |
| **UI** | SwiftUI with selected UIKit integrations |
| **Project** | `AI Client.xcodeproj` |
| **Scheme** | `AI Client` |
| **App target / module** | `MewyAI` |
| **Test target** | `MewyAITests` |

## Quick start

### Requirements

- macOS with an Xcode version that supports Swift 6 and the iOS 17 SDK
- Internet access for the first Swift Package Manager dependency resolution
- Your own Apple development team when installing on a physical device

### Build

Clone the repository and open `AI Client.xcodeproj`. Xcode restores the pinned
Swift packages from `Package.resolved`.

Build without code signing:

```sh
xcodebuild -project 'AI Client.xcodeproj' \
  -scheme 'AI Client' \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Build the app and test bundle without launching a simulator:

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
contains invalid signing placeholders for reference and is not loaded by the
project automatically.

> [!NOTE]
> Before redistributing a build, replace the deliberately invalid
> `support@example.invalid` address in
> `AI Client/App/Onboarding/OnboardingConsentView.swift` with a monitored public
> support address.

### Add an API key

No provider key is required at build time.

1. Launch the app and open the provider configuration screen.
2. Add or select a provider and verify its base URL and protocol.
3. Enter your own API key and any required sensitive custom headers.
4. Add or fetch model identifiers and test the configuration.

Provider API keys, agent secrets, and sensitive custom-header values are stored
as generic-password items in the iOS Keychain with
`WhenUnlockedThisDeviceOnly` accessibility. Non-secret configuration metadata
is stored separately. Never place provider keys in source files, `.xcconfig`
files, tests, screenshots, or issue reports.

## Architecture

The app is organized around explicit feature and service boundaries:

```text
AI Client/
├── App, Chat             SwiftUI presentation and chat-session state
├── AIService             Provider requests and streaming response parsing
├── Configuration         Provider, model, and credential metadata
├── Persistence           Local SQLite conversation storage
├── Agent, MCP            Tool capabilities and orchestration
├── KnowledgeBase         Local document processing and retrieval
├── AppIntents            Apple platform integrations
└── SharedUI              Reusable interface components
```

See [Docs/architecture.md](Docs/architecture.md) for the full data flow and
security boundaries.

### Supported protocols

| Protocol | Typical use |
| --- | --- |
| OpenAI Chat Completions | OpenAI and OpenAI-compatible chat APIs |
| OpenAI Responses | OpenAI Responses-compatible APIs |
| Anthropic Messages | Claude-compatible message APIs |
| Vertex AI Express | Gemini model access through the Vertex Express API |

Custom base URLs and headers are supported. Treat a custom endpoint as a
separate trust boundary: prompts, attachments, and recalled context are sent to
the endpoint selected for that request.

## Privacy and security

Conversations and knowledge-base data are stored locally in the app's
Application Support directory. Content is transmitted to the provider or
custom endpoint selected by the user when a request requires it. The local
database does not provide protection equivalent to Keychain, so users should
not treat the device as a zero-trust storage environment.

- [Privacy and data inventory](Docs/privacy.md)
- [Security policy and reporting](SECURITY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Screenshots

Reviewed public screenshots have not been committed yet. See the
[screenshot sanitization and capture checklist](Docs/screenshots/README.md).
Synthetic screenshots and private test conversations are not used as
substitutes.

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

## Contributing

Before opening an issue or pull request, read [CONTRIBUTING.md](CONTRIBUTING.md)
and review the [change history](CHANGELOG.md). Please do not include API keys,
private conversations, or other sensitive data in reports.

## License

MewyAI is developed by **SharkyMew**. Commit authorship and dates are preserved
in the cleaned Git history.

The MewyAI source is made available under an **all rights reserved** license;
it is not an open-source license. See [LICENSE](LICENSE). Bundled dependencies
remain under their respective licenses.
