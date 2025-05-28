import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:homeapp_android_host/online.dart';
import 'package:homeapp_android_host/settings.dart';
import 'package:localpkg/dialogue.dart';
import 'package:number_pad_keyboard/number_pad_keyboard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:localpkg/logger.dart';

String version = "1.0.0A";
bool debug = kDebugMode;
bool verbose = true;
String host = debug ? "http://192.168.0.21" : "https://home.calebh101.com";

bool dark = true;
bool showLoadingProgress = false;
bool lockDashboard = true;
String settingsPasscode = '0000';
String? dashboardPasscode;
bool locked = true;
bool useCamera = false;
bool entireDashboardLocked = lockDashboard;
double opacity = 0;
int time = 0;
int timeout = 20; // seconds
double imageDifferenceThreshold = 0.5; // percent
int cameraProcessInterval = 50; // ms
CameraController? cameraController;
StreamController cameraStream = StreamController.broadcast();
String? globalerror;
int stateUpdateInterval = 2000; // ms

void main() async {
  print("initializing app...");
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  WebViewPlatform.instance = AndroidWebViewPlatform();
  SharedPreferences prefs = await SharedPreferences.getInstance();

  if (debug) {
    print("implementing http overrides");
    HttpOverrides.global = WebsocketOverrides();
  }

  await setupPrefs();
  init(prefs.getString("id"));

  print("running preflight prefs logic...");
  lockDashboard = dashboardPasscode?.isNotEmpty ?? false;
  entireDashboardLocked = lockDashboard;

  print("running app...");
  runApp(const MyApp());
}

Future<void> setupPrefs() async {
  print("getting preferences...");
  await cameraController?.stopImageStream();
  SharedPreferences prefs = await SharedPreferences.getInstance();

  dark = prefs.getBool("darkMode") ?? dark;
  showLoadingProgress = prefs.getBool("showLoadingProgress") ?? showLoadingProgress;
  settingsPasscode = prefs.getString("settingsPasscode") ?? settingsPasscode;
  dashboardPasscode = prefs.getString("dashboardPasscode") ?? dashboardPasscode;
  timeout = prefs.getInt("screenTimeout") ?? timeout;
  useCamera = prefs.getBool("useCamera") ?? useCamera;
  cameraProcessInterval = prefs.getInt("cameraProcessInterval") ?? cameraProcessInterval;
  imageDifferenceThreshold = prefs.getDouble("imageDifferenceThreshold") ?? imageDifferenceThreshold;
  stateUpdateInterval = prefs.getInt("stateUpdateInterval") ?? stateUpdateInterval;

  if (useCamera == true) {
    await initCameras();
  }
}

Future<void> initCameras() async {
  print("initializing cameras...");
  List cameras = await availableCameras();
  CameraDescription? camera;

  for (var cam in cameras) {
    if (cam.lensDirection == CameraLensDirection.front) {
      camera = cam;
      print("found camera: $cam");
      break;
    }
  }

  if (camera == null) {
    warn("No front camera found.");
    return;
  }

  cameraController = CameraController(camera, ResolutionPreset.low, enableAudio: false);
  await cameraController!.initialize();
  CameraImage? prevImage;
  Timer? timer;
  print("camera initialized");

  cameraController!.startImageStream((CameraImage image) {
    if (timer?.isActive ?? false) {
      return;
    }

    timer = Timer(Duration(milliseconds: cameraProcessInterval), () {});

    if (prevImage == null) {
      print("camera image stream: prevImage is null (correcting)");
      prevImage = image;
      return;
    }

    bool different = framesDifferent(prevImage!, image);
    prevImage = image;

    if (different) {
      cameraStream.sink.add(true);
    }
  });
}

bool framesDifferent(CameraImage a, CameraImage b) {
  List<int> getBytes(CameraImage image) {
    return List.generate(image.planes.length, (int i) {
      Plane plane = image.planes[i];
      return plane.bytes;
    }).expand((x) => x).toList();
  }

  Set<int> bytesA = getBytes(a).toSet();
  Set<int> bytesB = getBytes(b).toSet();
  int different = bytesA.difference(bytesB).length + bytesB.difference(bytesA).length;
  int threshold = (bytesA.length * imageDifferenceThreshold).round();

  if (different > threshold) {
    print("image reached threshold of movement: $different to $threshold");
    return true;
  }

  return false;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home Host',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
      ),
      home: Home(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    );
  }
}

