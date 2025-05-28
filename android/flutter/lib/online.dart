import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:homeapp_android_host/main.dart';
import 'package:http/http.dart' as http;
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/logger.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

bool secureWebsocket = true;
Map? location;

enum Host {
  debug,
  release,
  forceDebug,
  forceDebugIgnore,
}

Future<void> init(String? id) async {
  int port = (await request(endpoint: 'system/status'))!["socket"]["port"];
  String url = '${getBaseUrl(websocket: true)}:$port';
  print("building socket... (url: $url)");

  if (id == null) {
    warn("id is null");
    return;
  }

  io.Socket socket = io.io(url, io.OptionBuilder()
    .setTransports(['websocket'])
    .setPath('/dashboardstate')
    .setQuery({"id": id})
    .build());

  print("socket built");

  socket.on('connect', (_) {
    print("socket connected");
  });

  socket.on('update', (data) {
    if (data.containsKey("error")) {
      warn("socket error: ${data["error"]}");
      if (data["code"] == "dev-id-invalid") globalerror = "Invalid device ID.";
    }
  });

  socket.on('connect_error', (error) {
    warn("socket connection error: $error");
  });

  socket.on('disconnect', (_) {
    print("socket disconnected");
  });

  Timer.periodic(Duration(milliseconds: stateUpdateInterval), (Timer timer) async {
    Map data = await getState();
    if (verbose) print("verbose: pushing state...");
    socket.emit("update", data);
  });

  Timer.periodic(Duration(minutes: 10), (Timer timer) async {
    getLocation();
  });
}

Future<Map> getState() async {
  try {
    Battery battery = Battery();
    MethodChannel platform = MethodChannel('com.calebh101.homeapphost.channel');
    NetworkInfo info = NetworkInfo();

    return {
      "lastUpdated": DateTime.now().toUtc().toIso8601String(),
      "battery": {
        "level": await battery.batteryLevel,
        "charging": (await battery.batteryState) == BatteryState.charging,
      },
      "admin": {
        "adminLocked": locked,
        "dashboardLocked": lockDashboard ? entireDashboardLocked : null,
        "awake": opacity == 0,
      },
      "hardware": {
        "temps": {
          "battery": await platform.invokeMethod('getBatteryTemperature'), // degrees celsius
        },
        "memory": await platform.invokeMethod('getMemoryInfo'), // megabytes
      },
      "info": {
        "app": version,
        "debug": debug,
      },
      "network": {
        "ip": await info.getWifiIP(),
        "wifi": (await info.getWifiName())?.replaceAll("\"", ""),
      },
      "location": location,
    };
  } catch (e) {
    warn("state error: $e");
    return {"error": "$e"};
  }
}

Future<Map?> getLocation() async {
  print("location: starting...");
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    print("location: service not enabled");
    return null;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  print("location: found permission: $permission");

  if (permission == LocationPermission.denied) {
    warn("location: permission is invalid: $permission");
    return null;
  }

  Position position = await Geolocator.getCurrentPosition(
    locationSettings: LocationSettings(
      accuracy: LocationAccuracy.best,
    ),
  );

  return {
    'latitude': position.latitude,
    'longitude': position.longitude,
    'accuracy': position.accuracy,
    'altitude': position.altitude,
    'heading': position.heading,
    'speed': position.speed,
    'speedAccuracy': position.speedAccuracy,
    'timestamp': position.timestamp.toIso8601String(),
  };
}

String getBaseUrl({bool websocket = false}) {
  return debug ? "${websocket && secureWebsocket ? "wss" : "http"}://192.168.0.21" : "${websocket && secureWebsocket ? "wss" : (websocket ? "http" : "https")}://home.calebh101.com";
}

Future<Map?> request({required String endpoint, Map<String, String>? headers, Map? body, BuildContext? context, String action = "complete action", Host? host, bool showError = true, bool silentLogging = false}) async {
  String baseurl = getBaseUrl();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  headers ??= {'Content-Type': 'application/json', 'authentication': prefs.getString("accessCode") ?? "null"};
  body ??= {};

  Uri url = Uri.parse("$baseurl/api/$endpoint");
  if (silentLogging == false || verbose) print("request: requesting url $url with body $body");

  try {
    http.Response response = await http.post(
      url,
      headers: headers,
      body: jsonEncode(body),
    );

    Map result = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      if (silentLogging == false || verbose == true) print('response data (url: $url): $result');
      return result;
    } else if (isInvalidPasswordResponse(response, result)) {
      globalerror = "Invalid access code.";
    } else {
      if (result.containsKey('error')) {
        warn('response error: $result', code: "${response.statusCode}");
      } else {
        warn('response error', code: "${response.statusCode}");
      }
      if (showError && context != null) {
        showSnackBar(context, "Unable to $action. Please try again later.");
      }
    }
  } catch (e) {
    warn('send error: $e', trace: true);
    if (showError && context != null) {
      showSnackBar(context, "Unable to $action. Please try again later.");
    }
  }

  return null;
}

bool isInvalidPasswordResponse(http.Response response, Map body) {
  return response.statusCode == 403 && body["code"] == "ATV x1";
}

class WebsocketOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return client;
  }
}