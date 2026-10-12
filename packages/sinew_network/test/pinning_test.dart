import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_network/sinew_network.dart';

/// On every platform, the browser's no-op included.
void main() {
  test('pinning nothing is refused', () {
    expect(
      () => pinCertificateAuthorities(Dio(), const []),
      throwsArgumentError,
    );
  });
}
