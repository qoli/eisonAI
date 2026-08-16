# Local Validation

`NV_CHANGELOG_SCHEMA=bilingual-version-heading` requires:

- Both changelog files are non-empty and contain no HTML.
- `fastlane/changelog.txt` contains exactly one `## x.y` heading, equals the CLI version, and contains no Chinese/Japanese/Korean text.
- `telegram/changelog.md` contains exactly one `## x.y` heading, equals the CLI version, and contains Chinese text.
- `events.jsonl` must include `session.task_complete success=true` and `translation-validator` PASS.
