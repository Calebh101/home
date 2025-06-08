import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_environments_plus/flutter_environments_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homeapp/announcements.dart';
import 'package:homeapp/calendar.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/fireplace.dart';
import 'package:homeapp/glucose.dart';
import 'package:homeapp/settings.dart';
import 'package:homeapp/text.dart';
import 'package:homeapp/tv.dart';
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/error.dart';
import 'package:localpkg/functions.dart';
import 'package:localpkg/theme.dart';
import 'package:localpkg/logger.dart';
import 'package:homeapp/online.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

String version = "2.0.0A";
String homedir = "/var/www/home";

bool forceKiosk = false;
bool forceNativeSpotify = false;
bool allowDebugAlerts = false;
bool alwaysShowTime = true;
bool verbose = false;
bool showUncoloredGlucose = false;
bool allowTvControlsWhenTvIsOff = false;
bool showCalendarForTheNextWeekRenderer = true;
bool dynamicCalendar = false; // deprecated because it looks ugly and also doesn't align days correctly
bool noDashboardUiInKioskMode = true;
bool showRefreshOnWeatherWidget = false;
bool hostHasScreen = true;
bool useIconsForTabs = true;
bool useAutomation = false;
bool useLocalHost = false;

Mode mode = Mode.auto;
Host? defaultHost = Host.debug;
Host? serverHost;
ThemeMode defaultKioskThemeMode = ThemeMode.dark; // experimental

List globalArgs = [];
List dialogues = [];
bool globalDebug = false;
bool globalKiosk = false;
bool globalTest = false;

Timer? loopTimer;
bool forceDarkTheme = kIsWeb && Uri.base.queryParameters["forceDarkTheme"] == "1";
ThemeMode themeMode = forceDarkTheme ? ThemeMode.dark : ThemeMode.system;
StreamController commandController = StreamController.broadcast();
StreamController updateController = StreamController.broadcast();
Map? globalGlucoseLimits;
int? timeBuffer;
bool dexcomCrash = false;
Map updateData = {};

Color getSeed(BuildContext context, {Brightness? brightness}) {
  return (brightness ?? getBrightness(context: context)) == Brightness.light ? Colors.orange : Colors.deepOrange;
}

enum Mode {
  debug,
  release,
  auto,
}

Never test() {
  print(jsonEncode({"defaultHost": defaultHost == null ? null : "$defaultHost".replaceAll("Host.", ""), "serverHost": serverHost == null ? null : "$serverHost".replaceAll("Host.", "")}));
  return exit(0);
}

void main(List args, {bool debug = kDebugMode, bool kiosk = false}) {
  if (args.contains("--test")) {
    print("detected test mode from arg");
    globalTest = true;
    test();
    return;
  }

  if (args.contains('--kiosk')) {
    print("detected kiosk mode from arg");
    kiosk = true;
  }

  if (args.contains('--debug')) {
    print("detected debug mode from arg");
    debug = true;
  }

  if (mode == Mode.release) {
    print("forcing release mode");
    debug = false;
  } else if (mode == Mode.debug) {
    print("forcing debug mode");
    debug = true;
  }

  if (mode == Mode.debug && kDebugMode == false) {
    print("wrong mode: $mode");
    alert(message: "Release test #1 failed: Mode was not set to appropriate mode for non-debug build: $mode", severity: getSeverityFromObject(Severity.low), id: "releasetest-wrongmode");
  }

  if (debug == false && defaultHost != Host.release && defaultHost != Host.forceDebugIgnore) {
    print("wrong host: $defaultHost (enforce)");
    alert(message: "Release test #2 failed: Host was not set to appropriate host for non-debug build: $defaultHost", severity: getSeverityFromObject(Severity.low), id: "releasetest-wronghost", response: 0);
    defaultHost = Host.release;
  }
  
  if (defaultHost == Host.forceDebugIgnore) {
    print("wrong host: $defaultHost (ignore)");
    defaultHost = Host.forceDebug;
  }

  if (forceKiosk) kiosk = true;
  debugPaintSizeEnabled = false;
  globalArgs = args;
  globalDebug = debug;
  globalKiosk = kiosk;

  if (kiosk) {
    themeMode = defaultKioskThemeMode;
  }

  print("setting up initializers...");
  stateInputter();
  taskquarter();
  registerDialogues();

  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (debug) {
    print("implementing http overrides");
    HttpOverrides.global = CustomHttpOverrides();
  }

  loopTimerSetup();
  socket();
  tempMonitor();
  reinit(debug: debug, kiosk: kiosk);

  stateController.stream.listen((data) {
    announcements = data["state"]["announcements"];
  });

  Timer.periodic(Duration(seconds: 30), (Timer timer) {
    updateTvStates();
    updateHomekit();
  });

  if (!debug) {
    window(active: kiosk);
  }
}

class CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return client;
  }
}

void reinit({required bool debug, required bool kiosk}) {
  dexcomSetup();
  runApp(HomeApp(debug: debug, kiosk: kiosk));

  (() async {
    try {
      print("registering glucose limits...");
      Map value = (await request(endpoint: "system/limits"))!["glucose"];
      globalGlucoseLimits = value;
      timeBuffer = globalGlucoseLimits?["timeBuffer"];
      print("registered glucose limits: $globalGlucoseLimits");
    } catch (e) {
      warn("register glucose limits: $e");
      dexcomCrash = true;
    }
  })();
}

Future<Map> checkForUpdates() async {
  print("checking for updates...");
  Map data = (await request(endpoint: "system/version/app"))!;

  updateData = {
    "status": data["version"] != version, // true if updates are available
    "version": data["version"],
  };

  print("check for updates: $updateData");
  updateController.sink.add(updateData); // make sure Dashboard() is aware
  return updateData;
}

void loopTimerSetup() {
  int loopTime = 1000; // milliseconds
  print("setting up loop timer... (interval: $loopTime)");

  loopTimer = Timer.periodic(Duration(milliseconds: loopTime), (timer) {
    alerts = alerts.where((map) {
      DateTime date = DateTime.parse(map['date']);
      bool status = DateTime.now().difference(date).inHours <= 6 || map['show'] == true; // If the alert is at least 6 hours old and if it has been dismissed, we can remove the alert, which will allow the alert to be repeated if it's called again.
      if (status == false) print("removing alert ${map['id']}");
      return status;
    }).toList();
  });
}

Future<void> window({bool active = true}) async {
  if (active && Environment.isDesktop) {
    print("activating windows");
    await windowManager.ensureInitialized();

    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setFullScreen(true);
      await windowManager.setTitle("Home");
      await windowManager.setFullScreen(true);
    });
  }
}

