import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_network/sinew_network.dart';

void main() {
  ErrorBody? read(Object? body) => ErrorBodyReader.standard.read(422, body);

  test('reads message and errors from a decoded map', () {
    expect(
      read({
        'message': 'Check the form.',
        'errors': {
          'email': ['Taken.', 'Too long.'],
          'name': 'Required.',
        },
      }),
      const ErrorBody(
        message: 'Check the form.',
        fieldErrors: {
          'email': ['Taken.', 'Too long.'],
          'name': ['Required.'],
        },
      ),
    );
  });

  test('reads a JSON string too', () {
    expect(
      read('{"message":"Out of stock."}'),
      const ErrorBody(message: 'Out of stock.'),
    );
  });

  test('reads errors alone', () {
    expect(
      read({
        'errors': {
          'email': ['Taken.'],
        },
      }),
      const ErrorBody(
        fieldErrors: {
          'email': ['Taken.'],
        },
      ),
    );
  });

  test('ignores unknown keys', () {
    expect(
      read({
        'code': 'E42',
        'message': 'No.',
        'trace': {'id': 1},
      }),
      const ErrorBody(message: 'No.'),
    );
  });

  test('a blank message is unreadable', () {
    expect(read({'message': '   '}), isNull);
  });

  test('blank and non-string field messages are dropped', () {
    expect(
      read({
        'message': 'Bad.',
        'errors': {
          'email': ['Taken.', '', 3, null],
          'name': <Object>[],
          'age': 42,
        },
      }),
      const ErrorBody(
        message: 'Bad.',
        fieldErrors: {
          'email': ['Taken.'],
        },
      ),
    );
  });

  test('field errors with only empty lists are no field errors', () {
    expect(
      read({
        'message': 'No.',
        'errors': {'name': <Object>[], 'email': ''},
      }),
      const ErrorBody(message: 'No.'),
    );
  });

  test('a non-string message is ignored', () {
    expect(
      read({
        'message': {'text': 'nested'},
      }),
      isNull,
    );
  });

  test('returns null for an HTML page', () {
    expect(read('<html><body><h1>502 Bad Gateway</h1></body></html>'), isNull);
  });

  test('returns null for an empty or missing body', () {
    expect(read(null), isNull);
    expect(read(''), isNull);
    expect(read('  \n'), isNull);
  });

  test('returns null for non-JSON and non-objects', () {
    expect(read('Service Unavailable'), isNull);
    expect(read('{"message": "unterminated'), isNull);
    expect(read('["message"]'), isNull);
    expect(read(['message']), isNull);
    expect(read('"just a string"'), isNull);
    expect(read(<String, Object?>{}), isNull);
    expect(read(42), isNull);
  });

  test('a custom reader receives the status', () {
    final reader = ErrorBodyReader.from(
      (status, body) => ErrorBody(message: '$status: $body'),
    );
    expect(reader.read(409, 'taken'), const ErrorBody(message: '409: taken'));
  });
}
