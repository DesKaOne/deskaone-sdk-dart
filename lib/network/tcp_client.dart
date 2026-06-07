import 'dart:io';

import 'handler/http.dart';
import 'handler/socks4.dart';
import 'handler/socks5.dart';
import '../proxy/proxy_config.dart';
import '../proxy/proxy_picker.dart';
import '../proxy/proxy_type.dart';
import 'tcp_connection.dart';

class TcpClientException implements Exception {
  final String message;

  const TcpClientException(this.message);

  @override
  String toString() => message;
}

typedef BadCertificateCallback = bool Function(X509Certificate certificate);

class TCPClient {
  final Duration timeout;

  final ProxyConfig? proxyConfig;
  final ProxyPicker? proxyPicker;

  final Object? sourceAddress;
  final int sourcePort;

  /// Kalau true:
  /// - direct TCP akan di-upgrade dengan SecureSocket.secure()
  /// - proxy TCP akan handshake proxy dulu, lalu di-upgrade dengan SecureSocket.secure()
  final bool secure;

  /// Biasanya sama dengan host tujuan.
  /// Berguna kalau connect ke IP tapi TLS SNI/hostname beda.
  final String? serverName;

  final SecurityContext? securityContext;
  final BadCertificateCallback? onBadCertificate;
  final List<String>? supportedProtocols;

  const TCPClient({
    this.timeout = const Duration(seconds: 30),
    this.proxyConfig,
    this.proxyPicker,
    this.sourceAddress,
    this.sourcePort = 0,
    this.secure = false,
    this.serverName,
    this.securityContext,
    this.onBadCertificate,
    this.supportedProtocols,
  });

  Future<TcpConnection> connect(String host, int port) async {
    final dstHost = host.trim();

    if (dstHost.isEmpty) {
      throw const TcpClientException('empty destination host');
    }

    if (port <= 0 || port > 65535) {
      throw TcpClientException('invalid destination port: $port');
    }

    final proxy = _pickProxy();

    if (proxy == null) {
      return _connectDirect(dstHost, port);
    }

    return _connectViaProxy(proxy, dstHost, port);
  }

  ProxyConfig? _pickProxy() {
    if (proxyConfig != null) {
      return proxyConfig;
    }

    if (proxyPicker != null) {
      return proxyPicker!.pick();
    }

    return null;
  }

  Future<TcpConnection> _connectDirect(String host, int port) async {
    final socket = await Socket.connect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout > Duration.zero ? timeout : null,
    );
    _configureSocket(socket);

    if (!secure) {
      return DirectTcpConnection(socket);
    }

    return _secureSocket(socket: socket, host: host);
  }

  Future<TcpConnection> _connectViaProxy(
    ProxyConfig proxy,
    String dstHost,
    int dstPort,
  ) async {
    final rawSocket = await Socket.connect(
      proxy.host,
      proxy.port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout > Duration.zero ? timeout : null,
    );

    _configureSocket(rawSocket);

    try {
      final tunnel = await _proxyHandshake(
        rawSocket: rawSocket,
        proxy: proxy,
        dstHost: dstHost,
        dstPort: dstPort,
      );

      if (!secure) {
        return tunnel;
      }

      return _secureSocket(socket: tunnel.socket, host: dstHost);
    } catch (_) {
      rawSocket.destroy();
      rethrow;
    }
  }

  Future<TcpConnection> _proxyHandshake({
    required Socket rawSocket,
    required ProxyConfig proxy,
    required String dstHost,
    required int dstPort,
  }) {
    switch (proxy.type) {
      case ProxyType.http:
        return httpHandlerConn(
          conn: rawSocket,
          proxyConfig: proxy,
          dstHost: dstHost,
          dstPort: dstPort,
          timeout: timeout,
        );

      case ProxyType.socks4:
        return socks4HandlerConn(
          conn: rawSocket,
          proxyConfig: proxy,
          host: dstHost,
          port: dstPort,
          timeout: timeout,
        );

      case ProxyType.socks5:
        return socks5HandlerConn(
          conn: rawSocket,
          proxyConfig: proxy,
          host: dstHost,
          port: dstPort,
          timeout: timeout,
        );
    }
  }

  Future<TcpConnection> _secureSocket({
    required Socket socket,
    required String host,
  }) async {
    try {
      final secureSocket = await SecureSocket.secure(
        socket,
        host: serverName ?? host,
        context: securityContext,
        onBadCertificate: onBadCertificate,
        supportedProtocols: supportedProtocols,
      );

      return DirectTcpConnection(secureSocket);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  void _configureSocket(Socket socket) {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {
      // Ignore unsupported platform.
    }
  }
}
