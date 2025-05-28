import 'package:flutter/foundation.dart';
import 'package:localpkg/logger.dart';
import 'package:web/web.dart' as web;

void _init() {
  print("web service: init");
  if (!kIsWeb) {
    throw Exception("Platform is not web in kIsWeb in web.dart.");
  }
}

void reload() {
  _init();
  Uri uri = Uri.base;
  int reloads = int.tryParse("${uri.queryParameters["reload"]}") ?? 0;

  uri = uri.replace(queryParameters: {
    ...uri.queryParameters,
    'reload': "${reloads + 1}",
  });

  if (reloads >= 3) {
    throw Exception("Maximum reloads hit: $reloads");
  }

  print("reloading page... (reload: $reloads)");
  web.window.location.href = "$uri";
}