Future<void> socket() async {
  if (globalKiosk || globalDebug) {
    int socketPort = 8020;
    ServerSocket server = await ServerSocket.bind(InternetAddress.loopbackIPv4, socketPort, shared: true);
    print('command listening on port: $socketPort');
    
    await for (Socket client in server) {
      void writeout(Map message) {
        client.writeln(jsonEncode(message));
      }

      void writeerr(int code, [Map? details]) {
        writeout({"code": code, "details": details, "error": true});
      }

      client.listen((data) async {
        String message = String.fromCharCodes(data).trim();
        if (message != "state_dump") print('command received: $message');
        commandController.sink.add(message);

        // this if/else block handles any commands that require a non-generic output
        if (message == "info_dump") {
          writeout({
            "version": {
              "app": version,
            }
          });
        } else if (message == "state_dump") {
          writeout({
            "fireplace": {
              "active": activeFireplace,
              "sound": fireplaceSound,
            },
            "dashboard": {
              "active": dashboardActive,
            },
            "music": {
              "status": await getSpotify(),
            },
            "glucose": {
              "active": glucoseActive,
            },
            "theme": {
              "current": themeMode == ThemeMode.system ? 0 : (themeMode == ThemeMode.dark ? 1 : 0),
              "nightmode": nightMode,
            },
            "alerts": alerts,
          });
        } else if (message == "speedtest") {
          print("speedtest requested");
          final result = await Process.run("$homedir/tools/speedtest", ["--format=json"]);

          if (result.exitCode != 0) {
            warn("result error: ${result.stderr.trim()} (code: ${result.exitCode})");
            request(endpoint: "internet/report/speedtest", body: {"error": result.stderr.trim()});
            writeerr(500);
          } else {
            print("speedtest complete");
            writeout({"result": jsonDecode(result.stdout)});
          }
        } else if (message == "build_description") {
          client.writeln(jsonEncode({"error": "deprecated"}));
          client.close();
          return;
        } else if (message == "exit") {
          print("exiting...");
          exit(0);
        } else {
          // This doesn't mean the command isn't available, just it means there's no data to be sent back.
          writeout({"code": 200});
        }

        // this if/else block handles generic global commands
        if (message.contains("alert_test")) {
          alert(message: "This is a test alert.", severity: getSeverityFromObject(Severity.low), id: "testalert");
        } else if (message.contains("dismiss_alert")) {
          dismissAlert(id: message.split("dismiss_alert")[1].trim());
        } else if (message.contains("set_theme")) {
          int status = int.parse(message.split(' ')[1]);
          print("setting theme to status $status");
          themeMode = status == 1 ? ThemeMode.dark : ThemeMode.light;
          runApp(HomeApp(debug: globalDebug, kiosk: globalKiosk));
        } else if (message.contains("glucose_crash")) {
          dexcomCrash = true;
        } else if (message.contains("fireplace_sound_on")) {
          fireplaceSound = true;
          commandController.sink.add("fireplace_update");
        } else if (message.contains("fireplace_sound_off")) {
          fireplaceSound = false;
          commandController.sink.add("fireplace_update");
        }

        client.close();
      });
    }
  } else {
    print("skipping socket setup: $globalKiosk:$globalDebug (expected false:false)");
  }
}

void dismissAlert({required String id}) {
  print("dismissing alert: $id");
  Map? alert = alerts.firstWhere((element) => element['id'] == id, orElse: () => null);
  
  if (alert == null) {
    print("invalid alert id: $id");
    return;
  }

  alert["show"] = false;
  print("dismissed alert: $id");
}

class HomeApp extends StatelessWidget {
  final bool kiosk;
  final bool debug;
  const HomeApp({super.key, this.kiosk = false, required this.debug});

  @override
  Widget build(BuildContext context) {
    print("building app... (kiosk: $kiosk, debug: $debug)");
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home',
      theme: brandTheme(seedColor: getSeed(context), customFont: GoogleFonts.robotoTextTheme()),
      darkTheme: brandTheme(seedColor: getSeed(context), customFont: GoogleFonts.robotoTextTheme(), darkMode: true, backgroundColor: const Color.fromARGB(255, 15, 15, 15)),
      themeMode: themeMode,
      home: Dashboard(kiosk: kiosk, debug: debug),
    );
  }
}

double decideRotation(int mode, int input) {
  if (mode == 1) {
    return input == 3
        ? 3.14159 / -2
        : input == 2
            ? 3.14159 / -2
            : input == 1
                ? 3.14159 / -4
                : input == -3
                    ? 3.14159 / 2
                    : input == -2
                        ? 3.14159 / 2
                        : input == -1
                            ? 3.14159 / 4
                            : input == 0
                                ? 0
                                : 0;
  } else {
    return 0;
  }
}

int getTrend(String trend) {
  int newTrend = -4;

  switch (trend) {
    case "Flat":
      newTrend = 0;
      break;
    case "FortyFiveDown":
      newTrend = -1;
      break;
    case "FortyFiveUp":
      newTrend = 1;
      break;
    case "SingleDown":
      newTrend = -2;
      break;
    case "SingleUp":
      newTrend = 2;
      break;
    case "DoubleDown":
      newTrend = -3;
      break;
    case "DoubleUp":
      newTrend = 3;
      break;
    case "None":
      newTrend = -4;
      break;
    case "NonComputable":
      newTrend = -4;
      break;
    case "RateOutOfRange":
      newTrend = -4;
      break;
    default:
      newTrend = -4;
      break;
  }

  return newTrend;
}

