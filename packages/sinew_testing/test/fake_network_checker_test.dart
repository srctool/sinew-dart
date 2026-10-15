import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  test('a test switches it by hand', () async {
    final checker = FakeNetworkChecker();
    final changes = <NetworkStatus>[];
    checker.changes.listen(changes.add);
    expect(checker.isOnline, isTrue);
    checker.goOffline();
    expect(checker.status, NetworkStatus.offline);
    checker
      ..goOffline()
      ..goOnline();
    expect(checker.isOnline, isTrue);
    expect(changes, [NetworkStatus.offline, NetworkStatus.online]);
    await checker.dispose();
    expect(checker.disposed, isTrue);
  });

  test('starts from the status a test gives it', () {
    expect(FakeNetworkChecker(NetworkStatus.offline).isOnline, isFalse);
  });

  test('ignores switches after dispose', () async {
    final checker = FakeNetworkChecker();
    await checker.dispose();
    checker.goOffline();
    expect(checker.isOnline, isTrue);
  });
}
