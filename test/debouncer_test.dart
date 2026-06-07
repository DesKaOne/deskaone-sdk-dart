import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('call resets the timer', () async {
    var count = 0;
    final debouncer = Debouncer(const Duration(milliseconds: 20), () => count++);

    debouncer.call();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    debouncer.call();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(count, 1);
    debouncer.dispose();
  });

  test('cancel prevents pending action', () async {
    var count = 0;
    final debouncer = Debouncer(const Duration(milliseconds: 10), () => count++);

    debouncer.call();
    debouncer.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(count, 0);
  });

  test('dispose prevents future scheduling', () async {
    var count = 0;
    final debouncer = Debouncer(const Duration(milliseconds: 10), () => count++);

    debouncer.dispose();
    debouncer.call();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(count, 0);
  });
}
