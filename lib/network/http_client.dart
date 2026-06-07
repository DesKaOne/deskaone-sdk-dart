import 'dart:async';
import 'dart:convert';
import 'dart:io' hide HttpRequest, HttpResponse;
import 'dart:typed_data';

import '../proxy/proxy_config.dart';
import '../proxy/proxy_picker.dart';
import 'tcp_client.dart';
import 'tcp_connection.dart';

class HTTPClientException implements Exception {
  final String message;

  const HTTPClientException(this.message);

  @override
  String toString() => message;
}

class HttpResponse {
  final Uri uri;
  final String version;
  final int statusCode;
  final String reasonPhrase;
  final Map<String, List<String>> headers;
  final Uint8List body;

  const HttpResponse({
    required this.uri,
    required this.version,
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
  });

  bool get isSuccess {
    return statusCode >= 200 && statusCode < 300;
  }

  String? header(String name) {
    final values = headers[name.toLowerCase()];
    if (values == null || values.isEmpty) {
      return null;
    }

    return values.join(', ');
  }

  String bodyAsString({bool allowMalformed = true}) {
    return utf8.decode(body, allowMalformed: allowMalformed);
  }

  @override
  String toString() {
    return 'HTTP/$version $statusCode $reasonPhrase';
  }
}

class HTTPClient {
  final Duration timeout;

  final ProxyConfig? proxyConfig;
  final ProxyPicker? proxyPicker;

  final Object? sourceAddress;
  final int sourcePort;

  final SecurityContext? securityContext;
  final BadCertificateCallback? onBadCertificate;

  /// Karena client ini HTTP/1.1 manual, jangan isi h2.
  final List<String>? supportedProtocols;

  final String userAgent;
  final int maxResponseHeaderSize;
  final int maxRedirects;

  final Duration readTimeout;
  final int maxBodySize;

  const HTTPClient({
    this.timeout = const Duration(seconds: 30),
    this.proxyConfig,
    this.proxyPicker,
    this.sourceAddress,
    this.sourcePort = 0,
    this.securityContext,
    this.onBadCertificate,
    this.supportedProtocols = const ['http/1.1'],
    this.userAgent = 'DesKaOneDart/0.0.1',
    this.maxResponseHeaderSize = 32 * 1024,
    this.maxRedirects = 5,
    this.readTimeout = const Duration(seconds: 30),
    this.maxBodySize = 10 * 1024 * 1024,
  });

