# Changelog

This file summarizes verifiable development milestones from the retained Git
history. It is not a reconstructed App Store release ledger, and no historical
tag or release date has been invented.

## Public repository preparation - 2026-07-17

- Retained and sanitized the original development history.
- Removed Apple signing identifiers and historical Xcode user data.
- Added public setup, architecture, privacy, security, and contribution docs.
- Added repository hygiene rules and complete third-party license resources.

## Development milestones

### July 2026

- Added conversation branching, camera capture, App Intents, and knowledge-base
  integration.
- Migrated conversation persistence to SQLite.
- Added multi-key provider failover and migrated the project to Swift 6.

### June 2026

- Added Skills/MCP tool integration, temporary private chats, localization,
  usage tracking, search, background completion notifications, and chat memory.
- Modularized the chat architecture and reorganized the source tree.
- Added onboarding, acknowledgements, and expanded test coverage.

### May 2026

- Built the initial streaming chat experience and provider configuration flow.
- Added multi-conversation support, multimodal input, document context,
  Markdown/LaTeX rendering, model management, and multiple provider protocols.
- Hardened request handling and local credential storage.

For commit-level details, use `git log --reverse`.
