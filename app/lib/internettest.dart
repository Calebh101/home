import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:http/http.dart' as http;
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/logger.dart';

class InternetTest extends StatefulWidget {
  const InternetTest({super.key});

  @override
  State<InternetTest> createState() => _InternetTestState();
}

enum Status {
  waiting,
  complete,
  show,
  failed,
  connectingToRouter,
  waitingOnHost,
  runningSpeedTest,
  gettingNetworkDetails,
  personalRequest,
}

Future<Map> ping(String url) async {
  print("ping start: $url");
  Stopwatch stopwatch = Stopwatch();

  try {
    stopwatch.start();
    final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 10));
    stopwatch.stop();
    print("ping success: $url");

    if (response.statusCode >= 500) {
      throw Exception("HTTP statuscode ${response.statusCode}");
    }

    return {
      "status": true,
      "host": url,
      "elapsed": stopwatch.elapsedMilliseconds,
      "error": null,
    };
  } catch (e) {
    stopwatch.stop();
    warn("ping connect error: $e");

    return {
      "status": false,
      "host": url,
      "elapsed": stopwatch.elapsedMilliseconds,
      "error": "$e",
    };
  }
}

Future<Map> getPersonalData() async {
  String host = "calebh101.com";
  Uri uri = Uri.parse("${(serverHost ?? defaultHost) == Host.release ? "https://api.$host" : "http://api.localhost:5000"}/v1/launch/check/general");
  Map pinged = await ping("$uri");
  Map? responseData;

  try {
    print("request: start: $uri");
    final response = await http.get(uri);
    Map data = json.decode(response.body);

    if (response.statusCode == 200) {
      print("request: success");
      responseData = {
        "code": response.statusCode,
        "available": data["general"]["available"],
      };
    } else {
      warn("request: error: ${data["error"]}");
      responseData = {
        "code": response.statusCode,
        "error": data["error"] ?? "unknown error",
      };
    }
  } catch (e) {
    error("request: error: $e");
    responseData = {
      "code": 0,
      "error": "$e",
    };
  }

  return {
    "ping": pinged,
    "request": responseData,
  };
}

class _InternetTestState extends State<InternetTest> {
  Status status = Status.waiting;
  Map? data;
  StreamSubscription? ssestream;
  String? recordederror;

  void setStatus(Status value) {
    status = value;
    refresh();
  }

  Status getStatusFromInt(int value) {
    switch (value) {
      case -1: return Status.failed;
      case 0: return Status.complete;
      case 1: return Status.runningSpeedTest;
      case 2: return Status.gettingNetworkDetails;
      case 3: return Status.connectingToRouter;
      default: throw Exception("Unknown status: $value");
    }
  }

  String getStringFromStatus(Status value) {
    switch (value) {
      case Status.waiting: return "Start";
      case Status.complete: return "Scan Complete";
      case Status.show: return "Scan Results";
      case Status.connectingToRouter: return "Pinging router...";
      case Status.gettingNetworkDetails: return "Getting network details...";
      case Status.runningSpeedTest: return "Running speed test...";
      case Status.waitingOnHost: return "Waiting on host...";
      case Status.personalRequest: return "Requesting server...";
      case Status.failed: return "Failed";
    }
  }

  void start() async {
    try {
      setStatus(Status.connectingToRouter);
      Map? routerStatus = await request(endpoint: "internet/router");
      if (routerStatus == null) throw Exception("routerStatus was null.");

      setStatus(Status.personalRequest);
      Map personalStatus = await getPersonalData();

      void callback(Map sseData) async {
        print("received callback");
        ssestream?.cancel();

        data = {
          "router": routerStatus,
          "server": sseData,
          "request": personalStatus,
        };

        print("internet test complete");
        setStatus(Status.complete);
      }

      setStatus(Status.waitingOnHost);
      String url = "${getBaseUrl()}/api/internet/test";
      bool buffering = false;
      List<List<int>> buffer = [];
      print("sse: starting: $url");
      http.StreamedResponse sse = await http.Client().send(http.Request('POST', Uri.parse(url)));

      ssestream = sse.stream.listen((List<int> data) {
        print("sse: received event");
        try {
          String decoded = utf8.decode(data);
          print("decoded data: $decoded");
          if (decoded.contains('"status":0') || buffering == true) {
            buffering = true;
            buffer.add(data);
            print("sse: buffer received (${buffer.length})");
          } else {
            Map message = jsonDecode(decoded);
            print("sse: message: $message");
            Status newStatus = getStatusFromInt(message["status"]);

            if (newStatus == Status.complete) {
              print("sse: complete");
              callback(message);
            } else {
              if (newStatus == Status.failed) {
                warn("sse: server error: ${message["error"]}");
                recordederror = message["error"];
              }
              setStatus(getStatusFromInt(message["status"]));
            }
          }
        } catch (e) {
          warn("sse: error: $e");
          recordederror = "$e";
          setStatus(Status.failed);
        }
      }, onDone: () {
        print('sse: closed');
        String message = utf8.decode(buffer.expand((innerList) => innerList).toList());
        print("sse: buffer: $message");
        callback(jsonDecode(message));
      });
    } catch (e) {
      warn("start error: $e");
      recordederror = "$e";
      setStatus(Status.failed);
    }
  }

  @override
  void dispose() {
    ssestream?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    showSectionDialogue(context: context, id: "internet-test");
  }

  void refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Internet Test"),
        centerTitle: true,
        leading: IconButton(onPressed: () {
          Navigator.of(context).pop();
        }, icon: Icon(Icons.arrow_back)),
        actions: [
          if (status == Status.show)
          IconButton(onPressed: () {
            Clipboard.setData(ClipboardData(text: jsonEncode(data)));
            showSnackBar(context, "Data copied!");
          }, icon: Icon(Icons.copy)),
          if (status == Status.failed)
          IconButton(onPressed: () {
            Clipboard.setData(ClipboardData(text: "Error: ${recordederror ?? "unkown error"}"));
            showSnackBar(context, "Error message copied!");
          }, icon: Icon(Icons.copy)),
          if (status == Status.complete || status == Status.show || status == Status.failed || status == Status.waiting)
          IconButton(onPressed: () {
            start();
          }, icon: Icon(status == Status.waiting ? Icons.play_arrow_rounded : Icons.refresh)),
        ],
      ),
      body: Center(
        child: Builder(
          builder: (context) {
            String text = getStringFromStatus(status);
            double iconSize = status == Status.show ? 8 : 64;

            return SingleChildScrollView(
              child: Column(
                children: [
                  AnimatedSwitcher(
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    duration: Duration(milliseconds: 300),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      final offsetAnimation = Tween<Offset>(
                        begin: Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: offsetAnimation,
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      key: ValueKey("status:$status"),
                      children: [
                        Text(text, style: TextStyle(fontSize: 24)),
                        Container(width: iconSize, height: iconSize, child: status == Status.waiting ? IconButton(
                          icon: Icon(Icons.play_arrow_rounded),
                          onPressed: () {
                            start();
                          },
                          iconSize: iconSize - 16,
                          color: getThemeColor(context)
                        ) : (status == Status.failed ? Icon(Icons.warning_amber_rounded, size: iconSize - 16, color: getThemeColor(context)) : (status != Status.complete && status != Status.show ? Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(color: getThemeColor(context)),
                        ) : (status == Status.complete ? IconButton(icon: Icon(Icons.check), iconSize: iconSize - 16, color: getThemeColor(context), onPressed: () {
                          setStatus(Status.show);
                        }) : (SizedBox.shrink()))))),
                        if (status == Status.show)
                        Builder(
                          builder: (context) {
                            Map results = data!;
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ResultsTitle("Router"),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: "Status: ",
                                        ),
                                        TextSpan(
                                          text: results["router"]["status"] ? "Up" : "Down",
                                          style: TextStyle(
                                            color: results["router"]["status"] ? Colors.green : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (results["router"]["status"])
                                  Builder(
                                    builder: (context) {
                                      num value = results["router"]["elapsed"];
                                      return Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: "Response time: ",
                                            ),
                                            TextSpan(
                                              text: "${value.round()}",
                                              style: TextStyle(
                                                color: value <= 5 ? Colors.green : (value >= 50 ? Colors.red : Colors.yellow),
                                              ),
                                            ),
                                            TextSpan(
                                              text: " ms",
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  ),
                                  Text("Host: ${results["router"]["host"]}"),
                                  if (results["server"]["result"]["speedtest"] != null)
                                  Builder( // main speedtest results renderer
                                    builder: (context) {
                                      Map speedtest = results["server"]["result"]["speedtest"]["result"];

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              ResultsTitle("Speed Test"),
                                              SizedBox(width: 4),
                                              IconButton(onPressed: () {
                                                openUrlConf(context, Uri.parse(speedtest["result"]["url"]));
                                              }, icon: Icon(Icons.public), color: Colors.blue),
                                            ],
                                          ),
                                          ResultsTitle("Download", level: ResultsTitleLevel.medium),
                                          SpeedResults(input: speedtest["download"], range: Range(high: 150, low: 40)),
                                          LatencyResult(speedtest["download"]["latency"]),
                                          ResultsTitle("Upload", level: ResultsTitleLevel.medium),
                                          SpeedResults(input: speedtest["upload"], range: Range(high: 20, low: 5)),
                                          LatencyResult(speedtest["upload"]["latency"]),
                                          ResultsTitle("Ping", level: ResultsTitleLevel.medium),
                                          PingResult(speedtest["ping"]),
                                        ],
                                      );
                                    }
                                  ),
                                  ResultsTitle("Server Request"),
                                  Builder(
                                    builder: (context) {
                                      Map ping = results["request"]["ping"];
                                      Map request = results["request"]["request"];
                                      request["available"] ??= {"enabled": false};

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: "Reachable: ",
                                                ),
                                                TextSpan(
                                                  text: ping["status"] ? "Yes" : "No",
                                                  style: TextStyle(
                                                    color: ping["status"] ? Colors.green : Colors.red,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: "Available: ",
                                                ),
                                                TextSpan(
                                                  text: request["available"]["enabled"] ? "Yes" : "No",
                                                  style: TextStyle(
                                                    color: request["available"]["enabled"] ? Colors.green : Colors.red,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: " (code: ",
                                                ),
                                                TextSpan(
                                                  text: "${request["code"]}",
                                                  style: TextStyle(
                                                    color: request['code'] >= 200 && request['code'] < 300 ? Colors.green : (request['code'] >= 300 && request['code'] < 400 ? Colors.yellow : Colors.red)
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: ")",
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text("Host: ${ping["host"]}"),
                                        ],
                                      );
                                    },
                                  ),
                                  Builder(
                                    builder: (context) {
                                      Map? status = results["server"]["result"]["status"];
                                      Map? speedtest = results["server"]["result"]["speedtest"]?["result"];

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          ResultsTitle("Network Info"),
                                          if (status != null)
                                          Builder(
                                            builder: (context) {
                                              num value = num.parse(RegExp(r'(\d+)').firstMatch(status["CAPABILITIES"]["SPEED"])?.group(1) ?? "0");
                                              return Text.rich(
                                                TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: "Network speed: ",
                                                    ),
                                                    TextSpan(
                                                      text: "$value",
                                                      style: TextStyle(
                                                        color: value <= 50 ? Colors.red : (value >= 200 ? Colors.green : Colors.yellow),
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: " Mbps",
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          ),
                                          Text("External IP address: ${speedtest?["interface"]["externalIp"] ?? "unknown"}"),
                                          if (status != null)
                                          Text("Router IP address: ${status["DHCP4-parsed"]["routers"]}"),
                                          if (status != null)
                                          Text("DHCP server IP address: ${status["DHCP4-parsed"]["dhcp_server_identifier"]}"),
                                          if (status != null)
                                          Text("Network subnet mask: ${status["DHCP4-parsed"]["subnet_mask"]}"),
                                          if (status != null)
                                          Text("DNS servers: ${status["DHCP4-parsed"]["domain_name_servers"].split(" ").join(", ")}"),
                                          if (status != null)
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: "Metered: ",
                                                ),
                                                TextSpan(
                                                  text: status["GENERAL"]["METERED"] ? "Yes" : "No",
                                                  style: TextStyle(
                                                    color: status["GENERAL"]["METERED"] ? Colors.red : Colors.green,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text("ISP: ${speedtest?["isp"] ?? "unknown"}"),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          }
                        ),
                      ],
                    )
                  ),
                ],
              ),
            );
          }
        ),
      ),
    );
  }
}

class SpeedResults extends StatelessWidget {
  final Map input;
  final Range range;
  const SpeedResults({super.key, required this.input, required this.range});

  double getSpeed(num value) {
    return (value * 8) / 1000000; // Mbps
  }

  @override
  Widget build(BuildContext context) {
    double speed = getSpeed(input["bandwidth"]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: "Speed: ",
              ),
              TextSpan(
                text: "${double.parse(speed.toStringAsFixed(2))}",
                style: TextStyle(
                  color: speed < range.low ? Colors.red : (speed < range.high ? Colors.yellow : Colors.green)
                ),
              ),
              TextSpan(
                text: " Mbps",
              ),
            ],
          ),
        ),
        Text("Elapsed: ${(input["elapsed"] / 6000).round()}s"),
      ],
    );
  }
}

