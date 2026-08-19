<h1 align="center">Quarry</h1>

<p align="center">
  <img src="assets/logo.png" width="128" alt="Quarry logo" />
</p>

<p align="center">
  A fast, native macOS workspace for your databases.
</p>

<p align="center"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" />&nbsp;<img alt="Swift" src="https://img.shields.io/badge/swift-6.0-orange" />&nbsp;<img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-green" />&nbsp;<img alt="Latest release" src="https://img.shields.io/github/v/release/ribban-co/Quarry" /></p>

<p align="center">
  <a href="https://github.com/ribban-co/Quarry/releases/latest">Download</a>
  &nbsp;·&nbsp;
  <a href="https://ribban.co/quarry">Website</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/ribban-co/Quarry/issues/new/choose">Report an issue</a>
</p>

---

> Connect PostgreSQL, MySQL, MariaDB, MongoDB, SQLite, or Convex and work with the data in one focused Mac app — no Electron, no browser tabs, no context switching.

Quarry is built and maintained by [RIBBAN AB](https://ribban.co). It began as a fork of [Pluk](https://github.com/pluk-inc/Pluk) and is not affiliated with or endorsed by Pluk, Inc.

## Installation

Download the latest signed DMG from [Releases](https://github.com/ribban-co/Quarry/releases/latest), open it, and drag Quarry to Applications.

Quarry requires macOS 15 or later and runs on Apple Silicon and Intel Macs.

## A native home for your data

<p align="center">
  <img src="assets/workspace.png" width="900" alt="Quarry workspace with recent connections and notebooks" />
</p>

<p align="center">
  <em>Keep connections, notebooks, local files, and Docker databases together in one workspace.</em>
</p>

<p align="center">
  <img src="assets/data-grid.png" width="900" alt="Browsing a PostgreSQL table in Quarry" />
</p>

<p align="center">
  <em>Browse, sort, filter, and edit real data in a fast native grid.</em>
</p>

<p align="center">
  <img src="assets/query-editor.png" width="900" alt="Quarry SQL query editor" />
</p>

<p align="center">
  <em>Open a query beside the active schema, write SQL with autocomplete, and keep the results in a tab.</em>
</p>

<p align="center">
  <img src="assets/table-assistant.png" width="900" alt="Quarry table assistant summarizing active data" />
</p>

<p align="center">
  <em>Ask about the table in front of you — Quarry already has the database, schema, and rows in context.</em>
</p>

<p align="center">
  <img src="assets/notebook-assistant.png" width="900" alt="Quarry assistant building a notebook dashboard" />
</p>

<p align="center">
  <em>Turn a question into queries, metrics, and charts while the assistant builds alongside you.</em>
</p>

<p align="center">
  <img src="assets/dashboard.png" width="900" alt="A finished analytics dashboard in Quarry" />
</p>

<p align="center">
  <em>Publish the result as a focused native dashboard.</em>
</p>

## Features

- **Native macOS interface** — AppKit and SwiftUI throughout, with real windows, tabs, sheets, keyboard navigation, and platform-standard controls.
- **Six database families** — PostgreSQL, MySQL, MariaDB, MongoDB, SQLite, and Convex in one connection model.
- **Editable data grid** — browse, filter, sort, copy, paste, and edit rows directly, with dedicated views for larger values.
- **Query workspace** — SQL editing, autocomplete, multiple result sets, history, schema-aware execution, and saved notebooks.
- **Schema tools** — inspect columns and indexes, create tables and databases, and make schema changes without leaving the app.
- **Notebook dashboards** — combine queries, values, text, and charts in a flexible native canvas.
- **Context-aware assistant** — chat about the open table or notebook and review generated writes before they run.
- **Real-world connections** — SSH tunnels, SSL certificates, URI import, local SQLite files, and Docker container discovery.
- **Secure local handling** — Keychain-backed secrets, encrypted query history, and no Quarry telemetry in unconfigured community builds.

## Supported databases

| Database | What Quarry supports |
| --- | --- |
| PostgreSQL | Tables, schemas, SQL, JSON, SSL, SSH tunnels |
| MySQL and MariaDB | Tables, SQL, SSL, SSH tunnels |
| MongoDB | Collections, documents, filters, aggregation |
| SQLite | Local database files and SQL |
| Convex | Projects, deployments, documents, and queries |

## Building from source

You need macOS 15 or later and Xcode 26 or later with Swift 6 support.

```sh
git clone https://github.com/ribban-co/Quarry.git
cd Quarry
open Quarry.xcodeproj
```

Build and run the shared `Collection` scheme. Swift Package Manager resolves the pinned dependencies on the first build.

If signing fails, select your own development team in Xcode or build locally with code signing disabled. Never commit personal signing configuration.

### Community builds

The database client builds without access to Quarry's hosted services. When `quarry/Secrets.xcconfig` is absent, PostHog, Sentry, WorkOS sign-in, Convex OAuth, and funded Bedrock AI are not configured. Manual Convex connections remain available.

Maintainers can copy `quarry/Secrets.xcconfig.example` to the ignored `quarry/Secrets.xcconfig` for official builds. Those values are embedded in the app binary and must not be treated as server-side secrets.

See [DATA_COLLECTION.md](DATA_COLLECTION.md) for the service and telemetry boundary.

## Project layout

```text
quarry/               Main macOS app source and resources
quarryTests/          Unit tests
quarryUITests/        UI test target
BSON/                 Vendored BSON package
Quarry.xcodeproj/     Shared Xcode project, scheme, and package pins
scripts/              Release and rollback automation
```

## Contributing

Pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), keep changes focused, and test user-facing behavior in the running app before submitting.

Please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md). Third-party software and attribution are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Quarry's source code is available under the [GNU Affero General Public License v3.0](LICENSE).

Quarry is a fork of [Pluk](https://github.com/pluk-inc/Pluk), © Pluk, Inc., and is not affiliated with or endorsed by Pluk, Inc. Pluk's marks remain subject to the [Pluk Trademark Policy](TRADEMARKS.md).

The source license does not grant permission to use the Quarry name, logo, icon, or visual identity for another product.
