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
  deviceStates = await request(endpoint: "devices/house/state");
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
            child: deviceStates == null ? Center(child: CircularProgressIndicator()) : Column(
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
                  Expanded(child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: (device["widget"] as Widget),
                  )),
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
          children: [
            Icon(Icons.power, color: getThemeColor(context), size: 24),
            Text("The device is not reachable."),
          ],
        ),
      );
    }

    int batteryvalue = data!["battery"]["level"];
    bool charging = data!["battery"]["charging"];
    bool adminlocked = data!["admin"]["adminLocked"];
    bool? dashboardlocked = data!["admin"]["dashboardLocked"];
    bool awake = data!["admin"]["appawake"];

    return Column(
      children: [
        Text.rich(
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
                  color: charging ? Colors.white : Colors.green,
                ),
              ),
            ],
          ),
        ),
        Text("${awake ? "Awake" : "Asleep"} and ${dashboardlocked == true ? "Locked" : "Unlocked"}"),
        Text("Admin ${adminlocked ? "Locked" : "Unlocked"}"),
        Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: () {
              command(awake ? "sleep" : "wake");
            }, child: Text(awake ? "Sleep" : "Wake Up")),
            TextButton(onPressed: () async {
              if (!((await showConfirmDialogue(context: context, title: "Are you sure?", description: "This will suspend the host until it is turned on again. It will still send updates to the server in the background. Press the power button on the device to turn it back on.")) ?? false)) return;
              command("lock");
            }, child: Text("Suspend")),
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
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SettingTitle(title: "General"),
          Setting(title: "Name", text: widget.device.name),
          Setting(title: "ID", text: widget.device.id),
          Setting(title: "Type", text: "${widget.data["model"]["physical"] ? "Physical" : "Emulated"} Dashboard"),
          Setting(title: "App Version", text: "${widget.data["info"]["version"]}${widget.data["info"]["debug"] ? " (Debug)" : ""}"),
          SettingTitle(title: "State"),
          Setting(title: "Battery", text: "${widget.data["battery"]["level"]}% and ${widget.data["battery"]["charging"] ? "Charging" : "Not Charging"}"),
          Setting(title: "Memory", text: "${widget.data["memory"]["available"]}MB out of ${widget.data["memory"]["total"]}MB"),
          Setting(title: "Battery Temperature", text: "${widget.data["temps"]["battery"]}°C"),
          SettingTitle(title: "Device"),
          Setting(title: "Device Name", text: "${widget.data["device"]["name"]}"),
          Setting(title: "Model", text: "${widget.data["model"]["brand"]} ${widget.data["model"]["model"]}"),
          Setting(title: "Manufacturer", text: "${widget.data["model"]["manufacturer"]}"),
          Setting(title: "Android Version", text: "${widget.data["version"]["release"]}"),
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