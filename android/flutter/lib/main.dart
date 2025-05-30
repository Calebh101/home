import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:device_policy_controller/device_policy_controller.dart';
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
 
// Most of these variables are set later by SharedPreferences. Right now they have the default value.
// Some others are also just variables like stream controllers.
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

// Main function. Asynchronous for shared preferences stuff.
void main() async {
  print("initializing app...");
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); // Make the app go into fullscreen anda hide controls.
  WebViewPlatform.instance = AndroidWebViewPlatform(); // Initialize the Android WebView.

  if (!Platform.isAndroid) {
    throw Exception("Platform is not Android! Android is required for this application.");
  }

  if (debug) {
    print("implementing http overrides...");
    HttpOverrides.global = WebsocketOverrides(); // To allow connecting to unsigned certificates.
  }

  try {
    // Set some policies with the device policy controller. Also request permissions if applicable.
    print("setting policies...");
    DevicePolicyController dpc = DevicePolicyController.instance;
    await dpc.requestAdminPrivilegesIfNeeded();
    await dpc.lockApp(home: true);
  } catch (e) {
    warn("device policy controller: $e");
  }

  await setupPrefs();
  print("running app...");
  runApp(const MyApp());
}

// Setup shared preferences settings. It tries to find the value in shared preferences, but it falls back to itself if not found.
Future<void> setupPrefs() async {
  print("getting preferences...");
  await cameraController?.stopImageStream(); // Make sure the image stream isn't running.
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

  // Some extra stuff that uses some preferences to be set.
  lockDashboard = dashboardPasscode?.isNotEmpty ?? false;
  entireDashboardLocked = lockDashboard;

  if (useCamera == true) {
    await initCameras(); // Reinitialize cameras.
  }
}

// Start camera streams for motion detection.
Future<void> initCameras() async {
  print("initializing cameras...");
  List cameras = await availableCameras();
  CameraDescription? camera;

  // Find the first front camera. We don't need the back cameras.
  for (CameraDescription cam in cameras) {
    if (cam.lensDirection == CameraLensDirection.front) {
      camera = cam;
      print("found camera: $cam");
      break;
    }
  }

  // No camera found, we can't setup motion detection. Warn via the console and don't continue.
  if (camera == null) {
    warn("No front camera found.");
    return;
  }

  cameraController = CameraController(camera, ResolutionPreset.low, enableAudio: false);
  await cameraController!.initialize();
  CameraImage? prevImage;
  Timer? timer;
  print("camera initialized");

  // Start the image stream.
  cameraController!.startImageStream((CameraImage image) {
    if (timer?.isActive ?? false) {
      return;
    }

    // This makes sure we're not processing every single frame, only one per the specified interval.
    timer = Timer(Duration(milliseconds: cameraProcessInterval), () {});

    // If the previous image hasn't been found, what can we compare the current image to?
    if (prevImage == null) {
      print("camera image stream: prevImage is null (correcting)");
      prevImage = image;
      return;
    }

    // Get if they're different, then set the previous image to this image.
    bool different = framesDifferent(prevImage!, image);
    prevImage = image;

    if (different) {
      // Notify.
      cameraStream.sink.add(true);
    }
  });
}

