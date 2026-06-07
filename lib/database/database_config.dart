enum DatabaseDialect { sqlite, postgres }

class DatabaseConfig {
  final DatabaseDialect dialect;
  final String database;
  final String? host;
  final int? port;
  final String? username;
  final String? password;
  final bool ssl;
  final String? url;
  final Map<String, String> options;

  const DatabaseConfig._({
    required this.dialect,
    required this.database,
    this.host,
    this.port,
    this.username,
    this.password,
    this.ssl = false,
    this.url,
    this.options = const <String, String>{},
  });

  factory DatabaseConfig.sqlite(String path) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    return DatabaseConfig._(dialect: DatabaseDialect.sqlite, database: path);
  }

  factory DatabaseConfig.postgres({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    required String password,
    bool ssl = false,
  }) {
    if (host.trim().isEmpty) {
      throw ArgumentError.value(host, 'host', 'must not be empty');
    }
    if (database.trim().isEmpty) {
      throw ArgumentError.value(database, 'database', 'must not be empty');
    }
    return DatabaseConfig._(
      dialect: DatabaseDialect.postgres,
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      ssl: ssl,
    );
  }

  factory DatabaseConfig.fromUrl(String url) {
    final uri = Uri.parse(url);
    final scheme = uri.scheme.toLowerCase();

    switch (scheme) {
      case 'sqlite':
        final path = uri.path.isEmpty
            ? uri.host
            : Uri.decodeComponent(uri.path);
        return DatabaseConfig._(
          dialect: DatabaseDialect.sqlite,
          database: path,
          url: url,
          options: Map<String, String>.from(uri.queryParameters),
        );
      case 'postgres':
      case 'postgresql':
        final sslMode = uri.queryParameters['sslmode'];
        return DatabaseConfig._(
          dialect: DatabaseDialect.postgres,
          host: uri.host.isEmpty ? 'localhost' : uri.host,
          port: uri.hasPort ? uri.port : 5432,
          database: uri.pathSegments.isEmpty
              ? 'postgres'
              : uri.pathSegments.last,
          username: uri.userInfo.isEmpty
              ? null
              : Uri.decodeComponent(uri.userInfo.split(':').first),
          password: _passwordFromUserInfo(uri.userInfo),
          ssl: sslMode == 'require' ||
              sslMode == 'verify-full' ||
              sslMode == 'verify-ca',
          url: url,
          options: Map<String, String>.from(uri.queryParameters),
        );
      default:
        throw FormatException(
          'unsupported database URL scheme: ${uri.scheme}',
          url,
        );
    }
  }
}

String? _passwordFromUserInfo(String userInfo) {
  if (userInfo.isEmpty || !userInfo.contains(':')) {
    return null;
  }
  return Uri.decodeComponent(userInfo.substring(userInfo.indexOf(':') + 1));
}
