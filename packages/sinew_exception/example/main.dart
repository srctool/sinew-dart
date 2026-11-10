// ignore_for_file: avoid_print

import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

Future<String> loadOrder() async {
  throw const FormatException('not json');
}

Future<void> main() async {
  // region guard
  // A guard turns whatever a call throws into a typed failure, once, where it
  // happened. The handlers say which errors mean what for this layer.
  final result = await processCall<String>(
    'ORD',
    'load',
    ExceptionLayer.repository,
    [
      ExceptionHandler(
        (error) => error is FormatException,
        (error) =>
            const ParseException('ORD', ExceptionLayer.repository, 'load'),
      ),
    ],
    loadOrder,
  );
  // endregion

  result.when(
    success: (order, message) => print('Loaded $order'),
    // The code reads module-layer-function-type, so a support report points at
    // the exact call.
    failure: (error, stackTrace) => print('Failed with ${error.code}'),
  );
}
