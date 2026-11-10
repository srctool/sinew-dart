// ignore_for_file: avoid_print

import 'package:sinew_models/sinew_models.dart';

// region models
/// What the app needs, in business language.
final class Order extends Domain {
  const Order(this.id, this.title);

  final int id;
  final String title;

  @override
  List<Object?> get props => [id, title];

  @override
  String toString() => 'Order($id, $title)';
}

/// What the backend sends, shaped like its JSON.
final class OrderRemote extends Remote<Order> {
  const OrderRemote(this.id, this.title);

  final int id;
  final String title;

  @override
  Order toDomain() => Order(id, title);
}

/// A response body: one order under `data`.
final class OrderEnvelope extends ObjectEnvelope<OrderRemote, Order> {
  const OrderEnvelope(this.data);

  @override
  final OrderRemote? data;
}
// endregion

void main() {
  // The envelope maps the backend's shape to the domain.
  const body = OrderEnvelope(OrderRemote(7, 'Two coffees'));
  final Result<Order> result = Result.success(body.toDomain());

  // region result
  // A Result is a success or a failure, never both: read it with `when`.
  final text = result.when(
    success: (order, message) => 'Loaded $order',
    failure: (error, stackTrace) => 'Failed: ${error.code}',
  );
  print(text);
  // endregion

  // A page renders a ViewState. Loading and Failed can keep the previous data.
  final ViewState<Order> state = Done(result.requireData());
  print(state);
}
