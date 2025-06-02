import 'package:flutter/foundation.dart';
import 'package:localpkg/logger.dart';
import 'package:web/web.dart' as web;

int reloads = int.tryParse("${Uri.base.queryParameters["reload"]}") ?? 0;

void _init() {
  print("web service: init");
  if (!kIsWeb) {
    throw Exception("Platform is not web in kIsWeb in web.dart.");
  }

  Future.delayed(Duration(seconds: 10), () {
    if (reloads >= 3) return;
    reloads = 0;
    print("reloads set to $reloads");
  });
}

void reload() {
  _init();
  Uri uri = Uri.base;

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