// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.
//
// These tests exercise the span/attribute machinery of
// `tracedPostgresCall` using a fake `invoke` callback — no real
// Postgres server is needed.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_postgres/otel_postgres.dart';
import 'package:test/test.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;
  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

Map<String, Object> _attrMap(Span span) => {
      for (final a in span.attributes.toList()) a.key: a.value,
    };

void main() {
  group('tracedPostgresCall', () {
    late _MemorySpanExporter exporter;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'otel_postgres-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
    });

    tearDown(() async {
      await OTel.shutdown();
      await OTel.reset();
    });

    test('SELECT names span "SELECT <table>" per OTel stable semconv',
        () async {
      await tracedPostgresCall<int>(
        sqlText: r'SELECT id, name FROM users WHERE id = $1',
        invoke: () async => 1,
      );
      expect(exporter.spans, hasLength(1));
      final span = exporter.spans.first;
      // OTel stable semconv: span name is `{db.operation.name} {target}`
      // with NO system prefix. `db.system.name=postgresql` carries the
      // system info; including it in the span name is redundant.
      expect(span.name, 'SELECT users');
      final attrs = _attrMap(span);
      expect(attrs['db.system'], 'postgresql');
      expect(attrs['db.operation'], 'SELECT');
      expect(attrs['db.collection.name'], 'users');
      expect(attrs['db.query.text'], contains('FROM users'));
    });

    test('INSERT extracts table from INTO', () async {
      await tracedPostgresCall<int>(
        sqlText: "INSERT INTO orders (sku, qty) VALUES ('a', 1)",
        invoke: () async => 1,
      );
      final attrs = _attrMap(exporter.spans.single);
      expect(attrs['db.operation'], 'INSERT');
      expect(attrs['db.collection.name'], 'orders');
    });

    test('UPDATE extracts table', () async {
      await tracedPostgresCall<int>(
        sqlText: r'UPDATE users SET name = $1 WHERE id = $2',
        invoke: () async => 1,
      );
      final attrs = _attrMap(exporter.spans.single);
      expect(attrs['db.operation'], 'UPDATE');
      expect(attrs['db.collection.name'], 'users');
    });

    test('namespace becomes db.namespace', () async {
      await tracedPostgresCall<int>(
        sqlText: 'SELECT 1',
        namespace: 'shop',
        invoke: () async => 1,
      );
      final attrs = _attrMap(exporter.spans.single);
      expect(attrs['db.namespace'], 'shop');
    });

    test('span name drops target when no table can be extracted', () async {
      // `SELECT 1` has no FROM/INTO/UPDATE target — span name should
      // be just the operation, with NO trailing system or namespace.
      await tracedPostgresCall<int>(
        sqlText: 'SELECT 1',
        invoke: () async => 1,
      );
      expect(exporter.spans.single.name, 'SELECT');
    });

    test('records exception and sets error status on throw', () async {
      await expectLater(
        tracedPostgresCall<int>(
          sqlText: 'SELECT 1',
          invoke: () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      final span = exporter.spans.single;
      expect(span.status, SpanStatusCode.Error);
      final attrs = _attrMap(span);
      expect(attrs['error.type'], 'StateError');
    });

    test('zone-scoped suppression skips span creation', () async {
      await runWithoutPostgresInstrumentationAsync(() async {
        await tracedPostgresCall<int>(
          sqlText: 'SELECT 1',
          invoke: () async => 1,
        );
      });
      expect(exporter.spans, isEmpty);
    });

    test('SQL with leading comments still extracts operation', () async {
      await tracedPostgresCall<int>(
        sqlText: '-- migration step\nSELECT count(*) FROM widgets',
        invoke: () async => 1,
      );
      final attrs = _attrMap(exporter.spans.single);
      expect(attrs['db.operation'], 'SELECT');
      expect(attrs['db.collection.name'], 'widgets');
    });
  });
}
