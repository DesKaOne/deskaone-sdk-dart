import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => setTermColorEnabled(true));

  test('format uses provided time and name prefix', () {
    setTermColorEnabled(false);
    final logger = Logger('sdk')
      ..useEmoji = false
      ..colorizeLevel = false;

    final line = logger.format(
      'info',
      'ready',
      now: DateTime(2024, 1, 2, 3, 4, 5),
    );

    expect(line, '03:04:05 | INFO | [sdk] ready');
  });

  test('format can omit name prefix and include emoji', () {
    setTermColorEnabled(false);
    final logger = Logger('sdk')
      ..includeNamePrefix = false
      ..colorizeLevel = false;

    expect(
      logger.format('success', 'done', now: DateTime(2024, 1, 2, 3, 4, 5)),
      '03:04:05 | ✅ SUCCESS | done',
    );
  });
}
