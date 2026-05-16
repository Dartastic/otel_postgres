// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
// `OTelSession`'s receiver is `postgres`'s `Session` type (the supertype
// for `Connection` / `TxSession`), but the OTel semconv API also exports
// a `Session` namespace. Prefix postgres so we can name both unambiguously.
import 'package:postgres/postgres.dart' as pg;

import 'otel_postgres_suppression.dart';

const _tracerName = 'otel_postgres';
const _dbSystem = 'postgresql';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Best-effort SQL operation extraction. Pulls the first word
/// (SELECT, INSERT, UPDATE, DELETE, BEGIN, COMMIT, ROLLBACK, etc.)
/// and uppercases it.
String? _extractOperation(String sql) {
  final trimmed = sql.trimLeft();
  if (trimmed.isEmpty) return null;
  // Strip any leading SQL comments (`--` or `/* */`).
  var s = trimmed;
  while (true) {
    if (s.startsWith('--')) {
      final nl = s.indexOf('\n');
      if (nl == -1) return null;
      s = s.substring(nl + 1).trimLeft();
    } else if (s.startsWith('/*')) {
      final end = s.indexOf('*/');
      if (end == -1) return null;
      s = s.substring(end + 2).trimLeft();
    } else {
      break;
    }
  }
  final match = RegExp(r'^([A-Za-z]+)').firstMatch(s);
  return match?.group(1)?.toUpperCase();
}

/// Best-effort table-name extraction from the SQL text.
///
/// Handles the common DML / DQL shapes:
/// - `SELECT ... FROM <table>`
/// - `INSERT INTO <table> ...`
/// - `UPDATE <table> SET ...`
/// - `DELETE FROM <table> ...`
///
/// Returns `null` for anything more exotic (CTEs, joins where the
/// first table isn't representative, DDL, etc.).
String? _extractTable(String sql) {
  final patterns = <RegExp>[
    RegExp(r'\bFROM\s+([a-zA-Z_][\w.]*)', caseSensitive: false),
    RegExp(r'\bINTO\s+([a-zA-Z_][\w.]*)', caseSensitive: false),
    RegExp(r'\bUPDATE\s+([a-zA-Z_][\w.]*)', caseSensitive: false),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(sql);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Builds the OTel attributes for a Postgres query span following
/// the semantic conventions for DB calls.
Attributes _attrs({
  required String sqlText,
  String? namespace,
  String? operationOverride,
  String? tableOverride,
}) {
  final operation = operationOverride ?? _extractOperation(sqlText);
  final table = tableOverride ?? _extractTable(sqlText);
  return OTel.attributesFromMap(<String, Object>{
    Database.dbSystem.key: _dbSystem,
    Database.dbSystemName.key: _dbSystem,
    if (operation != null) Database.dbOperation.key: operation,
    if (operation != null) Database.dbOperationName.key: operation,
    if (table != null) Database.dbCollectionName.key: table,
    if (namespace != null) Database.dbNamespace.key: namespace,
    Database.dbQueryText.key: sqlText,
  });
}

/// Runs [invoke] inside a CLIENT-kind span named
/// `postgresql <op> [<table>]` with `db.system=postgresql`,
/// `db.operation`, `db.collection.name`, and `db.query.text`.
///
/// The span is closed automatically. Exceptions are recorded with
/// `error.type`, `recordException`, and the span status is set to
/// `Error` before the exception is rethrown.
///
/// Pass [namespace] when you know the database / schema (it becomes
/// `db.namespace`). Pass [operationOverride] / [tableOverride] when
/// the SQL is non-trivial and best-effort extraction would mis-tag
/// the span.
Future<R> tracedPostgresCall<R>({
  required String sqlText,
  required Future<R> Function() invoke,
  String? namespace,
  String? operationOverride,
  String? tableOverride,
}) async {
  if (postgresInstrumentationSuppressed()) return invoke();
  final operation = operationOverride ?? _extractOperation(sqlText);
  final table = tableOverride ?? _extractTable(sqlText);
  // OTel stable semconv: span name is `{db.operation.name} {target}`
  // with no system prefix. `db.system.name=postgresql` carries the
  // system info; including it in the span name is redundant.
  final op = operation ?? 'query';
  final name = table != null ? '$op $table' : op;
  final span = _tracer().startSpan(
    name,
    kind: SpanKind.client,
    attributes: _attrs(
      sqlText: sqlText,
      namespace: namespace,
      operationOverride: operationOverride,
      tableOverride: tableOverride,
    ),
  );
  try {
    return await invoke();
  } catch (e, st) {
    span.addAttributes(
      OTel.attributes([
        OTel.attributeString(
          ErrorResource.errorType.key,
          e.runtimeType.toString(),
        ),
      ]),
    );
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Traced operations on `Session` (covers both top-level `Connection`
/// queries and `runTx` `TxSession` queries).
extension OTelSession on pg.Session {
  /// Traced `execute`. The SQL text is best-effort parsed for the
  /// operation and primary table; pass [operationOverride] /
  /// [tableOverride] if you want explicit control.
  Future<pg.Result> executeTraced(
    Object /* String | Sql */ query, {
    Object? parameters,
    bool ignoreRows = false,
    pg.QueryMode? queryMode,
    Duration? timeout,
    String? namespace,
    String? operationOverride,
    String? tableOverride,
  }) {
    final sqlText = _querySql(query);
    return tracedPostgresCall<pg.Result>(
      sqlText: sqlText,
      namespace: namespace,
      operationOverride: operationOverride,
      tableOverride: tableOverride,
      invoke: () => execute(
        query,
        parameters: parameters,
        ignoreRows: ignoreRows,
        queryMode: queryMode,
        timeout: timeout,
      ),
    );
  }
}

String _querySql(Object query) {
  if (query is String) return query;
  // Sql.toString() in package:postgres returns the underlying SQL text,
  // so this works for both String and Sql inputs. Any future Sql variant
  // can override toString to keep this stable.
  return query.toString();
}
