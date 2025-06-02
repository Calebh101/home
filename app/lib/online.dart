import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:homeapp/login.dart';
import 'package:homeapp/main.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/logger.dart';

bool secureWebsocket = true;
bool debugHost = globalDebug;

enum Host {
  debug,
  release,
  forceDebug,
  forceDebugIgnore,
}

String getBaseUrl({Host? host, bool websocket = false}) {
  return globalKiosk ? "${websocket && secureWebsocket ? "wss" : "http"}://localhost" : ((defaultHost == Host.forceDebug ? Host.debug : (host ?? ((defaultHost) ?? (debugHost ? Host.debug : Host.release)))) == Host.debug) ? "${websocket && secureWebsocket ? "wss" : "http"}://192.168.0.21" : "${websocket && secureWebsocket ? "wss" : (websocket || useLocalHost ? "http" : "https")}://${useLocalHost ? "192.168.0.23" : "home.calebh101.com"}";
}

bool isInvalidPasswordResponse(http.Response response, Map body) {
  return response.statusCode == 403 && body["code"] == "ATV x1";
}

Future<Map?> request({required String endpoint, Map<String, String>? headers, Map? body, BuildContext? context, String action = "complete action", Host? host, bool showError = true, bool silentLogging = false}) async {
  String baseurl = getBaseUrl(host: host);
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
      warn("invalid password response received");
      runApp(LoginApp(kiosk: globalKiosk, debug: globalDebug));
    } else {
      if (result.containsKey('error')) {
        error('response error: $result', code: "${response.statusCode}");
      } else {
        error('response error', code: "${response.statusCode}");
      }
      if (showError && context != null) {
        showSnackBar(context, "Unable to $action. Please try again later.");
      }
    }
  } catch (e) {
    error('send error: $e', trace: true);
    if (showError && context != null) {
      showSnackBar(context, "Unable to $action. Please try again later.");
    }
  }

  return null;
}

Future<List> getGlucose({BuildContext? context, bool? sandbox}) async {
  print("getting glucose");
  sandbox ??= globalDebug;

  if (sandbox) {
    final int now = DateTime.now().millisecondsSinceEpoch - 5000;
    final List trends = ["Flat", "FortyFiveUp", "FortyFiveDown", "SingleUp", "SingleDown", "DoubleUp", "DoubleDown", "None", "NonComputable"];
    
    List readings = [];
    
    for (int i = 0; i < 12; i++) {
      var random = Random();
      int value = 40 + random.nextInt(221);
      int timestamp = now - (i * 5 * 60 * 1000);
      String trend = trends[random.nextInt(trends.length)];
      
      readings.add({
        "WT": "Date($timestamp)",
        "ST": "Date($timestamp)",
        "DT": "Date($timestamp-0500)",
        "Value": value,
        "Trend": trend,
      });
    }
    
    return readings;
  } else {
    return (await request(endpoint: "dexcom/get", showError: false, context: context, action: "fetch glucose", silentLogging: true))!["data"];
  }
}

Future<Map> getSpotify() async {
  var result = await Process.run('playerctl', [
    '-p',
    'spotifyd',
    'metadata',
    '--format',
    '{{ position }} |%%| {{ volume * 100 }} |%%| {{ status }} |%%| {{ artist }} |%%| {{ album }} |%%| {{ title }} |%%| {{ duration(position) }} |%%| {{ mpris:length - position}} |%%| {{ duration(mpris:length - position) }} |%%| {{ mpris:length }} |%%| {{ duration(mpris:length) }}'
  ]);

  String rawOut = (result.stdout.toString().trim().isEmpty)
      ? result.stderr.toString().trim()
      : result.stdout.toString().trim();

  if (rawOut == "No player could handle this command" || rawOut == "No players found") {
    return {"status": 0};
  }

  List<String> output = rawOut.split(" |%%| ");
  int positionRaw = int.tryParse(output[0]) ?? 0;
  String positionPretty = output[6];
  int remainingRaw = int.tryParse(output[7]) ?? 0;
  String remainingPretty = output[8];
  int lengthRaw = int.tryParse(output[9]) ?? 0;
  String lengthPretty = output[10];
  double volume = double.tryParse(output[1]) ?? 0.0;
  int status = getSpotifyStatus(output[2]);
  String artist = output[3];
  String album = output[4];
  String title = output[5];

  Map<String, dynamic> data = {
    "position": {
      "raw": positionRaw,
      "formatted": positionPretty,
    },
    "remaining": {
      "raw": remainingRaw,
      "formatted": remainingPretty,
    },
    "length": {
      "raw": lengthRaw,
      "formatted": lengthPretty,
    },
    "volume": volume,
    "status": status,
    "artist": artist,
    "album": album,
    "title": title,
  };

  return data;
}

