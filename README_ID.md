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
  final proxy = ProxyConfig.fromUrlString('http://proxy.example.com:8080');
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
  final proxy = ProxyConfig.fromUrlString('socks5://user:pass@host:port');
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
  final proxy = ProxyConfig.fromUrlString('socks5://user:pass@host:port');
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

## Environment variable PROXY_URL

Gunakan environment variable agar kredensial proxy tidak ditulis langsung di source file:

```bash
PROXY_URL=socks5://user:pass@host:port dart run example/http_client_example.dart
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
