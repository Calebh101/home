import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:device_policy_controller/device_policy_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:homeapp_android_host/main.dart';
import 'package:http/http.dart' as http;
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/logger.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_dotenv/flutter_dotenv.dart' as dotenv;

String? zip;
bool secureWebsocket = true;
Map? location;
bool deviceAwake = true;
Host host = debug ? Host.debug : Host.release;

enum Host {
  debug,
  release,
  forceDebug,
  forceDebugIgnore,
}

// Initialize the socket.
Future<void> init(String? id, {required HomeState widget}) async {
  // Get the socket port and URL.
  int port = 3000;
  String url = '${getBaseUrl(websocket: true)}:$port';
  print("building socket... (url: $url)");

  if (id == null) {
    warn("id is null");
    return;
  }

  // Create the socket.
  io.Socket socket = io.io(url, io.OptionBuilder()
    .setTransports(['websocket'])
    .setPath('/dashboardstate')
    .setQuery({"id": id})
    .setExtraHeaders({"auth": dotenv.DotEnv().env["ACCESS_CODE"]}) // Use the access code for verification.
    .build());

  print("socket built");

  socket.on('connect', (_) {
    print("socket connected");
  });

  socket.on('update', (data) {
    if (data.containsKey("error")) { // Error, tell the user
      warn("socket error: ${data["error"]}");
      if (data["code"] == "dev-id-invalid") globalerror = "Invalid device ID.";
    } else if (data.containsKey("action")) { // Action, like sleep or wake
      String action = data["action"];
      print("action received: $action");

      switch (action) {
        case "sleep": widget.sleep(); break;
        case "wake": widget.wakeup(); break;
        case "lock": lock(); break;
        case "unlock": unlock(widget: widget); break;
      }
    }
  });

  socket.on('connect_error', (error) {
    warn("socket connection error: $error");
  });

  socket.on('disconnect', (_) {
    print("socket disconnected");
  });

  Timer.periodic(Duration(milliseconds: stateUpdateInterval), (Timer timer) async {
    // Once per specified interval, get and send the current state.
    Map data = await getState();
    if (verbose) print("verbose: pushing state...");
    socket.emit("update", data);
  });

  // Every 10 minutes, update location.
  Timer.periodic(Duration(minutes: 10), (Timer timer) async {
    getLocation();
  });
}

// Lock the device using Device Policy Controller. Needs Device Admin. (Device Owner isn't necessary.)
Future<void> lock() async {
  try {
    print('locking device...');
    DevicePolicyController dpc = DevicePolicyController.instance;
    print("locking device...");
    bool locked = await dpc.lockDevice(); // Try to lock the device.

    if (locked) {
      print("device policy controller: device locked");
    } else {
      warn("device policy controller: device not locked");
    }
  } catch (e) {
    warn("device policy controller: device not locked: $e"); // Failed to lock the device, probably due to permissions.
  }
}

Future<bool> unlock({required HomeState widget}) async {
  MethodChannel platform = MethodChannel('com.calebh101.homeapphost.channel');
  bool result = await platform.invokeMethod('unlockDevice');
  widget.wakeup();
  print("unlock result: $result (time: $time)");
  return result;
}