Future<Map> getConfig() async {
  String path = "$homedir/config.json";
  print("getting config from path $path");
  
  String content = await File(path).readAsString();
  return jsonDecode(content);
}

Brightness getBrightness({required BuildContext context, bool night = false}) {
  return (night || forceDarkTheme) ? Brightness.dark : (themeMode == ThemeMode.dark ? Brightness.dark : (themeMode == ThemeMode.light ? Brightness.light : MediaQuery.of(context).platformBrightness));
}

enum Severity {
  low,
  moderate,
  high,
  extreme,
}

// response
  // 0: add to alerts
  // 1: send email
  // 2: shut down

void alert({required String message, required int severity, required String id, int response = 0}) {
  if (alerts.any((map) => map['id'] == id)) return;
  if (globalKiosk == false && !kDebugMode) return;

  print("received alert: $id");
  alerts.add({"severity": severity, "message": message, "id": id, "show": true, "date": DateTime.now().toIso8601String()});

  if (response >= 1) {
    print("sending email...");
    if (globalDebug) return;
    request(endpoint: 'alert/send', body: {"severity": severity, "message": message}, showError: false);
  }
  if (response >= 2) {
    print('sending shutdown...');
    if (globalDebug) return;
    request(endpoint: 'system/shutdown', showError: false);
  }
}

String getSeverityFromInt(int input) {
  switch (input) {
    case 0: return "Low";
    case 1: return "Moderate";
    case 2: return "High";
    case 3: return "Extreme";
    default: throw Exception("Unknown severity: $input");
  }
}

int getSeverityFromObject(Severity input) {
  switch (input) {
    case Severity.low: return 0;
    case Severity.moderate: return 1;
    case Severity.high: return 2;
    case Severity.extreme: return 3;
  }
}

Color getColorFromSeverity(int input) {
  switch (input) {
    case 0: return Colors.orange;
    case 1: return Colors.deepOrange;
    case 2: return Colors.red;
    case 3: return Colors.pink;
    default: throw Exception("Unknown severity: $input");
  }
}

double tempHigh = 86;
double tempExtreme = 95;

void handleTemp({required String adapter, required String adapterId, required String sensor, required num temperature}) {
  temperature = temperature.toDouble();
  late double threshold;

  if (temperature >= tempHigh) {
    if (temperature >= tempExtreme) {
      threshold = tempExtreme;
    } else {
      threshold = tempHigh;
    }

    if (globalDebug == false || allowDebugAlerts == true) {
      alert(message: 'Sensor "$sensor" on adapter "$adapter ($adapterId)" recorded temperature of $temperature°C. Threshold is $threshold°C.', severity: getSeverityFromObject(temperature >= tempExtreme ? Severity.extreme : Severity.high), id: "sensor:$sensor;adapter:$adapter,temp:>$threshold", response: 1);
    }
  }
}

Color? getColorForTemp(num input) {
  if (input >= 30) {
    if (input >= 55) {
      if (input >= 75) {
        if (input >= 85) {
          return Colors.pink;
        } else {
          return Colors.red;
        }
      } else {
        return Colors.orange;
      }
    } else {
      return Colors.green;
    }
  } else {
    if (input <= 0) {
      return null;
    } else {
      return Colors.blue;
    }
  }
}

Color? getColorForTime(int time) {
  if (timeBuffer == null) return null;

  if (time >= 240) {
    if (time >= (300 + timeBuffer!)) {
      if (time >= 600) {
        return Colors.red;
      } else {
        return Colors.deepOrange;
      }
    } else {
      return Colors.orange;
    }
  } else {
    return Colors.green;
  }
}

