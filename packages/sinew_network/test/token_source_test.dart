import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/sinew_network.dart';

void main() {
  test('outcomes compare by kind, and Unavailable by its cause', () {
    const offline = NoInternetConnectionException(
      'AUTH',
      ExceptionLayer.repository,
      'REFRESH',
    );
    expect(const Refreshed(), const Refreshed());
    expect(const Rejected(), const Rejected());
    expect(const Unavailable(offline), const Unavailable(offline));
    expect(const Refreshed() == const Rejected(), isFalse);
    expect(
      const Unavailable(offline) ==
          const Unavailable(
            RequestTimeOutException('AUTH', ExceptionLayer.repository, 'X'),
          ),
      isFalse,
    );
  });
}
