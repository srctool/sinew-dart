// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'envelopes.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderRemote _$OrderRemoteFromJson(Map<String, dynamic> json) => OrderRemote(
  id: json['id'] as String?,
  status:
      $enumDecodeNullable(
        _$OrderStatusRemoteEnumMap,
        json['status'],
        unknownValue: OrderStatusRemote.unknown,
      ) ??
      OrderStatusRemote.unknown,
  total: (json['total'] as num?)?.toInt(),
);

const _$OrderStatusRemoteEnumMap = {
  OrderStatusRemote.pending: 'pending',
  OrderStatusRemote.paid: 'paid',
  OrderStatusRemote.unknown: 'unknown',
};

PageMeta _$PageMetaFromJson(Map<String, dynamic> json) => PageMeta(
  page: (json['page'] as num?)?.toInt(),
  limit: (json['limit'] as num?)?.toInt(),
  total: (json['total'] as num?)?.toInt(),
  totalPage: (json['totalPage'] as num?)?.toInt(),
  hasNextPage: json['hasNextPage'] as bool?,
);

PagedResponse<T, D>
_$PagedResponseFromJson<T extends Remote<D>, D extends Domain>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
  D Function(Object? json) fromJsonD,
) => PagedResponse<T, D>(
  ok: json['success'] as bool?,
  text: json['message'] as String?,
  errors: (json['errors'] as Map<String, dynamic>?)?.map(
    (k, e) =>
        MapEntry(k, (e as List<dynamic>).map((e) => e as String).toList()),
  ),
  items: (json['data'] as List<dynamic>?)?.map(fromJsonT).toList(),
  meta: json['meta'] == null
      ? null
      : PageMeta.fromJson(json['meta'] as Map<String, dynamic>),
);

ObjectResponse<T, D>
_$ObjectResponseFromJson<T extends Remote<D>, D extends Domain>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
  D Function(Object? json) fromJsonD,
) => ObjectResponse<T, D>(
  ok: json['success'] as bool?,
  text: json['message'] as String?,
  errors: (json['errors'] as Map<String, dynamic>?)?.map(
    (k, e) =>
        MapEntry(k, (e as List<dynamic>).map((e) => e as String).toList()),
  ),
  data: _$nullableGenericFromJson(json['data'], fromJsonT),
);

T? _$nullableGenericFromJson<T>(
  Object? input,
  T Function(Object? json) fromJson,
) => input == null ? null : fromJson(input);

ListResponse<T, D>
_$ListResponseFromJson<T extends Remote<D>, D extends Domain>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
  D Function(Object? json) fromJsonD,
) => ListResponse<T, D>(
  items: (json['data'] as List<dynamic>?)?.map(fromJsonT).toList(),
);

VoidResponse _$VoidResponseFromJson(Map<String, dynamic> json) =>
    VoidResponse(text: json['message'] as String?);

RecordsBody<T> _$RecordsBodyFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) => RecordsBody<T>(
  records: (json['records'] as List<dynamic>?)?.map(fromJsonT).toList(),
  maxPage: (json['max_page'] as num?)?.toInt(),
  total: (json['total'] as num?)?.toInt(),
  pageSize: (json['page_size'] as num?)?.toInt(),
  page: (json['current_page'] as num?)?.toInt(),
);

RecordsPagedResponse<T, D>
_$RecordsPagedResponseFromJson<T extends Remote<D>, D extends Domain>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
  D Function(Object? json) fromJsonD,
) => RecordsPagedResponse<T, D>(
  body: json['data'] == null
      ? null
      : RecordsBody<T>.fromJson(
          json['data'] as Map<String, dynamic>,
          (value) => fromJsonT(value),
        ),
);