Color? getColorForTrend(String trend) {
  if (globalGlucoseLimits == null) return null;
  bool showColorOnSlowTrend = globalGlucoseLimits?["colorOnSlowTrend"] ?? false;

  switch (trend) {
    case "Flat": return Colors.green;
    case "FortyFiveDown": return showColorOnSlowTrend ? Colors.orange : Colors.green;
    case "FortyFiveUp": return showColorOnSlowTrend ? Colors.orange : Colors.green;
    case "SingleDown": return showColorOnSlowTrend ? Colors.deepOrange : Colors.orange;
    case "SingleUp": return showColorOnSlowTrend ? Colors.deepOrange : Colors.orange;
    case "DoubleDown": return Colors.red;
    case "DoubleUp": return Colors.red;
    default: return null;
  }
}

Color? getColorForValue(int value) {
  if (globalGlucoseLimits != null) {
    if (value <= 90) {
      if (value <= 70) {
        if (value <= 55) {
          return Colors.red;
        } else {
          return Colors.deepOrange;
        }
      } else {
        return Colors.orange;
      }
    } else if (value >= 150) {
      if (value >= 180) {
        if (value >= 240) {
          return Colors.red;
        } else {
          return Colors.deepOrange;
        }
      } else {
        return Colors.orange;
      }
    } else {
      return Colors.green;
    }
  } else {
    return null;
  }
}

Widget generateArrow(String direction, {required BuildContext context, double size = 1}) {
  int trend = getTrend(direction);

  Color getTrendColor(String direction) {
    return getColorForTrend(direction) ?? getThemeColor(context);
  }

  return Stack(
    children: [
      if (trend >= -3)
      Transform.rotate(
        angle: decideRotation(1, trend),
        child: Icon(Icons.arrow_forward, size: 50.0 * size, color: getTrendColor(direction)),
      ),
      if (trend <= -4)
      SizedBox(width: 10),
      if (trend == 3 || trend == -3)
      Row(
        children: [
          SizedBox(width: 30 * size),
          Icon(trend == 3 ? Icons.arrow_upward : Icons.arrow_downward, size: 50.0 * size, color: getTrendColor(direction)),
        ],
      ),
    ],
  );
}

enum RoundMode {
  oneth,
  tenth,
}

void taskquarter() {
  print("setting up task.quarter");
  void run() {
    (() {
      print("running task.quarter at ${DateTime.now()}");
      updateWeather();
      updateCalendar();
      checkForUpdates();
    })();

    final now = DateTime.now();
    final nextQuarter = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 15 + 1) * 15 % 60,
    );

    final nextExecution = nextQuarter.minute == 0 && now.minute >= 45
        ? nextQuarter.add(Duration(hours: 1))
        : nextQuarter;

    final durationUntilNext = nextExecution.difference(now);
    Timer(durationUntilNext, run);
  }

  final now = DateTime.now();
  final minutesPastQuarter = now.minute % 15;
  final secondsUntilNextQuarter = ((15 - minutesPastQuarter) % 15) * 60 - now.second;
  Timer(Duration(seconds: secondsUntilNextQuarter), run);
}

Color getHue(double hue) {
  return HSVColor.fromAHSV(1.0, hue % 256, 0.6, 1).toColor();
}

List<GradientColor> getGradientForTemp(num value) {
  if (value < 70) {
    return [GradientColor(Colors.blue), GradientColor(Colors.lightBlueAccent)];
  } else if (value > 75) {
    return [GradientColor(Colors.deepOrange), GradientColor(Colors.yellow)];
  } else {
    return [GradientColor(Colors.white, intensity: 2)];
  }
}

num getTemp(num value, {RoundMode roundMode = RoundMode.tenth}) { // set to fahrenheit and round to nearest 10th
  num value2 = ((value * 9/5) + 32);
  if (roundMode == RoundMode.tenth) {
    return (value2 * 10).round() / 10;
  } else if (roundMode == RoundMode.oneth) {
    return value2.round();
  } else {
    throw Exception("Invalid roundMode: $roundMode");
  }
}

