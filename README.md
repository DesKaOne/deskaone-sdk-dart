# DesKaOne SDK Dart

[Indonesian version: README_ID.md](README_ID.md)

DesKaOne SDK Dart is a dependency-light Dart package for opening direct or proxied TCP connections, then building HTTP and WebSocket clients on top of the same transport layer.

## Features

- `ProxyConfig` parser for proxy URLs such as HTTP, SOCKS4, and SOCKS5.
- `ProxyPicker` strategies: single proxy, random proxy, and round-robin proxy.
- `TCPClient` with direct and proxy connection support.
- HTTP proxy, SOCKS4, and SOCKS5 tunnel handlers.
- Automatic TLS upgrade with `SecureSocket.secure()` for HTTPS and WSS connections.
- Custom `HTTPClient` over `TCPClient`.
- Custom `WebSocketClient` over `TCPClient`.
- Lightweight utilities: `Debouncer`, `EventEmitter`, `TermColor`, `Logger`, `NetworkStream`, and `ReconnectWebSocketClient`.

## Installation / import

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  deskaone_sdk_dart: ^1.0.0
```

Import the SDK in your Dart code:

```dart
import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
```

## HTTP direct example

```dart
import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final client = HTTPClient(timeout: const Duration(seconds: 15));
  final response = await client.get(Uri.parse('https://api.ipify.org/'));

  print(response);
  print('Status code: ${response.statusCode}');
  print(response.headers);
  print(response.bodyAsString());
}
```

## HTTP over proxy example

```dart
import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final proxy = ProxyConfig.fromUrlString('http://<proxy-host>:8080');
  final client = HTTPClient(
    timeout: const Duration(seconds: 15),
    proxyConfig: proxy,
  );

  final response = await client.get(Uri.parse('http://example.com/'));

  print(response);
  print(response.headers);
  print(response.bodyAsString());
}
```

## HTTPS over proxy example

```dart
import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final proxy = ProxyConfig.fromUrlString('socks5://<proxy-host>:<proxy-port>');
  final client = HTTPClient(
    timeout: const Duration(seconds: 15),
    proxyConfig: proxy,
  );

  final response = await client.get(Uri.parse('https://api.ipify.org/'));

  print(response);
  print(response.headers);
  print(response.bodyAsString());
}
```

## WebSocket WSS example

```dart
import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final ws = await WebSocketClient.connect(
    Uri.parse('wss://ws.postman-echo.com/raw'),
    timeout: const Duration(seconds: 15),
    pingInterval: const Duration(seconds: 20),
  );

  final subscription = ws.messages.listen((message) {
    if (message.isText) {
      print('TEXT: ${message.text}');
    } else if (message.isBinary) {
      print('BINARY: ${message.data.length} bytes');
    } else if (message.isPing) {
      print('PING');
    } else if (message.isPong) {
      print('PONG');
    }
  });

  await ws.sendText('halo dari DesKaOne SDK Dart');
  await Future<void>.delayed(const Duration(seconds: 3));
  await ws.close(code: 1000);
  await subscription.cancel();
}
```

## WebSocket WSS over proxy example

```dart
import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final proxy = ProxyConfig.fromUrlString('socks5://<proxy-host>:<proxy-port>');
  final ws = await WebSocketClient.connect(
    Uri.parse('wss://ws.postman-echo.com/raw'),
    proxyConfig: proxy,
    timeout: const Duration(seconds: 15),
    pingInterval: const Duration(seconds: 20),
  );

  final subscription = ws.messages.listen((message) {
    if (message.isText) {
      print('TEXT: ${message.text}');
    } else if (message.isBinary) {
      print('BINARY: ${message.data.length} bytes');
    } else if (message.isPing) {
      print('PING');
    } else if (message.isPong) {
      print('PONG');
    }
  });

  await ws.sendText('halo dari DesKaOne SDK Dart');
  await Future<void>.delayed(const Duration(seconds: 3));
  await ws.close(code: 1000);
  await subscription.cancel();
}
```

## Utilities

The SDK also includes lightweight utility APIs ported from the Go SDK:

- `Debouncer` for delaying an action until calls have stopped for a configured duration.
- `EventEmitter<T, D, E>` for typed `on`, `once`, `off`, sync emit, and async emit workflows.
- `TermColor` helpers (`red`, `green`, `rgb`, `style`, and more) with `NO_COLOR` support.
- `Logger` for simple timestamped SDK logs with optional colors and emoji.
- `NetworkStream` for little-endian binary reads/writes over an in-memory buffer.
- `ReconnectWebSocketClient` for reconnecting an existing `WebSocketClient` automatically after unexpected disconnects.

```dart
final debouncer = Debouncer(const Duration(milliseconds: 250), () {
  print('search now');
});
debouncer.call();

final events = EventEmitter<String, int, void>();
events.once('ready', (value, _) => print('ready: $value'));
events.emit('ready', 1, null);

final stream = NetworkStream()..writeString('hello');
stream.setPosition(0);
print(stream.readString());
```

## SecureStorage

`SecureStorage` is an encrypted file-based key-value store. It serializes JSON, encrypts it with AES-CBC + PKCS7 padding, and verifies HMAC-SHA256 before decrypting. Read real keys from the environment; the exported `secureStorageDevKeyHex` is only for tests and examples.

```dart
final storage = SecureStorage(
  keyHex: Platform.environment['SECURE_STORAGE_KEY_HEX']!,
);
await storage.initialize();
await storage.setString('username', 'deskaone-user');
print(storage.getString('username'));
```

See `example/secure_storage_example.dart`.

## SQLite database

```dart
final db = Database.sqlite('example.db');
await db.open();
await db.execute('CREATE TABLE IF NOT EXISTS users (name TEXT)');
await db.execute('INSERT INTO users (name) VALUES (?)', ['Alice']);
print(await db.query('SELECT name FROM users'));
await db.close();
```

See `example/sqlite_database_example.dart`.

## PostgreSQL database

Use `Database.fromUrl()` with a `DATABASE_URL` environment variable. The public API accepts `?` placeholders; the PostgreSQL driver converts them to named parameters internally.

```dart
final db = Database.fromUrl(Platform.environment['DATABASE_URL']!);
await db.open();
print(await db.queryOne('SELECT 1 AS value'));
await db.close();
```

See `example/postgres_database_example.dart`.

## CI

GitHub Actions CI is configured in `.github/workflows/dart.yml` to run `dart pub get`, formatting checks, analysis, and tests on push and pull request.

## Security notes

- Do not hardcode keys, database URLs, proxy credentials, API keys, tokens, or passwords.
- Do not use `secureStorageDevKeyHex` in production.
- `SecureStorage(debug: true)` writes a plaintext JSON dump for debugging and can expose sensitive data.
- Prefer environment variables or a secret manager for `SECURE_STORAGE_KEY_HEX`, `DATABASE_URL`, and proxy URLs.

## Environment variable proxy URL

Use an environment variable instead of hardcoding proxy credentials in source files:

```bash
PROXY_URL=socks5://<proxy-host>:<proxy-port> dart run example/http_client_example.dart
```

```dart
import 'dart:io';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

void main() {
  final proxyUrl = Platform.environment['PROXY_URL'];
  final proxy = proxyUrl == null || proxyUrl.trim().isEmpty
      ? null
      : ProxyConfig.fromUrlString(proxyUrl);

  print(
    proxy == null ? 'Using direct connection' : 'Using proxy from PROXY_URL',
  );
}
```

## Security warning

Never hardcode proxy credentials, API keys, tokens, passwords, or secrets in source files. Use environment variables, a secure secret manager, or your deployment platform's secret storage instead.
