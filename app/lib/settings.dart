import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/internettest.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:homeapp/temps.dart';
import 'package:intl/intl.dart';
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/functions.dart';
import 'package:localpkg/logger.dart';
import 'package:localpkg/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

String? adminPassword;

class Settings extends StatefulWidget {
  final bool debug;
  final bool kiosk;
  const Settings({super.key, required this.debug, required this.kiosk});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  StreamSubscription? stream;
  DateTime? lastRefreshed;
  SharedPreferences? prefs;

  @override
  void initState() {
    print("initializing settings...");
    super.initState();
    showSectionDialogue(context: context, id: "settings");

    stream = stateController.stream.listen((data) {
      DateTime? time = DateTime.tryParse(data["state"]["lastRefresh"]);
      if (time == null) return;
      lastRefreshed = time.toLocal();
      setState(() {});
    });

    (() async {
      print("prefs: loading");
      prefs = await SharedPreferences.getInstance();
      setState(() {});
      print("prefs: loaded");
    })();
  }

  Future<bool> admin({required BuildContext context}) async {
    if (adminPassword == null) {
      await showDialogue(context: context, title: "Enter Admin Password", content: AdminPasswordDialogue());
      if (adminPassword == null) {
        print("admin: fail: refuse");
        return false;
      }
    } else {
      showSnackBar(context, "Loading...");
    }

    bool status = (await request(endpoint: "system/admin/check", body: {"password": adminPassword}))!["status"];
    print("admin: status: $status");

    if (!status) { // if (check with server - make sure non null)["status"] is false
      print("admin: fail: incorrect");
      showSnackBar(context, "Incorrect password.");
      adminPassword = null;
      return false;
    }

    print("admin: pass");
    return true;
  }

