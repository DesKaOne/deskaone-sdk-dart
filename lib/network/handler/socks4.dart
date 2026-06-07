import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../proxy/proxy_config.dart';
import '../tcp_connection.dart';

class Socks4Exception implements Exception {
  final String message;

  const Socks4Exception(this.message);

  @override
  String toString() => message;
}

class Socks4TunnelConn implements TcpConnection {
  @override
  final Socket socket;

  final StreamController<Uint8List> _controller = StreamController<Uint8List>(
    sync: true,
  );

  late final StreamSubscription<Uint8List> _subscription;

  final Completer<_Socks4ReplyReadResult> _replyCompleter =
      Completer<_Socks4ReplyReadResult>();

  final List<int> _buffer = <int>[];

  Timer? _timer;
  bool _replyDone = false;
  bool _closed = false;

  Socks4TunnelConn._(this.socket, {Duration? timeout}) {
    _start(timeout: timeout);
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
    _timer?.cancel();

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
    _timer?.cancel();

    _subscription.cancel();
    _controller.close();
    socket.destroy();
  }

  void _start({Duration? timeout}) {
    if (timeout != null && timeout > Duration.zero) {
      _timer = Timer(timeout, () {
        if (!_replyCompleter.isCompleted) {
          _replyCompleter.completeError(
            const Socks4Exception('SOCKS4 reply read timed out'),
          );
        }

        destroy();
      });
    }

    _subscription = socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onData(Uint8List data) {
    if (_replyDone) {
      _controller.add(data);
      return;
    }

    _buffer.addAll(data);

    if (_buffer.length < 8) {
      return;
    }

    final reply = Uint8List.fromList(_buffer.sublist(0, 8));
    final leftover = Uint8List.fromList(_buffer.sublist(8));

    _buffer.clear();
    _replyDone = true;
    _timer?.cancel();

    if (!_replyCompleter.isCompleted) {
      _replyCompleter.complete(
        _Socks4ReplyReadResult(reply: reply, leftover: leftover),
      );
    }

    if (leftover.isNotEmpty) {
      _controller.add(leftover);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _timer?.cancel();

    if (!_replyCompleter.isCompleted) {
      _replyCompleter.completeError(error, stackTrace);
      return;
    }

    _controller.addError(error, stackTrace);
  }

  void _onDone() {
    _timer?.cancel();

    if (!_replyCompleter.isCompleted) {
      _replyCompleter.completeError(
        const Socks4Exception('connection closed while reading SOCKS4 reply'),
      );
    }

    _controller.close();
  }

  Future<_Socks4ReplyReadResult> get _readReply {
    return _replyCompleter.future;
  }
}

class _Socks4ReplyReadResult {
  final Uint8List reply;
  final Uint8List leftover;

  const _Socks4ReplyReadResult({required this.reply, required this.leftover});
}

Future<Socks4TunnelConn> socks4HandlerConn({
  required Socket conn,
  required ProxyConfig proxyConfig,
  required String host,
  required int port,
  Duration timeout = Duration.zero,
}) async {
  final dstHost = host.trim();

  if (dstHost.isEmpty) {
    throw const Socks4Exception('empty destination host');
  }

  if (port <= 0 || port > 65535) {
    throw Socks4Exception('invalid destination port: $port');
  }

  final username = proxyConfig.username ?? '';

  if (username.contains('\x00')) {
    throw const Socks4Exception('socks4 userid contains null byte');
  }

  if (dstHost.contains('\x00')) {
    throw const Socks4Exception('socks4 host contains null byte');
  }

  final req = _buildSocks4ConnectRequest(
    host: dstHost,
    port: port,
    username: username,
  );

  final tunnel = Socks4TunnelConn._(
    conn,
    timeout: timeout > Duration.zero ? timeout : null,
  );

  try {
    conn.add(req);

    if (timeout > Duration.zero) {
      await conn.flush().timeout(timeout);
    } else {
      await conn.flush();
    }

    final result = await tunnel._readReply;
    final resp = result.reply;

    // SOCKS4 response:
    // VN should be 0x00
    // CD 0x5A means request granted.
    if (resp[0] != 0x00) {
      await tunnel.close();
      throw Socks4Exception('invalid socks4 response version: ${resp[0]}');
    }

    if (resp[1] != 0x5A) {
      await tunnel.close();
      throw Socks4Exception(
        'socks4 connect failed: ${socks4ReplyError(resp[1])}',
      );
    }

    return tunnel;
  } catch (_) {
    tunnel.destroy();
    rethrow;
  }
}

Uint8List _buildSocks4ConnectRequest({
  required String host,
  required int port,
  required String username,
}) {
  final builder = BytesBuilder(copy: false);

  // VN = 0x04, CD = 0x01 CONNECT.
  builder.addByte(0x04);
  builder.addByte(0x01);

  // DSTPORT, big endian.
  builder.addByte((port >> 8) & 0xff);
  builder.addByte(port & 0xff);

  final ip4 = _parseIPv4(host);

  if (ip4 != null) {
    // SOCKS4 IPv4 mode.
    builder.add(ip4);

    builder.add(username.codeUnits);
    builder.addByte(0x00);
  } else {
    // SOCKS4a domain mode.
    // DSTIP = 0.0.0.1
    builder.add(const [0x00, 0x00, 0x00, 0x01]);

    builder.add(username.codeUnits);
    builder.addByte(0x00);

    builder.add(host.codeUnits);
    builder.addByte(0x00);
  }

  return builder.takeBytes();
}

Uint8List? _parseIPv4(String host) {
  final address = InternetAddress.tryParse(host);

  if (address == null) {
    return null;
  }

  if (address.type != InternetAddressType.IPv4) {
    return null;
  }

  return Uint8List.fromList(address.rawAddress);
}

String socks4ReplyError(int code) {
  switch (code) {
    case 0x5B:
      return 'request rejected or failed';
    case 0x5C:
      return 'request failed because client is not running identd';
    case 0x5D:
      return 'request failed because client identd could not confirm userid';
    default:
      return 'unknown error code $code';
  }
}
