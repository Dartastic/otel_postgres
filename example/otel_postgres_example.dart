// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.
//
// Demonstrates otel_postgres against a local Postgres server.
// Run a server first, e.g.:
//   docker run --rm -p 5432:5432 -e POSTGRES_PASSWORD=pass postgres:16

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_postgres/otel_postgres.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  // Spans export via OTLP (default http://localhost:4318).
  await OTel.initialize(serviceName: 'otel_postgres-example');

  final conn = await Connection.open(
    Endpoint(
      host: 'localhost',
      database: 'postgres',
      username: 'postgres',
      password: 'pass',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  // Drop-in traced replacement for `execute`. Emits a CLIENT span
  // named `SELECT` with db.system.name=postgresql,
  // db.operation.name=SELECT, db.query.text, etc.
  final result = await conn.executeTraced('SELECT 1 AS one');
  print('executeTraced -> ${result.first.first}');

  // Manual span around any block of Postgres work.
  final version = await tracedPostgresCall<String>(
    sqlText: 'SELECT version()',
    invoke: () async {
      final r = await conn.execute('SELECT version()');
      return r.first.first! as String;
    },
  );
  print('tracedPostgresCall -> $version');

  // Zone-scoped suppression: no spans inside this block.
  await runWithoutPostgresInstrumentationAsync(() async {
    await conn.executeTraced('SELECT 1'); // not traced
  });

  await conn.close();
  await OTel.shutdown();
}
