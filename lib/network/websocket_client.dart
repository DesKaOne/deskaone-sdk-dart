import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../proxy/proxy_config.dart';
import '../proxy/proxy_picker.dart';
import 'tcp_client.dart';
import 'tcp_connection.dart';

const String websocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

class WebSocketClientException implements Exception {
  final String message;

  const WebSocketClientException(this.message);

  @override
  String toString() => message;
}

class WebSocketOpcode {
  static const int continuation = 0x0;
  static const int text = 0x1;
  static const int binary = 0x2;
  static const int close = 0x8;
  static const int ping = 0x9;
  static const int pong = 0xA;
}

enum WebSocketReadyState { connecting, open, closing, closed }

class WebSocketMessage {
  final int opcode;
  final Uint8List data;

  const WebSocketMessage({required this.opcode, required this.data});

  bool get isText => opcode == WebSocketOpcode.text;
  bool get isBinary => opcode == WebSocketOpcode.binary;
  bool get isClose => opcode == WebSocketOpcode.close;
  bool get isPing => opcode == WebSocketOpcode.ping;
  bool get isPong => opcode == WebSocketOpcode.pong;

  String get text {
    return utf8.decode(data);
  }
}

class WebSocketClient {
  final Uri uri;
  final TcpConnection _conn;
  final int maxHeaderSize;
  final int maxPayloadSize;
  final bool autoPong;
  final Duration? pingInterval;

  final Random _rng = Random.secure();
  final List<int> _buffer = <int>[];

  final StreamController<WebSocketMessage> _messages =
      StreamController<WebSocketMessage>(sync: true);

  final Completer<void> _handshakeCompleter = Completer<void>();
  final Completer<void> _closedCompleter = Completer<void>();

  late final StreamSubscription<Uint8List> _subscription;

  bool _subscriptionCanceled = false;

  WebSocketReadyState _state = WebSocketReadyState.connecting;

  Timer? _pingTimer;

  int? _fragmentOpcode;
  BytesBuilder? _fragmentBuffer;

  String? _protocol;
  int? closeCode;
  String? closeReason;

  WebSocketClient._({
    required this.uri,
    required TcpConnection conn,
    required this.maxHeaderSize,
    required this.maxPayloadSize,
    required this.autoPong,
    required this.pingInterval,
  }) : _conn = conn;

  WebSocketReadyState get readyState => _state;

  bool get isOpen => _state == WebSocketReadyState.open;

  String? get protocol => _protocol;

  Stream<WebSocketMessage> get messages => _messages.stream;

  Future<void> get done => _closedCompleter.future;

  static Future<WebSocketClient> connect(
    Uri uri, {
    Map<String, String>? headers,
    List<String>? protocols,
    Duration timeout = const Duration(seconds: 30),
    ProxyConfig? proxyConfig,
    ProxyPicker? proxyPicker,
    Object? sourceAddress,
    int sourcePort = 0,
    String? serverName,
    SecurityContext? securityContext,
    BadCertificateCallback? onBadCertificate,
    List<String>? supportedProtocols = const ['http/1.1'],
    String userAgent = 'DesKaOneDart/0.0.1',
    int maxHeaderSize = 32 * 1024,
    int maxPayloadSize = 16 * 1024 * 1024,
    bool autoPong = true,
    Duration? pingInterval,
  }) async {
    final scheme = uri.scheme.toLowerCase();

    if (scheme != 'ws' && scheme != 'wss') {
      throw WebSocketClientException(
        'unsupported websocket scheme: ${uri.scheme}',
      );
    }

    if (uri.host.trim().isEmpty) {
      throw const WebSocketClientException('empty websocket host');
    }

    final secure = scheme == 'wss';
    final host = uri.host.trim();
    final port = _effectivePort(uri);

    final tcp = TCPClient(
      timeout: timeout,
      proxyConfig: proxyConfig,
      proxyPicker: proxyPicker,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      secure: secure,
      serverName: serverName ?? host,
      securityContext: securityContext,
      onBadCertificate: onBadCertificate,
      supportedProtocols: supportedProtocols,
    );

    final conn = await tcp.connect(host, port);

    final client = WebSocketClient._(
      uri: uri,
      conn: conn,
      maxHeaderSize: maxHeaderSize,
      maxPayloadSize: maxPayloadSize,
      autoPong: autoPong,
      pingInterval: pingInterval,
    );

    client._start();

    try {
      final key = _generateWebSocketKey();
      final request = _buildHandshakeRequest(
        uri: uri,
        key: key,
        headers: headers,
        protocols: protocols,
        userAgent: userAgent,
      );

      conn.add(request);
      await conn.flush();

      await client._handshakeCompleter.future.timeout(
        timeout,
        onTimeout: () {
          client.destroy();
          throw const WebSocketClientException('websocket handshake timed out');
        },
      );

      final expectedAccept = _webSocketAccept(key);
      client._validateAccept(expectedAccept);

      client._startPingTimer();

      return client;
    } catch (_) {
      client.destroy();
      rethrow;
    }
  }

