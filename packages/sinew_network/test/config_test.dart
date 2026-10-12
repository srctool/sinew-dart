import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_network/sinew_network.dart';

void main() {
  SinewConfig config({
    String baseUrl = 'https://api.example.com/v1',
    Duration connect = const Duration(seconds: 15),
    Duration read = const Duration(seconds: 30),
    Duration write = const Duration(seconds: 60),
    Set<String> anonymous = const {},
  }) => SinewConfig(
    baseUrl: baseUrl,
    locale: () => 'en',
    connectTimeout: connect,
    readTimeout: read,
    writeTimeout: write,
    anonymousPaths: anonymous,
  );

  test('the defaults', () {
    final c = SinewConfig(
      baseUrl: 'https://api.example.com',
      locale: () => 'en',
    );
    expect(c.connectTimeout, const Duration(seconds: 15));
    expect(c.readTimeout, const Duration(seconds: 30));
    expect(c.writeTimeout, const Duration(seconds: 60));
    expect(c.logHttp, isFalse);
    expect(c.anonymousPaths, isEmpty);
    expect(c.defaultHeaders, isNull);
    expect(identical(c.errorBodyReader, ErrorBodyReader.standard), isTrue);
  });

  test('locale and headers are read each time', () {
    var language = 'en';
    var build = 1;
    final c = SinewConfig(
      baseUrl: 'https://api.example.com',
      locale: () => language,
      defaultHeaders: () => {'X-Build': '$build'},
    );
    language = 'id';
    build = 2;
    expect(c.locale(), 'id');
    expect(c.defaultHeaders!(), {'X-Build': '2'});
  });

  test('a blank baseUrl fails', () {
    expect(() => config(baseUrl: ' '), throwsArgumentError);
  });

  test('a timeout that is not positive fails', () {
    expect(() => config(connect: Duration.zero), throwsArgumentError);
    expect(
      () => config(read: const Duration(seconds: -1)),
      throwsArgumentError,
    );
    expect(() => config(write: Duration.zero), throwsArgumentError);
  });

  test('an anonymous path must start with a slash', () {
    config(anonymous: {'/auth/login'});
    expect(
      () => config(anonymous: {'/auth/login', 'auth/refresh'}),
      throwsArgumentError,
    );
  });
}