Future<void> resetDeviceID({required BuildContext context}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text("Register"),
          content: RegisterPrompts(),
        ),
      );
    },
  );

  if (!context.mounted) return;
  showConstantDialogue(context: context, message: "Please close and reopen the app for your changes to take effect.");
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int loading = 0;
  WebViewController controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)..loadRequest(Uri.parse("$host/?forceDarkTheme=${dark ? 1 : 0}"));
  MethodChannel channel = MethodChannel('com.calebh101.homeapphost.channel');
  Timer? timer;
  StreamSubscription? cameraSubscription;

  @override
  void initState() {
    (() async {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? id = prefs.getString("id");
      if (id == null && mounted) await resetDeviceID(context: context);
    })();

    controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int progress) {
          loading = progress;
          setState(() {});
        },
        onPageStarted: (String url) {
          print("page start: $url");
        },
        onPageFinished: (String url) {
          print("page finish: $url");
        },
        onHttpError: (HttpResponseError e) {},
        onWebResourceError: (WebResourceError e) {
          globalerror = "Web resource error: ${e.description}";
          print("error: $globalerror");
          setState(() {});
        },
        onNavigationRequest: (NavigationRequest request) {
          print("navigating to: $request");
          return NavigationDecision.navigate;
        },
      ),
    );

    timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      time++;
      setState(() {});
      if (time >= timeout) sleep();
    });

    channel.setMethodCallHandler((call) async {
      print("method call: ${call.method}");
      if (call.method == "onFocus") {
        onFocus();
      }
    });

    cameraSubscription = cameraStream.stream.listen((data) {
      if (data == true) {
        print("camera wakeup called");
        wakeup();
      }
    });

    print("initializing controller with host: $host");
    super.initState();
  }

  void lockSettings() {
    locked = true;
    print("locked");
    setState(() {});
  }

  void onFocus() {
    print("onFocus called (progress: $lockDashboard)");
    if (lockDashboard == false) return;
    entireDashboardLocked = true;

    showPinInput(
      context: context,
      onValid: (BuildContext context) {
        print("pin valid");
        entireDashboardLocked = false;
        setState(() {});
      },
      method: PinInputType.dashboard,
      canPop: () => !entireDashboardLocked,
    );
  }

  void setOpacity(bool status) {
    opacity = status ? 0 : 1;
    setState(() {});
  }

  void wakeup() {
    time = 0;
    setOpacity(true);
    onFocus();
  }
  
  void sleep() {
    if (locked == false || entireDashboardLocked == true) {
      time = 0;
      setState(() {});
      return;
    }
    setOpacity(false);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (verbose) {
      print("verbose: building widget... (opacity: $opacity) (time: $time)");
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        print("back button pressed");
        showPinInput(
          context: context,
          onValid: (BuildContext context) {
            locked = false;
            setState(() {});
          },
        );
      },
      child: TapRegion(
        onTapInside: (event) {
          print("detected gesture: $event");
          wakeup();
        },
        child: Stack(
          children: [
            Scaffold(
              appBar:
                  locked
                      ? null
                      : AppBar(
                        leading: IconButton(
                          icon: Icon(Icons.lock),
                          onPressed: () {
                            lockSettings();
                          },
                        ),
                        actions: [
                          IconButton(
                            icon: Icon(Icons.refresh),
                            onPressed: () {
                              controller.reload();
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.settings),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => Settings()),
                              );

                              await setupPrefs();
                              setState(() {});
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.power_settings_new),
                            onPressed: () {
                              lockSettings();
                              sleep();
                            },
                          ),
                        ],
                      ),
              body: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child:
                    entireDashboardLocked
                        ? Center(child: Icon(Icons.lock, size: 196))
                        : (globalerror == null
                            ? (loading >= 100
                                ? WebViewWidget(controller: controller)
                                : Center(
                                  child: CircularProgressIndicator(
                                    value:
                                        showLoadingProgress == false
                                            ? null
                                            : (loading / 100),
                                  ),
                                ))
                            : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 196,
                                  ),
                                  Text(
                                    "$globalerror",
                                    style: TextStyle(fontSize: 28),
                                  ),
                                ],
                              ),
                            )),
              ),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                duration: Duration(milliseconds: opacity == 1 ? 2000 : 500),
                opacity: opacity,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showPinInput({
  required BuildContext context,
  required void Function(BuildContext context) onValid,
  PinInputType method = PinInputType.settings,
  bool Function()? canPop,
}) {
  Widget child;
  switch (method) {
    case PinInputType.settings:
      child = SettingsPinInput(onValid: onValid);
    case PinInputType.dashboard:
      child = DashboardPinInput(onValid: onValid);
  }

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: PopScope(canPop: (canPop ?? (() => true))(), child: child),
        ),
      );
    },
  );
}

enum PinInputType { settings, dashboard }

abstract class PinInput extends StatefulWidget {
  final void Function(BuildContext context) onValid;
  const PinInput({super.key, required this.onValid});
}

class SettingsPinInput extends PinInput {
  const SettingsPinInput({super.key, required super.onValid});

  @override
  State<PinInput> createState() => _SettingsPinInputState();
}

class _SettingsPinInputState extends State<SettingsPinInput> {
  TextEditingController controller = TextEditingController();
  String label = 'PIN';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: label,
                border: OutlineInputBorder(),
              ),
              onChanged: (String text) {
                if (text != '') {
                  label = 'PIN';
                  setState(() {});
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: () {
              if (controller.text == settingsPasscode) {
                print("pin input: valid");
                widget.onValid(context);
                Navigator.of(context).pop();
              } else {
                print("pin input: invalid (${controller.text})");
                label = 'Invalid';
                controller.text = "";
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }
}

class DashboardPinInput extends PinInput {
  const DashboardPinInput({super.key, required super.onValid});

  @override
  State<DashboardPinInput> createState() => _DashboardPinInputState();
}

class _DashboardPinInputState extends State<DashboardPinInput> {
  String text = '';
  String label = 'PIN';

  void onEnter(BuildContext context, {bool useElse = true}) {
    if (text == dashboardPasscode) {
      print("pin input: valid");
      widget.onValid(context);
      Navigator.of(context).pop();
    } else if (useElse) {
      print("pin input: invalid ($text)");
      label = 'Invalid';
      text = "";
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (text.length == dashboardPasscode!.length) {
      (() async {
        print("pin input: length reached (${text.length})");
        await Future.delayed(Duration(milliseconds: 250));
        if (!mounted) return;
        onEnter(context, useElse: false);
      })();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 20)),
        Text(text, style: TextStyle(fontSize: 36)),
        NumberPadKeyboard(
          addDigit: (int value) {
            text += "$value";
            label = 'PIN';
            setState(() {});
          },
          backspace: () {
            if (text.isEmpty) return;
            text = text.substring(0, text.length - 1);
            setState(() {});
          },
          onEnter: () {
            print("pin input: enter reached");
            onEnter(context);
          },
        ),
      ],
    );
  }
}
