import 'dart:core';
import 'dart:io';

String approot = "/var/www/home/app";
int threw = 0;

void print(Object? input, {int? color}) {
  stdout.writeln("\x1b[${color ?? Colors.reset}m$input\x1b[${Colors.reset}m");
}

// Only for test fails. Use other methods for general execution warns/errors.
void testwarn(Object? input, {required String file}) {
  threw++;
  print("WARNING: $input in $file!", color: Colors.yellow);
}

void main() {
  print("Starting code tests...");
  String main = "$approot/lib/main.dart";
  String maincode = File(main).readAsStringSync();

  if (!maincode.contains(RegExp(r'Host\??\s*defaultHost\s*=\s*Host\.release', multiLine: true))) {
    testwarn("defaultHost assignment is not Host.release", file: main);
  }

  if (!maincode.contains(RegExp(r'Host\??\s*serverHost\s*=\s*Host\.release', multiLine: true)) && !maincode.contains(RegExp(r'Host\??\s*serverHost;', multiLine: true))) {
    testwarn("serverHost assignment is not Host.release", file: main);
  }

  if (!maincode.contains(RegExp(r'bool\??\s*forceKiosk\s*=\s*false', multiLine: true))) {
    testwarn("forceKiosk assignment is not false", file: main);
  }

  if (!maincode.contains(RegExp(r'bool\??\s*useLocalHost\s*=\s*false', multiLine: true))) {
    testwarn("useLocalHost assignment is not false", file: main);
  }

  String textdart = "$approot/lib/text.dart";
  String textdartcode = File(textdart).readAsStringSync();

  textdartcode.split("\n").asMap().forEach((int i, String line) {
    if (line.contains("Dialogue.placeholder")) {
      testwarn("Dialogue.placeholder found at line ${i + 1}", file: textdart);
    }
  });

  if (threw > 0) {
    print("Code testing failed with $threw error${threw == 1 ? "" : "s"}!", color: Colors.red);
  } else {
    print("Code testing passed!", color: Colors.green);
  }

  exit(threw > 0 ? 1 : 0);
}

class Colors {
  static int red = 31;
  static int yellow = 33;
  static int green = 32;
  static int reset = 0;
}
