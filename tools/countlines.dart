import 'dart:convert';
import 'dart:io';
import 'dart:math';

// Version 1.0.0
// Run with --json for a plain JSON output.

bool json = false;
Map<String, dynamic> data = {"languages": {}};

List<HomeFile> files = [
  file("server/server.js", language: Language.JavaScript),
  file("server/socket.js", language: Language.JavaScript),
  file("server/vizio.js", language: Language.JavaScript),
  file("server/vizio.js", language: Language.JavaScript),
  file("server/localpkg.cjs", language: Language.JavaScript),
  file("server/api.js", language: Language.JavaScript),
  file("server/services/announcer.js", language: Language.JavaScript),
  ...directory("app/lib", language: Language.Dart),
  ...directory("android/flutter/lib", language: Language.Dart),
  ...directory("tools", language: Language.Dart, extensions: ["dart"], recursive: false),
  ...directory("tools", language: Language.Shell, extensions: ["sh"], recursive: false, exempted: ["fancontrol.sh"])
];

List<HomeFile> directory(String path, {required Language language, List? extensions, List exempted = const [], bool recursive = true}) {
  final dir = Directory(path);
  return dir.listSync(recursive: recursive).whereType<File>().where((File file) => (extensions == null || extensions.contains(file.path.split(".").last) && !exempted.contains(file.path.split("/").last))).map((File f) => file(f.path, language: language)).toList();
}

HomeFile file(String path, {required Language language}) {
  return HomeFile("/var/www/home/$path", language: language);
}

void main(List<String> args) {
  if (args.contains("--json")) json = true;
  int allTotal = 0;

  for (Language language in Language.values) {
    List languageFiles = files.where((HomeFile file) => file.language == language).toList();
    List filedata = [];
    int total = 0;

    for (HomeFile file in languageFiles) {
      String data = File(file.path).readAsStringSync();
      List<String> lines = data.split("\n");
      total = total + lines.length;
      filedata.add({"file": file.path, "lines": lines.length});
    }

    allTotal = allTotal + total;
    data["languages"][getStringForLanguage(language)] = {"files": filedata, "lines": total, "totalFiles": languageFiles.length};
  }

  data["lines"] = allTotal;
  data["files"] = files.length;
  data["totalLanguages"] = Language.values.length; // all languages
  outputjson(data);

  output("${AsciiEffect.bold}${AsciiEffect.red}Total files: ${data["files"]}\n${AsciiEffect.green}Total languages: ${data["totalLanguages"]}\n${AsciiEffect.blue}Total lines: ${data["lines"]}${AsciiEffect.reset}");
  ln();
  List colors = [];

  (data["languages"] as Map).forEach((key, value) {
    if (colors.isEmpty) colors = [AsciiEffect.red, AsciiEffect.green, AsciiEffect.blue, AsciiEffect.yellow, AsciiEffect.magenta, AsciiEffect.cyan];
    int colorIndex = Random().nextInt(colors.length);
    String color = colors[colorIndex];
    colors.removeAt(colorIndex);
    output("$color$key: ${value["totalFiles"]} files, ${value["lines"]} lines${AsciiEffect.reset}");
  });
}

void log(dynamic input, {bool override = false}) {
  if (json && override == false) return;
  print(input.runtimeType == Map || input.runtimeType == List || input.runtimeType == Set ? jsonEncode(input) : "$input");
}

void output(dynamic input) {
  log(input);
}

void ln() {
  log("");
}

void outputjson(dynamic input) {
  if (!json) return;;
  print(jsonEncode(input));
}

enum Language {
  JavaScript,
  Dart,
  Shell,
}

class HomeFile {
  String path;
  Language language;
  int lines;
  HomeFile(this.path, {required this.language, this.lines = 0});
}

String getStringForLanguage(Language language) {
  return language.toString().replaceFirst("Language.", "");
}

class AsciiEffect {
  static String reset = "\x1B[0m";
  static String bold = "\x1B[1m";
  static String defaultColor = "\x1B[33m";
  static String red = "\x1B[31m";
  static String green = "\x1B[32m";
  static String blue = "\x1B[34m";
  static String yellow = "\x1B[33m";
  static String magenta = "\x1B[35m";
  static String cyan = "\x1B[36m";
  static String white = "\x1B[37m";
}