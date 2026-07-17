# Contributing

MewyAI is a source-available, all-rights-reserved maintenance project. Public
access grants only the limited evaluation permission stated in `LICENSE`; it
does not grant permission to redistribute or create derivative works.

## Issues

Concise, reproducible bug reports and documentation corrections are welcome.
Before opening an issue:

1. Check the latest `main` branch and existing issues.
2. Remove API keys, custom headers, personal conversations, local paths, and
   signing information.
3. Include the affected commit, environment, reproduction steps, and expected
   behavior.

Use the private process in `SECURITY.md` for vulnerabilities.

## Code contributions

Pull requests are not accepted by default. Discuss a proposed code contribution
with the maintainer before doing substantial work. Any permission to contribute
or incorporate code must be agreed separately in writing; the repository's
public visibility is not such permission.

If a contribution is requested, keep it focused, preserve authorship, add
relevant tests, and verify at minimum:

```sh
git diff --check
xcodebuild -project 'AI Client.xcodeproj' -scheme 'AI Client' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild build-for-testing -project 'AI Client.xcodeproj' -scheme 'AI Client' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```
