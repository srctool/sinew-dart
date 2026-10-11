// The mixins on a riverpod_generator notifier: the generated `_$Greeting`
// extends Riverpod's codegen base, which must satisfy the mixins' `on`
// clause. Regenerate with `dart run build_runner build` after a Riverpod
// upgrade.

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sinew_riverpod/sinew_riverpod.dart';

part 'codegen_test.g.dart';

@riverpod
class Greeting extends _$Greeting
    with
        StateEffectNotifier<String, String>,
        EventActionNotifier<String, String, String, String> {
  @override
  String build() => '';

  @override
  String? mapEventToAction(String event) => event.isEmpty ? null : event;

  @override
  Future<void> onAction(String action) async {
    setState((_) => 'Hello, $action');
    emitEffect('greeted $action');
  }

  void rebuild() => ref.invalidateSelf();
}

void main() {
  test('the mixins compose with a generated notifier', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(greetingProvider, (_, _) {});
    final notifier = container.read(greetingProvider.notifier);
    final effects = <String>[];
    var done = false;
    notifier.effects.listen(effects.add, onDone: () => done = true);

    notifier
      ..onEvent('')
      ..onEvent('Ada');
    await pumpEventQueue();
    expect(container.read(greetingProvider), 'Hello, Ada');

    notifier.rebuild();
    await pumpEventQueue();
    expect(container.read(greetingProvider), '');
    notifier.onEvent('Grace');
    await pumpEventQueue();
    expect(effects, ['greeted Ada', 'greeted Grace']);

    container.dispose();
    await pumpEventQueue();
    expect(done, isTrue);
  });
}
