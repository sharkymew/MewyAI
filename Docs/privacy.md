# Privacy and data handling

This document describes the public source snapshot. It is technical project
documentation, not a substitute for the privacy disclosures attached to any
particular App Store binary.

## Local data

MewyAI can store the following data on the device:

- provider and model configuration metadata;
- API keys, agent secrets, and sensitive custom headers in the iOS Keychain;
- conversations and search indexes in an Application Support SQLite database;
- message attachments and knowledge-base documents/indexes in Application
  Support;
- app preferences, feature selections, and non-secret identifiers in local
  preference storage.

Provider secrets use Keychain generic-password items with
`WhenUnlockedThisDeviceOnly` accessibility. They are not intended to synchronize
to another device. Conversation and knowledge-base files are not encrypted by a
separate application-level end-to-end encryption scheme.

Temporary private chats are excluded from normal conversation persistence, but
their content exists in memory while in use and is transmitted to the selected
provider when a request is made.

## Data sent over the network

Depending on the feature used, MewyAI may send the following to a provider or
custom endpoint selected by the user:

- system prompts, user messages, and relevant conversation history;
- images, extracted document text, or generated image descriptions;
- tool definitions, tool inputs, and tool results;
- recalled memory or knowledge-base snippets;
- model parameters and provider-specific request metadata;
- document chunks sent to the selected embedding provider.

The app is BYOK: the user supplies the account and credential for each provider.
The public source tree does not define a MewyAI-operated relay or account
backend for model requests. Provider retention, training, logging, regional
processing, and account policies are controlled by the endpoint operator.

## Apple platform services

Speech input, notifications, camera/photo access, App Intents, and Keychain use
Apple platform frameworks and their permission/lifecycle rules. The app requests
the relevant capability only when the corresponding feature is used.

## Analytics and logs

No first-party analytics or crash-reporting SDK is declared in the pinned Swift
package set for this public snapshot. Development builds, Xcode, iOS, network
providers, and custom endpoints may still produce their own diagnostic logs.
Do not attach such logs to public issues without reviewing URLs, headers, local
paths, conversations, and identifiers.

## Deletion and retention

Use the app's configuration and content-management controls to remove provider
keys or generated content you no longer want stored. Removing the app normally
removes its container files, but Keychain item lifecycle is controlled by iOS;
delete provider configurations/keys explicitly when that distinction matters.

Deleting local data does not delete content already sent to a provider. Use the
provider's account tools and retention controls for remote copies.

## Public repository safeguards

The public repository must not contain:

- real keys, tokens, cookies, session values, or sensitive headers;
- Apple Team IDs, certificates, provisioning profiles, or private keys;
- conversation exports, user uploads, test databases, crash logs, or request
  logs;
- Xcode user data, local absolute paths, or private agent/session state;
- screenshots containing personal conversations, provider balances, account
  identifiers, or notification previews.

See `SECURITY.md` for responsible reporting guidance.
