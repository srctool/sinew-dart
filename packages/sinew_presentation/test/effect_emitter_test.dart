import 'dart:async';

import 'package:sinew_presentation/sinew_presentation.dart';
import 'package:test/test.dart';

void main() {
  late EffectEmitter<String> emitter;
  setUp(() => emitter = EffectEmitter<String>());

  test('an effect before the first listener is delivered', () async {
    emitter
      ..emit('a')
      ..emit('b');
    final got = <String>[];
    emitter.stream.listen(got.add);
    await pumpEventQueue();
    expect(got, ['a', 'b']);
  });

  test('an effect while listening is delivered in order', () async {
    final got = <String>[];
    emitter.stream.listen(got.add);
    emitter
      ..emit('a')
      ..emit('b');
    await pumpEventQueue();
    emitter.emit('c');
    await pumpEventQueue();
    expect(got, ['a', 'b', 'c']);
  });

  test(
    'a second listener after cancelling the first gets only new effects',
    () async {
      final first = <String>[];
      final subscription = emitter.stream.listen(first.add);
      emitter.emit('a');
      await pumpEventQueue();
      await subscription.cancel();

      emitter.emit('b'); // while nobody listens: buffered
      final second = <String>[];
      emitter.stream.listen(second.add);
      emitter.emit('c');
      await pumpEventQueue();
      expect(first, ['a']);
      expect(second, ['b', 'c']);
    },
  );

  test('a second listener while one is active throws', () {
    emitter.stream.listen((_) {});
    expect(() => emitter.stream.listen((_) {}), throwsStateError);
  });

  test('an effect emitted then cancelled before delivery goes to the next listener', () async {
    final first = <String>[];
    final subscription = emitter.stream.listen(first.add);
    emitter.emit('a');
    await subscription.cancel(); // before the microtask that delivers it

    final second = <String>[];
    emitter.stream.listen(second.add);
    await pumpEventQueue();
    expect(first, isEmpty);
    expect(second, ['a']);
  });

  test('a paused listener gets its effects on resume, once', () async {
    final got = <String>[];
    final subscription = emitter.stream.listen(got.add)..pause();
    emitter.emit('a');
    await pumpEventQueue();
    expect(got, isEmpty);

    subscription.resume();
    await pumpEventQueue();
    expect(got, ['a']);
  });

  test('an effect emitted while paused survives a cancel', () async {
    final first = <String>[];
    final subscription = emitter.stream.listen(first.add)..pause();
    emitter.emit('a');
    await pumpEventQueue();
    await subscription.cancel();

    final second = <String>[];
    emitter.stream.listen(second.add);
    await pumpEventQueue();
    expect(first, isEmpty);
    expect(second, ['a']);
  });

  test('cancelling inside a callback leaves the rest buffered', () async {
    final first = <String>[];
    late StreamSubscription<String> subscription;
    subscription = emitter.stream.listen((e) {
      first.add(e);
      subscription.cancel();
    });
    emitter
      ..emit('a')
      ..emit('b');
    await pumpEventQueue();

    final second = <String>[];
    emitter.stream.listen(second.add);
    await pumpEventQueue();
    expect(first, ['a']);
    expect(second, ['b']);
  });

  test('an effect emitted from a callback is delivered after it', () async {
    final got = <String>[];
    emitter.stream.listen((e) {
      got.add(e);
      if (e == 'a') emitter.emit('from a');
    });
    emitter
      ..emit('a')
      ..emit('b');
    await pumpEventQueue();
    expect(got, ['a', 'b', 'from a']);
  });

  group('after dispose', () {
    test('nothing is delivered, and the stream is done', () async {
      final got = <String>[];
      var done = false;
      emitter.stream.listen(got.add, onDone: () => done = true);
      emitter
        ..emit('a') // buffered, then dropped by dispose
        ..dispose()
        ..emit('b');
      await pumpEventQueue();
      expect(got, isEmpty);
      expect(done, isTrue);
    });

    test('a new listener gets nothing and is done', () async {
      emitter
        ..emit('a')
        ..dispose();
      final got = <String>[];
      var done = false;
      emitter.stream.listen(got.add, onDone: () => done = true);
      await pumpEventQueue();
      expect(got, isEmpty);
      expect(done, isTrue);
    });

    test('dispose twice is harmless', () {
      emitter
        ..dispose()
        ..dispose();
    });
  });
}