  void _start() {
    _subscription = _conn.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onData(Uint8List data) {
    if (_state == WebSocketReadyState.closed) {
      return;
    }

    try {
      _buffer.addAll(data);

      if (_state == WebSocketReadyState.connecting) {
        _tryParseHandshake();
        return;
      }

      _parseFrames();
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _tryParseHandshake() {
    if (_buffer.length > maxHeaderSize) {
      throw const WebSocketClientException(
        'websocket handshake response header too large',
      );
    }

    final idx = _indexOfBytes(_buffer, const [13, 10, 13, 10]);
    if (idx < 0) {
      return;
    }

    final headerEnd = idx + 4;
    final headerBytes = Uint8List.fromList(_buffer.sublist(0, headerEnd));
    final leftover = _buffer.sublist(headerEnd);

    _buffer
      ..clear()
      ..addAll(leftover);

    final head = _parseHttpHead(headerBytes);

    if (head.statusCode != 101) {
      throw WebSocketClientException(
        'websocket upgrade failed: status=${head.statusCode} '
        'reason="${head.reasonPhrase}"',
      );
    }

    final upgrade = _firstHeader(head.headers, 'upgrade');
    if (upgrade == null || upgrade.toLowerCase() != 'websocket') {
      throw WebSocketClientException(
        'invalid websocket upgrade header: $upgrade',
      );
    }

    final connection = _firstHeader(head.headers, 'connection');
    if (connection == null || !_containsHeaderToken(connection, 'upgrade')) {
      throw WebSocketClientException(
        'invalid websocket connection header: $connection',
      );
    }

    final selectedProtocol = _firstHeader(
      head.headers,
      'sec-websocket-protocol',
    );

    if (selectedProtocol != null && selectedProtocol.trim().isNotEmpty) {
      _protocol = selectedProtocol.trim();
    }

    _serverAccept = _firstHeader(head.headers, 'sec-websocket-accept');

    _state = WebSocketReadyState.open;

    if (!_handshakeCompleter.isCompleted) {
      _handshakeCompleter.complete();
    }

    if (_buffer.isNotEmpty) {
      _parseFrames();
    }
  }

  String? _serverAccept;

  void _validateAccept(String expectedAccept) {
    final serverAccept = _serverAccept;

    if (serverAccept == null || serverAccept.trim().isEmpty) {
      throw const WebSocketClientException(
        'missing Sec-WebSocket-Accept header',
      );
    }

    if (serverAccept.trim() != expectedAccept) {
      throw WebSocketClientException(
        'invalid Sec-WebSocket-Accept: expected=$expectedAccept got=$serverAccept',
      );
    }
  }

  void _parseFrames() {
    while (true) {
      if (_buffer.length < 2) {
        return;
      }

      final b0 = _buffer[0];
      final b1 = _buffer[1];

      final fin = (b0 & 0x80) != 0;
      final rsv = b0 & 0x70;
      final opcode = b0 & 0x0f;

      if (rsv != 0) {
        throw WebSocketClientException('unsupported websocket RSV bits: $rsv');
      }

      final masked = (b1 & 0x80) != 0;
      var payloadLength = b1 & 0x7f;
      var offset = 2;

      if (payloadLength == 126) {
        if (_buffer.length < offset + 2) {
          return;
        }

        payloadLength = (_buffer[offset] << 8) | _buffer[offset + 1];
        offset += 2;
      } else if (payloadLength == 127) {
        if (_buffer.length < offset + 8) {
          return;
        }

        var len = 0;
        for (var i = 0; i < 8; i++) {
          len = (len << 8) | _buffer[offset + i];
        }

        payloadLength = len;
        offset += 8;
      }

      if (payloadLength > maxPayloadSize) {
        throw WebSocketClientException(
          'websocket payload too large: $payloadLength',
        );
      }

      List<int>? maskKey;

      if (masked) {
        if (_buffer.length < offset + 4) {
          return;
        }

        maskKey = _buffer.sublist(offset, offset + 4);
        offset += 4;
      }

      if (_buffer.length < offset + payloadLength) {
        return;
      }

      final payload = Uint8List.fromList(
        _buffer.sublist(offset, offset + payloadLength),
      );

      _buffer.removeRange(0, offset + payloadLength);

      if (maskKey != null) {
        for (var i = 0; i < payload.length; i++) {
          payload[i] ^= maskKey[i & 3];
        }
      }

      _handleFrame(fin: fin, opcode: opcode, payload: payload);
    }
  }

  void _handleFrame({
    required bool fin,
    required int opcode,
    required Uint8List payload,
  }) {
    final isControl = opcode >= 0x8;

    if (isControl) {
      if (!fin) {
        throw const WebSocketClientException(
          'fragmented websocket control frame',
        );
      }

      if (payload.length > 125) {
        throw const WebSocketClientException(
          'websocket control frame payload too large',
        );
      }

      switch (opcode) {
        case WebSocketOpcode.close:
          unawaited(_handleCloseFrame(payload));
          return;

        case WebSocketOpcode.ping:
          _messages.add(
            WebSocketMessage(opcode: WebSocketOpcode.ping, data: payload),
          );

          if (autoPong && _state == WebSocketReadyState.open) {
            unawaited(pong(payload));
          }

          return;

        case WebSocketOpcode.pong:
          _messages.add(
            WebSocketMessage(opcode: WebSocketOpcode.pong, data: payload),
          );
          return;

        default:
          throw WebSocketClientException(
            'unsupported websocket control opcode: $opcode',
          );
      }
    }

    switch (opcode) {
      case WebSocketOpcode.text:
      case WebSocketOpcode.binary:
        if (_fragmentOpcode != null) {
          throw const WebSocketClientException(
            'new websocket data frame while fragmented message is active',
          );
        }

        if (fin) {
          _messages.add(WebSocketMessage(opcode: opcode, data: payload));
          return;
        }

        _fragmentOpcode = opcode;
        _fragmentBuffer = BytesBuilder(copy: false);
        _fragmentBuffer!.add(payload);
        return;

      case WebSocketOpcode.continuation:
        final fragmentOpcode = _fragmentOpcode;
        final fragmentBuffer = _fragmentBuffer;

        if (fragmentOpcode == null || fragmentBuffer == null) {
          throw const WebSocketClientException(
            'websocket continuation frame without active fragment',
          );
        }

        fragmentBuffer.add(payload);

        if (!fin) {
          return;
        }

        final data = fragmentBuffer.takeBytes();

        _fragmentOpcode = null;
        _fragmentBuffer = null;

        _messages.add(WebSocketMessage(opcode: fragmentOpcode, data: data));
        return;

      default:
        throw WebSocketClientException(
          'unsupported websocket data opcode: $opcode',
        );
    }
  }

  Future<void> sendText(String text) {
    return _sendFrame(WebSocketOpcode.text, utf8.encode(text));
  }

  Future<void> sendJson(Object? value) {
    return sendText(jsonEncode(value));
  }

  Future<void> sendBinary(List<int> data) {
    return _sendFrame(WebSocketOpcode.binary, data);
  }

  Future<void> ping([List<int> payload = const <int>[]]) {
    if (payload.length > 125) {
      throw const WebSocketClientException('websocket ping payload too large');
    }

    return _sendFrame(WebSocketOpcode.ping, payload);
  }

  Future<void> pong([List<int> payload = const <int>[]]) {
    if (payload.length > 125) {
      throw const WebSocketClientException('websocket pong payload too large');
    }

    return _sendFrame(WebSocketOpcode.pong, payload);
  }

  Future<void> close({
    int code = 1000,
    String reason = '',
    Duration wait = const Duration(seconds: 1),
  }) async {
    if (_state == WebSocketReadyState.closed) {
      return;
    }

    if (_state == WebSocketReadyState.open) {
      _state = WebSocketReadyState.closing;

      final payload = _buildClosePayload(code, reason);
      await _sendFrame(WebSocketOpcode.close, payload, allowClosing: true);
    }

    if (wait > Duration.zero) {
      try {
        await _closedCompleter.future.timeout(wait);
        return;
      } catch (_) {
        // Force close below.
      }
    }

    await _finishClose(closeSocket: true);
  }

  void destroy() {
    if (_state == WebSocketReadyState.closed) {
      return;
    }

    _state = WebSocketReadyState.closed;
    _pingTimer?.cancel();

    _cancelSubscriptionUnawaited();

    try {
      _conn.destroy();
    } catch (_) {
      // Ignore destroy error.
    }

    if (!_messages.isClosed) {
      unawaited(_messages.close());
    }

    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }
  }

  Future<void> _sendFrame(
    int opcode,
    List<int> payload, {
    bool allowClosing = false,
  }) async {
    if (_state != WebSocketReadyState.open &&
        !(allowClosing && _state == WebSocketReadyState.closing)) {
      throw const WebSocketClientException('websocket is not open');
    }

    if (payload.length > maxPayloadSize) {
      throw WebSocketClientException(
        'websocket outgoing payload too large: ${payload.length}',
      );
    }

    final frame = _buildClientFrame(
      opcode: opcode,
      payload: payload,
      rng: _rng,
    );

    _conn.add(frame);
    await _conn.flush();
  }

  Future<void> _handleCloseFrame(Uint8List payload) async {
    if (payload.length >= 2) {
      closeCode = (payload[0] << 8) | payload[1];

      if (payload.length > 2) {
        closeReason = utf8.decode(payload.sublist(2), allowMalformed: true);
      } else {
        closeReason = '';
      }
    }

    if (_state == WebSocketReadyState.open) {
      _state = WebSocketReadyState.closing;

      try {
        await _sendFrame(WebSocketOpcode.close, payload, allowClosing: true);
      } catch (_) {
        // Ignore close reply error.
      }
    }

    await _finishClose(closeSocket: true);
  }

  Future<void> _finishClose({required bool closeSocket}) async {
    if (_state == WebSocketReadyState.closed) {
      return;
    }

    _state = WebSocketReadyState.closed;
    _pingTimer?.cancel();

    await _cancelSubscription();

    if (!_messages.isClosed) {
      await _messages.close();
    }

    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }

    if (closeSocket) {
      try {
        await _conn.close();
      } catch (_) {
        // Ignore close error.
      }
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _fail(error, stackTrace);
  }

  void _onDone() {
    _subscriptionCanceled = true;

    if (_state == WebSocketReadyState.closed) {
      return;
    }

    _state = WebSocketReadyState.closed;
    _pingTimer?.cancel();

    if (!_messages.isClosed) {
      unawaited(_messages.close());
    }

    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }

    if (!_handshakeCompleter.isCompleted) {
      _handshakeCompleter.completeError(
        const WebSocketClientException(
          'connection closed during websocket handshake',
        ),
      );
    }
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (!_handshakeCompleter.isCompleted) {
      _handshakeCompleter.completeError(error, stackTrace);
    }

    if (!_messages.isClosed) {
      _messages.addError(error, stackTrace);
    }

    destroy();
  }

  void _startPingTimer() {
    final interval = pingInterval;

    if (interval == null || interval <= Duration.zero) {
      return;
    }

    _pingTimer = Timer.periodic(interval, (_) {
      if (_state != WebSocketReadyState.open) {
        return;
      }

      unawaited(
        ping().catchError((_) {
          destroy();
        }),
      );
    });
  }

  Future<void> _cancelSubscription() async {
    if (_subscriptionCanceled) {
      return;
    }

    _subscriptionCanceled = true;

    try {
      await _subscription.cancel();
    } catch (_) {
      // Ignore cancel error.
    }
  }

  void _cancelSubscriptionUnawaited() {
    if (_subscriptionCanceled) {
      return;
    }

    _subscriptionCanceled = true;

    unawaited(
      _subscription.cancel().catchError((_) {
        // Ignore cancel error.
      }),
    );
  }
}

Uint8List _buildClientFrame({
  required int opcode,
  required List<int> payload,
  required Random rng,
}) {
  final payloadLength = payload.length;
  final maskKey = List<int>.generate(4, (_) => rng.nextInt(256));

  final builder = BytesBuilder(copy: false);

  builder.addByte(0x80 | (opcode & 0x0f));

  if (payloadLength < 126) {
    builder.addByte(0x80 | payloadLength);
  } else if (payloadLength <= 0xffff) {
    builder.addByte(0x80 | 126);
    builder.addByte((payloadLength >> 8) & 0xff);
    builder.addByte(payloadLength & 0xff);
  } else {
    builder.addByte(0x80 | 127);

    for (var i = 7; i >= 0; i--) {
      builder.addByte((payloadLength >> (8 * i)) & 0xff);
    }
  }

  builder.add(maskKey);

  final maskedPayload = Uint8List.fromList(payload);

  for (var i = 0; i < maskedPayload.length; i++) {
    maskedPayload[i] ^= maskKey[i & 3];
  }

  builder.add(maskedPayload);

  return builder.takeBytes();
}

Uint8List _buildClosePayload(int code, String reason) {
  if (code <= 0 || code > 65535) {
    throw WebSocketClientException('invalid websocket close code: $code');
  }

  final reasonBytes = utf8.encode(reason);

  if (reasonBytes.length > 123) {
    throw const WebSocketClientException('websocket close reason too long');
  }

  final builder = BytesBuilder(copy: false);

  builder.addByte((code >> 8) & 0xff);
  builder.addByte(code & 0xff);
  builder.add(reasonBytes);

  return builder.takeBytes();
}

Uint8List _buildHandshakeRequest({
  required Uri uri,
  required String key,
  required Map<String, String>? headers,
  required List<String>? protocols,
  required String userAgent,
}) {
  final outHeaders = <String, String>{};

  final reservedHeaders = <String>{
    'host',
    'upgrade',
    'connection',
    'sec-websocket-key',
    'sec-websocket-version',
    'sec-websocket-accept',
    'sec-websocket-extensions',
  };

  if (headers != null) {
    for (final entry in headers.entries) {
      _validateHeader(entry.key, entry.value);

      final name = entry.key.trim();
      final lower = name.toLowerCase();

      if (reservedHeaders.contains(lower)) {
        throw WebSocketClientException(
          'reserved websocket header cannot be overridden: $name',
        );
      }

      outHeaders[name] = entry.value;
    }
  }

  outHeaders['Host'] = _hostHeader(uri);
  outHeaders['Upgrade'] = 'websocket';
  outHeaders['Connection'] = 'Upgrade';
  outHeaders['Sec-WebSocket-Key'] = key;
  outHeaders['Sec-WebSocket-Version'] = '13';
  outHeaders['User-Agent'] = userAgent;

  if (protocols != null && protocols.isNotEmpty) {
    for (final protocol in protocols) {
      _validateHeader('Sec-WebSocket-Protocol', protocol);

      if (protocol.trim().isEmpty) {
        throw const WebSocketClientException('empty websocket subprotocol');
      }
    }

    outHeaders['Sec-WebSocket-Protocol'] = protocols.join(', ');
  }

  final builder = BytesBuilder(copy: false);

  builder.add(ascii.encode('GET ${_requestTarget(uri)} HTTP/1.1\r\n'));

  for (final entry in outHeaders.entries) {
    builder.add(ascii.encode('${entry.key}: ${entry.value}\r\n'));
  }

  builder.add(ascii.encode('\r\n'));

  return builder.takeBytes();
}

void _validateHeader(String key, String value) {
  final name = key.trim();

  if (name.isEmpty) {
    throw const WebSocketClientException('empty header name');
  }

  if (name.contains('\r') || name.contains('\n')) {
    throw WebSocketClientException('invalid header name: $key');
  }

  if (value.contains('\r') || value.contains('\n')) {
    throw WebSocketClientException('invalid header value for: $name');
  }
}

class _ParsedHttpHead {
  final String version;
  final int statusCode;
  final String reasonPhrase;
  final Map<String, List<String>> headers;