  @override
  void dispose() {
    stream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: getColor(brightness: getBrightness(context: context), context: context, type: ColorType.theme)),
          onPressed: () {
            print("back");
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SettingTitle(title: "General"),
            Setting(title: "Colored Graphs", desc: "If enabled, graphs will have colored dots and labels.", text: prefs != null ? ((prefs!.getBool("coloredGraphs") ?? true) ? "On" : "Off") : "Loading...", action: () {
              if (prefs == null) return;
              prefs!.setBool("coloredGraphs", !(prefs!.getBool("coloredGraphs") ?? true));
              print("set");
              setState(() {});
            }),
            SettingTitle(title: "About"),
            Setting(title: "Version", text: version, desc: "Version of the home app."),
            Setting(title: "Host Info", desc: "Show info about the host machine.", action: () {
              showDialogue(context: context, title: "Host Info", content: DeviceInfo());
            }),
            Setting(title: "Show Help Dialogue", desc: "Show a help dialogue for a specific section.", action: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return Dialog(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Select Help Dialogue', style: TextStyle(fontSize: 18)),
                        ),
                        Expanded(
                          child: ListView.builder(itemCount: dialogues.length, itemBuilder: (BuildContext context, int i) {
                            Dialogue dialogue = dialogues[i];
                              return ListTile(
                                title: Text(dialogue.section),
                                subtitle: Text("${dialogue.section} - ${dialogue.id}"),
                                onTap: () {
                                  showSectionDialogue(context: context, id: dialogue.id, override: true);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }
              );
            }),
            SettingTitle(title: "Device"),
            Setting(title: "Theme", desc: "Set light mode or dark mode for the host.", text: darkMode ? "Dark Mode" : "Light Mode", action: () {
              showDialogue(context: context, title: "Select Theme", content: Column(
                spacing: 16,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TileBox(width: 1.5, child: Text("Light Mode"), rowPosition: TileRowPosition.none, onPressed: darkMode ? () async {
                    Navigator.of(context).pop();
                    await request(endpoint: "theme/light", context: context, action: "turn dark mode off", host: Host.release);
                    darkMode = false;
                    setState(() {});
                  }: null, active: !darkMode, hover: !darkMode),
                  TileBox(width: 1.5, child: Text("Dark Mode"), rowPosition: TileRowPosition.none, onPressed: !darkMode ? () async {
                    Navigator.of(context).pop();
                    await request(endpoint: "theme/dark", context: context, action: "turn dark mode on", host: Host.release);
                    darkMode = true;
                    setState(() {});
                  } : null, active: darkMode),
                ],
              ));
            }),
            Setting(title: "Refresh", desc: "Refresh cached announcements and contacts on the host machine. This normally refreshes every hour, but can be manually refreshed as well.", action: () async {
              print("refreshing...");
              showSnackBar(context, "Refreshing host...");
              request(endpoint: "system/refresh", context: context, action: "refresh host");
              print("refreshed");
            }, text: lastRefreshed == null ? null : "Last Refreshed on\n${DateFormat('MMMM d, y h:mm a').format(lastRefreshed!)}"),
            Setting(title: "Temperatures", desc: "View the current temperature of the host in real-time.", action: () {
              navigate(context: context, page: TemperatureMonitor());
            }),
            Setting(title: "Suspend", desc: "Suspend the host. This will suspend all operations and make the host unusable until the host is reactivated. Do not use this as a way to turn the system screen off or as a solution for overnight.", action: () async {
              if (!(await admin(context: context))) return;
              if ((await showConfirmDialogue(context: context, title: "Are you sure?", description: "This will suspend all operations and make the host unusable until the host is reactivated. Do not use this as a way to turn the system screen off or as a solution for overnight.")) ?? false) {
                request(endpoint: "system/suspend", context: context, action: "suspend host", body: {"password": adminPassword});
              }
            }),
            Setting(title: "Power Off", desc: "Completely power down the host. In order to be restarted the host will have to be manually powered back on and the server restarted. This will cause loss of all temporary data.", action: () async {
              if (!(await admin(context: context))) return;
              if ((await showConfirmDialogue(context: context, title: "Are you sure?", description: "This will completely power down the host. In order to be restarted the host will have to be manually powered back on and the server restarted. This will disrupt all current users of the host and cause loss of all temporary data.")) ?? false) {
                Map? data = await request(endpoint: "system/shutdown", action: "power off the host", context: context, body: {"password": adminPassword});
                showSnackBar(context, "The system will shut down in ${data?["seconds"] ?? "an unknown amount of"} seconds.");
              }
            }),
            SettingTitle(title: "Network"),
            Setting(title: "Internet Test", desc: "Run an Internet test from the host's perspective.", action: () {
              navigate(context: context, page: InternetTest());
            }),
            SettingTitle(title: "Settings & Data"),
            Setting(title: "Reset Help Dialogues", desc: "Reset help dialogues. They will show next time you open the pages.", action: () async {
              await resetDialogueStatus();
              showSnackBar(context, "Dialogue status cleared!");
            }),
            Setting(title: "Reset All Settings and Data", desc: "Reset all settings and data of the ${widget.kiosk ? "host's app" : "current web app (not the host's app)"}. This cannot be undone.", action: () async {
              if (!(await showConfirmDialogue(context: context, title: "Are you sure?", description: "Are you sure you want to reset all settings and data of the current web app? This cannot be undone.") ?? false)) return;
              SharedPreferences prefs = await SharedPreferences.getInstance();
              prefs.clear();
              showSnackBar(context, "Cleared all settings and data!");
            }),
            Column(
              children: [
                SettingTitle(title: "Admin"),
                Setting(title: "Update ${widget.kiosk ? "App" : "Host"}", desc: "Have the host OTA update.", action: () async {
                  if (!(await admin(context: context))) return;
                  request(endpoint: "system/update", context: context, action: "update the host", body: {"password": adminPassword});
                }),
                if (widget.kiosk)
                Setting(title: "Close App", desc: "Close the current app for debug or maintenance purposes.", action: () async {
                  if (!(await admin(context: context))) return;
                  if ((await showConfirmDialogue(context: context, title: "Are you sure?", description: "This will close the current running app and stop certain services on the host. This is only to be used for debugging or maintenance.") ?? false) == false) {
                    return;
                  }

                  print("closing app...");
                  exit(0);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void restartApp({bool? kiosk, bool? debug}) {
    navigate(context: context, page: Dashboard(kiosk: kiosk ?? widget.kiosk, debug: debug ?? widget.debug), mode: 2);
  }
}

class DeviceInfo extends StatefulWidget {
  const DeviceInfo({super.key});

  @override
  State<DeviceInfo> createState() => _DeviceInfoState();
}

class _DeviceInfoState extends State<DeviceInfo> {
  Map? data;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    data = await request(endpoint: "system/about", action: "get device info", context: context);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return data == null ? Center(child: CircularProgressIndicator()) : SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SettingTitle(title: "Version"),
            Setting(title: "Server Version", desc: "The version of the running server on the host.", text: data!["version"]["server"]),
            Setting(title: "System Version", desc: "The version of the operating system of the host.", text: data!["version"]["system"]),
            Setting(title: "Config Version", desc: "The version of the configuration of the host's server.", text: data!["version"]["config"]),
            Setting(title: "App Version", desc: "The version of the Home app running on the host.", text: data!["version"]["app"], action: () {
              if (data!["version"]["app"] == null) {
                showDialogue(context: context, title: "Why is there no app version?", content: Text("This can happen if the app is not currently running on the host. The app must be running to query the app info."));
              }
            }),
            SettingTitle(title: "Code Stats"),
            Setting(title: "Total lines", text: "${data!["code"]["lines"]}"),
            Setting(title: "Total files", text: "${data!["code"]["files"]}"),
            Setting(title: "Total languages", text: "${data!["code"]["totalLanguages"]}", desc: "${data!["code"]["languages"].keys.join(", ")}"),
            Setting(title: "See More", desc: "See more code stats.", action: () {
              showDialogue(context: context, title: "Code Stats", content: DeviceInfoCodeStats(data: data!["code"]));
            }),
          ],
        ),
      ),
    );
  }
}

