<div align="center">
  <img src="AI%20Client/Assets.xcassets/MewyAILogo.imageset/MewyAI.png" alt="MewyAI logo" width="128">

  <h1>MewyAI</h1>

  <p>A native, local-first BYOK AI client for iPhone and iPad.</p>

  <p><a href="README.zh-CN.md">简体中文</a></p>

  <p>
    <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
    <img src="https://img.shields.io/badge/iOS-17.0%2B-000000?logo=apple&logoColor=white" alt="iOS 17.0 or later">
    <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
    <img src="https://img.shields.io/badge/version-1.1.0-2ea44f" alt="Version 1.1.0">
    <img src="https://img.shields.io/badge/license-Source--Available-lightgrey" alt="源码可见的专有许可证">
  </p>

  <p>
    <a href="#features">Features</a> ·
    <a href="#quick-start">Quick start</a> ·
    <a href="Docs/architecture.md">Architecture</a> ·
    <a href="Docs/privacy.md">Privacy</a> ·
    <a href="CONTRIBUTING.md">Feedback</a>
  </p>
</div>

MewyAI is an independently developed native iOS AI client built with Swift 6,
SwiftUI, and selected UIKit integrations. Its bring-your-own-key (BYOK) model
keeps provider configuration and local app data on the device while supporting
multiple model API protocols, streaming responses, tool calling, and local
conversation storage.

> [!WARNING]
> **Source-available, not open source.** This repository makes its source code
> visible under a source-available proprietary license. It permits only
> non-commercial personal evaluation, individual educational study, and local
> running of an unmodified copy, except for limited configuration changes strictly
> necessary to build or run it. Without prior written permission, do not make
> other modifications, distribute or republish the source or compiled artifacts,
> create or publish forks, host, deploy, use commercially, or create derivative
> works. See [LICENSE](LICENSE) for the complete terms.

## Features

| Chat experience | Providers and models |
| --- | --- |
| Streaming responses and multiple-conversation management | OpenAI Chat Completions and OpenAI Responses |
| Markdown rendering, syntax highlighting, tables, and LaTeX | Anthropic Messages and Vertex AI Express |
| Image and document attachments, camera input, and speech input | OpenAI-compatible custom providers |
| Message editing, branching, search, and export | Multiple API keys with locally tracked failover state |

| Local data | Tools and integrations |
| --- | --- |
| SQLite conversation persistence | Model tool calling and Skills/MCP support |
| Local knowledge-base indexing and retrieval | App Intents and Apple platform integrations |
| API keys and sensitive headers stored in Keychain | Background completion notifications |
| Local usage and cost estimates | Custom base URLs and request headers |

This list describes implementation scope that can be reviewed in the public
source. It does not mean that every feature is available for every provider,
model, device, or system version. Agent, MCP, knowledge-base, and some
background behaviors are experimental. Provider and model behavior depends on
the specific API implementation.

## Project status

This repository is a public version prepared from a project originally
developed privately. It is in maintenance mode and is primarily intended for
technical review and portfolio presentation; it is not a continuously developed
commercial product. The maintainer may make necessary fixes at their discretion,
but does not promise ongoing development, feature updates, response times, or
commercial support.

A version of MewyAI passed App Store review and was released during the
project's private development. This repository does not indicate that version
is currently available on the App Store, and it is not automatically
synchronized with any historical or current production binary.

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

Cloning, building, and running this repository are subject to
[LICENSE](LICENSE). Local builds and runs are limited to the non-commercial
personal evaluation and individual educational study allowed there. They do not
authorize publication, distribution, deployment, hosting, or the creation,
publication, or use of any other modified version.

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

For installation on a physical device, use your own Apple development team and
a bundle identifier that you own. The public project intentionally contains no
Apple Developer Team ID. [`Secrets.example.xcconfig`](Secrets.example.xcconfig)
contains invalid signing placeholders only and is not loaded automatically by
the project.

> [!NOTE]
> `support@example.invalid` in
> [`AI Client/App/Onboarding/OnboardingConsentView.swift`](AI%20Client/App/Onboarding/OnboardingConsentView.swift)
> is a deliberately invalid placeholder. It is provided only for local builds
> and personal evaluation within the scope of the License. The License does not
> grant a right to redistribute compiled artifacts.

### Add an API key

No provider API key is required at build time.