  const _ParsedHttpHead({
    required this.version,
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
  });
}

_ParsedHttpHead _parseHttpHead(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final lines = text.split('\r\n');

  if (lines.isEmpty || lines.first.trim().isEmpty) {
    throw const WebSocketClientException('empty websocket status line');
  }

  final statusLine = lines.first.trim();
  final parts = statusLine.split(RegExp(r'\s+'));

  if (parts.length < 2) {
    throw WebSocketClientException(
      'invalid websocket status line: $statusLine',
    );
  }

  final versionRaw = parts[0];

  if (!versionRaw.startsWith('HTTP/')) {
    throw WebSocketClientException(
      'invalid websocket HTTP version: $versionRaw',
    );
  }

  final statusCode = int.tryParse(parts[1]);

  if (statusCode == null) {
    throw WebSocketClientException(
      'invalid websocket status code: ${parts[1]}',
    );
  }

  final reasonPhrase = parts.length > 2
      ? statusLine
            .substring(statusLine.indexOf(parts[1]) + parts[1].length)
            .trim()
      : '';

  final headers = <String, List<String>>{};

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];

    if (line.isEmpty) {
      continue;
    }

    final index = line.indexOf(':');
    if (index <= 0) {
      continue;
    }

    final key = line.substring(0, index).trim().toLowerCase();
    final value = line.substring(index + 1).trim();

