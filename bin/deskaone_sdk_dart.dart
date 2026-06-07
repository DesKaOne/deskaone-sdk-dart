import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main(List<String> arguments) async {
  final proxyConfig = ProxyConfig.fromUrlString(
    "socks5://ugofubio-rotate:oyrjp9rfjv06@p.webshare.io:80",
  );

  /*final client = TCPClient(
    timeout: const Duration(seconds: 15),
    secure: true,
    proxyConfig: proxyConfig, // kosongkan untuk direct
  );

  final conn = await client.connect('api.ipify.org', 443);

  conn.write('GET / HTTP/1.1\r\n');
  conn.write('Host: api.ipify.org\r\n');
  conn.write('Connection: close\r\n');
  conn.write('\r\n');

  await conn.flush();

  conn.stream.listen(
    stdout.add,
    onError: (e) {
      print('\ntcp error: $e');
    },
    onDone: () async {
      print('\ntcp closed');
      await conn.close();
    },
  );*/

  /*final client = HTTPClient(
    timeout: const Duration(seconds: 15),
    proxyConfig: proxyConfig,
  );

  final res = await client.get(Uri.parse('https://api.ipify.org/'));

  print(res);
  print(res.headers);
  print(res.bodyAsString());*/

  final ws = await WebSocketClient.connect(
    Uri.parse('wss://echo.websocket.org'),
    proxyConfig: proxyConfig,
    timeout: const Duration(seconds: 15),
    pingInterval: const Duration(seconds: 20),
  );

  print('websocket connected protocol=${ws.protocol}');

  final sub = ws.messages.listen(
    (msg) {
      if (msg.isText) {
        print('TEXT: ${msg.text}');
      } else if (msg.isBinary) {
        print('BINARY: ${msg.data.length} bytes');
      } else if (msg.isPing) {
        print('PING');
      } else if (msg.isPong) {
        print('PONG');
      }
    },
    onError: (e) {
      print('ws error: $e');
    },
    onDone: () {
      print('ws closed code=${ws.closeCode} reason=${ws.closeReason}');
    },
  );

  await ws.sendText('halo dari DesKaOne SDK Dart');
  await Future<void>.delayed(const Duration(seconds: 3));

  await ws.close();
  await sub.cancel();
}
