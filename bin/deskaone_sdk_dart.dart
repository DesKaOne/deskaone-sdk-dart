import 'dart:io';

import 'package:deskaone_sdk/deskaone_sdk_dart.dart';

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
  print(response.headers);
  print(response.bodyAsString());
}
