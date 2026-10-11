import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_presentation/sinew_presentation.dart';
import 'package:sinew_riverpod/sinew_riverpod.dart';

class _Opened extends HookWidget {
  const _Opened(this.onEvent, this.label);

  final void Function(String event) onEvent;
  final String label;

  @override
  Widget build(BuildContext context) {
    useOnOpened(onEvent, 'Opened');
    return Text(label, textDirection: TextDirection.ltr);
  }
}

class _Effects extends HookWidget {
  const _Effects(this.effects, this.onEffect);

  final Stream<String> effects;
  final void Function(BuildContext context, String effect) onEffect;

  @override
  Widget build(BuildContext context) {
    useEffects(effects, onEffect);
    return const SizedBox();
  }
}

void main() {
  group('useOnOpened', () {
    testWidgets('sends the event once across rebuilds', (tester) async {
      final sent = <String>[];
      final phases = <SchedulerPhase>[];
      void onEvent(String event) {
        sent.add(event);
        phases.add(SchedulerBinding.instance.schedulerPhase);
      }

      await tester.pumpWidget(_Opened(onEvent, 'a'));
      await tester.pump();
      expect(sent, ['Opened']);
      expect(phases.single, isNot(SchedulerPhase.persistentCallbacks));

      await tester.pumpWidget(_Opened(onEvent, 'b'));
      await tester.pump();
      expect(sent, ['Opened']);
    });

    testWidgets('a new page instance sends it again', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(_Opened(sent.add, 'a'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_Opened(sent.add, 'a'));
      await tester.pump();
      expect(sent, ['Opened', 'Opened']);
    });
  });

  group('useEffects', () {
    testWidgets('calls onEffect with the page context', (tester) async {
      final emitter = EffectEmitter<String>();
      final got = <String>[];
      BuildContext? seen;
      await tester.pumpWidget(
        _Effects(emitter.stream, (context, effect) {
          seen = context;
          got.add(effect);
        }),
      );
      emitter.emit('a');
      await tester.pump();
      expect(got, ['a']);
      expect(seen, isNotNull);
    });

    testWidgets('subscribes once across rebuilds and calls the latest '
        'onEffect', (tester) async {
      final emitter = EffectEmitter<String>();
      final first = <String>[];
      final latest = <String>[];
      await tester.pumpWidget(_Effects(emitter.stream, (_, e) => first.add(e)));
      // A second subscription to the same stream would throw.
      await tester.pumpWidget(
        _Effects(emitter.stream, (_, e) => latest.add(e)),
      );
      emitter.emit('a');
      await tester.pump();
      expect(first, isEmpty);
      expect(latest, ['a']);
    });

    testWidgets('cancels on unmount; the next page gets what it missed', (
      tester,
    ) async {
      final emitter = EffectEmitter<String>();
      final first = <String>[];
      await tester.pumpWidget(_Effects(emitter.stream, (_, e) => first.add(e)));
      await tester.pumpWidget(const SizedBox());

      emitter.emit('while away');
      await tester.pump();
      final second = <String>[];
      await tester.pumpWidget(
        _Effects(emitter.stream, (_, e) => second.add(e)),
      );
      await tester.pump();
      expect(first, isEmpty);
      expect(second, ['while away']);
    });

    testWidgets('a new stream is subscribed to instead', (tester) async {
      final a = EffectEmitter<String>();
      final b = EffectEmitter<String>();
      final got = <String>[];
      await tester.pumpWidget(_Effects(a.stream, (_, e) => got.add(e)));
      await tester.pumpWidget(_Effects(b.stream, (_, e) => got.add(e)));
      a.emit('old');
      b.emit('new');
      await tester.pump();
      expect(got, ['new']);
    });
  });
}
