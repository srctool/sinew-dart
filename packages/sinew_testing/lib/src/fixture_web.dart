import 'package:web/web.dart';

import 'missing_fixture.dart';

/// Fetches `/fixtures/<name>`: the browser test server serves the package's
/// `test` folder at its root. A synchronous request, so a fixture reads like a
/// file; the server is local.
String fixture(String name) {
  final path = '/fixtures/$name';
  final request = XMLHttpRequest()
    ..open('GET', path, false)
    ..send();
  if (request.status != 200) {
    throw MissingFixture(
      'No fixture "$name": expected test/fixtures/$name '
      '(GET $path answered ${request.status})',
    );
  }
  return request.responseText;
}
