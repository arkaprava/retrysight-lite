# Security Policy

## Supported versions


| Version | Supported |
| ------- | --------- |
| 1.x     | Yes       |


## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Email the maintainer([arkapravaghosh@hotmail.com](mailto:arkapravaghosh@hotmail.com)) with:

- A description of the issue and impact
- Steps to reproduce
- Affected version or commit
- Suggested fix (if any)

We aim to acknowledge reports within a few business days.

## Security model

RetrySight Lite is designed for **local, single-user** use:

- The API binds to loopback (`127.0.0.1`) by default.
- Admin endpoints require a bearer token or `X-RetrySight-Admin-Token`.
- Secrets are generated on first run and stored with restrictive file permissions.
- The Flutter app stores the admin token in OS secure storage.

Binding to `0.0.0.0` or exposing the service on a network increases risk. Only do so intentionally, with strong tokens and network controls.

## Data at rest

The SQLite database is **not** encrypted by the application. Use full-disk encryption or an encrypted volume for sensitive environments.

## Dependency updates

Report third-party dependency vulnerabilities through the same private channel or via a GitHub Security Advisory if you prefer coordinated disclosure.