bool framesDifferent(CameraImage a, CameraImage b) {
  List<int> getBytes(CameraImage image) {
    // When inputted an image, we get each plane, then extract the raw bytes from that plane. We then compile this "list of lists" to one big list to return it.
    return List.generate(image.planes.length, (int i) {
      Plane plane = image.planes[i];
      return plane.bytes;
    }).expand((x) => x).toList();
  }

  Set<int> bytesA = getBytes(a).toSet();
  Set<int> bytesB = getBytes(b).toSet();

  // Get their difference.
  int different = bytesA.difference(bytesB).length + bytesB.difference(bytesA).length;
  int threshold = (bytesA.length * imageDifferenceThreshold).round(); // imageDifferenceThreshold is a percent, not a set value. threshold is dependent on the camera's resolution.

  if (different > threshold) {
    // Detected a big enough difference.
    print("image reached threshold of movement: $different to $threshold");
    return true;
  }

  // Else, no difference found, just continue.
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

// Function to reshow the register dialogue. It is not dismissable.
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
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home> {
  int loading = 0;
  // Unrestricted JavaScript, and forceDarkTheme set based on preferences.
  WebViewController controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)..loadRequest(Uri.parse("$host/?forceDarkTheme=${dark ? 1 : 0}"));
  MethodChannel channel = MethodChannel('com.calebh101.homeapphost.channel');
  Timer? timer;
  StreamSubscription? cameraSubscription;

  @override
  void initState() {
    (() async { 
      // If it hasn't been registered, force the user to register it.
      SharedPreferences prefs = await SharedPreferences.getInstance();
      init(prefs.getString("id"), widget: this);
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

    // Sleep timer.
    timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      time++;
      setState(() {});
      if (time >= timeout) sleep();
    });

    // Detect when the app has been focused upon or has lost focus. This typically happens when turning on the device while the app is pinned.
    channel.setMethodCallHandler((call) async {
      print("method call: ${call.method}");
      if (call.method == "onFocus") {
        deviceAwake = true;
        onFocus();
      } else if (call.method == "onPause") {
        deviceAwake = false;
      }
    });

    // This is where we receive the "true" that the camera image stream put out.
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

  // Here's where we receive onFocus.
  void onFocus() {
    print("onFocus called (progress: $lockDashboard)");
    if (lockDashboard == false) return; // We shouldn't lock the dashboard if the user doesn't want us to.
    entireDashboardLocked = true;

    // Show a pin input before allowing them in.
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

  // Change opacity and set state. opacity is the opacity of a big black box that goes over the screen.
  void setOpacity(bool status) {
    setOpacityGlobal(status);
    setState(() {});
  }

  // Set opacity to true (0) and also call onFocus.
  void wakeup() {
    time = 0;
    setOpacity(true);
    onFocus();
  }

  // If admin is unlocked or the dashboard is locked, then reset the timer and don't sleep. Else, set opacity to false (1).
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

    // We override the default back button behavior, and instead we show a pin input to unlock admin settings.
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
      child: TapRegion( // Detect any gestures on the screen whatsoever, and make sure timer is 0 and we're awake.
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
                            // Lock the admin settings back.
                            lockSettings();
                          },
                        ),
                        actions: [
                          IconButton(
                            icon: Icon(Icons.refresh),
                            onPressed: () {
                              // Reload the webpage.
                              controller.reload();
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.settings),
                            onPressed: () async {
                              // Open settings.
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => Settings()),
                              );

                              // Reload preferences after exiting.
                              await setupPrefs();
                              setState(() {});
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.power_settings_new),
                            onPressed: () {
                              // Sleep the device (after locking again).
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
                    // If the dashboard is locked, then show a big lock icon to hide stuff behind it.
                    entireDashboardLocked
                        ? Center(child: Icon(Icons.lock, size: 196))
                        // If there's an error, show that instead.
                        : (globalerror == null
                            // If loading, then show a progress indicator.
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
            // A big black box that emulates sleeping. It can't get hit tested.
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

void setOpacityGlobal(bool status) {
  opacity = status ? 0 : 1;
}

// Show a pin input. method allows you to specify if it's a dashboard pin or a settings pin.
void showPinInput({
  required BuildContext context,
  required void Function(BuildContext context) onValid,
  PinInputType method = PinInputType.settings,
  bool Function()? canPop,
}) {
  Widget child; 
  // There are different types of pin inputs. The dashboard pin input needs to be quick and fast, and the settings pin input needs to be strong and secure.
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
          // Can only pop if allowed.
          child: PopScope(canPop: /*(canPop ?? (() => true))()*/ false, child: child),
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
    // A simple text box with a send button. No auto-enter.
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
    // If correct, then yay! Exit and unlock the dashboard. Else, tell the user they were wrong.
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
    // If they've entered a code the same length of the correct password, wait just a bit then give them feedback.
    if (text.length == dashboardPasscode!.length) {
      (() async {
        print("pin input: length reached (${text.length})");
        await Future.delayed(Duration(milliseconds: 250));
        if (!mounted) return;
        onEnter(context, useElse: false);
      })();
    }

    // Uses NumberPadKeyboard to show a number pad.
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
            // They can also use the enter key.
            print("pin input: enter reached");
            onEnter(context);
          },
        ),
      ],
    );
  }
}
