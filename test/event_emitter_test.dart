import 'package:deskaone_sdk/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('on and emit invoke listeners', () {
    final emitter = EventEmitter<String, int, String>();
    final seen = <String>[];

    emitter.on('value', (data, extra) => seen.add('$data:$extra'));
    emitter.emit('value', 42, 'ok');

    expect(seen, ['42:ok']);
    expect(emitter.listenerCount('value'), 1);
  });

  test('off removes listener by id', () {
    final emitter = EventEmitter<String, int, void>();
    var count = 0;

    final id = emitter.on('tick', (data, extra) => count += data);
    emitter.off('tick', id);
    emitter.emit('tick', 1, null);

    expect(count, 0);
    expect(emitter.listenerCount('tick'), 0);
  });

  test('once removes listener before invoking it', () {
    final emitter = EventEmitter<String, int, void>();
    late final int id;
    var count = 0;

    id = emitter.once('tick', (data, extra) {
      expect(emitter.listenerCount('tick'), 0);
      emitter.off('tick', id);
      count += data;
    });

    emitter.emit('tick', 1, null);
    emitter.emit('tick', 1, null);

    expect(count, 1);
  });

  test('emit snapshots handlers', () {
    final emitter = EventEmitter<String, int, void>();
    final seen = <int>[];
    late final int first;

    first = emitter.on('event', (data, extra) {
      seen.add(1);
      emitter.off('event', first);
    });
    emitter.on('event', (data, extra) => seen.add(2));

    emitter.emit('event', 0, null);

    expect(seen, [1, 2]);
  });

  test('emitAsync schedules listeners asynchronously', () async {
    final emitter = EventEmitter<String, int, void>();
    final seen = <int>[];

    emitter.on('event', (data, extra) => seen.add(data));
    final future = emitter.emitAsync('event', 7, null);

    expect(seen, isEmpty);
    await future;
    expect(seen, [7]);
  });

  test('clear removes all or event-specific listeners', () {
    final emitter = EventEmitter<String, int, void>();

    emitter.on('a', (data, extra) {});
    emitter.on('b', (data, extra) {});
    emitter.clear('a');

    expect(emitter.listenerCount('a'), 0);
    expect(emitter.listenerCount('b'), 1);

    emitter.clear();
    expect(emitter.listenerCount('b'), 0);
  });
}