  Future<HttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    bool followRedirects = true,
  }) {
    return request(
      'GET',
      uri,
      headers: headers,
      followRedirects: followRedirects,
    );
  }

  Future<HttpResponse> delete(
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
    bool followRedirects = true,
  }) {
    return request(
      'DELETE',
      uri,
      headers: headers,
      body: body,
      followRedirects: followRedirects,
    );
  }

  Future<HttpResponse> post(
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
    bool followRedirects = true,
  }) {
    return request(
      'POST',
      uri,
      headers: headers,
      body: body,
      followRedirects: followRedirects,
    );
  }

  Future<HttpResponse> postString(
    Uri uri, {
    Map<String, String>? headers,
    required String body,
    Encoding encoding = utf8,
    bool followRedirects = true,
  }) {
    return request(
      'POST',
      uri,
      headers: {
        'Content-Type': 'text/plain; charset=${encoding.name}',
        ...?headers,
      },
      body: encoding.encode(body),
      followRedirects: followRedirects,
    );
  }

  Future<HttpResponse> postJson(
    Uri uri, {
    Map<String, String>? headers,
    required Object? body,
    Encoding encoding = utf8,
    bool followRedirects = true,
  }) {
    return request(
      'POST',
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8', ...?headers},
      body: encoding.encode(jsonEncode(body)),
      followRedirects: followRedirects,
    );
  }

  Future<HttpResponse> put(
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
    bool followRedirects = true,
  }) {
    return request(
      'PUT',
      uri,
      headers: headers,
      body: body,
      followRedirects: followRedirects,
    );
  }

  Future<HttpResponse> patch(
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
    bool followRedirects = true,
  }) {
    return request(
      'PATCH',
      uri,
      headers: headers,
      body: body,
      followRedirects: followRedirects,
    );
  }

  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
    bool followRedirects = true,
  }) {
    return _request(
      method.trim().toUpperCase(),
      uri,
      headers: headers,
      body: body,
      followRedirects: followRedirects,
      redirectCount: 0,
    );
  }

  Future<HttpResponse> _request(
    String method,
    Uri uri, {
    required Map<String, String>? headers,
    required List<int>? body,
    required bool followRedirects,
    required int redirectCount,
  }) async {
    final normalizedUri = _normalizeUri(uri);

    final response = await _requestOnce(
      method,
      normalizedUri,
      headers: headers,
      body: body,
    );

    if (!followRedirects) {
      return response;
    }

    if (!_isRedirectStatus(response.statusCode)) {
      return response;
    }

    if (redirectCount >= maxRedirects) {
      throw HTTPClientException('too many redirects: $redirectCount');
    }

    final location = response.header('location');
    if (location == null || location.trim().isEmpty) {
      return response;
    }

    final nextUri = normalizedUri.resolve(location.trim());

    var nextMethod = method;
    List<int>? nextBody = body;

    // Umumnya 303 mengubah request jadi GET.
    // Untuk 301/302, banyak client juga ubah POST jadi GET.
    if (response.statusCode == 303 ||
        ((response.statusCode == 301 || response.statusCode == 302) &&
            method == 'POST')) {
      nextMethod = 'GET';
      nextBody = null;
    }

    return _request(
      nextMethod,
      nextUri,
      headers: headers,
      body: nextBody,
      followRedirects: followRedirects,
      redirectCount: redirectCount + 1,
    );
  }

  Future<HttpResponse> _requestOnce(
    String method,
    Uri uri, {
    required Map<String, String>? headers,
    required List<int>? body,
  }) async {
    final scheme = uri.scheme.toLowerCase();
    final secure = scheme == 'https';

    if (scheme != 'http' && scheme != 'https') {
      throw HTTPClientException('unsupported scheme: ${uri.scheme}');
    }

    final host = uri.host.trim();
    if (host.isEmpty) {
      throw const HTTPClientException('empty uri host');
    }

    final port = _effectivePort(uri);

    final client = TCPClient(
      timeout: timeout,
      proxyConfig: proxyConfig,
      proxyPicker: proxyPicker,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      secure: secure,
      serverName: host,
      securityContext: securityContext,
      onBadCertificate: onBadCertificate,
      supportedProtocols: supportedProtocols,
    );

    final conn = await client.connect(host, port);

    try {
      final requestBytes = _buildRequestBytes(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
      );

      conn.add(requestBytes);
      await conn.flush();

      return await _readResponse(conn: conn, uri: uri, method: method);
    } finally {
      await conn.close();
    }
  }

  Uint8List _buildRequestBytes({
    required String method,
    required Uri uri,
    required Map<String, String>? headers,
    required List<int>? body,
  }) {
    final requestTarget = _requestTarget(uri);
    final bodyBytes = body == null ? null : Uint8List.fromList(body);

    final outHeaders = <String, String>{};

    void setDefault(String key, String value) {
      if (!_containsHeader(outHeaders, key)) {
        outHeaders[key] = value;
      }
    }

    if (headers != null) {
      for (final entry in headers.entries) {
        validateHeader(entry.key, entry.value);

        final key = entry.key.trim();
        if (key.isEmpty) continue;

        outHeaders[key] = entry.value;
      }
    }

    setDefault('Host', _hostHeader(uri));
    setDefault('User-Agent', userAgent);
    setDefault('Accept', '*/*');

    // Biar server/proxy tidak kirim gzip dulu.
    // Nanti kalau mau auto decompress, baru ubah ini.
    setDefault('Accept-Encoding', 'identity');

    // Simpel dan aman: satu request satu koneksi.
    setDefault('Connection', 'close');

    if (bodyBytes != null) {
      setDefault('Content-Length', bodyBytes.length.toString());
    }

    final builder = BytesBuilder(copy: false);

    builder.add(ascii.encode('$method $requestTarget HTTP/1.1\r\n'));

    for (final entry in outHeaders.entries) {
      builder.add(ascii.encode('${entry.key}: ${entry.value}\r\n'));
    }

    builder.add(ascii.encode('\r\n'));

    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      builder.add(bodyBytes);
    }

    return builder.takeBytes();
  }

  Future<HttpResponse> _readResponse({
    required TcpConnection conn,
    required Uri uri,
    required String method,
  }) async {
    final headerBuffer = <int>[];
    final bodyBuffer = <int>[];

    _ParsedHttpHead? head;

    final stream = readTimeout > Duration.zero
        ? conn.stream.timeout(
            readTimeout,
            onTimeout: (sink) {
              sink.addError(
                const HTTPClientException('HTTP response read timed out'),
              );
              sink.close();
            },
          )
        : conn.stream;

    await for (final data in stream) {
      if (head == null) {
        headerBuffer.addAll(data);

        if (headerBuffer.length > maxResponseHeaderSize) {
          throw const HTTPClientException('HTTP response header too large');
        }

        final idx = _indexOfBytes(headerBuffer, const [13, 10, 13, 10]);
        if (idx < 0) {
          continue;
        }

        final headerEnd = idx + 4;

        final headerBytes = Uint8List.fromList(
          headerBuffer.sublist(0, headerEnd),
        );

        bodyBuffer.addAll(headerBuffer.sublist(headerEnd));
        headerBuffer.clear();

        head = _parseHttpHead(headerBytes);

        if (_hasNoBody(method, head.statusCode)) {
          break;
        }

        final completeBody = _tryCompleteBody(
          headers: head.headers,
          bodyBuffer: bodyBuffer,
        );

        if (completeBody != null) {
          bodyBuffer
            ..clear()
            ..addAll(completeBody);
          break;
        }

        continue;
      }

      bodyBuffer.addAll(data);

      if (bodyBuffer.length > maxBodySize) {
        throw HTTPClientException(
          'HTTP response body too large: ${bodyBuffer.length}',
        );
      }

      final completeBody = _tryCompleteBody(
        headers: head.headers,
        bodyBuffer: bodyBuffer,
      );

      if (completeBody != null) {
        bodyBuffer
          ..clear()
          ..addAll(completeBody);
        break;
      }
    }

    if (head == null) {
      throw const HTTPClientException('empty HTTP response');
    }

    Uint8List finalBody;

    if (_hasNoBody(method, head.statusCode)) {
      finalBody = Uint8List(0);
    } else {
      final chunked = _isChunked(head.headers);
      if (chunked) {
        final decoded = _tryDecodeChunked(bodyBuffer);
        if (decoded == null) {
          throw const HTTPClientException('incomplete chunked HTTP response');
        }

        finalBody = decoded.body;
      } else {
        final contentLength = _contentLength(head.headers);
        if (contentLength != null) {
          if (bodyBuffer.length < contentLength) {
            throw HTTPClientException(
              'incomplete HTTP response body: '
              'got=${bodyBuffer.length} want=$contentLength',
            );
          }

          finalBody = Uint8List.fromList(bodyBuffer.sublist(0, contentLength));
        } else {
          // Tidak ada Content-Length dan bukan chunked.
          // Karena kita kirim Connection: close, body selesai saat stream close.
          finalBody = Uint8List.fromList(bodyBuffer);
        }
      }
    }

    return HttpResponse(
      uri: uri,
      version: head.version,
      statusCode: head.statusCode,
      reasonPhrase: head.reasonPhrase,
      headers: head.headers,
      body: finalBody,
    );
  }

  Uint8List? _tryCompleteBody({
    required Map<String, List<String>> headers,
    required List<int> bodyBuffer,
  }) {
    if (_isChunked(headers)) {
      final decoded = _tryDecodeChunked(bodyBuffer);
      return decoded?.body;
    }

    final contentLength = _contentLength(headers);
    if (contentLength != null && bodyBuffer.length >= contentLength) {
      return Uint8List.fromList(bodyBuffer.sublist(0, contentLength));
    }

    return null;
  }

  Uri _normalizeUri(Uri uri) {
    if (uri.scheme.isEmpty) {
      throw const HTTPClientException('uri scheme is required');
    }

    if (uri.host.isEmpty) {
      throw const HTTPClientException('uri host is required');
    }

    return uri;
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }

    switch (uri.scheme.toLowerCase()) {
      case 'http':
        return 80;
      case 'https':
        return 443;
      default:
        throw HTTPClientException('unsupported scheme: ${uri.scheme}');
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
        (uri.scheme == 'http' && port == 80) ||
        (uri.scheme == 'https' && port == 443);

    if (defaultPort) {
      return host;
    }

    return '$host:$port';
  }

  bool _containsHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();

    for (final key in headers.keys) {
      if (key.toLowerCase() == lower) {
        return true;
      }
    }

    return false;
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  bool _hasNoBody(String method, int statusCode) {
    if (method == 'HEAD') {
      return true;
    }

    if (statusCode >= 100 && statusCode < 200) {
      return true;
    }

    return statusCode == 204 || statusCode == 304;
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
    throw const HTTPClientException('empty HTTP status line');
  }

  final statusLine = lines.first.trim();
  final parts = statusLine.split(RegExp(r'\s+'));

  if (parts.length < 2) {
    throw HTTPClientException('invalid HTTP status line: $statusLine');
  }

  final versionRaw = parts[0];

  if (!versionRaw.startsWith('HTTP/')) {
    throw HTTPClientException('invalid HTTP version: $versionRaw');
  }

  final version = versionRaw.substring(5);
  final statusCode = int.tryParse(parts[1]);

  if (statusCode == null) {
    throw HTTPClientException('invalid HTTP status code: ${parts[1]}');
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
    version: version,
    statusCode: statusCode,
    reasonPhrase: reasonPhrase,
    headers: headers,
  );
}

