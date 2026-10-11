// The two worked envelopes from the Models note, as an app would declare them
// with json_serializable. Test-only.

import 'package:json_annotation/json_annotation.dart';
import 'package:sinew_models/sinew_models.dart';

part 'envelopes.g.dart';

enum OrderStatus { pending, paid, unknown }

class Order extends Domain {
  const Order(this.id, this.status, this.total);

  // Retrofit asks for a fromJson on every type argument; the domain type is never parsed.
  factory Order.fromJson(Map<String, dynamic> json) =>
      unreachableDomainFromJson(json);

  final String id;
  final OrderStatus status;
  final int total;

  @override
  List<Object?> get props => [id, status, total];
}

Order orderFromJson(Object? json) =>
    Order.fromJson(json! as Map<String, dynamic>);

enum OrderStatusRemote { pending, paid, unknown }

@JsonSerializable(createToJson: false)
class OrderRemote extends Remote<Order> {
  const OrderRemote({
    this.id,
    this.status = OrderStatusRemote.unknown,
    this.total,
  });

  factory OrderRemote.fromJson(Map<String, dynamic> json) =>
      _$OrderRemoteFromJson(json);

  final String? id;

  @JsonKey(unknownEnumValue: OrderStatusRemote.unknown)
  final OrderStatusRemote status;

  final int? total;

  @override
  Order toDomain() => Order(id ?? '', switch (status) {
    OrderStatusRemote.pending => OrderStatus.pending,
    OrderStatusRemote.paid => OrderStatus.paid,
    OrderStatusRemote.unknown => OrderStatus.unknown,
  }, total ?? 0);
}

OrderRemote orderRemoteFromJson(Object? json) =>
    OrderRemote.fromJson(json! as Map<String, dynamic>);

// Example 1: a backend with a success flag, a message and a `meta` object.

@JsonSerializable(createToJson: false)
class PageMeta extends PagingMetaEnvelope {
  const PageMeta({
    this.page,
    this.limit,
    this.total,
    this.totalPage,
    this.hasNextPage,
  });

  factory PageMeta.fromJson(Map<String, dynamic> json) =>
      _$PageMetaFromJson(json);

  final int? page;
  final int? limit;
  final int? total;
  final int? totalPage;
  final bool? hasNextPage;

  @override
  PagingMetaDomain toDomain() => PagingMetaDomain(
    page: page ?? 1,
    limit: limit ?? 0,
    total: total ?? 0,
    totalPage: totalPage ?? 0,
    hasNextPage: hasNextPage ?? false,
  );
}

@JsonSerializable(genericArgumentFactories: true, createToJson: false)
class PagedResponse<T extends Remote<D>, D extends Domain>
    extends PagedEnvelope<T, D> {
  const PagedResponse({this.ok, this.text, this.errors, this.items, this.meta});

  factory PagedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
    D Function(Object? json) fromJsonD,
  ) => _$PagedResponseFromJson(json, fromJsonT, fromJsonD);

  @JsonKey(name: 'success')
  final bool? ok;

  @JsonKey(name: 'message')
  final String? text;

  final Map<String, List<String>>? errors;

  @override
  @JsonKey(name: 'data')
  final List<T>? items;

  @override
  final PageMeta? meta;

  @override
  EnvelopeFailure? failure() =>
      ok == false ? EnvelopeFailure(message: text, fieldErrors: errors) : null;

  @override
  String? message() => text;
}

@JsonSerializable(genericArgumentFactories: true, createToJson: false)
class ObjectResponse<T extends Remote<D>, D extends Domain>
    extends ObjectEnvelope<T, D> {
  const ObjectResponse({this.ok, this.text, this.errors, this.data});

  factory ObjectResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
    D Function(Object? json) fromJsonD,
  ) => _$ObjectResponseFromJson(json, fromJsonT, fromJsonD);

  @JsonKey(name: 'success')
  final bool? ok;

  @JsonKey(name: 'message')
  final String? text;

  final Map<String, List<String>>? errors;

  @override
  final T? data;

  @override
  EnvelopeFailure? failure() =>
      ok == false ? EnvelopeFailure(message: text, fieldErrors: errors) : null;

  @override
  String? message() => text;
}

@JsonSerializable(genericArgumentFactories: true, createToJson: false)
class ListResponse<T extends Remote<D>, D extends Domain>
    extends ListEnvelope<T, D> {
  const ListResponse({this.items});

  factory ListResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
    D Function(Object? json) fromJsonD,
  ) => _$ListResponseFromJson(json, fromJsonT, fromJsonD);

  @override
  @JsonKey(name: 'data')
  final List<T>? items;
}

@JsonSerializable(createToJson: false)
class VoidResponse extends VoidEnvelope {
  const VoidResponse({this.text});

  factory VoidResponse.fromJson(Map<String, dynamic> json) =>
      _$VoidResponseFromJson(json);

  @JsonKey(name: 'message')
  final String? text;

  @override
  String? message() => text;
}

// Example 2: records nested in `data` with the page keys beside them, no success flag or message.
// The body is both the items' holder and the meta, so it extends PagingMetaEnvelope itself.

@JsonSerializable(genericArgumentFactories: true, createToJson: false)
class RecordsBody<T> extends PagingMetaEnvelope {
  const RecordsBody({
    this.records,
    this.maxPage,
    this.total,
    this.pageSize,
    this.page,
  });

  factory RecordsBody.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$RecordsBodyFromJson(json, fromJsonT);

  final List<T>? records;

  @JsonKey(name: 'max_page')
  final int? maxPage;

  final int? total;

  @JsonKey(name: 'page_size')
  final int? pageSize;

  @JsonKey(name: 'current_page')
  final int? page;

  @override
  PagingMetaDomain toDomain() => PagingMetaDomain(
    page: page ?? 1,
    limit: pageSize ?? 0,
    total: total ?? 0,
    totalPage: maxPage ?? 0,
    hasNextPage: (page ?? 1) < (maxPage ?? 0),
  );
}

@JsonSerializable(genericArgumentFactories: true, createToJson: false)
class RecordsPagedResponse<T extends Remote<D>, D extends Domain>
    extends PagedEnvelope<T, D> {
  const RecordsPagedResponse({this.body});

  factory RecordsPagedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
    D Function(Object? json) fromJsonD,
  ) => _$RecordsPagedResponseFromJson(json, fromJsonT, fromJsonD);

  @JsonKey(name: 'data')
  final RecordsBody<T>? body;

  @override
  List<T>? get items => body?.records;

  @override
  RecordsBody<T>? get meta => body;
}
