import 'dart:io';

bool termColorEnabled = !Platform.environment.containsKey('NO_COLOR');

void setTermColorEnabled(bool value) {
  termColorEnabled = value;
}

class StyleOpt {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool dim;
  final bool inverse;
  final bool strike;

  const StyleOpt({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.dim = false,
    this.inverse = false,
    this.strike = false,
  });
}

class TermColor {
  static String red(Object value) => _wrap(value, const [31]);
  static String green(Object value) => _wrap(value, const [32]);
  static String yellow(Object value) => _wrap(value, const [33]);
  static String blue(Object value) => _wrap(value, const [34]);
  static String magenta(Object value) => _wrap(value, const [35]);
  static String cyan(Object value) => _wrap(value, const [36]);
  static String white(Object value) => _wrap(value, const [37]);
  static String gray(Object value) => _wrap(value, const [90]);

  static String xterm(Object value, int color) {
    if (color < 0 || color > 255) {
      throw RangeError.range(color, 0, 255, 'color');
    }
    return _wrap(value, [38, 5, color]);
  }

  static String rgb(Object value, int r, int g, int b) {
    RangeError.checkValueInInterval(r, 0, 255, 'r');
    RangeError.checkValueInInterval(g, 0, 255, 'g');
    RangeError.checkValueInInterval(b, 0, 255, 'b');
    return _wrap(value, [38, 2, r, g, b]);
  }

  static String style(Object value, StyleOpt options) {
    final codes = <int>[
      if (options.bold) 1,
      if (options.dim) 2,
      if (options.italic) 3,
      if (options.underline) 4,
      if (options.inverse) 7,
      if (options.strike) 9,
    ];
    return _wrap(value, codes);
  }

  static String _wrap(Object value, List<int> codes) {
    final text = value.toString();
    if (!termColorEnabled || codes.isEmpty) {
      return text;
    }
    return '\x1B[${codes.join(';')}m$text\x1B[0m';
  }
}

String red(Object value) => TermColor.red(value);
String green(Object value) => TermColor.green(value);
String yellow(Object value) => TermColor.yellow(value);
String blue(Object value) => TermColor.blue(value);
String magenta(Object value) => TermColor.magenta(value);
String cyan(Object value) => TermColor.cyan(value);
String white(Object value) => TermColor.white(value);
String gray(Object value) => TermColor.gray(value);
String xterm(Object value, int color) => TermColor.xterm(value, color);
String rgb(Object value, int r, int g, int b) => TermColor.rgb(value, r, g, b);
String style(Object value, StyleOpt options) => TermColor.style(value, options);
