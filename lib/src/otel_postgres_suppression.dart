// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

const Symbol _suppressKey = #otel_postgres_suppress;

/// Whether Postgres instrumentation is suppressed in the current [Zone].
///
/// `tracedPostgresCall` checks this and skips span creation when true.
bool postgresInstrumentationSuppressed() {
  return Zone.current[_suppressKey] == true;
}

/// Runs [body] in a [Zone] where Postgres instrumentation is suppressed:
/// no spans are created for traced calls made inside it.
T runWithoutPostgresInstrumentation<T>(T Function() body) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}

/// Async variant of [runWithoutPostgresInstrumentation]: awaited traced
/// calls inside [body] create no spans.
Future<T> runWithoutPostgresInstrumentationAsync<T>(
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}
