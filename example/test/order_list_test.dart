import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'order_list_flow.dart';

void main() {
  // Android clamps a pull at the top and iOS bounces it, and the list handles
  // them differently, so the flow runs on both.
  testWidgets(
    'the list screen runs its full cycle',
    runOrderListFlow,
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
