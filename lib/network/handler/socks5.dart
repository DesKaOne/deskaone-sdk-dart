import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../proxy/proxy_config.dart';
import '../tcp_connection.dart';

class Socks5Exception implements Exception {
  final String message;

  const Socks5Exception(this.message);

  @override
  String toString() => message;
}

class Socks5TunnelConn implements TcpConnection {
  @override
  final Socket socket;

  final StreamController<Uint8List> _controller = StreamController<Uint8List>(
    sync: true,
  );

  late final StreamSubscription<Uint8List> _subscription;

  final List<int> _buffer = <int>[];

  Completer<Uint8List>? _pendingCompleter;
  int _pendingLength = 0;

  bool _handshakeDone = false;
  bool _closed = false;

  Socks5TunnelConn._(this.socket) {
    _subscription = socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  Future<void> get done => socket.done;

  @override
  void add(List<int> data) {
    socket.add(data);
  }

  @override
  void write(String data) {
    socket.write(data);
  }

  @override
  Future<void> flush() {
    return socket.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;

    _closed = true;

    await _subscription.cancel();
    await _controller.close();

    try {
      await socket.close();
    } catch (_) {
      // Ignore close error.
    }
  }

  @override
  void destroy() {
    if (_closed) return;

    _closed = true;

    _subscription.cancel();
    _controller.close();
    socket.destroy();
  }

  Future<Uint8List> _readExact(
    int length, {
    Duration timeout = Duration.zero,
    String timeoutMessage = 'SOCKS5 read timed out',
  }) {
    if (_closed) {
      return Future.error(const Socks5Exception('connection already closed'));
    }

    if (length <= 0) {
      return Future.value(Uint8List(0));
    }

    if (_pendingCompleter != null) {
      return Future.error(
        const Socks5Exception('another SOCKS5 read is already pending'),
      );
    }

    final ready = _tryTake(length);
    if (ready != null) {
      return Future.value(ready);
    }

    final completer = Completer<Uint8List>();
    _pendingCompleter = completer;
    _pendingLength = length;

    var future = completer.future;

    if (timeout > Duration.zero) {
      future = future.timeout(
        timeout,
        onTimeout: () {
          _pendingCompleter = null;
          _pendingLength = 0;

          destroy();

          throw Socks5Exception(timeoutMessage);
        },
      );
    }

    return future;
  }

  Uint8List? _tryTake(int length) {
    if (_buffer.length < length) {
      return null;
    }

    final out = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);

    return out;
  }

  void _markHandshakeDone() {
    _handshakeDone = true;

    if (_buffer.isNotEmpty) {
      final leftover = Uint8List.fromList(_buffer);
      _buffer.clear();
      _controller.add(leftover);
    }
  }