class DeviceInfoCodeStats extends StatefulWidget {
  final Map data;
  const DeviceInfoCodeStats({super.key, required this.data});

  @override
  State<DeviceInfoCodeStats> createState() => _DeviceInfoCodeStatsState();
}

class _DeviceInfoCodeStatsState extends State<DeviceInfoCodeStats> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          children: [
            SettingTitle(title: "General Stats"),
            Setting(title: "Total lines", text: "${widget.data["lines"]}"),
            Setting(title: "Total files", text: "${widget.data["files"]}"),
            Setting(title: "Total languages", text: "${widget.data["totalLanguages"]}", desc: "${widget.data["languages"].keys.join(", ")}"),
            ...List.generate(widget.data["languages"].keys.length, (int i) {
              String language = widget.data["languages"].keys.toList()[i];
              Map data = widget.data["languages"][language];
              return Column(
                children: [
                  SettingTitle(title: language),
                  Setting(title: "Total lines", text: "${data["lines"]}"),
                  Setting(title: "Total files", text: "${data["totalFiles"]}", action: () {
                    showDialogue(context: context, title: "$language Files", content: DeviceInfoCodeStatsExpandedView(language: language, data: data));
                  }),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class DeviceInfoCodeStatsExpandedView extends StatefulWidget {
  final String language;
  final Map data;
  const DeviceInfoCodeStatsExpandedView({super.key, required this.language, required this.data});

  @override
  State<DeviceInfoCodeStatsExpandedView> createState() => _DeviceInfoCodeStatsExpandedViewState();
}

class _DeviceInfoCodeStatsExpandedViewState extends State<DeviceInfoCodeStatsExpandedView> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          children: [
            ...List.generate(widget.data["files"].length, (int i) {
              Map file = widget.data["files"][i];
              return Setting(title: "${file["file"].split("/").last}", text: "${file["lines"]} Lines");
            }),
          ],
        ),
      ),
    );
  }
}