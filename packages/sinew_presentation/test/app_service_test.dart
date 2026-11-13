import 'dart:async';

import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_presentation/sinew_presentation.dart';
import 'package:sinew_testing/sinew_testing.dart';
import 'package:test/test.dart';

/// Records its steps in [log]; [failInit] throws, [guardInit] reports through the service guard instead.
final class _Recorder extends AppService {
  _Recorder(
    super.lifetime,
    this.name,
    this.log, {
    this.failInit = false,
    this.guardInit = false,
    this.initGate,
    this.failDestroy = false,
  });

  final String name;
  final List<String> log;
  final bool failInit;
  final bool guardInit;
  final Completer<void>? initGate;
  final bool failDestroy;

  @override
  Future<void> init() async {
    log.add('$name.init');
    if (guardInit) {
      await processCall<void>(
        'MSG',
        'INIT',
        ExceptionLayer.service,
        const [],
        () async {
          if (failInit) throw StateError('catch-up failed');
        },
      );
    } else if (failInit) {
      throw StateError('catch-up failed');
    }
    await initGate?.future;
  }

  @override
  void listen() => log.add('$name.listen');

  @override
  Future<void> destroy() async {
    log.add('$name.destroy');
    if (failDestroy) throw StateError('destroy failed');
  }
}

void main() {
  late RecordingCrashReporter reporter;
  late List<String> log;
  const app = ServiceLifetime.app;
  const session = ServiceLifetime.session;

  setUp(() {
    reporter = RecordingCrashReporter();
    CrashReporter.install(reporter);
    log = [];
  });
  tearDown(() => CrashReporter.install(CrashReporter.none));

  test(
    'startApp runs init then listen for app services only, in list order',
    () async {
      final host = AppServiceHost([
        _Recorder(app, 'a', log),
        _Recorder(session, 's', log),
        _Recorder(app, 'b', log),
      ]);
      await host.startApp();
      expect(log, ['a.init', 'a.listen', 'b.init', 'b.listen']);
    },
  );

  test('a second startApp does nothing', () async {
    final host = AppServiceHost([_Recorder(app, 'a', log)]);
    await host.startApp();
    await host.startApp();
    expect(log, ['a.init', 'a.listen']);
  });

  test('a second startSession while a session runs does nothing', () async {
    final host = AppServiceHost([_Recorder(session, 's', log)]);
    await host.startSession();
    await host.startSession();
    expect(log, ['s.init', 's.listen']);
  });

  test('stopSession destroys only session services in reverse order, and a new session starts them fresh', () async {
    final host = AppServiceHost([
      _Recorder(app, 'a', log),
      _Recorder(session, 's1', log),
      _Recorder(session, 's2', log),
    ]);
    await host.startApp();
    await host.startSession();
    log.clear();
    await host.stopSession();
    expect(log, ['s2.destroy', 's1.destroy']);
    log.clear();
    await host.startSession();
    expect(log, ['s1.init', 's1.listen', 's2.init', 's2.listen']);
  });

  test('stopSession with no session does nothing', () async {
    final host = AppServiceHost([_Recorder(session, 's', log)]);
    await host.stopSession();
    expect(log, isEmpty);
  });

  test('a failing guarded init is reported with the service layer and the service still listens', () async {
    final host = AppServiceHost([
      _Recorder(app, 'a', log, failInit: true, guardInit: true),
      _Recorder(app, 'b', log),
    ]);
    await host.startApp();
    expect(reporter.codes, ['MSG-SV-INIT-GEN']);
    expect(log, ['a.init', 'a.listen', 'b.init', 'b.listen']);
  });

  test('an unguarded init failure surfaces as an unhandled error and stops nothing', () async {
    final host = AppServiceHost([
      _Recorder(app, 'a', log, failInit: true),
      _Recorder(app, 'b', log),
    ]);
    final uncaught = <Object>[];
    await runZonedGuarded(() => host.startApp(), (e, _) => uncaught.add(e));
    await Future<void>.delayed(Duration.zero);
    expect(log, ['a.init', 'a.listen', 'b.init', 'b.listen']);
    expect(uncaught.map((e) => (e as StateError).message), ['catch-up failed']);
  });

  test('stopSession while an init is running destroys at once and the init never listens', () async {
    final gate = Completer<void>();
    final host = AppServiceHost([_Recorder(session, 's', log, initGate: gate)]);
    final starting = host.startSession();
    await Future<void>.delayed(Duration.zero);
    expect(log, ['s.init']);
    await host.stopSession();
    expect(log, ['s.init', 's.destroy']);
    gate.complete();
    await starting;
    expect(log, ['s.init', 's.destroy']); // no listen after the stop
  });

  test(
    'a failing destroy does not stop the others and is rethrown afterwards',
    () async {
      final host = AppServiceHost([
        _Recorder(session, 's1', log),
        _Recorder(session, 's2', log, failDestroy: true),
      ]);
      await host.startSession();
      log.clear();
      await expectLater(host.stopSession(), throwsA(isA<StateError>()));
      expect(log, ['s2.destroy', 's1.destroy']);
    },
  );

  test('stopAll destroys session then app services in reverse order', () async {
    final host = AppServiceHost([
      _Recorder(app, 'a1', log),
      _Recorder(session, 's', log),
      _Recorder(app, 'a2', log),
    ]);
    await host.startApp();
    await host.startSession();
    log.clear();
    await host.stopAll();
    expect(log, ['s.destroy', 'a2.destroy', 'a1.destroy']);
  });

  test('a service that never started is not destroyed', () async {
    final host = AppServiceHost([_Recorder(app, 'a', log)]);
    await host.stopAll();
    expect(log, isEmpty);
  });
}
