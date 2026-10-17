import 'dart:convert';
import 'dart:io';

import 'package:deskaone_sdk/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('HTTPS proxy transport establishes TLS before CONNECT', () async {
    // Locally generated test-only certificate; no external endpoints.
    final temp = await Directory.systemTemp.createTemp('dart_tls_proxy_');
    try {
      final cert = File('${temp.path}/proxy.crt');
      final key = File('${temp.path}/proxy.key');
      ProcessResult openssl;
      try {
        openssl = await Process.run('openssl', [
          'req', '-x509', '-newkey', 'rsa:2048',
          '-keyout', key.path,
          '-out', cert.path,
          '-sha256', '-nodes', '-days', '2',
          '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
        ]);
      } on ProcessException {
        // Not every Dart installation includes OpenSSL.
        return;
      }
      if (openssl.exitCode != 0) {
        fail('cannot generate local certificate: ${openssl.stderr}');
      }

      final serverContext = SecurityContext()
        ..useCertificateChain(cert.path)
        ..usePrivateKey(key.path);
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      try {
        server.listen((socket) {
          final request = StringBuffer();
          socket.listen((data) {
            request.write(latin1.decode(data));
            if (request.toString().contains('\r\n\r\n')) {
              if (!request.toString().startsWith('CONNECT example.com:80')) {
                socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
              } else {
                socket.add(latin1.encode(
                  'HTTP/1.1 200 Connection Established\r\n\r\nhello',
                ));
              }
            }
          }, onError: (Object _) {});
        }, onError: (Object _) {});

        final cfg = ProxyConfig.fromUrlString(
          'https://127.0.0.1:${server.port}',
        );
        final roots = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates(cert.path);

        final client = TCPClient(
          proxyConfig: cfg,
          proxySecurityContext: roots,
          timeout: const Duration(seconds: 5),
        );
        final tunnel = await client.connect('example.com', 80);
        try {
          final data = await tunnel.stream.first.timeout(
            const Duration(seconds: 5),
          );
          expect(latin1.decode(data), 'hello');
        } finally {
          tunnel.destroy();
        }

        final untrusted = TCPClient(
          proxyConfig: cfg,
          timeout: const Duration(seconds: 5),
        );
        await expectLater(
          untrusted.connect('example.com', 80),
          throwsA(isA<Exception>()),
        );

        final tlsInTls = TCPClient(
          proxyConfig: cfg,
          secure: true,
        );
        await expectLater(
          tlsInTls.connect('example.com', 443),
          throwsA(isA<TcpClientException>()),
        );
      } finally {
        await server.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
