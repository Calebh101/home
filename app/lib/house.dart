import 'package:flutter/material.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/online.dart';

Future<void> updateDeviceStates() async {
  deviceStates = null;
  deviceStates = await request(endpoint: "devices/house/state");
}

List<TileRow> generateRooms() {
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
            Map device = devicesInRange[index];
            return TileBox(
              rowPosition: devicesInRange.length == 1 ? TileRowPosition.both : TileRowPosition.none,
              width: 3 / devicesInRange.length,
              height: 2,
              child: Column(
                children: [
                  Text("${device["name"]}", style: TextStyle(fontSize: 20)),
                  Text("${device["id"]} - ${device["type"]}", style: TextStyle(fontSize: 12)),
                  Text("${deviceStates?[device["id"]] ?? "Loading..."}", style: TextStyle(fontSize: 18)),
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

enum DeviceType {
  relaySwitch,
  dimmerSwitch,
  smartPlug,
}

Future<void> setDevice({required DeviceType type, required Map device, required dynamic value}) async {
  String id = device["id"];
  // Emulate setting the device.
  deviceStates![id] = value;
}