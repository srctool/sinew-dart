import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:sinew_network/sinew_network.dart';

/// The device's connectivity, rebuilding the widget when it changes: for an
/// offline banner or a disabled submit button.
///
/// ```dart
/// final status = useNetworkChecker(ref.watch(networkCheckerProvider));
/// ```
NetworkStatus useNetworkChecker(NetworkChecker checker) {
  final changes = useMemoized(() => checker.changes, [checker]);
  return useStream(changes, initialData: checker.status).data ?? checker.status;
}
