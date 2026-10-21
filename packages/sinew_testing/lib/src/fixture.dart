import 'fixture_io.dart'
    if (dart.library.js_interop) 'fixture_web.dart'
    as platform;

/// The text of the test fixture [name] (`test/fixtures/<name>`), so response
/// shapes live as files beside the tests: `fixture('orders_page.json')`. A
/// missing fixture fails the test with its path, never returns ''.
///
/// Read from the package folder, where `flutter test` and `dart test` run, on
/// the VM; in a browser test it's fetched from the test server.
String fixture(String name) => platform.fixture(name);
