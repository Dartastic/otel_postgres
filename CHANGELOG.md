# Changelog

## [0.3.1] - 2026-10-17

### Changed

- README: standard header naming the instrumented library, its supported platforms and project links; pubspec description to match.

## [0.3.0] - 2026-10-11

### Changed

- Requires `dartastic_opentelemetry_api >=1.0.0-rc.4 <1.0.0-rc.5`.
- **Breaking:** depends on `dartastic_opentelemetry_api` only, no
  longer on the SDK. The application chooses and initializes the
  OpenTelemetry SDK. Parameters and fields typed with SDK classes
  now use the API types (`APITracer`, `APISpan`, `APILogger`, ...);
  SDK instances are still accepted wherever an API type is expected.

## [0.2.0] - 2026-08-10

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