String getModeForHeatCool(int value) {
  switch (value) {
    case 0: return "Off";
    case 1: return "Heat";
    case 2: return "Cool";
    case 3: return "Auto";
    case 4: return "Aux";
    default: throw Exception("Invalid heat/cool value: $value");
  }
}

Color? getColorForHeatCool(value) {
  switch (value) {
    case 0: return null;
    case 1: return Colors.orangeAccent;
    case 2: return Colors.lightBlue;
    case 3: return Colors.green;
    case 4: return Colors.deepOrange;
    default: throw Exception("Invalid heat/cool value: $value");
  }
}

Color getColorForOffset(num num1, num num2) {
  num offset = (num1 - num2).abs();
  bool positive = (num1 - num2) > 0;
  if (offset > 2) {
    if (positive) {
      return Colors.yellow;
    } else {
      return Colors.blue;
    }
  } else {
    return Colors.green;
  }
}

Color getThemeColor(BuildContext context) {
  return getColor(context: context, type: ColorType.theme, brightness: getBrightness(context: context));
}

class AdminPasswordDialogue extends StatefulWidget {
  const AdminPasswordDialogue({super.key});

  @override
  State<AdminPasswordDialogue> createState() => _AdminPasswordDialogueState();
}

class _AdminPasswordDialogueState extends State<AdminPasswordDialogue> {
  TextEditingController controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Password',
            ),
          ),
        ),
        IconButton(onPressed: () {
          adminPassword = controller.text;
          if (adminPassword == "") adminPassword = null;
          Navigator.of(context).pop();
        }, icon: Icon(Icons.check), color: getThemeColor(context)),
      ],
    );
  }
}

void showSectionDialogue({required BuildContext context, required String id, bool override = false}) {
  if (!dialogues.any((item) => item.id == id)) {
    warn("Invalid dialogue: $id (valid dialogues: ${dialogues.map((item) => item.id).join(", ")}) (Did you forget to add .register()?)");
    return;
  }

  if (globalKiosk) return;
  Dialogue dialogue = dialogues.firstWhere((item) => item.id == id);
  print("calling section dialogue: $id (${dialogue.section})");
  dialogue.trigger(context: context, override: override);
}

Future<void> resetDialogueStatus() async {
  print("clearing ${dialogues.length} dialogue statuses");
  SharedPreferences prefs = await SharedPreferences.getInstance();

  for (Dialogue dialogue in dialogues) {
    prefs.remove("${dialogue.id}-dialogue");
  }
}

class Dialogue {
  String id;
  String section;
  String title;
  List<String> description;

  // ignore: unused_field
  bool _registered = false;
  bool _placeholder = false;

  Dialogue({required this.id, required this.section, required this.title, required this.description});

  Dialogue.placeholder({required this.id, required this.section, required this.title, this.description = const []}) {
    description = ["This is placeholder dialogue."];
    _placeholder = true;
  }

  void register() {
    dialogues.add(this);
    _registered = true;
    if (_placeholder) warn("Dialogue $id is a placeholder.");
  }

  void trigger({required BuildContext context, bool override = false}) {
    showFirstTriggerDialogue(context: context, key: "$id-dialogue", title: title, ignorePrefs: override, children: List.generate(description.length, (int i) {
      return Text(description[i]);
    }));
  }
}

enum CrashSeverity {
  low,
  high,
}

void CrashReport({required BuildContext context, String title = "Unexpected Error", required String text, String content = "There was an unexpected error running the application. Please report this error.", String? trace, String code = "-1", CrashSeverity severity = CrashSeverity.low, bool showTrace = true}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    switch (severity) {
      case CrashSeverity.low:
        showDialogue(context: context, title: title, content: Text(content));
        break;

      case CrashSeverity.high:
        CrashScreen(message: title, description: "$content\n$text", code: code, trace: showTrace ? "${trace ?? StackTrace.current}" : null, close: false, support: false, retryFunction: () {
          runApp(HomeApp(debug: globalDebug, kiosk: globalKiosk));
        });
        break;
    }
  });
}