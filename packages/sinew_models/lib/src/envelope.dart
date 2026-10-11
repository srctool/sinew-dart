import 'domain.dart';
import 'exception.dart';
import 'paging.dart';

/// The shape of a response body, mapped to the domain.
///
/// Sinew assumes no JSON keys: an app's subclass declares its backend's
/// fields, and fills the two optional hooks from its own keys when its backend
/// has them. The bases return `null` from both.
abstract interface class Envelope<R> {
  /// Maps the payload to the domain.
  R toDomain();

  /// A failure reported inside a 2xx body (a `"success": false`). `null` means
  /// the call succeeded.
  EnvelopeFailure? failure();

  /// The backend's text on success. `null` means none.
  String? message();
}

/// A failure inside a 2xx body: the backend's message and, for a validation
/// failure, its field messages.
class EnvelopeFailure {
  /// Creates a failure.
  const EnvelopeFailure({this.message, this.fieldErrors});

  /// The backend's message.
  final String? message;

  /// Field name → messages, for a validation failure.
  final Map<String, List<String>>? fieldErrors;

  @override
  bool operator ==(Object other) =>
      other is EnvelopeFailure &&
      other.message == message &&
      _fieldErrorsEqual(other.fieldErrors, fieldErrors);

  @override
  int get hashCode => Object.hash(message, fieldErrors?.length);

  @override
  String toString() => 'EnvelopeFailure($message, $fieldErrors)';
}

bool _fieldErrorsEqual(
  Map<String, List<String>>? a,
  Map<String, List<String>>? b,
) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || other.length != entry.value.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != entry.value[i]) return false;
    }
  }
  return true;
}

/// One object. [toDomain] throws [EnvelopeDataMissing] when [data] is absent.
abstract class ObjectEnvelope<T extends Remote<D>, D extends Domain>
    implements Envelope<D> {
  /// Creates the base.
  const ObjectEnvelope();

  /// The payload.
  T? get data;

  @override
  D toDomain() => data?.toDomain() ?? (throw const EnvelopeDataMissing());

  @override
  EnvelopeFailure? failure() => null;

  @override
  String? message() => null;
}

/// A list. An absent list maps to an empty one: a missing list is not an error.
abstract class ListEnvelope<T extends Remote<D>, D extends Domain>
    implements Envelope<List<D>> {
  /// Creates the base.
  const ListEnvelope();

  /// The items.
  List<T>? get items;

  @override
  List<D> toDomain() => [for (final item in items ?? <T>[]) item.toDomain()];

  @override
  EnvelopeFailure? failure() => null;

  @override
  String? message() => null;
}

/// A page. Every item is mapped through its own `toDomain()`, and so is
/// [meta]. A subclass overrides [meta] with its backend's own meta type; an
/// absent meta maps to the default [PagingMetaDomain] (no next page).
abstract class PagedEnvelope<T extends Remote<D>, D extends Domain>
    implements Envelope<PagingDomain<D>> {
  /// Creates the base.
  const PagedEnvelope();

  /// The items of this page.
  List<T>? get items;

  /// The page information, in the backend's own shape.
  PagingMetaEnvelope? get meta;

  @override
  PagingDomain<D> toDomain() => PagingDomain(
    items: [for (final item in items ?? <T>[]) item.toDomain()],
    meta: meta?.toDomain() ?? const PagingMetaDomain(),
  );

  @override
  EnvelopeFailure? failure() => null;

  @override
  String? message() => null;
}

/// A backend's page information, shaped like its JSON: `total_page` on one
/// backend, `max_page` on another, keys nested or next to the items. Each app
/// declares its own subclass and maps it to the one [PagingMetaDomain] shape.
abstract class PagingMetaEnvelope {
  /// Creates the base.
  const PagingMetaEnvelope();

  /// Maps the backend's page keys to [PagingMetaDomain].
  PagingMetaDomain toDomain();
}

/// A body with no payload.
abstract class VoidEnvelope implements Envelope<void> {
  /// Creates the base.
  const VoidEnvelope();

  @override
  void toDomain() {}

  @override
  EnvelopeFailure? failure() => null;

  @override
  String? message() => null;
}

/// The `fromJson` a domain model declares so Retrofit can decode a generic
/// envelope (`PagedResponse<OrderRemote, Order>`): generated code asks for a
/// `fromJson` for every type argument, though the domain type is never parsed.
/// It throws if it's ever called.
///
/// ```dart
/// factory Order.fromJson(Map<String, dynamic> json) => unreachableDomainFromJson(json);
/// ```
Never unreachableDomainFromJson(Map<String, dynamic> json) => throw StateError(
  'A domain model is never parsed from JSON; parse its Remote instead.',
);
