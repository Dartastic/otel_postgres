# otel_postgres

OpenTelemetry instrumentation for
[`package:postgres`](https://pub.dev/packages/postgres) (v3.x).

Wraps Postgres `execute` calls in `CLIENT`-kind spans following the
OTel DB semantic conventions — `db.system=postgresql`,
`db.operation`, `db.collection.name`, `db.namespace`, `db.query.text`,
plus error attributes when a query throws.

## Install

```yaml
dependencies:
  postgres: ^3.0.0
  otel_postgres: ^0.1.0-beta.1
```

## Use

### Drop-in extension

```dart
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_postgres/otel_postgres.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  await OTel.initialize(
    serviceName: 'my-app',
    endpoint: 'http://localhost:4317',
  );

  final conn = await Connection.open(
    Endpoint(
      host: 'localhost',
      database: 'shop',
      username: 'user',
      password: 'pass',
    ),
  );

  // Instead of `conn.execute(...)`, call `executeTraced(...)`.
  final result = await conn.executeTraced(
    Sql.named('SELECT id, name FROM users WHERE id = @id'),
    parameters: {'id': 42},
    namespace: 'shop',
  );
  print(result);
}
```

### Manual span around any block

```dart
final orderId = await tracedPostgresCall<int>(
  sqlText: 'INSERT INTO orders (sku, qty) VALUES (\$1, \$2) RETURNING id',
  namespace: 'shop',
  invoke: () async {
    final r = await conn.execute(
      r'INSERT INTO orders (sku, qty) VALUES ($1, $2) RETURNING id',
      parameters: ['SKU-1', 1],
    );
    return r.first[0] as int;
  },
);
```

## Span shape

| OTel attribute        | Source                                |
|-----------------------|---------------------------------------|
| `db.system`           | hardcoded `postgresql`                |
| `db.operation`        | first SQL keyword (e.g. `SELECT`)     |
| `db.collection.name`  | best-effort table extraction          |
| `db.namespace`        | optional `namespace:` argument        |
| `db.query.text`       | raw SQL text                          |
| `error.type`          | exception class name (on throw)       |

Override the extracted operation/table via `operationOverride` /
`tableOverride` if the parse mis-tags a complex statement.

## Suppression

```dart
await runWithoutPostgresInstrumentationAsync(() async {
  await conn.executeTraced('SELECT 1');  // skipped
});
```

## License

Apache 2.0 — copyright Mindful Software LLC.
