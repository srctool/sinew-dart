/// The paging fakes alone, free of Flutter: for packages tested with
/// `dart test`, which can't load the network fakes (`sinew_network` imports
/// Flutter through `connectivity_plus`). `sinew_testing.dart` exports them too.
library;

export 'src/controlled_fetch.dart';
