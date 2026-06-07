# DesKaOne SDK Dart

[English version: README.md](README.md)

DesKaOne SDK Dart adalah package Dart yang minim dependensi untuk membuka koneksi TCP secara langsung atau melalui proxy, lalu memakai transport yang sama untuk client HTTP dan WebSocket.

## Fitur

- Parser `ProxyConfig` untuk URL proxy seperti HTTP, SOCKS4, dan SOCKS5.
- Strategi `ProxyPicker`: satu proxy, proxy acak, dan round-robin.
- `TCPClient` dengan dukungan koneksi langsung dan koneksi melalui proxy.
- Handler tunnel untuk HTTP proxy, SOCKS4, dan SOCKS5.
- Upgrade TLS otomatis dengan `SecureSocket.secure()` untuk koneksi HTTPS dan WSS.
- `HTTPClient` kustom di atas `TCPClient`.
- `WebSocketClient` kustom di atas `TCPClient`.
- Utilitas ringan: `Debouncer`, `EventEmitter`, `TermColor`, `Logger`, `NetworkStream`, dan `ReconnectWebSocketClient`.

## Instalasi / import

Tambahkan package ini ke `pubspec.yaml`:

```yaml
dependencies:
  deskaone_sdk_dart: ^1.0.0
```

Import SDK di kode Dart Anda:

```dart
import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
```

## Contoh HTTP direct

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

## Contoh HTTP melalui proxy

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

## Contoh HTTPS melalui proxy

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

## Contoh WebSocket WSS

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

## Contoh WebSocket WSS melalui proxy

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

## Utilitas

SDK ini juga menyertakan API utilitas ringan yang di-port dari Go SDK:

- `Debouncer` untuk menunda aksi sampai pemanggilan berhenti selama durasi tertentu.
- `EventEmitter<T, D, E>` untuk workflow `on`, `once`, `off`, emit sinkron, dan emit asinkron yang typed.
- Helper `TermColor` (`red`, `green`, `rgb`, `style`, dan lainnya) dengan dukungan `NO_COLOR`.
- `Logger` untuk log sederhana dengan timestamp, warna opsional, dan emoji opsional.
- `NetworkStream` untuk baca/tulis binary little-endian di buffer memori.
- `ReconnectWebSocketClient` untuk otomatis reconnect pada `WebSocketClient` setelah disconnect yang tidak disengaja.

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

`SecureStorage` adalah key-value store berbasis file terenkripsi. Data JSON dienkripsi memakai AES-CBC + padding PKCS7 dan diverifikasi dengan HMAC-SHA256 sebelum didekripsi. Baca key asli dari environment; `secureStorageDevKeyHex` hanya untuk test dan contoh.

```dart
final storage = SecureStorage(
  keyHex: Platform.environment['SECURE_STORAGE_KEY_HEX']!,
);
await storage.initialize();
await storage.setString('username', 'deskaone-user');
print(storage.getString('username'));
```

Lihat `example/secure_storage_example.dart`.

## Database SQLite

```dart
final db = Database.sqlite('example.db');
await db.open();
await db.execute('CREATE TABLE IF NOT EXISTS users (name TEXT)');
await db.execute('INSERT INTO users (name) VALUES (?)', ['Alice']);
print(await db.query('SELECT name FROM users'));
await db.close();
```

Lihat `example/sqlite_database_example.dart`.

## Database PostgreSQL

Gunakan `Database.fromUrl()` dengan environment variable `DATABASE_URL`. API publik menerima placeholder `?`; driver PostgreSQL mengubahnya menjadi named parameter secara internal.

```dart
final db = Database.fromUrl(Platform.environment['DATABASE_URL']!);
await db.open();
print(await db.queryOne('SELECT 1 AS value'));
await db.close();
```

Lihat `example/postgres_database_example.dart`.

## CI

GitHub Actions CI dikonfigurasi di `.github/workflows/dart.yml` untuk menjalankan `dart pub get`, pemeriksaan format, analysis, dan test pada push dan pull request.

## Catatan keamanan

- Jangan hardcode key, URL database, kredensial proxy, API key, token, atau password.
- Jangan gunakan `secureStorageDevKeyHex` di production.
- `SecureStorage(debug: true)` menulis dump JSON plaintext untuk debugging dan dapat mengekspos data sensitif.
- Utamakan environment variable atau secret manager untuk `SECURE_STORAGE_KEY_HEX`, `DATABASE_URL`, dan URL proxy.

## Environment variable PROXY_URL

Gunakan environment variable agar kredensial proxy tidak ditulis langsung di source file:

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

## Peringatan keamanan

Jangan pernah menulis kredensial proxy, API key, token, password, atau secret langsung di source file. Gunakan environment variable, secret manager yang aman, atau penyimpanan secret dari platform deployment Anda.
