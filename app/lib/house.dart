import 'dart:async';

import 'package:flutter/material.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:intl/intl.dart';
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/logger.dart';
import 'package:localpkg/widgets.dart';

Future<void> updateDeviceStates() async {
  deviceStates = null;
}

List<TileRow> generateRooms(BuildContext context) {
  int allowedInRow = 1;
  List<TileRow> result = [];

  for (Map room in rooms) {
    List devices = room["devices"];
    int TileRowLength = (devices.length / allowedInRow).ceil();

    result.addAll([
      TileRow(
        takeUpEntireRow: true,
        children: [
          TileBox(
            rowPosition: TileRowPosition.both,
            width: 3,
            height: 0.88,
            child: Column(
              children: [
                Text("${room["name"]}", style: TextStyle(fontSize: 20)),
                Text("${room["id"]} - ${room["devices"].length} Device${room["devices"].length == 1 ? "" : "s"}"),
              ],
            ),
          ),
        ],
      ),
      ...List.generate(TileRowLength, (int i) {
        int deviceIndex = i * allowedInRow;

        bool formula([int offset = 0]) {
          return deviceIndex + offset <= devices.length - 1 && allowedInRow >= offset + 1;
        }

        List devicesInRange = [
          if (formula(0))
          devices[deviceIndex],
          if (formula(1))
          devices[deviceIndex + 1],
          if (formula(2))
          devices[deviceIndex + 2],
        ];

        return TileRow(
          children: List.generate(devicesInRange.length, (int index) {
            Map device = getDeviceDashboard(data: devicesInRange[index], context: context);
            String id = device["device"].id;
            return TileBox(
              rowPosition: devicesInRange.length == 1 ? TileRowPosition.both : TileRowPosition.none,
              width: 3 / devicesInRange.length,
              height: device["height"],
              child: Column(
                children: [
                  Text("${device["device"].name}", style: TextStyle(fontSize: 20)),
                  Text("$id - ${device["device"].type}", style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: device["widget"],
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      }),
    ]);
  }

  return result;
}

Map getDeviceDashboard({required Map data, required BuildContext context}) {
  Device device;
  Widget widget;
  double height = 2;

  switch (data["type"]) {
    case "dashboard":
      device = Device(name: data["name"], id: data["id"], type: DeviceType.dashboard, data: data);
      widget = DashboardDevice(device: device);
      height = 2.5;
      break;
    
    case "relay-2":
      device = Device(name: data["name"], id: data["id"], type: DeviceType.dashboard, data: data);
      widget = DualRelaySwitchDevice();
      height = 2.5;
      break;

    default: throw Exception("Invalid device type: ${data["type"]}");
  }

  return {
    "device": device,
    "widget": widget,
    "height": height,
  };
}

enum DeviceType {
  relaySwitch,
  dimmerSwitch,
  smartPlug,
  dashboard,
}

Future<void> setDevice({required DeviceType type, required Map device, required dynamic value}) async {
  String id = device["id"];
  // Emulate setting the device.
  deviceStates![id] = value;
}

class Device {
  final String name;
  final String id;
  final DeviceType type;
  final Map data;
  Device({required this.name, required this.id, required this.type, required this.data});

  @override
  String toString() {
    return "Device(name: $name, id: $id, type: $type, data: ${data.runtimeType})";
  }
}

abstract class DeviceWidget extends StatefulWidget {
  final Device device;
  const DeviceWidget({super.key, required this.device});
}

class DashboardDevice extends DeviceWidget {
  const DashboardDevice({super.key, required super.device});

  @override
  State<DashboardDevice> createState() => _DashboardDeviceState();
}

class _DashboardDeviceState extends State<DashboardDevice> {
  Map? data;
  StreamSubscription? subscription;

  @override
  void initState() {
    print("initializing DashboardDevice...");
    super.initState();

    subscription = stateController.stream.listen((input) {
      data = input["state"]["dashboards"][widget.device.id];
      setState(() {});
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.power_settings_new, color: getThemeColor(context), size: 48),
            SizedBox(height: 8),
            Text("This device is not reachable."),
          ],
        ),
      );
    }

    int batteryvalue = data!["battery"]["level"];
    bool charging = data!["battery"]["charging"];
    bool adminlocked = data!["admin"]["adminLocked"];
    bool? dashboardlocked = data!["admin"]["dashboardLocked"];
    bool awake = data!["state"]["appawake"];
    bool deviceawake = data!["state"]["deviceawake"];

    return Column(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: "Battery: ",
                ),
                TextSpan(
                  text: "$batteryvalue%",
                  style: TextStyle(
                    color: getColorForBatteryLevel(batteryvalue),
                  ),
                ),
                TextSpan(
                  text: " and ",
                ),
                TextSpan(
                  text: charging ? "Charging" : "Not Charging",
                  style: TextStyle(
                    color: charging ? Colors.green : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        deviceawake ? Column(
          children: [
            Text("${awake ? "Awake" : "Asleep"} and ${dashboardlocked == true ? "Locked" : "Unlocked"}"),
            Text("Admin ${adminlocked ? "Locked" : "Unlocked"}"),
          ],
        ) : Expanded(child: Text("Device Suspended")),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: () {
              if (!deviceawake) return showSnackBar(context, "You can't wake the device when it's suspended.");
              command(awake ? "sleep" : "wake");
            }, child: Text(awake ? "Sleep" : "Wake Up")),
            TextButton(onPressed: () async {
              command(deviceawake ? "lock" : "unlock");
            }, child: Text(deviceawake ? "Suspend" : "Restore")),
            TextButton(onPressed: () {
              showDialogue(context: context, title: "Dashboard Info", content: DashboardDeviceInfo(data: data!, device: widget.device));
            }, child: Text("Info")),
          ],
        ),
        Text("Last updated: ${DateFormat("M/dd/yyyy h:mm:ss a").format(DateTime.parse(data!["lastUpdated"]).toLocal())}")
      ],
    );
  }

  void command(String input) {
    request(endpoint: "devices/house/dashboard/${widget.device.id}/command", body: {"command": input}, context: context, action: "send command to dashboard");
  }
}

class DashboardDeviceInfo extends StatefulWidget {
  final Map data;
  final Device device;
  const DashboardDeviceInfo({super.key, required this.device, required this.data});

  @override
  State<DashboardDeviceInfo> createState() => _DashboardDeviceInfoState();
}

class _DashboardDeviceInfoState extends State<DashboardDeviceInfo> {
  Map? data;
  StreamSubscription? subscription;

  @override
  void initState() {
    print("initializing DashboardDeviceInfo...");
    super.initState();

    subscription = stateController.stream.listen((input) {
      data = input["state"]["dashboards"][widget.device.id];
      setState(() {});
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    data ??= widget.data;

    return SingleChildScrollView(
      child: Column(
        children: [
          Setting(title: "Last Updated", text: DateFormat("M/dd/yyyy h:mm:ss a").format(DateTime.parse(data!["lastUpdated"]).toLocal())),
          SettingTitle(title: "General"),
          Setting(title: "Name", text: widget.device.name),
          Setting(title: "ID", text: widget.device.id),
          Setting(title: "Type", text: "${data!["model"]["physical"] ? "Physical" : "Emulated"} Dashboard"),
          Setting(title: "App Version", text: "${data!["info"]["version"]}${data!["info"]["debug"] ? " (Debug)" : ""}"),
          SettingTitle(title: "State"),
          Setting(title: "Battery", text: "${data!["battery"]["level"]}% and ${data!["battery"]["charging"] ? "Charging" : "Not Charging"}"),
          Setting(title: "Memory", text: "${data!["memory"]["available"]}MB out of ${data!["memory"]["total"]}MB"),
          Setting(title: "Battery Temperature", text: "${data!["temps"]["battery"]}°C"),
          SettingTitle(title: "Device"),
          Setting(title: "Device Name", text: "${data!["device"]["name"]}"),
          Setting(title: "Model", text: "${data!["model"]["brand"]} ${data!["model"]["model"]}"),
          Setting(title: "Manufacturer", text: "${data!["model"]["manufacturer"]}"),
          Setting(title: "Android Version", text: "${data!["version"]["release"]}"),
        ],
      ),
    );
  }
}

Color getColorForBatteryLevel(int value) {
  if (value > 80) {
    return Colors.green;
  } else if (value > 50) {
    return Colors.yellow;
  } else if (value > 20) {
    return Colors.orange;
  } else {
    return Colors.red;
  }
}

class RelaySwitchDevice extends StatefulWidget {
  const RelaySwitchDevice({super.key});

  @override
  State<RelaySwitchDevice> createState() => _RelaySwitchDeviceState();
}

class _RelaySwitchDeviceState extends State<RelaySwitchDevice> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}

class DualRelaySwitchDevice extends StatefulWidget {
  const DualRelaySwitchDevice({super.key});

  @override
  State<DualRelaySwitchDevice> createState() => _DualRelaySwitchDeviceState();
}

class _DualRelaySwitchDeviceState extends State<DualRelaySwitchDevice> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}