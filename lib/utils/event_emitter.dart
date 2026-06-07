/// Handles an event payload and an extra value.
typedef EventHandler<D, E> = void Function(D data, E extra);

class _Listener<D, E> {
  final int id;
  final EventHandler<D, E> handler;
  final bool once;

  const _Listener({required this.id, required this.handler, required this.once});
}

/// A small generic event emitter with integer listener ids.
class EventEmitter<T, D, E> {
  final Map<T, List<_Listener<D, E>>> _listeners = <T, List<_Listener<D, E>>>{};
  int _nextId = 1;

  int on(T event, EventHandler<D, E> handler) {
    final id = _nextId++;
    _listeners
        .putIfAbsent(event, () => <_Listener<D, E>>[])
        .add(_Listener(id: id, handler: handler, once: false));
    return id;
  }

  int once(T event, EventHandler<D, E> handler) {
    final id = _nextId++;
    _listeners
        .putIfAbsent(event, () => <_Listener<D, E>>[])
        .add(_Listener(id: id, handler: handler, once: true));
    return id;
  }

  void off(T event, int id) {
    final listeners = _listeners[event];
    if (listeners == null) {
      return;
    }

    listeners.removeWhere((listener) => listener.id == id);
    if (listeners.isEmpty) {
      _listeners.remove(event);
    }
  }

  void emit(T event, D data, E extra) {
    final snapshot = List<_Listener<D, E>>.of(_listeners[event] ?? const []);

    for (final listener in snapshot) {
      if (listener.once) {
        off(event, listener.id);
      }
      listener.handler(data, extra);
    }
  }

  Future<void> emitAsync(T event, D data, E extra) async {
    final snapshot = List<_Listener<D, E>>.of(_listeners[event] ?? const []);

    await Future.wait(
      snapshot.map((listener) {
        if (listener.once) {
          off(event, listener.id);
        }
        return Future<void>.microtask(() => listener.handler(data, extra));
      }),
    );
  }

  void clear([T? event]) {
    if (event == null) {
      _listeners.clear();
    } else {
      _listeners.remove(event);
    }
  }

  int listenerCount(T event) => _listeners[event]?.length ?? 0;
}
