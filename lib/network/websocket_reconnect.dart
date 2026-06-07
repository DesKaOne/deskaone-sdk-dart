import 'dart:async';
import 'dart:io';

import '../proxy/proxy_config.dart';
import '../proxy/proxy_picker.dart';
import 'tcp_client.dart';
import 'websocket_client.dart';

/// A reconnecting wrapper around [WebSocketClient].
///
/// [maxReconnects] limits consecutive reconnect failures. A successful
/// connection resets the failure count, so long-lived clients can recover from
/// later independent outages. Set [maxReconnects] to `-1` for unlimited retries.
class ReconnectWebSocketClient {
  final Uri uri;
  final Map<String, String>? headers;
  final List<String>? protocols;
  final Duration timeout;
  final ProxyConfig? proxyConfig;
  final ProxyPicker? proxyPicker;
  final Object? sourceAddress;
  final int sourcePort;
  final String? serverName;
  final SecurityContext? securityContext;
  final BadCertificateCallback? onBadCertificate;
  final List<String>? supportedProtocols;
  final String userAgent;
  final int maxHeaderSize;
  final int maxPayloadSize;
  final bool autoPong;
  final Duration? pingInterval;
  final Duration reconnectDelay;
  final int maxReconnects;

  final void Function(WebSocketClient client)? onConnect;
  final void Function(WebSocketMessage message)? onMessage;
  final void Function(Object error, StackTrace? stackTrace)? onError;
  final void Function(Object? error)? onDisconnect;

  bool _running = false;
  bool _stopping = false;
  WebSocketClient? _current;
  Future<void>? _runFuture;
  StreamSubscription<WebSocketMessage>? _messageSubscription;

  ReconnectWebSocketClient(
    this.uri, {
    this.headers,
    this.protocols,
    this.timeout = const Duration(seconds: 30),
    this.proxyConfig,
    this.proxyPicker,
    this.sourceAddress,
    this.sourcePort = 0,
    this.serverName,
    this.securityContext,
    this.onBadCertificate,
    this.supportedProtocols = const ['http/1.1'],
    this.userAgent = 'DesKaOneDart/0.0.1',
    this.maxHeaderSize = 32 * 1024,
    this.maxPayloadSize = 16 * 1024 * 1024,
    this.autoPong = true,
    this.pingInterval,
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxReconnects = -1,
    this.onConnect,
    this.onMessage,
    this.onError,
    this.onDisconnect,
  });

  WebSocketClient? get current => _current;
  bool get isRunning => _running;

  Future<void> run() {
    if (_runFuture != null) {
      return _runFuture!;
    }

    _stopping = false;
    _running = true;
    _runFuture = _runLoop().whenComplete(() {
      _running = false;
      _runFuture = null;
    });
    return _runFuture!;
  }

  Future<void> stop() async {
    _stopping = true;
    await _messageSubscription?.cancel();
    _messageSubscription = null;

    final client = _current;
    _current = null;
    if (client != null) {
      await client.close();
    }

    await _runFuture;
  }

  Future<void> sendText(String text) async {
    final client = _requireCurrent();
    await client.sendText(text);
  }

  Future<void> sendJson(Object? value) async {
    final client = _requireCurrent();
    await client.sendJson(value);
  }

  Future<void> sendBinary(List<int> data) async {
    final client = _requireCurrent();
    await client.sendBinary(data);
  }

  Future<void> close() => stop();

  Future<void> _runLoop() async {
    var reconnectFailures = 0;
    var firstAttempt = true;

    while (!_stopping) {
      if (!firstAttempt) {
        await Future<void>.delayed(reconnectDelay);
        if (_stopping) {
          break;
        }
      }
      firstAttempt = false;

      Object? disconnectError;

      try {
        final client = await WebSocketClient.connect(
          uri,
          headers: headers,
          protocols: protocols,
          timeout: timeout,
          proxyConfig: proxyConfig,
          proxyPicker: proxyPicker,
          sourceAddress: sourceAddress,
          sourcePort: sourcePort,
          serverName: serverName,
          securityContext: securityContext,
          onBadCertificate: onBadCertificate,
          supportedProtocols: supportedProtocols,
          userAgent: userAgent,
          maxHeaderSize: maxHeaderSize,
          maxPayloadSize: maxPayloadSize,
          autoPong: autoPong,
          pingInterval: pingInterval,
        );

        if (_stopping) {
          await client.close();
          break;
        }

        reconnectFailures = 0;
        _current = client;
        onConnect?.call(client);

        _messageSubscription = client.messages.listen(
          onMessage,
          onError: (Object error, StackTrace stackTrace) {
            disconnectError = error;
            onError?.call(error, stackTrace);
          },
          cancelOnError: false,
        );

        await client.done;
        await _messageSubscription?.cancel();
        _messageSubscription = null;

        if (identical(_current, client)) {
          _current = null;
        }

        if (!_stopping) {
          onDisconnect?.call(disconnectError);
        }
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
        if (!_stopping) {
          onDisconnect?.call(error);
        }

        reconnectFailures++;
        if (maxReconnects >= 0 && reconnectFailures > maxReconnects) {
          break;
        }
      }
    }
  }

  WebSocketClient _requireCurrent() {
    final client = _current;
    if (client == null || !client.isOpen) {
      throw const WebSocketClientException('websocket is not connected');
    }
    return client;
  }
}
