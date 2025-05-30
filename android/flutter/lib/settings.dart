import 'package:device_policy_controller/device_policy_controller.dart';
import 'package:flutter/material.dart';
import 'package:homeapp_android_host/main.dart';
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localpkg/logger.dart';

Future<void> setSetting({required String name, required dynamic value}) async {
  // Set a setting. The type is dependent on the value's runtime type.
  print("setting $name to $value (${value.runtimeType})");
  SharedPreferences prefs = await getPrefs();

  switch (value.runtimeType) {
    case const (bool): prefs.setBool(name, value);
    case const (String): prefs.setString(name, value);
    case const (List<String>): prefs.setStringList(name, value);
    case const (int): prefs.setInt(name, value);
    case const (double): prefs.setDouble(name, value);
    default: throw Exception("Invalid value type: ${value.runtimeType}");
  }
}

// Clear a setting.
Future<void> removeSetting({required String name}) async {
  SharedPreferences prefs = await getPrefs();
  prefs.remove(name);
}

// This is here for the FutureBuilder.
Future<SharedPreferences> getPrefs() async {
  return await SharedPreferences.getInstance();
}

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Settings"),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: FutureBuilder(
        future: getPrefs(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (!snapshot.hasData) { // No data to use, no data to show.
            return Center(
              child: CircularProgressIndicator(),
            );
          }

          // Each setting has a title, a description, most of them have a text (the value shown at the end of the box), and most of them have an action (what to do when clicked).
          // The action normally opens editSetting, which specifies a "type", key, and value. The type is an identifier for what type of input to show, like "bool", "slider-1-2000", etcetera.

          SharedPreferences prefs = snapshot.data;
          return Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SettingTitle(title: "About"),
                  Setting(title: "About", desc: "A small kiosk-like app with a lot of nifty features for my home system.. Made to be used on older Androids."),
                  Setting(title: "Version", desc: "Version of the app.", text: version),
                  Setting(title: "Device ID", desc: "Device ID of the kiosk device. This is used to report to the home server.", text: prefs.getString("id")),
                  SettingTitle(title: "Appearance"),
                  Setting(title: "Theme", desc: "Set the kiosk to light or dark mode. If set to dark mode, the kiosk app will request the home app with a parameter to force dark mode.", text: (prefs.getBool("darkMode") ?? true) ? "Dark" : "Light", action: () => editSetting(context: context, key: "darkMode", value: prefs.getBool("darkMode") ?? true, type: "theme")),
                  Setting(title: "Show Loading Progress", desc: "Show the progress of loading the WebView in a progress indicator.", text: (prefs.getBool("showLoadingProgress") ?? false) ? "Yes" : "No", action: () => editSetting(context: context, key: "showLoadingProgress", value: prefs.getBool("showLoadingProgress") ?? false, type: "bool")),
                  Setting(title: "Screen Timeout", desc: "How long to wait before sleeping the dashboard.", text: "${prefs.getInt("screenTimeout") ?? 20}s", action: () => editSetting(context: context, key: "screenTimeout", value: prefs.getInt("screenTimeout") ?? 20, type: "slider-5-600-sec")),
                  SettingTitle(title: "Camera"),
                  Setting(title: "Use Camera", desc: "Use the camera to detect motion to automatically wake the device. Not recommended on less powerful devices.", text: (prefs.getBool("useCamera") ?? false) ? "Yes" : "No", action: () => editSetting(context: context, key: "useCamera", value: prefs.getBool("useCamera") ?? false, type: "bool")),
                  Setting(title: "Camera Frame Processing Interval", desc: "How long to wait before processing each frame (in milliseconds). The smaller the interval, the more consistent the motion features, but it will use a lot more memory.", text: "${prefs.getInt("cameraProcessInterval") ?? 50}ms", action: () => editSetting(context: context, key: "cameraProcessInterval", value: prefs.getInt("cameraProcessInterval") ?? 50, type: "slider-1-2000-ms")),
                  Setting(title: "Camera Movement Threshold", desc: "The percent of pixels that need to be different in order for the program to classify it as movement.", text: "${(prefs.getDouble("imageDifferenceThreshold") ?? 0.5) * 100}%", action: () => editSetting(context: context, key: "imageDifferenceThreshold", value: (prefs.getDouble("imageDifferenceThreshold") ?? 0.5), type: "percent-notempty")),
                  SettingTitle(title: "Functionality"),
                  Setting(title: "State Update Interval", desc: "How long to wait before updating and reporting the state of the kiosk device (in milliseconds). The smaller the interval, the more accurate the reported state, but it will use more memory. This setting requires an app restart to implement.", text: "${prefs.getInt("stateUpdateInterval") ?? 2000}ms", action: () => editSetting(context: context, key: "stateUpdateInterval", value: prefs.getInt("stateUpdateInterval") ?? 2000, type: "slider-500-10000-ms")),
                  SettingTitle(title: "Admin"),
                  Setting(title: "Settings Passcode", desc: "Select the PIN to access the settings and navbar.", text: prefs.getString("settingsPasscode") ?? "0000", action: () => editSetting(context: context, key: "settingsPasscode", value: prefs.getString("settingsPasscode") ?? "0000", type: "pin")),
                  Setting(title: "Dashboard Passcode", desc: "Use a passcode to access the dashboard after sleep.", text: prefs.getString("dashboardPasscode") ?? "None", action: () => editSetting(context: context, key: "dashboardPasscode", value: prefs.getString("dashboardPasscode"), type: "pin-null")),
                  Setting(title: "Unlock Kiosk Mode", desc: "Toggle kiosk mode/pinned app mode for the app. To turn back on, close and reopen the app.", action: () async {
                    try {
                      print("setting kiosk mode...");
                      DevicePolicyController dpc = DevicePolicyController.instance;
                      await dpc.unlockApp();
                      print("device policy controller: disable kiosk mode: success");
                    } catch (e) {
                      warn("device policy controller: kiosk mode: $e");
                      showSnackBar(context, "Unable to toggle kiosk mode.");
                    }
                  }),
                  SettingTitle(title: "Data"),
                  Setting(title: "Erase All Data & Settings", desc: "Erase all data and settings of the kiosk app. This cannot be undone.", action: () async {
                    if (!((await showConfirmDialogue(context: context, title: "Are you sure?", description: "Are you sure you want to erase all data and settings? This cannot be undone.")) ?? false)) return;
                    if (!mounted) return;
                    prefs.clear();
                    showConstantDialogue(context: context, message: "Please close and reopen the app for your changes to take effect.");
                  }),
                  Setting(title: "Re-Register", desc: "Re-register your device. This cannot be undone.", action: () async {
                    if (!((await showConfirmDialogue(context: context, title: "Are you sure?", description: "Are you sure you want to re-register this device? This can cause server issues and/or \"ghost devices\" to appear.")) ?? false)) return;
                    resetDeviceID(context: context);
                  }),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  // Show the settings changing dialogue, then refresh.
  Future<void> editSetting({required BuildContext context, required String key, required dynamic value, required String type}) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return EditSettingAlertDialogue(name: key, value: value, type: type);
      },
    );
    setState(() {});
  }
}

