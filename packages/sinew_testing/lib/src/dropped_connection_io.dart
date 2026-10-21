import 'dart:io';

import 'package:dio/dio.dart';

/// What `IOHttpClientAdapter` throws when the connection drops.
Object droppedConnection(RequestOptions options) =>
    const SocketException('Connection reset by peer');
