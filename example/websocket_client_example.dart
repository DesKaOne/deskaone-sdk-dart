import 'dart:async';
import 'dart:io';

import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final proxyUrl = Platform.environment['PROXY_URL'];
  final proxyConfig = proxyUrl == null || proxyUrl.trim().isEmpty
      ? null
      : ProxyConfig.fromUrlString(proxyUrl);

  WebSocketClient? ws;
  StreamSubscription<WebSocketMessage>? subscription;
  final firstMessage = Completer<void>();

  try {
    ws = await WebSocketClient.connect(
      Uri.parse('wss://ws.postman-echo.com/raw'),
      proxyConfig: proxyConfig,
      timeout: const Duration(seconds: 15),
      pingInterval: const Duration(seconds: 20),
    );

    print('websocket connected protocol=${ws.protocol}');

    subscription = ws.messages.listen(
      (message) {
        if (message.isText) {
          print('TEXT: ${message.text}');
          if (!firstMessage.isCompleted) {
            firstMessage.complete();
          }
        } else if (message.isBinary) {
          print('BINARY: ${message.data.length} bytes');
        } else if (message.isPing) {
          print('PING: ${message.data.length} bytes');
        } else if (message.isPong) {
          print('PONG: ${message.data.length} bytes');
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        print('websocket error: $error');
        if (!firstMessage.isCompleted) {
          firstMessage.completeError(error, stackTrace);
        }
      },
      onDone: () {
        print(
          'websocket closed code=${ws?.closeCode} reason=${ws?.closeReason}',
        );
        if (!firstMessage.isCompleted) {
          firstMessage.complete();
        }
      },
    );

    await ws.sendText('halo dari DesKaOne SDK Dart');
    await firstMessage.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('timed out waiting for websocket echo');
      },
    );

    await ws.close(code: 1000);
  } finally {
    await subscription?.cancel();

    if (ws != null && ws.readyState != WebSocketReadyState.closed) {
      await ws.close(code: 1000);
    }
  }
}
