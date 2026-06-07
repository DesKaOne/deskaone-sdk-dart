import 'dart:io';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final proxyUrl = Platform.environment['PROXY_URL'];
  final proxyConfig = proxyUrl == null || proxyUrl.trim().isEmpty
      ? null
      : ProxyConfig.fromUrlString(proxyUrl);

  final client = HTTPClient(
    timeout: const Duration(seconds: 15),
    proxyConfig: proxyConfig,
  );

  final response = await client.get(Uri.parse('https://api.ipify.org/'));

  print(response);
  print('Status code: ${response.statusCode}');
  print('Headers:');
  for (final entry in response.headers.entries) {
    print('${entry.key}: ${entry.value.join(', ')}');
  }
  print('Body:');
  print(response.bodyAsString());
}