1. Launch the app and open the provider configuration screen.
2. Add or select a provider and verify its base URL and protocol.
3. Enter your own API key and any required sensitive custom headers.
4. Add or fetch model identifiers and test the configuration.

Provider API keys, agent secrets, and sensitive custom-header values are stored
as generic-password items in the iOS Keychain with
`WhenUnlockedThisDeviceOnly` accessibility. This means the app can access a
credential while the device is unlocked, and that credential does not migrate to
another device. Non-secret configuration metadata is stored separately. Do not
place keys in source files, `.xcconfig` files, tests, screenshots, or issue
reports.

## Architecture

The app is organized around explicit feature and service boundaries:

```text
AI Client/
├── App, Chat             SwiftUI presentation and chat-session state
├── AIService             Provider requests and streaming response parsing
├── Configuration         Provider, model, and credential metadata
├── Persistence           Local SQLite conversation storage
├── Agent                 Agent capabilities, MCP, and Skills orchestration
├── KnowledgeBase         Local document processing and retrieval
├── AppIntents            Apple platform integrations
└── SharedUI              Reusable interface components
```

See [Docs/architecture.md](Docs/architecture.md) for the full data flow and
security boundaries.

### Supported protocols

| Protocol | Typical use |
| --- | --- |
| OpenAI Chat Completions | OpenAI API and custom endpoints implementing compatible interfaces |
| OpenAI Responses | OpenAI Responses API and compatible implementations |
| Anthropic Messages | Anthropic Messages API and compatible implementations |
| Vertex AI Express | Access to supported Gemini models through Vertex AI Express |

Actual provider and model behavior depends on the API implementation. Listed
presets do not imply endorsement, affiliation, or a compatibility guarantee.
Product and service names may be trademarks of their respective owners.

Custom base URLs and request headers are supported. Treat each custom endpoint
as a separate trust boundary: prompts, attachments, and recalled context are
sent to the endpoint selected for the current request.

## Privacy and security

Conversations and knowledge-base data are stored in the app's Application
Support directory. When a model request is made, its content is sent to the
provider or custom endpoint selected by the user. The local database does not
have the same protection boundary as Keychain credentials, and local
conversation and knowledge-base files do not use application-level end-to-end
encryption.

Do not treat MewyAI as a secure vault for highly sensitive information. Rely on
your device passcode, system updates, and the data-protection mechanisms
provided by the operating system.

- [Privacy and data inventory](Docs/privacy.md)
- [Security policy and reporting](SECURITY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Screenshots

This repository does not currently include unreviewed development screenshots.
Public screenshots must be reviewed against the
[screenshot sanitization and capture checklist](Docs/screenshots/README.md) to
avoid exposing API keys, private conversations, device information, or other
test data.

## Known limitations

- BYOK APIs can change independently of this maintenance repository.
- Vertex AI Express model discovery is not automatic; model IDs are added
  manually.
- Tool calling, reasoning fields, usage reporting, and image support depend on
  the selected provider and model.
- Agent, MCP, knowledge-base, and some background capabilities are experimental.
- Compatibility with a custom provider depends on its API implementation.
- Local conversation and knowledge-base files are not application-level
  end-to-end encrypted.
- App Store binaries may differ from the public source snapshot.
- The project does not guarantee response times or commercial support.

## Feedback

Use [CONTRIBUTING.md](CONTRIBUTING.md) to submit issues, bug reports, and
feature suggestions, and review the [change history](CHANGELOG.md) for context.
Report security vulnerabilities through [SECURITY.md](SECURITY.md). Do not
include API keys, private conversations, personal data, device identifiers, or
other sensitive information in any report.

Unless the copyright holder grants prior written permission, this project does
not accept external pull requests containing code changes. Submitting an issue,
suggestion, or vulnerability report does not grant permission to modify,
distribute, fork, or create derivative works from the project.

## License

MewyAI is developed by **SharkyMew**. The cleaned Git history preserves the
original commit authors and dates.

This repository is released under a **Source-Available Proprietary License**;
it is not open-source software. It permits viewing the source code and running
an unmodified local copy for non-commercial personal evaluation or individual
educational study. Limited configuration changes strictly necessary to build or
run the software are governed by the complete terms in [LICENSE](LICENSE).

Without prior written permission from the copyright holder, the License does
not permit other modification, redistribution, republication, hosting,
deployment, commercial use, or derivative works. Third-party dependencies
remain subject to their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
If this README summary differs from the complete [LICENSE](LICENSE), the
LICENSE controls.
