// ignore_for_file: avoid_print

import 'dart:async';

import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_presentation/sinew_presentation.dart';

// region counter
/// The state a page renders.
final class CounterState {
  const CounterState(this.count);

  final int count;
}

/// A one-time reaction: never state, so a rebuild can't repeat it.
final class ReachedTen {
  const ReachedTen();
}

/// A page with one intent: state in, state and effects out.
final class Counter extends StateEffectHandler<CounterState, ReachedTen> {
  Counter() : super(const CounterState(0));

  void increment() {
    setState((state) => CounterState(state.count + 1));
    if (state.count == 10) emitEffect(const ReachedTen());
  }
}
// endregion

final class Purchase {
  const Purchase(this.id);

  final String id;
}

/// What the store gives the app: purchases made while it wasn't running, and ones arriving now.
abstract interface class PurchaseStore {
  Future<List<Purchase>> unacknowledged();

  Stream<Purchase> get arrivals;
}

/// The use case a page could call too: idempotent, because the store delivers the same purchase again.
typedef AcknowledgePurchase = Future<void> Function(Purchase purchase);

// region app-service
/// Work with the app's lifetime and no UI: purchases arrive from the store at any time, with or without a screen.
final class BillingService extends AppService {
  BillingService(this.store, this.acknowledge) : super(ServiceLifetime.app);

  final PurchaseStore store;
  final AcknowledgePurchase acknowledge;
  StreamSubscription<Purchase>? _arrivals;

  /// Catches up first, before [listen] subscribes. A bug here is reported as `BIL-SV-INIT-GEN`.
  @override
  Future<void> init() async {
    await processCall<void>(
      'BIL',
      'INIT',
      ExceptionLayer.service,
      const [],
      () async {
        for (final purchase in await store.unacknowledged()) {
          await acknowledge(purchase);
        }
      },
    );
  }

  @override
  void listen() {
    _arrivals = store.arrivals.listen((purchase) async {
      await processCall<void>(
        'BIL',
        'LISTEN',
        ExceptionLayer.service,
        const [],
        () => acknowledge(purchase),
      );
    });
  }

  @override
  Future<void> destroy() async => _arrivals?.cancel();
}
// endregion

// region app-service-host
/// Built once in `main()`, before `runApp`, and kept for the life of the app.
AppServiceHost appServices(
  PurchaseStore store,
  AcknowledgePurchase acknowledge,
) => AppServiceHost([BillingService(store, acknowledge)]);

/// App services start at launch, session services at sign-in and stop at sign-out.
final class AppLifecycle {
  AppLifecycle(this.services);

  final AppServiceHost services;

  Future<void> launched() => services.startApp();

  Future<void> signedIn() => services.startSession();

  Future<void> signedOut() => services.stopSession();
}
// endregion

Future<void> main() async {
  final counter = Counter();
  counter.effects.listen((effect) => print('effect: the counter reached ten'));
  counter.states.listen((state) => print('count: ${state.count}'));

  for (var i = 0; i < 10; i++) {
    counter.increment();
    await Future<void>.delayed(Duration.zero); // let the page see each state
  }
  counter.dispose();
}
