import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('parses sqlite URL', () {
    final config = DatabaseConfig.fromUrl('sqlite:///tmp/example.db');

    expect(config.dialect, DatabaseDialect.sqlite);
    expect(config.database, '/tmp/example.db');
  });

  test('parses postgres URL', () {
    final user = 'db_user';
    final password = 'placeholder_password';
    final url = Uri(
      scheme: 'postgres',
      userInfo: '$user:$password',
      host: 'localhost',
      port: 5433,
      path: '/app_db',
      queryParameters: {'sslmode': 'require'},
    ).toString();

    final config = DatabaseConfig.fromUrl(url);

    expect(config.dialect, DatabaseDialect.postgres);
    expect(config.host, 'localhost');
    expect(config.port, 5433);
    expect(config.database, 'app_db');
    expect(config.username, 'db_user');
    expect(config.password, 'placeholder_password');
    expect(config.ssl, isTrue);
  });

  test('parses postgresql URL alias', () {
    final config = DatabaseConfig.fromUrl('postgresql://localhost/app_db');

    expect(config.dialect, DatabaseDialect.postgres);
    expect(config.host, 'localhost');
    expect(config.port, 5432);
    expect(config.database, 'app_db');
  });

  test('converts postgres placeholders while skipping literals and comments', () {
    final converted = convertQuestionMarksToPostgresPlaceholders(
      "SELECT '?' AS literal, col FROM t WHERE a = ? AND b = ? -- ?\n/* ? */",
    );

    expect(
      converted,
      "SELECT '?' AS literal, col FROM t WHERE a = @p1 AND b = @p2 -- ?\n/* ? */",
    );
  });
}
