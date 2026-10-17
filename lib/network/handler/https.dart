import 'dart:async';
import 'dart:io';

import '../../proxy/proxy_config.dart';
import '../tcp_connection.dart';
import 'http.dart';

/// HTTPS proxies negotiate TLS with the proxy *before* HTTP CONNECT.
///
/// The proxy's certificate is verified by default. Supply a trusted
/// [proxySecurityContext] for private certificate authorities.
Future<HttpTunnelConn> httpsHandlerConn({
  required Socket conn,
  required ProxyConfig proxyConfig,
  required String dstHost,
  required int dstPort,
  Duration timeout = Duration.zero,
  SecurityContext? proxySecurityContext,
  bool Function(X509Certificate certificate)? onBadProxyCertificate,
}) async {
  if (proxyConfig.host.trim().isEmpty) {
    throw const HttpProxyException('empty HTTPS proxy host');
  }

  SecureSocket? secureProxy;
  try {
    final handshake = SecureSocket.secure(
      conn,
      host: proxyConfig.host,
      context: proxySecurityContext,
      onBadCertificate: onBadProxyCertificate,
      supportedProtocols: const ['http/1.1'],
    );

    secureProxy = timeout > Duration.zero
        ? await handshake.timeout(timeout)
        : await handshake;

    return await httpHandlerConn(
      conn: secureProxy,
      proxyConfig: proxyConfig,
      dstHost: dstHost,
      dstPort: dstPort,
      timeout: timeout,
    );
  } catch (_) {
    secureProxy?.destroy();
    conn.destroy();
    rethrow;
  }
}