class Range {
  final double high;
  final double low;
  const Range({required this.high, required this.low});
}

class LatencyResult extends StatelessWidget {
  final Map latency;
  final Range? average;
  final Range? low;
  final Range? high;
  final Range? jitter;
  const LatencyResult(this.latency, {super.key, this.average, this.low, this.high, this.jitter});

  double round(num value) {
    return double.parse(value.toStringAsFixed(2));
  }

  Color getColorForRange(num value, {required Range range}) {
    return value <= range.low ? Colors.green : (value >= range.high ? Colors.red : Colors.yellow);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildSpan(value: latency["iqm"], type: "average", range: Range(high: 80, low: 40)),
        buildSpan(value: latency["high"], type: "highest", range: Range(high: 200, low: 100)),
        buildSpan(value: latency["low"], type: "lowest", range: Range(high: 60, low: 30)),
        buildSpan(value: latency["jitter"], type: "jitter", range: Range(high: 30, low: 10)),
      ],
    );
  }

  Widget buildSpan({required num value, required String type, required Range range}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: "${type[0].toUpperCase() + type.substring(1).toLowerCase()} latency: ",
          ),
          TextSpan(
            text: "${round(value)}",
            style: TextStyle(
              color: getColorForRange(value, range: range),
            ),
          ),
          TextSpan(
            text: " ms",
          ),
        ],
      ),
    );
  }
}

