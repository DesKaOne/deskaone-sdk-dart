import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';

Future<void> main() async {
  final client = ReconnectWebSocketClient(
    Uri.parse('wss://echo.websocket.events'),
    reconnectDelay: const Duration(seconds: 2),
    maxReconnects: -1,
    onConnect: (ws) async {
      print('connected');
      await ws.sendText('hello from reconnecting client');
    },
    onMessage: (message) {
      if (message.isText) {
        print('message: ${message.text}');
      }
    },
    onError: (error, stackTrace) {
      print('websocket error: $error');
    },
    onDisconnect: (error) {
      print('disconnected${error == null ? '' : ': $error'}');
    },
  );

  await client.run();
}
