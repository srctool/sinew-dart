import 'package:sinew_models/sinew_models.dart';

// An app-style envelope, as json_serializable would generate it: `success`,
// `message` and `errors` beside `data`, mapped through the two hooks.

enum OrderStatus { open, shipped, unknown }

final class Order extends Domain {
  const Order(this.id, this.status);

  final String id;
  final OrderStatus status;

  @override
  List<Object?> get props => [id, status];
}

final class OrderRemote extends Remote<Order> {
  const OrderRemote(this.id, this.status);

  /// As generated: a wrong type throws a TypeError; an unknown status falls
  /// back to `unknown` (`@JsonKey(unknownEnumValue: …)`), unless [strict].
  factory OrderRemote.fromJson(
    Map<String, dynamic> json, {
    bool strict = false,
  }) => OrderRemote(json['id'] as String, switch (json['status']) {
    'open' => OrderStatus.open,
    'shipped' => OrderStatus.shipped,
    final other when strict => throw ArgumentError(
      '`$other` is not one of the supported values: open, shipped',
    ),
    _ => OrderStatus.unknown,
  });

  final String id;
  final OrderStatus status;

  @override
  Order toDomain() => Order(id, status);
}

final class OrderResponse extends ObjectEnvelope<OrderRemote, Order> {
  const OrderResponse({this.data, this.success = true, this.text, this.errors});

  factory OrderResponse.fromJson(
    Map<String, dynamic> json, {
    bool strict = false,
  }) => OrderResponse(
    data: json['data'] == null
        ? null
        : OrderRemote.fromJson(
            json['data'] as Map<String, dynamic>,
            strict: strict,
          ),
    success: json['success'] as bool? ?? true,
    text: json['message'] as String?,
    errors: (json['errors'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, [for (final m in v as List<dynamic>) m as String]),
    ),
  );

  @override
  final OrderRemote? data;
  final bool success;
  final String? text;
  final Map<String, List<String>>? errors;

  @override
  EnvelopeFailure? failure() =>
      success ? null : EnvelopeFailure(message: text, fieldErrors: errors);

  @override
  String? message() => text;
}
