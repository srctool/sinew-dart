/// A fixture that isn't there: the test fails with where it was looked for.
final class MissingFixture implements Exception {
  /// The failure, saying where the fixture was expected.
  const MissingFixture(this.message);

  /// Where the fixture was expected.
  final String message;

  @override
  String toString() => message;
}
