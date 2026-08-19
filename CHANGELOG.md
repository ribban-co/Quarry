# Changelog

# Quarry Release Notes

## [0.0.51] – 2026-08-19

The app is now Quarry, built and maintained by RIBBAN AB. This release is the rebrand itself — no feature or behavior changes.

- **New name throughout.** Menus, windows, settings, the built-in assistant, and the app icon are all Quarry. The About window credits RIBBAN AB and records that Quarry is based on Pluk, © Pluk, Inc., under the AGPL.
- **Your data carries over untouched.** Saved connections, passwords, file bookmarks, and query history all keep working. The keychain service, encryption salts, and Application Support location deliberately keep their original names so nothing is orphaned by the rename.

## [0.0.50-beta.1] – 2026-08-18

This beta fixes PostgreSQL connections that go through a local port-forward to a server that requires SSL.

- **SSL Mode is respected on local connections.** Pluk force-disabled TLS whenever the host was `localhost`, `127.0.0.1`, or `::1`, ignoring whatever the SSL Mode menu was set to. Connecting through an SSH or SSM port-forward to a server that enforces SSL — an RDS instance with `rds.force_ssl`, for example — failed with `no pg_hba.conf entry ... no encryption`, and no value in the menu could fix it. An explicit SSL Mode now wins. Local servers without TLS still connect, because `prefer` falls back to plaintext.

## [0.0.49] – 2026-08-10

Pluk v0.0.49 brings the AI agent out of notebooks and into the table view. You can now ask questions about the table you're looking at and have the agent make changes for you — with an approval step before anything touches your data. The rest of the release is stability: three crashes fixed, plus window and popover behavior that stays put.

Here’s what’s new:

- **Chat with the table you're looking at.** The right dock now switches between Row Detail and a full agent chat that already knows your open table, its schema, and the rest of your database — so it answers instead of spending turns discovering. Chat history persists per connection, and asking for a large result set opens a query tab with the results already running. ([#323](https://github.com/pluk-inc/app-pluk/pull/323))
- **The agent can change your data, but only with your say-so.** Ask for an edit and the agent shows you the exact SQL in an approval card before running it. Approve for me handles routine writes on its own, while risky statements — DROP, TRUNCATE, ALTER, or a DELETE/UPDATE with no WHERE — always stop and ask. The grid refreshes as soon as a write goes through. ([#323](https://github.com/pluk-inc/app-pluk/pull/323))
- **Three crashes are gone.** Pluk no longer crashes on launch when macOS restores a home window, when you delete a connection that's currently open, or when the sidebar's hover state lands on a row that's already been reloaded away. ([#325](https://github.com/pluk-inc/app-pluk/pull/325), [#326](https://github.com/pluk-inc/app-pluk/pull/326), [#327](https://github.com/pluk-inc/app-pluk/pull/327))

We’ve also shipped some small but mighty fixes:

- **Tabbed windows remember the right size.** Native tabs each kept their own stale frame under a shared autosave key, so closing or detaching a tab could snap the window back to an older size. Tab groups now stay in sync when they move or resize. ([#328](https://github.com/pluk-inc/app-pluk/pull/328))
- **The create-table popover sits on its button.** Opening it from the **+** in the connection header no longer drops the bubble below its arrow, over the table list. ([#329](https://github.com/pluk-inc/app-pluk/pull/329))

## [0.0.48] – 2026-06-23

This release adds SSH and SSL connection support, improves SQLite setup from Finder files, and smooths several query and confirmation flows.

Here’s what’s new:

- **Connect through SSH tunnels and SSL.** Pluk can now configure SSH tunnels for database connections and upload PostgreSQL/Supabase SSL key, certificate, and CA files, with TLS preserved through tunnels. ([#26](https://github.com/pluk-inc/Pluk/issues/26), [#318](https://github.com/pluk-inc/app-pluk/pull/318))
- **Create SQLite connections from files.** Drag `.db`, `.sqlite`, or `.sqlite3` files into SQLite setup, or open supported SQLite files from Finder to reuse an existing connection or start a new one with the file already selected. ([#25](https://github.com/pluk-inc/Pluk/issues/25), [#319](https://github.com/pluk-inc/app-pluk/pull/319))
- **PostgreSQL cross-schema queries work better.** The SQL editor now passes the selected schema into PostgreSQL execution and AI error correction uses schema-aware context, so schema-qualified queries no longer hit prepared-statement errors. ([#317](https://github.com/pluk-inc/app-pluk/pull/317))
- **Connection confirmations and save actions are clearer.** Delete dialogs now name the connection and use cleaner consequence copy, while floating save actions are more direct and visually balanced. ([#320](https://github.com/pluk-inc/app-pluk/pull/320), [#321](https://github.com/pluk-inc/app-pluk/pull/321))

## [0.0.47] – 2026-06-05

This release fixes Docker-backed connections on Home so rebuilding or removing local containers no longer leaves duplicate or stale connections behind.

Here’s what’s new:

- **Docker connections stay in sync.** Rebuilding a local database container now updates the existing Pluk connection instead of creating another one, even when Docker assigns the rebuilt container a new ID. When a synced container is removed, Pluk now removes its stale saved connection and cleans up related keychain credentials and query history. Existing duplicate Docker connections are also pruned the next time Docker discovery succeeds.

## [0.0.46] – 2026-06-05

This release improves Docker setup, makes the notebook agent faster and smoother, and fixes several stability and polish issues across notebooks, tables, and connection editing.

Here’s what’s new:

- **Docker setup is improved.** Docker now appears directly in the Create Connection provider list, with a native provider card and clearer `Platforms` grouping. ([#314](https://github.com/pluk-inc/app-pluk/pull/314))
- **Notebook agent feels faster and smoother.** Pluk now routes notebook agent calls through the Claude Sonnet Bedrock adapter for a more responsive agent experience. ([#312](https://github.com/pluk-inc/app-pluk/pull/312))
- **Notebook controls and edit mode are steadier.** Run All and Publish now use separate toolbar controls, Publish matches the Chat button style, and saved published notebooks no longer crash when switching a single-value view back into edit mode. ([#311](https://github.com/pluk-inc/app-pluk/pull/311), [#313](https://github.com/pluk-inc/app-pluk/pull/313))
- **Connection editing closes correctly.** Updating or canceling from the sidebar connection edit sheet now dismisses reliably and uses the same form sizing as Home. ([#309](https://github.com/pluk-inc/app-pluk/pull/309))
- **Fresh installs show table stripes by default.** Alternating table rows now match the default Settings toggle while preserving explicit user choices. ([#308](https://github.com/pluk-inc/app-pluk/pull/308))

## [0.0.45] – 2026-06-04

This release fixes Docker container discovery for users running OrbStack or other non-default Docker contexts.

Here’s what’s new:

- **Docker containers appear when OrbStack is the active context.** Pluk now resolves the active Docker context endpoint before falling back to `/var/run/docker.sock`, so containers are discovered correctly when the Docker CLI is pointed at OrbStack, Docker Desktop, or another configured context. Production diagnostics now also capture endpoint selection, command failures, container counts, and candidate skip reasons without logging secrets. ([#306](https://github.com/pluk-inc/app-pluk/pull/306))

## [0.0.44] – 2026-05-28

This release improves Docker connection setup, fixes token refresh recovery, and continues the macOS 26 window chrome polish.

Here’s what’s new:

- **Docker databases appear on Home.** Pluk now discovers local PostgreSQL, MySQL, and MongoDB containers and shows them on Home, with one-click setup from the Create Connection sheet. Stopped containers stay visible but disabled until they are running again. ([#298](https://github.com/pluk-inc/app-pluk/pull/298))
- **Existing sessions recover after server-side token rejection.** If WorkOS rejects an access token with a 401, Pluk now forces a token refresh before retrying instead of retrying with the same rejected token. ([#302](https://github.com/pluk-inc/app-pluk/pull/302))
- **Recents update only after a connection opens.** Opening or focusing a connection tab now updates Recents at the right time, while failed open attempts no longer move a connection to the top. ([#299](https://github.com/pluk-inc/app-pluk/pull/299))
- **App data moves out of the sandbox.** Pluk now runs without the App Sandbox and includes a one-time migration for the existing SwiftData store, preferences, and external-storage support files. ([#297](https://github.com/pluk-inc/app-pluk/pull/297))
- **Tab bars stay aligned when they become scrollable.** Opening enough tabs to make the tab bar scroll no longer shifts the tabs downward or clips the bottom edge. ([#295](https://github.com/pluk-inc/app-pluk/pull/295))
- **More polished macOS 26 chrome.** Tab bars, titlebar handling, sidebar persistence, fullscreen behavior, floating action bar glass, table tinting, and hover states have all been refined for macOS 26 while preserving older macOS behavior. ([#296](https://github.com/pluk-inc/app-pluk/pull/296), [#300](https://github.com/pluk-inc/app-pluk/pull/300), [#301](https://github.com/pluk-inc/app-pluk/pull/301), [#303](https://github.com/pluk-inc/app-pluk/pull/303), [#304](https://github.com/pluk-inc/app-pluk/pull/304))

## [0.0.43] – 2026-05-17

This release makes large tables feel much faster, improves sidebar navigation, and polishes Pluk's macOS 26 window chrome.

Here’s what’s new:

- **Heavy tables feel much faster.** Pluk now uses lightweight AppKit display cells for table rendering and creates the heavier editor only when you start editing, making large text and JSON-heavy datasets noticeably smoother. ([#286](https://github.com/pluk-inc/app-pluk/pull/286))
- **Browse columns directly from the sidebar.** Tables and views in the connection sidebar can now expand to show their columns, including matching type and foreign-key icons, plus column actions like Copy Name and Open Structure. ([#131](https://github.com/pluk-inc/Pluk/issues/131), [#290](https://github.com/pluk-inc/app-pluk/pull/290))
- **Better schema editing polish.** Nullable and Unique checkboxes in the schema editor now use Pluk's rounded checkbox style, and schema-mode index data loads reliably even when you open schema view before the table finishes loading. ([#292](https://github.com/pluk-inc/app-pluk/pull/292), [#293](https://github.com/pluk-inc/app-pluk/pull/293))
- **More native macOS 26 window chrome.** Tab bars, toolbar spacing, titlebar alignment, and Liquid Glass backgrounds have been tuned for macOS 26 while preserving older macOS behavior. ([#133](https://github.com/pluk-inc/Pluk/issues/133), [#287](https://github.com/pluk-inc/app-pluk/pull/287), [#291](https://github.com/pluk-inc/app-pluk/pull/291))
- **Foreign-key navigation stays in the right window.** Clicking a foreign-key cell now routes only through the table view that originated the click, so multi-window workflows no longer open the referenced table in another window. ([#132](https://github.com/pluk-inc/Pluk/issues/132), [#285](https://github.com/pluk-inc/app-pluk/pull/285))
- **Sidebar reveal fixes.** The left connection sidebar no longer clips after collapse and expand, and the row detail sidebar now reveals from the correct trailing edge. ([#134](https://github.com/pluk-inc/Pluk/issues/134), [#135](https://github.com/pluk-inc/Pluk/issues/135), [#288](https://github.com/pluk-inc/app-pluk/pull/288))
- **Smaller Account loading indicators.** Account actions now use mini loading spinners so the controls feel better balanced. ([#136](https://github.com/pluk-inc/Pluk/issues/136), [#289](https://github.com/pluk-inc/app-pluk/pull/289))

## [0.0.42] – 2026-05-17

This release makes large tables feel much faster, improves sidebar navigation, and polishes Pluk's macOS 26 window chrome.

Here’s what’s new:

- **Heavy tables feel much faster.** Pluk now uses lightweight AppKit display cells for table rendering and creates the heavier editor only when you start editing, making large text and JSON-heavy datasets noticeably smoother. ([#286](https://github.com/pluk-inc/app-pluk/pull/286))
- **Browse columns directly from the sidebar.** Tables and views in the connection sidebar can now expand to show their columns, including matching type and foreign-key icons, plus column actions like Copy Name and Open Structure. ([#131](https://github.com/pluk-inc/Pluk/issues/131), [#290](https://github.com/pluk-inc/app-pluk/pull/290))
- **Better schema editing polish.** Nullable and Unique checkboxes in the schema editor now use Pluk's rounded checkbox style, and schema-mode index data loads reliably even when you open schema view before the table finishes loading. ([#292](https://github.com/pluk-inc/app-pluk/pull/292), [#293](https://github.com/pluk-inc/app-pluk/pull/293))
- **More native macOS 26 window chrome.** Tab bars, toolbar spacing, titlebar alignment, and Liquid Glass backgrounds have been tuned for macOS 26 while preserving older macOS behavior. ([#133](https://github.com/pluk-inc/Pluk/issues/133), [#287](https://github.com/pluk-inc/app-pluk/pull/287), [#291](https://github.com/pluk-inc/app-pluk/pull/291))
- **Foreign-key navigation stays in the right window.** Clicking a foreign-key cell now routes only through the table view that originated the click, so multi-window workflows no longer open the referenced table in another window. ([#132](https://github.com/pluk-inc/Pluk/issues/132), [#285](https://github.com/pluk-inc/app-pluk/pull/285))
- **Sidebar reveal fixes.** The left connection sidebar no longer clips after collapse and expand, and the row detail sidebar now reveals from the correct trailing edge. ([#134](https://github.com/pluk-inc/Pluk/issues/134), [#135](https://github.com/pluk-inc/Pluk/issues/135), [#288](https://github.com/pluk-inc/app-pluk/pull/288))
- **Smaller Account loading indicators.** Account actions now use mini loading spinners so the controls feel better balanced. ([#136](https://github.com/pluk-inc/Pluk/issues/136), [#289](https://github.com/pluk-inc/app-pluk/pull/289))
## [0.0.41] – 2026-05-12

This stable release moves Pluk's release infrastructure to Amore and improves SQLite file access reliability.

Here’s what’s new:

- **SQLite files open more reliably.** Pluk now includes the file access entitlements needed for SQLite database files to work correctly in sandboxed builds.
- **Release automation moved to Amore.** The release scripts now use Amore for the macOS distribution flow, including signing, notarization, DMG creation, publishing, and Sparkle appcast handling.
- **Bug fixes and improvements.** A handful of smaller fixes and refinements across the app.

## [0.0.1-beta.42] – 2026-05-12

A small release focused on release infrastructure and SQLite file access reliability.

Here’s what’s new:

- **SQLite files open more reliably.** Pluk now includes the file access entitlements needed for SQLite database files to work correctly in sandboxed builds.
- **Release automation moved to Amore.** The release scripts now use Amore for the macOS distribution flow, including signing, notarization, DMG creation, publishing, and Sparkle appcast handling.
- **Bug fixes and improvements.** A handful of smaller fixes and refinements across the app.

## [0.0.1-beta.41] – 2026-04-26

A small polish release that keeps you in the right window after signing in.

Here’s what’s new:

- **Sign-in keeps Settings in front.** When you sign in from Settings → Account, Pluk now brings the Settings window back to the front after the browser callback instead of pushing it behind the home window. The same fix applies to billing and checkout callbacks, so whichever window you were last in stays where you expect. ([#127](https://github.com/pluk-inc/Pluk/issues/127))
- **Bug fixes and improvements.** A handful of smaller fixes and refinements across the app.

## [0.0.1-beta.40] – 2026-04-26

A small polish and stability release with a handful of fixes and improvements across the app.

Here’s what’s new:

- **A more responsive database selector.** The database picker sheet now closes properly when you hit Cancel or press Esc, so you can back out without committing to a database. ([#129](https://github.com/pluk-inc/Pluk/issues/129))
- **Bug fixes and improvements.** Lots of smaller fixes and refinements across the app to make everyday use feel smoother.

## [0.0.1-beta.39] – 2026-04-26

A small release with polish and stability improvements across the app.

Here’s what’s new:

- **Sign-in links bring Pluk to the front.** When an auth callback or any custom URL link opens Pluk while it’s in the background, the app now activates and brings a window forward instead of staying hidden behind your browser. ([#126](https://github.com/pluk-inc/Pluk/issues/126))
- **Bug fixes and polish.** A handful of smaller fixes and stability improvements across the app.

## [0.0.1-beta.38] – 2026-04-26

This release makes Pluk feel faster and more native in the places you touch most: opening table tabs, switching through the sidebar, setting up new connections, and working in schema view. It also fixes a Convex root-component loading hang and tightens up Ask AI for PostgreSQL.

Here’s what’s new:

- **Faster data loading.** Opening tables is now around 2x faster than before, so your data appears sooner when you move through a connection.
- **A native connection sidebar.** The connection sidebar has moved to an AppKit-backed implementation for smoother table browsing, search, query history, hover behavior, resizing, context menus, and database selection.
- **Cleaner connection setup.** The database picker, PostgreSQL setup, MySQL setup, create-database flow, and database selector modal have been redesigned to feel more focused and consistent. ([#119](https://github.com/pluk-inc/Pluk/issues/119), [#120](https://github.com/pluk-inc/Pluk/issues/120))
- **A steadier filter builder.** Table filters now use a native AppKit implementation that stays in sync with table state and schema changes. ([#121](https://github.com/pluk-inc/Pluk/issues/121))
- **Better schema view editing.** Schema and index tables now match the main data table styling, save changes refresh in place, and ⌘E toggles between content and schema view.
- **More reliable Convex root tables.** Convex tables in the root `app` component no longer hang when loading, querying, subscribing, or editing documents. ([#124](https://github.com/pluk-inc/Pluk/issues/124))

We’ve also shipped some small but mighty updates:

- **PostgreSQL Ask AI quotes identifiers.** Ask AI now generates PostgreSQL examples with quoted table and column names, and tapping outside no longer wipes an in-progress Ask AI prompt.
- **A cleaner home screen.** Empty states, recent workspaces, and first-run states on the home screen have been refreshed. ([#122](https://github.com/pluk-inc/Pluk/issues/122))
- **Window dragging feels native again.** Custom titlebar tab areas once again support expected window dragging behavior. ([#123](https://github.com/pluk-inc/Pluk/issues/123))
- **Sidebar search matches the design system.** The sidebar search field now uses the same toolbar island treatment as the surrounding controls.

## [0.0.1-beta.37] – 2026-04-21

Pluk v35 introduces SQL editor autocomplete, adds more keyboard shortcuts, makes shortcut handling more reliable across windows and databases, and fixes the repeated keychain access prompt for existing users. The rest of the release focuses on bug fixes and polish across the app.

Here’s what’s new:

- **SQL editor autocomplete.** The SQL editor now includes autocomplete to help you write queries faster.
- **More keyboard shortcuts.** Added more shortcuts to make it easier to move through Pluk.
- **More reliable shortcuts.** Fixed cases where shortcuts could be picked up by the wrong window or tab, with better routing across windows and databases.
- **Keychain access migration.** Existing users may need to approve keychain access one last time after updating as Pluk moves to a new keychain flow. Future updates will not ask again.
- **Bug fixes and polish.** Also includes fixes and refinements across the menu bar, Open Quickly, recent tables, and sidebar.

## [0.0.1-beta.36] – 2026-04-21

Pluk v35 introduces SQL editor autocomplete, adds more keyboard shortcuts, makes shortcut handling more reliable across windows and databases, and fixes the repeated keychain access prompt for existing users. The rest of the release focuses on bug fixes and polish across the app.

Here’s what’s new:

- **SQL editor autocomplete.** The SQL editor now includes autocomplete to help you write queries faster.
- **More keyboard shortcuts.** Added more shortcuts to make it easier to move through Pluk.
- **More reliable shortcuts.** Fixed cases where shortcuts could be picked up by the wrong window or tab, with better routing across windows and databases.
- **Keychain access migration.** Existing users may need to approve keychain access one last time after updating as Pluk moves to a new keychain flow. Future updates will not ask again.
- **Bug fixes and polish.** Also includes fixes and refinements across the menu bar, Open Quickly, recent tables, and sidebar.
- 
## [0.0.1-beta.35] – 2026-04-21

Pluk v35 introduces SQL editor autocomplete, adds more keyboard shortcuts, makes shortcut handling more reliable across windows and databases, and fixes the repeated keychain access prompt for existing users. The rest of the release focuses on bug fixes and polish across the app.

Here’s what’s new:

- **SQL editor autocomplete.** The SQL editor now includes autocomplete to help you write queries faster.
- **More keyboard shortcuts.** Added more shortcuts to make it easier to move through Pluk.
- **More reliable shortcuts.** Fixed cases where shortcuts could be picked up by the wrong window or tab, with better routing across windows and databases.
- **Keychain access migration.** Existing users may need to approve keychain access one last time after updating as Pluk moves to a new keychain flow. Future updates will not ask again.
- **Bug fixes and polish.** Also includes fixes and refinements across the menu bar, Open Quickly, recent tables, and sidebar.

## [0.0.1-beta.34] – 2026-04-19

v0.0.1-beta.34 makes workspace switching and table editing feel more settled. Open recent connections from the menu bar, jump into notebooks faster, refresh the sidebar with better control, and work through PostgreSQL editing with fewer rough edges.

Here’s what’s new:

- **Menu bar workspace switching.** Reopen recent connections, switch between open workspaces, and start a new notebook faster. ([#104](https://github.com/pluk-inc/Pluk/issues/104))
- **Refresh controls for the sidebar.** Tables, schemas, and the database can now be refreshed directly from the sidebar, so you no longer have to reconnect just to reload everything. ([#104](https://github.com/pluk-inc/Pluk/issues/104))
- **More reliable PostgreSQL editing.** Updates and deletes now work better for non-public schemas and UUID primary keys. ([#105](https://github.com/pluk-inc/Pluk/issues/105))
- **Better save behavior in tables.** Cmd+S now commits the active cell before saving. ([#107](https://github.com/pluk-inc/Pluk/issues/107))
- **Clearer bulk actions.** The floating action bar once again shows the correct delete count. ([#106](https://github.com/pluk-inc/Pluk/issues/106))
- **More polish throughout the app.** Smaller bug fixes and UI improvements round out the release.
- 
## [0.0.1-beta.33] – 2026-04-19

v0.0.1-beta.33 makes workspace switching and table editing feel more settled. Open recent connections from the menu bar, jump into notebooks faster, refresh the sidebar with better control, and work through PostgreSQL editing with fewer rough edges.

Here’s what’s new:

- **Menu bar workspace switching.** Reopen recent connections, switch between open workspaces, and start a new notebook faster. ([#104](https://github.com/pluk-inc/Pluk/issues/104))
- **Refresh controls for the sidebar.** Tables, schemas, and the database can now be refreshed directly from the sidebar, so you no longer have to reconnect just to reload everything. ([#104](https://github.com/pluk-inc/Pluk/issues/104))
- **More reliable PostgreSQL editing.** Updates and deletes now work better for non-public schemas and UUID primary keys. ([#105](https://github.com/pluk-inc/Pluk/issues/105))
- **Better save behavior in tables.** Cmd+S now commits the active cell before saving. ([#107](https://github.com/pluk-inc/Pluk/issues/107))
- **Clearer bulk actions.** The floating action bar once again shows the correct delete count. ([#106](https://github.com/pluk-inc/Pluk/issues/106))
- **More polish throughout the app.** Smaller bug fixes and UI improvements round out the release.

## [0.0.1-beta.32] – 2026-04-11

This release is focused on making everyday table work feel smoother and more reliable. We tightened up editing, improved QuickLook for JSON-heavy fields, fixed a bunch of database-specific edge cases, and cleaned up a few rough spots when switching between connections and databases.

- **Smoother table editing and navigation.** Copy, paste, undo, arrow-key navigation, tabbing between cells, enum updates, and foreign key links are now much more reliable when working directly inside tables. ([#93](https://github.com/pluk-inc/Pluk/issues/93))
- **A much better QuickLook experience.** JSON fields now open in a readable format by default, with syntax highlighting, a redesigned popover, added resizing, and more polished button styles. ([#96](https://github.com/pluk-inc/Pluk/issues/96))
- **Better handling for real-world database schemas.** Pluk now preserves mixed-case table names correctly, and AI-generated queries properly quote table and column identifiers across PostgreSQL, MySQL, and SQLite. ([#89](https://github.com/pluk-inc/Pluk/issues/89))
- **Cleaner behavior when switching databases and connections.** Recent tables are now scoped to the active database, and disconnecting a connection no longer throws you back to the first item in the list. ([#91](https://github.com/pluk-inc/Pluk/issues/91))
- **More reliable loading and streaming behind the scenes.** Table loading and agent streaming now use safer cancellation patterns, which helps avoid stale state and race conditions during rapid actions. ([#100](https://github.com/pluk-inc/Pluk/issues/100))
- **PostgreSQL sidebar and metadata fixes.** We fixed cases where sidebar tables could disappear after a fresh fetch, improved how cached sidebar items are typed, and resolved a few PostgreSQL-specific issues around enums and query history logging. ([#94](https://github.com/pluk-inc/Pluk/issues/94))

## [0.0.1-beta.31] – 2026-04-05

This release makes Convex in Pluk feel dramatically faster. Querying is smoother, tables load much quicker, and a bunch of connection and filtering edge cases have been cleaned up along the way.

Here’s what’s new:

- **Convex query editor support.** You can now use the query editor with Convex databases. ([#78](https://github.com/pluk-inc/Pluk/issues/78))
- **Convex AI query support.** Added Convex AI query support across the notebook agent and editor, with a floating action bar to keep things within reach. ([#82](https://github.com/pluk-inc/Pluk/issues/82))
- **Swift 6 upgrade.** Pluk is now upgraded from Swift 5 to Swift 6, setting us up for better concurrency correctness and newer platform improvements. ([#81](https://github.com/pluk-inc/Pluk/issues/81))

We’ve also shipped some small but mighty updates:

- **Convex loading is dramatically faster.** We cut time to first data from around 900ms to about 85ms, making table loads feel much more instant in everyday use. ([#74](https://github.com/pluk-inc/Pluk/issues/74))
- **Improvements to AI agents.** Better reliability and output quality across agent flows. ([#83](https://github.com/pluk-inc/Pluk/issues/83))
- **Notebook drag and drop is more reliable.** Fixes that make drag and drop feel less fragile. ([#84](https://github.com/pluk-inc/Pluk/issues/84))
- **Filters behave properly.**
  - Fixed table filter not clearing when clicking X or "Clear filters". ([#77](https://github.com/pluk-inc/Pluk/issues/77))
  - Fixed Convex table filter not working when schema is unavailable. ([#86](https://github.com/pluk-inc/Pluk/issues/86))
- **Connection lifecycle fixes.**
  - Closed connection windows no longer retain connection state in memory. ([#80](https://github.com/pluk-inc/Pluk/issues/80))
  - Closing a connection while it is still connecting no longer continues in the background and crashes on teardown. ([#79](https://github.com/pluk-inc/Pluk/issues/79))
  - Notebook connection list now refreshes correctly after creating the first connection. ([#76](https://github.com/pluk-inc/Pluk/issues/76))

## [0.0.1-beta.30] – 2026-03-11

Pluk v0.0.1-beta.30 continues to improve stability and polish across the board.

- **Bug fixes & improvements.** Resolved several issues affecting search, navigation, and general UI responsiveness. Things should feel more reliable across the board.
- **Performance tweaks.** Continued under-the-hood optimizations for a smoother experience, especially when working with larger databases.
- **A little something hidden.** We snuck in a small easter egg—not an official feature just yet. If you find it, send us a review before we push the real update.

## [0.0.1-beta.29] – 2026-03-10

Pluk v0.0.1-beta.29 continues to improve stability and polish across the board.

- **Bug fixes & improvements.** Resolved several issues affecting search, navigation, and general UI responsiveness. Things should feel more reliable across the board.
- **Performance tweaks.** Continued under-the-hood optimizations for a smoother experience, especially when working with larger databases.
- **A little something hidden.** We snuck in a small easter egg—not an official feature just yet. If you find it, send us a review before we push the real update.

## [0.0.1-beta.28] – 2026-02-15

Pluk v0.0.1-beta.28 brings a brand new way to understand your database—and makes everything else faster while it's at it.

- **Schema Visualizer** You can now see your entire database structure as an interactive visual diagram. Tables, columns, foreign keys, relationships—all laid out so you can understand how your data connects at a glance. No more mentally mapping table relationships from a list.
- **Everything feels faster** We've moved large portions of the UI from SwiftUI to AppKit. The result? Noticeably snappier rendering, smoother scrolling, and lower memory usage—especially when you're working with large datasets.

## [0.0.1-beta.27] – 2026-02-05

Pluk v0.0.1-beta.27 is a polish-heavy release focused on the small upgrades to the features you use every day when working with data.

- **Create schemas for Postgres** Set up schemas directly from Pluk instead of bouncing to another tool. ([#48](https://github.com/pluk-inc/Pluk/issues/48))
- **Copy Rows As…** Copy selected rows in multiple formats so you can paste into docs, PRs, or scripts without cleanup. ([#49](https://github.com/pluk-inc/Pluk/issues/49))
- **Paste rows with ⌘V.** Table pasting now behaves like you expect in a data grid workflow. ([#50](https://github.com/pluk-inc/Pluk/issues/50))
- **QuickLook-style cell editor.** Edit large cell values in a focused view instead of fighting tiny cells. ([#51](https://github.com/pluk-inc/Pluk/issues/51))
- **Keyboard shortcuts support.** More actions are reachable without leaving the keyboard. ([#15](https://github.com/pluk-inc/Pluk/issues/15))
- **Theme preferences.** Basic theme controls to shape your Pluk setup. ([#24](https://github.com/pluk-inc/Pluk/issues/24))
- **Striped table rows.** Easier scanning for wide datasets. ([#18](https://github.com/pluk-inc/Pluk/issues/18))

We’ve also shipped some small but mighty fixes:

- **Undo works after paste.** ⌘Z correctly undoes pasted rows. ([#52](https://github.com/pluk-inc/Pluk/issues/52))
- **MySQL/MariaDB tables list correctly in the sidebar.** Connections now reflect the real schema. ([#56](https://github.com/pluk-inc/Pluk/issues/56))
- **Better table readability.** Cell text is vertically centered again. ([#57](https://github.com/pluk-inc/Pluk/issues/57))
- **Quit on last window close.** Optional behavior for “close means quit”. ([#54](https://github.com/pluk-inc/Pluk/issues/54))

## [0.0.1-beta.26] – 2026-01-29

This release focuses on workflow polish: you can create databases without leaving Pluk, your tabs finally behave like a proper browser, and connection strings are much more resilient.

Here’s what’s new:

- **Create databases from Pluk.** Create new PostgreSQL, MySQL, and MongoDB databases right from the sidebar, with database-specific options (like Postgres encodings, MySQL charset and collation). Newly created databases open automatically in a new tab. ([#46](https://github.com/pluk-inc/Pluk/issues/46))
- **Draggable tabs, done right.** Reorder tabs by dragging with smooth animations, a clear insertion gap, auto-scroll at the edges, and haptic feedback at the moments that matter. ([#43](https://github.com/pluk-inc/Pluk/issues/43), [#2](https://github.com/pluk-inc/Pluk/issues/2))

We’ve also shipped some small but mighty updates:

- **Connection URIs now handle special characters properly.** Passwords with characters like `@` or `:` are no longer truncated, percent-encoded values decode correctly on import, and copied URIs are human-readable. ([#47](https://github.com/pluk-inc/Pluk/issues/47))
- **No more window resizing when opening a new tab.** Opening a tab should not mess with your window size or position, and now it doesn’t. ([#44](https://github.com/pluk-inc/Pluk/issues/44))

## [0.0.1-beta.25] – 2026-01-26

This update is all about staying in flow. You can edit schemas without leaving Pluk, inspect rows in a proper sidebar, and run multi-statement queries with cleaner results and fewer surprises.

Here’s what’s new:

- **Schema edits, built in.** Modify columns and indexes directly in Pluk, so schema work feels as fast as writing a query. ([#34](https://github.com/pluk-inc/Pluk/issues/34))
- **A right sidebar for row details.** Inspect full rows without fighting horizontal scroll, with a dedicated Row Details Inspector. ([#35](https://github.com/pluk-inc/Pluk/issues/35))
- **Enum values, without typing.** Enum fields now let you pick valid values instead of manually entering them. ([#36](https://github.com/pluk-inc/Pluk/issues/36))
- **Multiple query results in tabs.** Run multiple statements and flip through results in a clean tabbed view. ([#38](https://github.com/pluk-inc/Pluk/issues/38))
- **Switch databases from the sidebar.** Jump between databases using a dropdown, without rebuilding your workspace each time. ([#40](https://github.com/pluk-inc/Pluk/issues/40))
- **Query history is here.** Pluk now tracks executed queries so you can revisit what worked and keep moving. ([#41](https://github.com/pluk-inc/Pluk/issues/41))

We’ve also shipped some small but mighty updates:

- **Custom popovers are steadier.** Fixed reliability issues so popovers behave consistently. ([#37](https://github.com/pluk-inc/Pluk/issues/37))
- **Tooltips feel snappier after the first one.** Added warmup behavior so subsequent tooltips can appear instantly. ([#42](https://github.com/pluk-inc/Pluk/issues/42))
- **Multi-statement queries are more reliable.** Fixed a failure mode caused by prepared statement errors. ([#23](https://github.com/pluk-inc/Pluk/issues/23))
- **Postgres database selection behaves properly.** The database selector popup now shows when you connect without specifying a database. ([#39](https://github.com/pluk-inc/Pluk/issues/39))
- **No more TabBar click-through.** Background clicks won’t accidentally trigger macOS window controls anymore. ([#33](https://github.com/pluk-inc/Pluk/issues/33))

## [0.0.1-beta.24] – 2025-10-21

### ✨ New Features

- **Enhanced MongoDB View Support** - Restored full functionality to MongoDB views including edit, delete, and AI-powered query assistance with seamless integration across all MongoDB data types

### 🛠️ Bug Fixes & Improvements

- **FIXED**: MySQL remote server connections now work properly with SSL authentication ([#31](https://github.com/pluk-inc/Pluk/issues/31)) - Resolved "A secure connection to the server is required for authentication" error when connecting to remote MySQL hosts on local networks and external servers
- **FIXED**: New connection dialog no longer forces window to expand to full screen ([#32](https://github.com/pluk-inc/Pluk/issues/32)) - Application window now respects previously set dimensions with proper scrolling behavior and responsive layout
- Various interface refinements and minor UI improvements for better visual consistency and user experience

## [0.0.1-beta.23] – 2025-10-21

### ✨ New Features

#### **Database Schema Viewer**

- **Read-only Schema Browser** - Explore database structure including columns, indexes, and constraints
- Quick reference for understanding your database schema without leaving Pluk
- Foundation for future schema editing capabilities

#### **Enhanced User Experience**

- **Customizable Window Size** - Set preferred width and height when opening Pluk windows
- **Improved Search Focus** - Search input now automatically focuses for faster navigation

### 🛠️ Bug Fixes & Improvements

#### **Interface Stability**

- **FIXED**: Convex component documents now load correctly without errors
- **FIXED**: Tabs are now fully clickable and responsive throughout the interface
- Improved overall interface reliability and interaction handling

---

**Note**: The Schema Viewer is currently in read-only mode. Full editing capabilities will be added in a future release.

## [0.0.1-beta.22] – 2025-10-08

### 🪄 **Convex Joins Pluk** — Real-Time. Native. Seamless.

We’re thrilled to announce **native Convex integration** — bringing real-time data synchronization and reactive backends directly into Pluk. This unlocks an entirely new way to build and explore your data with zero setup friction.

#### **Convex Integration**

- 🧠 **Full Convex Backend Support** — Native integration for queries, mutations, and subscriptions with real-time synchronization built in
- ⚡ **One-Click OAuth Connection** — Securely connect to your Convex account using OAuth, then select a project and start exploring the data
- 🧪 Live Development & Deployment Ready — View your Convex production deployments and other environments, and seamlessly switch between environments and components directly from Pluk — no manual setup required.

This is our biggest backend integration yet — transforming Pluk into a powerful companion for Convex developers.

### 🎨 **A Fresh New Look**

#### **Modern UI Redesign**

- ✨ Complete visual overhaul with a modern interface, refined typography, and a cleaner color palette
- Improved visual hierarchy makes key actions more discoverable
- Polished animations and transitions create a smoother, more responsive experience

#### **Flexible Sidebar Layout**

- 🧱 Resizable sidebar — adjust to fit your workflow
- Optimized layouts for both compact and spacious workspaces

### 🚀 **Performance & Developer Experience**

#### **Native Tab Architecture**

- 🧩 Migrated to a native tab-based system for improved stability and speed
- 🌐 Intelligent connection pooling for more efficient resource use
- More robust state management and recovery for long-running sessions

## [0.0.1-beta.21] – 2025-09-17

### 🛠️ Bug Fixes & Improvements

#### **Database Connection Reliability**

- **FIXED**: PostgreSQL connection issues caused by URL encoding of passwords containing special characters
- **FIXED**: MySQL import URLs now correctly default to PostgreSQL database connections
- Enhanced connection string parsing to handle special characters in credentials properly

### ✨ New Features

#### **Connection Testing**

- **NEW**: Test Connection button added during connection creation process
- Verify database connectivity before saving connection configurations
- Immediate feedback on connection parameters and credentials

### 🔧 Under the Hood

- Improved URL-friendly parsing for database credentials
- Better handling of special characters in connection strings

## [0.0.1-beta.20] – 2025-09-05

### 🎯 Major Features

#### **AI-Powered SQL Editor is Here** 🆕

Pluk now comes with a **dedicated SQL Editor tab** that works across **SQLite, MySQL, PostgreSQL, and MongoDB**.

- **Open in a New Tab** – Write and run queries in a focused editor view
- **AI-Powered Querying** – Hit `cmd+k` to generate queries from natural language or refine existing SQL
- **Smart Error Recovery** – Pluk automatically detects query errors and suggests fixes, so you never get stuck
- **Schema Awareness** – Browse and explore your database schema directly from the editor

This isn’t just another SQL editor — it’s a smarter, AI-assisted way to work with your databases.

---

### ✨ New Features

#### **Schema Switching**

- Seamlessly switch between database schemas
- Select and explore tables across schemas within the same connection

---

### 🛠️ Bug Fixes & Improvements

#### **Query & Data Handling**

- **FIXED**: Active filters now persist after row updates and deletes (#4)
- **FIXED**: Query error state no longer locks the UI — you can now clear, edit, and retry queries (#6)
- **FIXED**: SQLite table names with spaces (e.g., `user profiles`) are now supported (#11)

#### **Interface & UX**

- **FIXED**: Scroll indicator now consistently appears in the Databases list during scroll (#7)
- Other minor bug fixes and UI improvements for a smoother experience

---

👉 With this release, Pluk becomes more than a database explorer — it’s your **AI-powered SQL companion**. Whether you’re working with SQLite, MySQL, Postgres, or MongoDB, Pluk now gives you a smarter way to query, debug, and explore your data.

## [0.0.1-beta.19] – 2025-08-22

### 🎯 Major Features

#### **MySQL Support is Here** 🆕

Pluk now speaks **MySQL**!

- Connect to any **MySQL database** with full driver support
- Run queries, edit data with **complete CRUD operations**
- **Query with AI** - Ask questions about your MySQL data in natural language
- **Rename and delete tables** directly from the interface
- Works seamlessly with existing MySQL installations and cloud instances

This makes Pluk a powerful companion for developers working with MySQL in development, staging, and production environments. From local development databases to cloud-hosted MySQL instances, Pluk now handles it all with full AI integration.

_Note: Table creation functionality is coming in a future release._

### ✨ New Features

#### **Enhanced Database Management**

- **Table Operations** - Delete and rename tables across MySQL, SQLite, and PostgreSQL databases
- **SQLite Filter Support** - Advanced filtering capabilities now available for SQLite databases, bringing parity with other database drivers

### 🛠️ Bug Fixes & Improvements

#### **Filter Operations**

- **FIXED**: Restored filter operators that were previously removed, improving data exploration capabilities across all database types
- Enhanced filter consistency between different database drivers

#### **User Experience**

- Better error handling for database operations

---

👉 With this release, **MySQL becomes a first-class citizen in Pluk**, joining SQLite as a fully supported database driver. Whether you're prototyping with SQLite or running production workloads on MySQL, Pluk now provides a unified interface for all your database exploration needs.

## [0.0.1-beta.18] – 2025-08-16

### 🚀 Major Release

#### **SQLite Support is Here** 🆕

Pluk now speaks **SQLite**!

- Connect to any **SQLite file** (`.sqlite`, `.db`, `.sqlite3`)
- Run queries, edit data with **full read/write access**
- Works seamlessly across all SQLite file formats

This makes Pluk a powerful local-first companion for developers who rely on SQLite for prototyping, embedded apps, and production systems.

---

### 🛠️ Fixes & Improvements

#### **Interface Stability**

- ✅ Fixed homescreen selection issues when disconnecting popovers
- ✅ Resolved startup loading glitches
- ✅ Corrected layout width calculation bugs
- ✅ Loading indicators now render in the right place

#### **Data Handling**

- ✅ Updates handle `NULL` values without errors
- ✅ Removed flickering invalid columns during state changes
- ✅ Popover connection data now stays accurate

#### **User Experience**

- Smoother, more reliable popover interactions
- Cleaner data transitions
- Improved error handling for tricky cases

---

👉 With this release, **SQLite becomes a first-class citizen in Pluk**, making it easier than ever to query and explore your data.

## [0.0.1-beta.17] - 2025-08-02

### 🛡️ Privacy & Security

#### **Enhanced Password Protection**

- **Keychain Integration** - Database passwords are now securely stored in the system keychain instead of local storage
- **Privacy Protection** - Passwords are completely hidden from the home screen to prevent accidental exposure and shoulder surfing

### ✨ New Features

#### **Connection Management**

- **Improved Connection Creation** - Improved connection creation experience that replaces complex URI strings like postgresql://user:pass@host:port/db with a simple, intuitive form
- **Right-Click Context Menus** - Added right-click support on connection status headers for quick access to connection actions

#### **User Interface Enhancements**

- **Updated Floating Action Bar** - AI Search bar is now more visually prominent than other buttons, making it easier to discover and use

### 🚀 Performance & Developer Experience

#### **Database Performance**

- **Faster Table Loading** - Significantly improved performance when tables are initially loaded
- **Optimized Data Refresh** - Enhanced refresh mechanisms that properly respect active filters and user preferences

### 🛠️ Bug Fixes & Improvements

#### **Connection Reliability**

- **FIXED**: Connected databases now display correctly even when no default database is configured
- **FIXED**: Data refresh operations now properly respect applied filters, ensuring consistent view state
- Improved connection state management and database discovery

### 🔧 Under the Hood

- Enhanced connection state handling for better reliability
- Improved error handling in database connection workflows
- Better separation of connection configuration logic
- Optimized data loading patterns for improved user experience
- Minor UI improvement to align with the design system

## [0.0.1-beta.16] - 2025-07-29

### ✨ New Features

#### **Foreign Key Navigation**

- **Quick Foreign Key Filtering** - Click any record to instantly navigate to related tables with foreign key filters automatically applied, streamlining relational data exploration

## [0.0.1-beta.15] - 2025-01-17

### ✨ New Features

#### **Enhanced Table Interaction**

- **Right-click Context Menu** - Table rows now support right-click actions for quick access to row-specific operations
- **Multi-row Selection** - Select multiple rows simultaneously for batch operations and improved workflow efficiency

#### **Smart Connection Management**

- **Intelligent Tab Handling** - When opening a connection, Pluk now asks whether to create a new tab or use an existing connection tab, preventing accidental duplicate connections

### 🎨 UI Improvements

#### **Visual Polish**

- **Enhanced Light Theme** - Improved light mode with better contrast, readability, and visual consistency across all interface elements
- **Smoother Cell Selection** - More responsive and fluid cell selection animations for a polished user experience

### 🛠️ Bug Fixes & Improvements

#### **Database Operations**

- **FIXED**: Insert operations now work correctly even when tables contain no existing records
- **FIXED**: Neon database connections no longer fail due to TLS configuration errors, ensuring reliable PostgreSQL connectivity

#### **Connection Reliability**

- **FIXED**: Automatic reconnection system now properly restores connections when network interruptions occur
- **FIXED**: Tab bar display no longer gets cut off on the last tab, ensuring all tabs remain fully visible and accessible

### 🔧 Under the Hood

- Improved error handling for database connection edge cases
- Enhanced connection state management for better reliability

## [0.0.1-beta.14] - 2025-01-17

### ✨ New Features

#### **Enhanced Table Interaction**

- **Right-click Context Menu** - Table rows now support right-click actions for quick access to row-specific operations
- **Multi-row Selection** - Select multiple rows simultaneously for batch operations and improved workflow efficiency

#### **Smart Connection Management**

- **Intelligent Tab Handling** - When opening a connection, Pluk now asks whether to create a new tab or use an existing connection tab, preventing accidental duplicate connections

### 🎨 UI Improvements

#### **Visual Polish**

- **Enhanced Light Theme** - Improved light mode with better contrast, readability, and visual consistency across all interface elements
- **Smoother Cell Selection** - More responsive and fluid cell selection animations for a polished user experience

### 🛠️ Bug Fixes & Improvements

#### **Database Operations**

- **FIXED**: Insert operations now work correctly even when tables contain no existing records
- **FIXED**: Neon database connections no longer fail due to TLS configuration errors, ensuring reliable PostgreSQL connectivity

#### **Connection Reliability**

- **FIXED**: Automatic reconnection system now properly restores connections when network interruptions occur
- **FIXED**: Tab bar display no longer gets cut off on the last tab, ensuring all tabs remain fully visible and accessible

### 🔧 Under the Hood

- Improved error handling for database connection edge cases
- Enhanced connection state management for better reliability