    headers.putIfAbsent(key, () => <String>[]).add(value);
  }

  return _ParsedHttpHead(
    version: versionRaw.substring(5),
    statusCode: statusCode,
    reasonPhrase: reasonPhrase,
    headers: headers,
  );
}

String? _firstHeader(Map<String, List<String>> headers, String name) {
  final values = headers[name.toLowerCase()];
  if (values == null || values.isEmpty) {
    return null;
  }

  return values.last;
}

bool _containsHeaderToken(String value, String token) {
  final target = token.toLowerCase();

  for (final part in value.split(',')) {
    if (part.trim().toLowerCase() == target) {
      return true;
    }
  }

  return false;
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }

  switch (uri.scheme.toLowerCase()) {
    case 'ws':
      return 80;
    case 'wss':
      return 443;
    default:
      throw WebSocketClientException(
        'unsupported websocket scheme: ${uri.scheme}',
      );
  }
}

String _requestTarget(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;

  if (uri.query.isEmpty) {
    return path;
  }

  return '$path?${uri.query}';
}

String _hostHeader(Uri uri) {
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final port = _effectivePort(uri);

  final defaultPort =
      (uri.scheme == 'ws' && port == 80) ||
      (uri.scheme == 'wss' && port == 443);

  if (defaultPort) {
    return host;
  }

  return '$host:$port';
}