int getSpotifyStatus(String input) {
  switch (input) {
    case 'Paused': return 2;
    case 'Playing': return 1;
    case 'Stopped': return 0;

    default:
      warn("invalid spotify status: $input");
      return -1;
  }
}

Timer? dexcomTimer;
int? dexcomTime;
StreamController dexcomController = StreamController.broadcast();
StreamController dexcomRefresherController = StreamController.broadcast();
bool dexcomRefresh = false;

void dexcomRefresher({bool? status}) {
  dexcomRefresh = status ?? dexcomRefresh;
  dexcomRefresherController.add(dexcomRefresh);
}

void dexcomSetup() async {
  bool isProcessing = false;
  List? previousData;

  dexcomTimer = Timer.periodic(Duration(seconds: 1), (Timer timer) async {
    if (dexcomController.isClosed || dexcomCrash) {
      warn("dexcom controller closed");
      timer.cancel();
      return;
    }

    int buffer = timeBuffer ?? 10;

    if (isProcessing == false) {
      if (dexcomTime == null || (((dexcomTime ?? 0) % 300 >= buffer) && ((dexcomTime ?? 0) % 300 < 30)) || dexcomRefresh) {
        if (verbose) print("$dexcomTime: ${(dexcomTime ?? 0) % 300} (true)");
        dexcomRefresher(status: true);

        isProcessing = true;
        dexcomTime ??= 0;

        try {
          (() async {
            List data = await getGlucose(sandbox: false);
            dexcomController.add(data);
            previousData = data;
          })();
        } catch (e) {
          dexcomController.addError(e);
          rethrow;
        } finally {
          isProcessing = false;
          if ((dexcomTime ?? 0) % 300 >= 30 || (dexcomTime ?? 0) <= 300) dexcomRefresher(status: false);
        }
      } else {
        if (verbose) print("$dexcomTime: ${(dexcomTime ?? 0) % 300} (false)");
        dexcomRefresher(status: false);
        dexcomController.add(previousData);
      }
    }

    if (previousData != null) dexcomTime = getDexcomTime(previousData![0]);
    dexcomTime = (dexcomTime == null ? 0 : dexcomTime! + 1);
  });
}

int getDexcomTime(Map data) {
  return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(int.parse(RegExp(r'\d+').firstMatch(data["DT"])?.group(0) ?? '0'), isUtc: true).toLocal()).inSeconds;
}

Map? currentState;
Map currentmusicstatus = {"status": 0};
StreamController stateController = StreamController.broadcast();
StreamController tempController = StreamController.broadcast();
io.Socket? stateSocket;

Future<void> stateInputter() async {
  int port = (await request(endpoint: 'system/status'))!["socket"]["port"];
  String url = '${getBaseUrl(websocket: true)}:$port';
  print("building socket... (url: $url)");

  io.Socket socket = io.io(url, io.OptionBuilder()
    .setTransports(['websocket'])
    .setPath('/state')
    .build());

  stateSocket = socket;
  print("socket built");

  socket.on('connect', (_) {
    print("socket connected");
  });

  socket.on('update', (data) {
    if (verbose) print("socket update: ${data.runtimeType}");
    stateController.sink.add({
      "music": data["app"]["music"],
      "state": data,
    });
  });

  socket.on('connect_error', (error) {
    warn("socket connection error: $error");
  });

  socket.on('disconnect', (_) {
    print("socket disconnected");
  });
}

void tempMonitor() {
  stateController.stream.listen((data) {
    List temperatures = [];
    Map result = {
      "fans": {
        "speed": data["state"]["fans"]["speed"],
      },
      "items": data["state"]["temperature"].entries.map((device) {
        try {
          String deviceId = device.key;
          Map<String, dynamic> details = device.value;

          String adapter = details["Adapter"];
          List<Map<String, dynamic>> sensors = [];

          details.forEach((key, value) {
            if (key != "Adapter") {
              sensors.add({
                "name": key,
                "values": value.entries.map((entry) {
                  if (entry.key.startsWith('temp') && entry.key.endsWith('_input')) {
                    temperatures.add({
                      "name": "$adapter ($deviceId) $key",
                      "value": entry.value,
                    });
                    handleTemp(adapter: adapter, adapterId: deviceId, sensor: key, temperature: entry.value);
                  }
                  return {
                    "name": entry.key,
                    "value": entry.value,
                  };
                }).toList(),
              });
            }
          });

          return {
            "id": deviceId,
            "adapter": adapter,
            "sensors": sensors,
          };
        } catch (e) {
          //print("temp error: $e");
        }
      }).toList(),
    };

    temperatures.sort((a, b) => b["value"].compareTo(a["value"]));
    result["temperatures"] = temperatures;
    tempController.add(result);
  });
}