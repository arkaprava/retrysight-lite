# Contributing to RetrySight Lite

Thank you for your interest in contributing! RetrySight Lite is licensed under [Apache-2.0](LICENSE).

## Getting started

1. Fork and clone the repository.
2. Install dependencies:
   ```bash
   npm install
   npm run install:app
   cd manager && npm run build
   cd ../app && flutter pub get
   ```
3. Run the headless backend and Flutter app (see [README.md](README.md)).

## Development workflow

- **Backend changes:** edit `manager/src/`, then `npm run build` in `manager/`.
- **Flutter changes:** edit `app/lib/`, then `flutter analyze` and `flutter test` in `app/`.
- **Smoke tests:** `cd manager && npm run smoke` (requires a built `dist/`).

Install git hooks to catch accidental secret commits:

```bash
./scripts/install-git-hooks.sh
```

## Code style

- Match existing patterns in each area (TypeScript in `manager/`, Dart in `app/`).
- Keep diffs focused — one logical change per pull request when possible.
- Add SPDX header `// SPDX-License-Identifier: Apache-2.0` to new TypeScript files in `manager/src/`.
- Do not commit secrets, tokens, or local database files.

## Pull requests

1. Describe what changed and why.
2. Note how you tested (commands run, platforms checked).
3. Update documentation if behavior, env vars, or install steps change.

## Reporting issues

- Use GitHub Issues for bugs and feature requests.
- For security vulnerabilities, see [SECURITY.md](SECURITY.md) — do not open public issues for those.

## License

By contributing, you agree that your contributions will be licensed under the Apache License, Version 2.0.