bool _isChunked(Map<String, List<String>> headers) {
  final values = headers['transfer-encoding'];
  if (values == null) {
    return false;
  }

  for (final value in values) {
    final parts = value.toLowerCase().split(',');

    for (final part in parts) {
      if (part.trim() == 'chunked') {
        return true;
      }
    }
  }

  return false;
}

int? _contentLength(Map<String, List<String>> headers) {
  final values = headers['content-length'];
  if (values == null || values.isEmpty) {
    return null;
  }

  return int.tryParse(values.last.trim());
}

class _ChunkedDecodeResult {
  final Uint8List body;
  final int consumed;

  const _ChunkedDecodeResult({required this.body, required this.consumed});
}

_ChunkedDecodeResult? _tryDecodeChunked(List<int> input) {
  final out = BytesBuilder(copy: false);
  var offset = 0;

  while (true) {
    final lineEnd = _indexOfCrlf(input, offset);
    if (lineEnd < 0) {
      return null;
    }

    final line = ascii.decode(
      input.sublist(offset, lineEnd),
      allowInvalid: true,
    );

    final sizeText = line.split(';').first.trim();
    final size = int.tryParse(sizeText, radix: 16);

    if (size == null) {
      throw HTTPClientException('invalid chunk size: $sizeText');
    }

    offset = lineEnd + 2;

    if (size == 0) {
      // Setelah zero chunk, ada trailer headers yang diakhiri CRLF.
      if (input.length < offset + 2) {
        return null;
      }

      // Tidak ada trailer.
      if (input[offset] == 13 && input[offset + 1] == 10) {
        return _ChunkedDecodeResult(
          body: out.takeBytes(),
          consumed: offset + 2,
        );
      }

      final trailerEnd = _indexOfBytesFrom(input, const [
        13,
        10,
        13,
        10,
      ], offset);

      if (trailerEnd < 0) {
        return null;
      }

      return _ChunkedDecodeResult(
        body: out.takeBytes(),
        consumed: trailerEnd + 4,
      );
    }

    if (input.length < offset + size + 2) {
      return null;
    }

    out.add(input.sublist(offset, offset + size));

    offset += size;

    if (input[offset] != 13 || input[offset + 1] != 10) {
      throw const HTTPClientException('invalid chunk delimiter');
    }

    offset += 2;
  }
}

int _indexOfCrlf(List<int> source, int start) {
  for (var i = start; i < source.length - 1; i++) {
    if (source[i] == 13 && source[i + 1] == 10) {
      return i;
    }
  }

  return -1;
}

int _indexOfBytes(List<int> source, List<int> pattern) {
  return _indexOfBytesFrom(source, pattern, 0);
}

int _indexOfBytesFrom(List<int> source, List<int> pattern, int start) {
  if (pattern.isEmpty || source.length < pattern.length) {
    return -1;
  }

  for (var i = start; i <= source.length - pattern.length; i++) {
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

void validateHeader(String key, String value) {
  final k = key.trim();

  if (k.isEmpty) {
    throw const HTTPClientException('empty header name');
  }

  if (k.contains('\r') || k.contains('\n')) {
    throw HTTPClientException('invalid header name: $key');
  }

  if (value.contains('\r') || value.contains('\n')) {
    throw HTTPClientException('invalid header value for: $key');
  }
}