class EditSettingAlertDialogue extends StatefulWidget {
  final String name;
  final dynamic value;
  final String type;
  const EditSettingAlertDialogue({super.key, required this.name, required this.value, required this.type});

  @override
  State<EditSettingAlertDialogue> createState() => _EditSettingAlertDialogueState();
}

class _EditSettingAlertDialogueState extends State<EditSettingAlertDialogue> {
  TextEditingController textController = TextEditingController();
  dynamic value;
  dynamic originalValue;

  @override
  void initState() {
    value = widget.value;
    originalValue = value;
    super.initState();
  }

  // Types
    // pin: A pin like the settings pin.
    // pin-null: A pin that can be null, like the dashboard pin can be null to disable it completely.
    // theme: Light/dark mode selection.
    // bool: Yes/no selection.
    // percent: 0% to 100% slider.
    // percent-notempty: 1% to 100% slider.
    // slider-min-max-unit: Slider from the specified min through the max, using the unit.

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Setting'),
      content: (widget.type == "pin" || widget.type == "pin-null") ? TextField(
        controller: textController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: "PIN",
          border: OutlineInputBorder(),
        ),
        onChanged: (String text) {
          if (text != '') {
            value = textController.text;
            if (widget.type == "pin-null" && value == '') value = null;
            setState(() {});
          }
        },
      ) : (widget.type == "theme" ? SizedBox(
        height: 100,
        width: 300,
        child: ListView(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          children: [
            ListTile(
              title: Text("Light Mode"),
              onTap: () {
                value = false;
                setState(() {});
              },
              leading: value == false ? Icon(Icons.check) : SizedBox.shrink(),
            ),
            ListTile(
              title: Text("Dark Mode"),
              onTap: () {
                value = true;
                setState(() {});
              },
              leading: value == true ? Icon(Icons.check) : SizedBox.shrink(),
            ),
          ],
        ),
      ) : (widget.type == "bool" ? SizedBox(
        height: 100,
        width: 300,
        child: ListView(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          children: [
            ListTile(
              title: Text("Yes"),
              onTap: () {
                value = true;
                setState(() {});
              },
              leading: value == true ? Icon(Icons.check) : SizedBox.shrink(),
            ),
            ListTile(
              title: Text("No"),
              onTap: () {
                value = false;
                setState(() {});
              },
              leading: value == false ? Icon(Icons.check) : SizedBox.shrink(),
            ),
          ],
        ),
      ) : (widget.type == "slider-5-600-sec" || widget.type == "slider-1-2000-ms" || widget.type == "slider-500-10000-ms" ? Builder(
        builder: (context) {
          double min = widget.type == "slider-5-600-sec" ? 5 : (widget.type == "slider-1-2000-ms" ? 1 : (widget.type == "slider-500-10000-ms" ? 500 : 0));
          double max = widget.type == "slider-5-600-sec" ? 600 : (widget.type == "slider-1-2000-ms" ? 2000 : (widget.type == "slider-500-10000-ms" ? 10000 : 100));
          int divisions = (max - min + 1).ceil();
          double valueToShow = value.toDouble();
          return SizedBox(
            width: 500,
            height: 100,
            child: Column(
              children: [
                Text("${valueToShow.round()}${widget.type.contains("ms") ? "ms" : (widget.type.contains("sec") ? "s" : "")}"),
                Slider(value: value.roundToDouble().clamp(min, max), onChanged: (n) => setState(() {
                  value = n.round();
                }), max: max, min: min, divisions: divisions, secondaryTrackValue: originalValue.toDouble()),
              ],
            ),
          );
        }
      ) : (widget.type == "percent" || widget.type == "percent-notempty" ? Builder(
        builder: (BuildContext context) {
          bool notempty = widget.type.contains("notempty");
          double min = notempty ? 0.01 : 0;
          double max = 1;
          int divisions = notempty ? 100 : 101;
          return SizedBox(
            width: 500,
            height: 100,
            child: Column(
              children: [
                Text("${(value * 100).round()}%"),
                Slider(value: value.clamp(min, max), onChanged: (n) => setState(() {
                  value = (n * 100).round() / 100;
                  if (verbose) print("verbose: setting value to $value (from $n)");
                }), max: max, min: min, divisions: divisions, secondaryTrackValue: ((originalValue * 100).round() / 100).toDouble()),
              ],
            ),
          );
        },
      ) : Text("Error: invalid type: ${widget.type}"))))),
      actions: <Widget>[
        TextButton(
          child: Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text('OK'),
          onPressed: () {
            print("ok");
            if (value == null) {
              // If value is null, just clear the setting.
              removeSetting(name: widget.name);
            } else {
              setSetting(name: widget.name, value: value);
            }
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

// Used to register the device with a unique ID.
class RegisterPrompts extends StatefulWidget {
  const RegisterPrompts({super.key});

  @override
  State<RegisterPrompts> createState() => _RegisterPromptsState();
}

class _RegisterPromptsState extends State<RegisterPrompts> {
  TextEditingController controller = TextEditingController();
  String label = "Device ID";

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Please register your kiosk device with a unique device ID."),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
            ),
            onChanged: (String value) {
              label = "Device ID";
              setState(() {});
            },
          ),
        ),
        TextButton(onPressed: () async {
          // Make sure, ID is valid, then save it to preferences.
          String id = controller.text;

          if (id == "") {
            label = "Invalid";
            setState(() {});
            return;
          }

          SharedPreferences prefs = await SharedPreferences.getInstance();
          if (!mounted) return;
          prefs.setString("id", id);
          Navigator.of(context).pop();
        }, child: Text("Register", style: TextStyle(fontSize: 20))),
      ],
    );
  }
}