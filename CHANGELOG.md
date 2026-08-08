# Changelog

## [0.2.0-wip]

### Changed

- Docs and tests now reference the current stable DB semconv keys
  (`db.system.name`, `db.operation.name`) instead of the deprecated
  `db.system` / `db.operation` forms the library had already stopped
  emitting.

### Added

- `example/otel_postgres_example.dart` — runnable example covering
  `executeTraced`, `tracedPostgresCall`, and zone-scoped suppression.
- Dartdoc for the suppression API.

## [0.1.0-beta.1] - 2026-05-16

### Changed

- Span name now follows OTel stable semconv: `{db.operation.name} {target}`
  (e.g. `SELECT users`) with no system prefix. Previously emitted
  `postgresql SELECT users` — the system is already in
  `db.system.name=postgresql`.

### Added

- `tracedPostgresCall<R>(...)` — wraps an arbitrary Postgres call in
  a CLIENT-kind span with OTel DB semantic conventions.
- `Session.executeTraced(...)` extension — drop-in replacement for
  `execute(...)` on `Connection` and `TxSession`.
- Best-effort SQL parsing for `db.operation` and `db.collection.name`
  (handles `SELECT … FROM`, `INSERT INTO …`, `UPDATE …`,
  `DELETE FROM …`; ignores leading `--` and `/* */` comments).
- `db.system=postgresql`, `db.namespace` (when provided),
  `db.query.text`.
- Error path records `error.type`, calls `recordException`, sets the
  span status to `Error` before rethrowing.
- Zone-scoped suppression via `runWithoutPostgresInstrumentation()` /
  `Async()`.
