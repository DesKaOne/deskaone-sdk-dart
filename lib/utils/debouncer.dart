import 'dart:async';

/// Runs [action] only after calls have been quiet for [delay].
class Debouncer {
  final Duration delay;
  final void Function() action;

  Timer? _timer;
  bool _disposed = false;

  Debouncer(this.delay, this.action);

  /// Schedules [action], resetting any pending timer.
  void call() {
    if (_disposed) {
      return;
    }

    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      if (!_disposed) {
        action();
      }
    });
  }

  /// Cancels the pending action, if any.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Cancels the timer and prevents future scheduling.
  void dispose() {
    _disposed = true;
    cancel();
  }
}
