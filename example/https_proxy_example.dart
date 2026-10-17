import 'dart:io';

import 'package:deskaone_sdk/deskaone_sdk_dart.dart';

Future<void> main() async {
  // Use environment variables for proxy credentials.
  final proxyUrl = Platform.environment['PROXY_URL'];
  if (proxyUrl == null || proxyUrl.isEmpty) {
    stderr.writeln('Set PROXY_URL=https://proxy.example.com:8443');
    exitCode = 2;
    return;
  }

  final proxy = ProxyConfig.fromUrlString(proxyUrl);
  final client = HTTPClient(
    proxyConfig: proxy,
    timeout: const Duration(seconds: 15),
  );

  // HTTPS proxies use verified TLS to the proxy, then HTTP CONNECT.
  // A plain HTTP target is supported here. Nested TLS (HTTPS target over
  // an HTTPS proxy) requires a separate TLS-over-TLS implementation.
  final response = await client.get(Uri.parse('http://example.com/'));
  print('Status: ${response.statusCode}');
  print(response.bodyAsString());
}
