import 'proxy_type.dart';

class ProxyConfig {
  final ProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;

  ProxyConfig({
    required this.type,
    required this.host,
    required this.port,
    this.username,
    this.password,
  }) {
    if (host == '') {
      throw FormatException('proxy host cannot be empty');
    }

    if (port <= 0 || port > 65535) {
      throw FormatException('invalid proxy port: $port');
    }
  }

  factory ProxyConfig.fromUrl(Uri uri) {
    if (!uri.hasAuthority) {
      throw FormatException('invalid proxy uri: $uri');
    }

    if (uri.host.trim().isEmpty) {
      throw FormatException('proxy host cannot be empty: $uri');
    }

    if (!uri.hasPort) {
      throw FormatException('proxy port is required: $uri');
    }

    final auth = _parseUserInfo(uri.userInfo);

    return ProxyConfig(
      type: ProxyType.fromString(uri.scheme),
      host: uri.host,
      port: uri.port,
      username: auth.username,
      password: auth.password,
    );
  }

  factory ProxyConfig.fromUrlString(
    String url, {
    ProxyType defaultType = ProxyType.http,
  }) {
    final raw = url.trim();

    if (raw.isEmpty) {
      throw const FormatException('proxy url cannot be empty');
    }

    // Support:
    // - http://host:port
    // - socks5://user:pass@host:port
    // - host:port
    // - user:pass@host:port
    final normalized = raw.contains('://')
        ? raw
        : '${defaultType.value}://$raw';

    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      throw FormatException('invalid proxy configuration: $url');
    }

    return ProxyConfig.fromUrl(uri);
  }

  Uri get toUri {
    return Uri(
      scheme: type.value,
      userInfo: _buildUserInfo(),
      host: host,
      port: port,
    );
  }

  ProxyConfig copyWith({
    ProxyType? type,
    String? host,
    int? port,
    String? username,
    String? password,
  }) {
    return ProxyConfig(
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  @override
  String toString() {
    return toUri.toString();
  }

  static ({String? username, String? password}) _parseUserInfo(
    String userInfo,
  ) {
    if (userInfo.isEmpty) {
      return (username: null, password: null);
    }

    final separatorIndex = userInfo.indexOf(':');

    if (separatorIndex < 0) {
      return (username: Uri.decodeComponent(userInfo), password: null);
    }

    final username = userInfo.substring(0, separatorIndex);
    final password = userInfo.substring(separatorIndex + 1);

    return (
      username: username.isEmpty ? null : Uri.decodeComponent(username),
      password: password.isEmpty ? null : Uri.decodeComponent(password),
    );
  }

  String _buildUserInfo() {
    if (username == null && password == null) {
      return '';
    }

    final encodedUsername = Uri.encodeComponent(username ?? '');
    final encodedPassword = Uri.encodeComponent(password ?? '');

    if (password == null) {
      return encodedUsername;
    }

    return '$encodedUsername:$encodedPassword';
  }
}
