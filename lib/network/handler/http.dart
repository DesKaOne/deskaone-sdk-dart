import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../proxy/proxy_config.dart';
import '../tcp_connection.dart';

const String httpUserAgent = 'DesKaOne/0.0.1';
const int maxHttpHeaderSize = 32 * 1024;

class HttpProxyException implements Exception {
  final String message;

  const HttpProxyException(this.message);

  @override
  String toString() => message;
}

class HttpTunnelConn implements TcpConnection {
  @override
  final Socket socket;

  final StreamController<Uint8List> _controller = StreamController<Uint8List>(
    sync: true,
  );

  late final StreamSubscription<Uint8List> _subscription;

  final Completer<_HttpHeaderReadResult> _headerCompleter =
      Completer<_HttpHeaderReadResult>();

  final List<int> _buffer = <int>[];

  Timer? _timer;
  bool _headerDone = false;
  bool _closed = false;

  HttpTunnelConn._(this.socket, {Duration? timeout}) {
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
        if (!_headerCompleter.isCompleted) {
          _headerCompleter.completeError(
            const HttpProxyException('HTTP CONNECT header read timed out'),
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
    if (_headerDone) {
      _controller.add(data);
      return;
    }

    _buffer.addAll(data);

    if (_buffer.length > maxHttpHeaderSize) {
      final err = const HttpProxyException(
        'HTTP CONNECT response header too large',
      );

      if (!_headerCompleter.isCompleted) {
        _headerCompleter.completeError(err);
      }

      destroy();
      return;
    }

    final index = _indexOfBytes(_buffer, const [13, 10, 13, 10]);
    if (index < 0) {
      return;
    }

    final headerEnd = index + 4;

    final headers = Uint8List.fromList(_buffer.sublist(0, headerEnd));
    final leftover = Uint8List.fromList(_buffer.sublist(headerEnd));

    _buffer.clear();
    _headerDone = true;
    _timer?.cancel();

    if (!_headerCompleter.isCompleted) {
      _headerCompleter.complete(
        _HttpHeaderReadResult(headers: headers, leftover: leftover),
      );
    }

    if (leftover.isNotEmpty) {
      _controller.add(leftover);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _timer?.cancel();

    if (!_headerCompleter.isCompleted) {
      _headerCompleter.completeError(error, stackTrace);
      return;
    }

    _controller.addError(error, stackTrace);
  }

  void _onDone() {
    _timer?.cancel();

    if (!_headerCompleter.isCompleted) {
      _headerCompleter.completeError(
        const HttpProxyException(
          'connection closed while reading HTTP CONNECT header',
        ),
      );
    }

    _controller.close();
  }

  Future<_HttpHeaderReadResult> get _readHeader {
    return _headerCompleter.future;
  }
}

class _HttpHeaderReadResult {
  final Uint8List headers;
  final Uint8List leftover;

  const _HttpHeaderReadResult({required this.headers, required this.leftover});
}

Future<HttpTunnelConn> httpHandlerConn({
  required Socket conn,
  required ProxyConfig proxyConfig,
  required String dstHost,
  required int dstPort,
  Duration timeout = Duration.zero,
}) async {
  final host = dstHost.trim();

  if (host.isEmpty) {
    throw const HttpProxyException('empty destination host');
  }

  if (dstPort <= 0 || dstPort > 65535) {
    throw HttpProxyException('invalid destination port: $dstPort');
  }

  final targetAddr = _joinHostPort(host, dstPort);

  final buffer = StringBuffer();

  buffer.write('CONNECT ');
  buffer.write(targetAddr);
  buffer.write(' HTTP/1.1\r\n');

  buffer.write('Host: ');
  buffer.write(targetAddr);
  buffer.write('\r\n');

  buffer.write('User-Agent: ');
  buffer.write(httpUserAgent);
  buffer.write('\r\n');

  buffer.write('Proxy-Connection: Keep-Alive\r\n');

  final username = proxyConfig.username;
  final password = proxyConfig.password;

  if (username != null && password != null) {
    final rawAuth = '$username:$password';
    final auth = base64.encode(utf8.encode(rawAuth));

    buffer.write('Proxy-Authorization: Basic ');
    buffer.write(auth);
    buffer.write('\r\n');
  }

  buffer.write('\r\n');

  final tunnel = HttpTunnelConn._(
    conn,
    timeout: timeout > Duration.zero ? timeout : null,
  );

  try {
    conn.add(utf8.encode(buffer.toString()));

    if (timeout > Duration.zero) {
      await conn.flush().timeout(timeout);
    } else {
      await conn.flush();
    }

    final result = await tunnel._readHeader;
    final headers = result.headers;

    final code = parseStatusCode(headers);
    if (code != 200) {
      final authHeader = findHeader(headers, 'Proxy-Authenticate');
      final msg = sanitizeHeaderForError(headers);

      await tunnel.close();

      if (authHeader.isNotEmpty) {
        throw HttpProxyException(
          'proxy refused CONNECT: status=$code '
          'authenticate="$authHeader" response="$msg"',
        );
      }

      throw HttpProxyException(
        'proxy refused CONNECT: status=$code response="$msg"',
      );
    }

    return tunnel;
  } catch (_) {
    tunnel.destroy();
    rethrow;
  }
}

int parseStatusCode(List<int> headers) {
  final text = latin1.decode(headers, allowInvalid: true);
  final lineEnd = text.indexOf('\r\n');

  final statusLine = lineEnd >= 0 ? text.substring(0, lineEnd) : text;
  final parts = statusLine.trim().split(RegExp(r'\s+'));

  if (parts.length < 2) {
    return -1;
  }

  return int.tryParse(parts[1]) ?? -1;
}

String findHeader(List<int> headers, String name) {
  final text = latin1.decode(headers, allowInvalid: true);
  final lines = text.split('\r\n');

  for (final line in lines) {
    if (line.isEmpty) continue;

    final index = line.indexOf(':');
    if (index <= 0) continue;

    final key = line.substring(0, index).trim();
    final value = line.substring(index + 1).trim();

    if (key.toLowerCase() == name.toLowerCase()) {
      return value;
    }
  }

  return '';
}

String sanitizeHeaderForError(List<int> headers) {
  var msg = latin1.decode(headers, allowInvalid: true);

  if (msg.length > 1024) {
    msg = '${msg.substring(0, 1024)}...[truncated]';
  }

  final lines = msg.split('\r\n');

  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();

    if (lower.startsWith('proxy-authorization:')) {
      lines[i] = 'Proxy-Authorization: [redacted]';
    }

    if (lower.startsWith('authorization:')) {
      lines[i] = 'Authorization: [redacted]';
    }
  }

  return lines.join('\r\n').trim();
}

String _joinHostPort(String host, int port) {
  final cleanHost = host.trim();

  if (cleanHost.startsWith('[') && cleanHost.endsWith(']')) {
    return '$cleanHost:$port';
  }

  if (cleanHost.contains(':')) {
    return '[$cleanHost]:$port';
  }

  return '$cleanHost:$port';
}

int _indexOfBytes(List<int> source, List<int> pattern) {
  if (pattern.isEmpty || source.length < pattern.length) {
    return -1;
  }

  for (var i = 0; i <= source.length - pattern.length; i++) {
    var matched = true;

    for (var j = 0; j < pattern.length; j++) {
      if (source[i + j] != pattern[j]) {
        matched = false;
        break;
      }
    }

    if (matched) {
      return i;
    }
  }

  return -1;
}