// Get the state of the device.
Future<Map> getState() async {
  try {
    Battery battery = Battery();
    MethodChannel platform = MethodChannel('com.calebh101.homeapphost.channel'); // For getting device stats like temperature.
    NetworkInfo info = NetworkInfo();
    //DevicePolicyController dpc = DevicePolicyController.instance;
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    AndroidBuildVersion androidVersion = androidInfo.version;

    return {
      "lastUpdated": DateTime.now().toUtc().toIso8601String(),
      "battery": {
        "level": await battery.batteryLevel,
        "charging": (await battery.batteryState) == BatteryState.charging,
      },
      "admin": {
        "adminLocked": locked,
        "dashboardLocked": lockDashboard ? entireDashboardLocked : null,
      },
      "state": {
        "appawake": opacity == 0,
        "deviceawake": deviceAwake,
        "sleeptimer": time,
      },
      "temps": {
        "battery": await platform.invokeMethod('getBatteryTemperature'), // degrees celsius
      },
      "memory": {
        "available": androidInfo.availableRamSize, // megabytes
        "total": androidInfo.physicalRamSize, // megabytes
        "low": androidInfo.isLowRamDevice,
      },
      "model": {
        "model": androidInfo.model,
        "manufacturer": androidInfo.manufacturer,
        "board": androidInfo.board,
        "brand": androidInfo.brand,
        "device": androidInfo.device,
        "display": androidInfo.display,
        "fingerprint": androidInfo.fingerprint,
        "hardware": androidInfo.hardware,
        "host": androidInfo.host,
        "type": androidInfo.type,
        "physical": androidInfo.isPhysicalDevice,
      },
      "device": {
        "name": androidInfo.name,
        //"serial": androidInfo.serialNumber,
        "id": androidInfo.id,
        "tags": androidInfo.tags,
        "features": androidInfo.systemFeatures,
      },
      "version": {
        "type": "android",
        "base": androidVersion.baseOS,
        "codename": androidVersion.codename,
        "incremental": androidVersion.incremental,
        "release": androidVersion.release,
        "patch": androidVersion.securityPatch,
        "sdk": androidVersion.sdkInt,
        "previewSdk": androidVersion.previewSdkInt,
      },
      "info": {
        "version": version,
        "debug": debug,
      },
      "network": {
        "ip": await info.getWifiIP(),
        "wifi": (await info.getWifiName())?.replaceAll("\"", ""),
      },
      "location": location,
    };
  } catch (e, stackTrace) {
    warn("state error: $e");
    return {"error": "$e", "stack": "$stackTrace".replaceAll("  ", " ").replaceAll("  ", " ").replaceAll("  ", " ")};
  }
}

// Get the current GPS location and return it.
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

bool isInvalidPasswordResponse(http.Response response, Map body) {
  return response.statusCode == 403 && body["code"] == "ATV x3";
}

class WebsocketOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return client;
  }
}

void initWeather() async {
  // Every 10 minutes, get the ZIP code and update the weather.
  print("initializing weather...");
  updateWeather();

  Timer.periodic(Duration(minutes: 10), (Timer timer) async {
    updateWeather();
  });
}

Future<void> updateWeather() async {
  print("weather: updating weather...");
  Map? newWeather = await request(endpoint: "weather", body: {"zip": zip});
  if (newWeather == null) return;
  print("weather: received weather: ${newWeather.runtimeType}");
  weather = newWeather;
}

Future<void> getZip() async {
  print("zip: getting position...");
  Position position = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high));
  String? result;

  print("zip: getting placemarks...");
  List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);

  if (placemarks.isNotEmpty) {
    print("zip: found placemark: ${placemarks.first}");
    result = placemarks.first.postalCode;
  }

  if (result != null) {
    print("zip: found zip: $result");
    zip = result;
  }
}

Future<Map?> request({required String endpoint, Map<String, String>? headers, Map? body, BuildContext? context, String action = "complete action", Host? host, bool showError = true, bool silentLogging = false}) async {
  String baseurl = getBaseUrl();
  headers ??= {'Content-Type': 'application/json'};
  body ??= {};
  body["dashboard-auth"] = dotenv.DotEnv().env["ACCESS_CODE"];

  Uri url = Uri.parse("$baseurl/public/$endpoint");
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
      warn("invalid password response received");
      globalerror = "Access code invalid.";
      if (context != null && context.mounted) showSnackBar(context, "Unable to $action. Invalid password.");
    } else {
      if (result.containsKey('error')) {
        error('response error: $result', code: "${response.statusCode}");
      } else {
        error('response error', code: "${response.statusCode}");
      }
      if (showError && context != null && context.mounted) {
        showSnackBar(context, "Unable to $action. Please try again later.");
      }
    }
  } catch (e) {
    error('send error: $e', trace: true);
    if (showError && context != null && context.mounted) showSnackBar(context, "Unable to $action. Please try again later.");
  }

  return null;
}