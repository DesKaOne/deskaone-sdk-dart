import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => setTermColorEnabled(true));

  test('disabled colors return raw text', () {
    setTermColorEnabled(false);

    expect(red('text'), 'text');
    expect(TermColor.rgb('text', 1, 2, 3), 'text');
    expect(style('text', const StyleOpt(bold: true)), 'text');
  });

  test('enabled colors wrap text with ansi codes', () {
    setTermColorEnabled(true);

    expect(green('ok'), '\x1B[32mok\x1B[0m');
    expect(xterm('ok', 34), '\x1B[38;5;34mok\x1B[0m');
    expect(rgb('ok', 1, 2, 3), '\x1B[38;2;1;2;3mok\x1B[0m');
    expect(style('ok', const StyleOpt(bold: true, underline: true)), '\x1B[1;4mok\x1B[0m');
  });
}