String _generateWebSocketKey() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64.encode(bytes);
}

String _webSocketAccept(String key) {
  final input = ascii.encode('$key$websocketGuid');
  final digest = _sha1(input);
  return base64.encode(digest);
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

Uint8List _sha1(List<int> input) {
  final bytes = List<int>.from(input);
  final bitLength = bytes.length * 8;

  bytes.add(0x80);

  while ((bytes.length % 64) != 56) {
    bytes.add(0x00);
  }

  for (var i = 7; i >= 0; i--) {
    bytes.add((bitLength >> (8 * i)) & 0xff);
  }

  var h0 = 0x67452301;
  var h1 = 0xefcdab89;
  var h2 = 0x98badcfe;
  var h3 = 0x10325476;
  var h4 = 0xc3d2e1f0;

  for (var chunk = 0; chunk < bytes.length; chunk += 64) {
    final w = List<int>.filled(80, 0);

    for (var i = 0; i < 16; i++) {
      final j = chunk + i * 4;

      w[i] =
          ((bytes[j] << 24) |
              (bytes[j + 1] << 16) |
              (bytes[j + 2] << 8) |
              bytes[j + 3]) &
          0xffffffff;
    }

    for (var i = 16; i < 80; i++) {
      w[i] = _rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;

    for (var i = 0; i < 80; i++) {
      late final int f;
      late final int k;

      if (i < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5a827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }

      final temp = (_rotl32(a, 5) + f + e + k + w[i]) & 0xffffffff;

      e = d;
      d = c;
      c = _rotl32(b, 30);
      b = a;
      a = temp;
    }

    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
  }

  final out = BytesBuilder(copy: false);

  for (final h in [h0, h1, h2, h3, h4]) {
    out.addByte((h >> 24) & 0xff);
    out.addByte((h >> 16) & 0xff);
    out.addByte((h >> 8) & 0xff);
    out.addByte(h & 0xff);
  }

  return out.takeBytes();
}

int _rotl32(int value, int shift) {
  return ((value << shift) | (value >> (32 - shift))) & 0xffffffff;
}