  void _onData(Uint8List data) {
    if (_handshakeDone) {
      _controller.add(data);
      return;
    }

    _buffer.addAll(data);

    final completer = _pendingCompleter;
    if (completer == null) {
      return;
    }

    final out = _tryTake(_pendingLength);
    if (out == null) {
      return;
    }

    _pendingCompleter = null;
    _pendingLength = 0;

    if (!completer.isCompleted) {
      completer.complete(out);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    final completer = _pendingCompleter;

    if (completer != null && !completer.isCompleted) {
      _pendingCompleter = null;
      _pendingLength = 0;
      completer.completeError(error, stackTrace);
      return;
    }

    _controller.addError(error, stackTrace);
  }

  void _onDone() {
    final completer = _pendingCompleter;

    if (completer != null && !completer.isCompleted) {
      _pendingCompleter = null;
      _pendingLength = 0;

      completer.completeError(
        const Socks5Exception(
          'connection closed while reading SOCKS5 response',
        ),
      );
    }

    _controller.close();
  }
}

Future<Socks5TunnelConn> socks5HandlerConn({
  required Socket conn,
  required ProxyConfig proxyConfig,
  required String host,
  required int port,
  Duration timeout = Duration.zero,
}) async {
  final dstHost = host.trim();

  if (dstHost.isEmpty) {
    throw const Socks5Exception('empty destination host');
  }

  final hostBytes = utf8.encode(dstHost);
  if (hostBytes.length > 255) {
    throw const Socks5Exception('host too long');
  }

  if (port <= 0 || port > 65535) {
    throw Socks5Exception('invalid destination port: $port');
  }

  final username = proxyConfig.username;
  final password = proxyConfig.password;

  final methods = <int>[0x00];

  List<int>? usernameBytes;
  List<int>? passwordBytes;

  if (username != null && password != null) {
    usernameBytes = utf8.encode(username);
    passwordBytes = utf8.encode(password);

    if (usernameBytes.length > 255) {
      throw const Socks5Exception('socks username too long');
    }

    if (passwordBytes.length > 255) {
      throw const Socks5Exception('socks password too long');
    }

    methods.add(0x02);
  }

  final tunnel = Socks5TunnelConn._(conn);

  try {
    // Method negotiation:
    // VER, NMETHODS, METHODS...
    conn.add([0x05, methods.length, ...methods]);

    await _flushWithOptionalTimeout(conn, timeout);

    final methodResp = await tunnel._readExact(
      2,
      timeout: timeout,
      timeoutMessage: 'SOCKS5 method negotiation timed out',
    );

    if (methodResp[0] != 0x05) {
      throw Socks5Exception('invalid socks version: ${methodResp[0]}');
    }

    if (methodResp[1] == 0xff) {
      throw const Socks5Exception('socks method rejected');
    }

    if (methodResp[1] != 0x00 && methodResp[1] != 0x02) {
      throw Socks5Exception(
        'unsupported socks auth method selected: ${methodResp[1]}',
      );
    }

    if (methodResp[1] == 0x02) {
      if (usernameBytes == null || passwordBytes == null) {
        throw const Socks5Exception(
          'socks proxy requested auth but credentials are missing',
        );
      }

      final authBuilder = BytesBuilder(copy: false);

      authBuilder.addByte(0x01);
      authBuilder.addByte(usernameBytes.length);
      authBuilder.add(usernameBytes);
      authBuilder.addByte(passwordBytes.length);
      authBuilder.add(passwordBytes);

      conn.add(authBuilder.takeBytes());
      await _flushWithOptionalTimeout(conn, timeout);

      final authResp = await tunnel._readExact(
        2,
        timeout: timeout,
        timeoutMessage: 'SOCKS5 auth response timed out',
      );

      if (authResp[0] != 0x01 || authResp[1] != 0x00) {
        throw const Socks5Exception('socks auth failed');
      }
    }

    // CONNECT request:
    // VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT
    //
    // Ini mengikuti kode Go kamu:
    // selalu pakai ATYP = 0x03 alias domain.
    final reqBuilder = BytesBuilder(copy: false);

    reqBuilder.addByte(0x05);
    reqBuilder.addByte(0x01);
    reqBuilder.addByte(0x00);
    reqBuilder.addByte(0x03);
    reqBuilder.addByte(hostBytes.length);
    reqBuilder.add(hostBytes);

    // DST.PORT big endian.
    reqBuilder.addByte((port >> 8) & 0xff);
    reqBuilder.addByte(port & 0xff);

    conn.add(reqBuilder.takeBytes());
    await _flushWithOptionalTimeout(conn, timeout);

    final head = await tunnel._readExact(
      4,
      timeout: timeout,
      timeoutMessage: 'SOCKS5 connect response timed out',
    );

    if (head[0] != 0x05) {
      throw Socks5Exception('invalid socks response version: ${head[0]}');
    }

    if (head[1] != 0x00) {
      throw Socks5Exception(
        'socks connect failed: ${socks5ReplyError(head[1])}',
      );
    }

    if (head[2] != 0x00) {
      throw Socks5Exception('invalid socks reserved byte: ${head[2]}');
    }

    int skip;

    switch (head[3]) {
      case 0x01:
        // IPv4 address + port.
        skip = 4 + 2;
        break;

      case 0x04:
        // IPv6 address + port.
        skip = 16 + 2;
        break;

      case 0x03:
        // Domain length, domain, port.
        final len = await tunnel._readExact(
          1,
          timeout: timeout,
          timeoutMessage: 'SOCKS5 domain length read timed out',
        );

        skip = len[0] + 2;
        break;

      default:
        throw Socks5Exception('unsupported socks address type: ${head[3]}');
    }

    await tunnel._readExact(
      skip,
      timeout: timeout,
      timeoutMessage: 'SOCKS5 bound address read timed out',
    );

    tunnel._markHandshakeDone();

    return tunnel;
  } catch (_) {
    tunnel.destroy();
    rethrow;
  }
}

Future<void> _flushWithOptionalTimeout(Socket conn, Duration timeout) {
  if (timeout > Duration.zero) {
    return conn.flush().timeout(timeout);
  }

  return conn.flush();
}

String socks5ReplyError(int code) {
  switch (code) {
    case 0x01:
      return 'general SOCKS server failure';
    case 0x02:
      return 'connection not allowed by ruleset';
    case 0x03:
      return 'network unreachable';
    case 0x04:
      return 'host unreachable';
    case 0x05:
      return 'connection refused';
    case 0x06:
      return 'TTL expired';
    case 0x07:
      return 'command not supported';
    case 0x08:
      return 'address type not supported';
    default:
      return 'unknown error code $code';
  }
}
