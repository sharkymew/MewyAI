# Issue reporting

MewyAI is a source-available proprietary maintenance project, not open-source
software. Public access grants only the limited evaluation permission stated in
`LICENSE`; it does not grant permission to redistribute, make other
modifications, or create derivative works.

## Issues and suggestions

Concise, reproducible bug reports, documentation corrections, and feature
suggestions are welcome as issues.
Before opening an issue:

1. Check the latest `main` branch and existing issues.
2. Remove API keys, custom headers, personal conversations, local paths,
   signing information, personal data, device identifiers, and other sensitive
   information.
3. Include the affected commit, environment, reproduction steps, and expected
   behavior.

Use the private process in `SECURITY.md` for vulnerabilities.

## External code changes

External pull requests containing code changes are not accepted unless the
copyright holder gives prior written permission. Submitting an issue,
suggestion, or vulnerability report does not grant permission to modify,
distribute, fork, or create derivative works from the project.

If a code contribution is separately authorized in writing, keep it focused,
preserve authorship, add relevant tests, and verify at minimum:

```sh
git diff --check
xcodebuild -project 'AI Client.xcodeproj' -scheme 'AI Client' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild build-for-testing -project 'AI Client.xcodeproj' -scheme 'AI Client' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```
