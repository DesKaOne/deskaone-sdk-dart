import 'dart:io';

import 'term_color.dart';

class Logger {
  String name;
  bool useEmoji;
  bool colorizeLevel;
  bool colorizeMessage;
  bool includeNamePrefix;

  Logger(this.name)
    : useEmoji = true,
      colorizeLevel = true,
      colorizeMessage = false,
      includeNamePrefix = true;

  void info(String message) => stdout.writeln(format('INFO', message));
  void warn(String message) => stdout.writeln(format('WARN', message));
  void error(String message) => stdout.writeln(format('ERROR', message));
  void success(String message) => stdout.writeln(format('SUCCESS', message));

  String format(String level, String message, {DateTime? now}) {
    final time = _formatTime(now ?? DateTime.now());
    final normalizedLevel = level.toUpperCase();
    var displayLevel = normalizedLevel;
    var displayMessage = message;

    if (useEmoji) {
      displayLevel = '${_emojiFor(normalizedLevel)} $displayLevel';
    }

    if (colorizeLevel) {
      displayLevel = _colorFor(normalizedLevel, displayLevel);
    }

    if (colorizeMessage) {
      displayMessage = _colorFor(normalizedLevel, displayMessage);
    }

    final prefix = includeNamePrefix && name.trim().isNotEmpty ? '[$name] ' : '';
    return '$time | $displayLevel | $prefix$displayMessage';
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  String _emojiFor(String level) {
    switch (level) {
      case 'INFO':
        return 'ℹ️';
      case 'WARN':
      case 'WARNING':
        return '⚠️';
      case 'ERROR':
        return '❌';
      case 'SUCCESS':
        return '✅';
      default:
        return '•';
    }
  }

  String _colorFor(String level, String value) {
    switch (level) {
      case 'INFO':
        return TermColor.cyan(value);
      case 'WARN':
      case 'WARNING':
        return TermColor.yellow(value);
      case 'ERROR':
        return TermColor.red(value);
      case 'SUCCESS':
        return TermColor.green(value);
      default:
        return value;
    }
  }
}
