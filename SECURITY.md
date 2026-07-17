# Security Policy

## Supported source

MewyAI is in maintenance mode. Security fixes, when made, target the latest
public `main` branch. App Store binaries may not correspond to that branch and
are not covered by a guaranteed support window.

## Reporting a vulnerability

Use GitHub private vulnerability reporting if it is enabled for the repository.
If it is unavailable, use the support channel shown in the distributed app and
do not place exploit details, credentials, private endpoints, or user data in a
public issue.

Include only the minimum information needed to reproduce the issue:

- affected commit or app version;
- affected feature and security boundary;
- sanitized reproduction steps;
- expected and observed behavior;
- impact and required preconditions.

Never submit a live API key, token, provisioning profile, certificate, private
database, conversation export, or screenshot containing personal data.

## Credential incidents

If a real credential is exposed, revoke or rotate it with its provider first.
Deleting it from the latest source or rewriting Git history does not invalidate
copies held by Git hosts, forks, caches, logs, or previous clones.

MewyAI stores provider keys and sensitive custom headers in the iOS Keychain.
Repository examples intentionally use invalid placeholders. See
[`Docs/privacy.md`](Docs/privacy.md) for local storage and network boundaries.

## Out of scope

- Availability or behavior of third-party model providers
- Jailbroken or otherwise compromised devices
- User-configured endpoints that intentionally receive request content
- Social engineering and credential reuse outside MewyAI