class PingResult extends StatelessWidget {
  final Map result;
  final Range? average;
  final Range? low;
  final Range? high;
  final Range? jitter;
  const PingResult(this.result, {super.key, this.average, this.low, this.high, this.jitter});

  double round(num value) {
    return double.parse(value.toStringAsFixed(2));
  }

  Color getColorForRange(num value, {required Range range}) {
    return value <= range.low ? Colors.green : (value >= range.high ? Colors.red : Colors.yellow);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildSpan(value: result["latency"], type: "latency", range: Range(high: 50, low: 20)),
        buildSpan(value: result["high"], type: "highest", range: Range(high: 100, low: 50)),
        buildSpan(value: result["low"], type: "lowest", range: Range(high: 50, low: 20)),
        buildSpan(value: result["jitter"], type: "jitter", range: Range(high: 30, low: 10)),
      ],
    );
  }

  Widget buildSpan({required num value, required String type, required Range range}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: "${type[0].toUpperCase() + type.substring(1).toLowerCase()} ping: ",
          ),
          TextSpan(
            text: "${round(value)}",
            style: TextStyle(
              color: getColorForRange(value, range: range),
            ),
          ),
          TextSpan(
            text: " ms",
          ),
        ],
      ),
    );
  }
}

class ResultsTitleLevel {
  static int large = 22;
  static int medium = 18;
}

// ignore: must_be_immutable
class ResultsTitle extends StatelessWidget {
  String data;
  int? level;
  ResultsTitle(this.data, {super.key, this.level});

  @override
  Widget build(BuildContext context) {
    level ??= ResultsTitleLevel.large;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(data, textAlign: TextAlign.center, style: TextStyle(fontSize: level!.toDouble())),
    );
  }
}