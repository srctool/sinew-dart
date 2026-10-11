// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'codegen_test.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Greeting)
final greetingProvider = GreetingProvider._();

final class GreetingProvider extends $NotifierProvider<Greeting, String> {
  GreetingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'greetingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$greetingHash();

  @$internal
  @override
  Greeting create() => Greeting();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$greetingHash() => r'64ecd81ca9ac0f837622e041fbb3065ca13a55d0';

abstract class _$Greeting extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
