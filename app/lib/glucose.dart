import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/fireplace.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:localpkg/functions.dart';
import 'package:localpkg/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

int minGlucose = 40;
int maxGlucose = 300;
bool glucoseActive = false;

class GlucoseMonitor extends StatefulWidget {
  final bool debug;
  final bool kiosk;
  final int type;
  const GlucoseMonitor({super.key, required this.debug, required this.kiosk, this.type = 1});

  @override
  State<GlucoseMonitor> createState() => _GlucoseMonitorState();
}

class _GlucoseMonitorState extends State<GlucoseMonitor> {
  bool? remoteGlucoseActive;
  bool loading = true;
  StreamSubscription? timer;
  StreamSubscription? commandStream;
  bool coloredGraph = true;

  @override
  void initState() {
    print("starting glucose monitor");
    glucoseActive = true;

    super.initState();
    init();
    showSectionDialogue(context: context, id: "dexcom");

    timer = stateController.stream.listen((data) {
      if (loading) return;
      if (data == null) {
        remoteGlucoseActive = null;
      } else {
        remoteGlucoseActive = data["state"]["app"]["glucose"]["active"];
      }
      refresh();
    });
  }

  void init() async {
    setState(() {});
    SharedPreferences prefs = await SharedPreferences.getInstance();

    commandStream = commandController.stream.listen((data) {
      if (data.contains("glucose_off")) {
        print("exiting glucose monitor");
        glucoseActive = false;
        back(context, kiosk: widget.kiosk, debug: widget.debug);
      } else if (data.contains("glucose_reload")) {
        print('refresh called');
        dexcomRefresher(status: true);
      } else if (data.contains("fireplace_on") && glucoseActive) {
        int type = int.tryParse(data.split("fireplace_on")[1].trim()) ?? 1;
        activateFireplace(context: context, kiosk: widget.kiosk, debug: widget.debug, type: type);
        dispose();
      }
    });

    coloredGraph = prefs.getBool("coloredGraphs") ?? coloredGraph;
    loading = false;
    refresh();
  }

  @override
  void dispose() {
    glucoseActive = false;
    timer?.cancel();
    commandStream?.cancel();
    super.dispose();
  }

  void refresh() {
    setState(() {});
  }

  Future<void> action(String action) async {
    loading = true;
    remoteGlucoseActive = null;
    refresh();
    await request(endpoint: 'dexcom/app/$action', context: context, action: "$action remote monitor");
    loading = false;
    refresh();
    return;
  }

  @override
  Widget build(BuildContext context) {
    double size = MediaQuery.of(context).size.width / 200;
    double maxSize = widget.kiosk ? 4 : 2;
    double iconSize = 24;

    if (size > maxSize) size = maxSize;
    return Scaffold(
      appBar: AppBar(
        title: Text("Glucose"),
        centerTitle: true,
        leading: IconButton(onPressed: () {
          back(context, kiosk: widget.kiosk, debug: widget.debug);
        }, icon: Icon(Icons.arrow_back), iconSize: iconSize),
        actions: [
          if (widget.kiosk == false)
          IconButton(onPressed: () async {
            if (remoteGlucoseActive == true) {
              await action("close");
            } else if (remoteGlucoseActive == false) {
              await action("open");
            }
          }, icon: remoteGlucoseActive == true ? Icon(Icons.stop_rounded) : (remoteGlucoseActive == false ? Icon(Icons.ios_share_rounded) : Container(child: CircularProgressIndicator(), width: iconSize, height: iconSize)), iconSize: iconSize),
          if (!dexcomCrash)
          StreamBuilder(
            stream: dexcomRefresherController.stream,
            builder: (context, snapshot) {
              return IconButton(onPressed: () {
                dexcomRefresher(status: true);
                if (!widget.kiosk) request(endpoint: 'dexcom/app/refresh', action: 'refresh monitor');
              }, icon: dexcomRefresh == false && snapshot.connectionState != ConnectionState.waiting && snapshot.hasData ? Icon(Icons.refresh) : Container(child: CircularProgressIndicator(), width: iconSize, height: iconSize), iconSize: iconSize);
            }
          ),
        ],
      ),
      body: dexcomCrash ? Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, color: getThemeColor(context), size: 96),
          Text("The Dexcom monitor crashed due to a fatal error."),
        ],
      )) : StreamBuilder(
        stream: dexcomController.stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || (globalGlucoseLimits == null && showUncoloredGlucose == false)) {
            return Center(child: const CircularProgressIndicator());
          } else if (snapshot.hasError) {
            error("snapshot error: ${snapshot.error}");
            return Center(child: Text('No Data', style: TextStyle(color: Colors.red, fontSize: 48)));
          } else if (snapshot.hasData) {
            List data = snapshot.data as List;

            if (data.isEmpty) {
              return Center(child: Text('No Data', style: TextStyle(color: Colors.red, fontSize: 48)));
            }

            return Center(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${data[0]["Value"]}',
                        style: TextStyle(fontSize: 48 * size, color: getColorForValue(data[0]["Value"])),
                      ),
                      generateArrow(data[0]["Trend"], size: size, context: context),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      data.length >= 2 ? Row(
                        children: [
                          Text(
                            "${data[1]["Value"]}",
                            style: TextStyle(fontSize: 20 * size, color: getColorForValue(data[1]["Value"])),
                          ),
                          generateArrow(data[1]["Trend"], size: 0.4 * size, context: context),
                        ],
                      ) : Text("No Data", style: TextStyle(fontSize: 20 * size, color: Colors.red)),
                      if (dexcomTime != null)
                      Row(
                        children: [
                          SizedBox(width: 10 * size),
                          Text("-${(dexcomTime ?? 0) ~/ 60}:${((dexcomTime ?? 0) % 60).toString().padLeft(2, '0')}", style: TextStyle(
                            color: getColorForTime(dexcomTime ?? 0),
                            fontSize: 20 * size,
                          )),
                        ],
                      ),
                    ],
                  ),
                  Builder(
                    builder: (context) {
                      bool pointOnMinX = false;
                      int length = data.length;
                      int maxLength = ((MediaQuery.of(context).size.width / 200) * 7).round();

                      if (length > maxLength) length = maxLength;
                      double minX = 5 - (length * 5);

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: LineChart(
                            LineChartData(
                              minX: minX,
                              maxX: 0,
                              minY: minGlucose.toDouble(),
                              maxY: maxGlucose.toDouble(),
                              baselineY: 40,
                              lineBarsData: [
                                LineChartBarData(
                                  spots: List.generate(length, (index) {
                                    int value = data[index]["Value"];
                                    double time = ((0 - ((getDexcomTime(data[index])) / 60)).floor().toDouble()) + 1;

                                    if (time < minX && pointOnMinX == false) time = minX;
                                    if (time == minX) pointOnMinX = true;
                                    if (time < minX && pointOnMinX == true) return null;

                                    if (value > maxGlucose) value = maxGlucose;
                                    if (value < minGlucose) value = minGlucose;
                                    return FlSpot(time, value.toDouble());
                                  }).whereType<FlSpot>().toList(),
                                  isCurved: true,
                                  belowBarData: BarAreaData(show: false),
                                  barWidth: 0,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter: (FlSpot spot, double xPercentage, LineChartBarData bar, int index, {double? size}) {
                                      Color? color =  coloredGraph ? getColorForValue(spot.y.toInt()) : Colors.blue;

                                      return FlDotCirclePainter(
                                        radius: 4,
                                        color: color ?? getThemeColor(context),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        '${value.toInt()}m',
                                        style: TextStyle(
                                          fontSize: 12,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: false,
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  axisNameWidget: SizedBox.shrink(),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 36,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        "${value.toInt()}",
                                        style: TextStyle(
                                          color: coloredGraph ? (getColorForValue(value.toInt())) : null,
                                        ),
                                        textAlign: TextAlign.center,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(show: true),
                              gridData: FlGridData(show: true),
                            ),
                          ),
                        ),
                      );
                    }
                  ),
                ],
              ),
            );
          } else {
            return Center(child: const CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

void back(BuildContext context, {required bool kiosk, required bool debug}) {
  navigate(context: context, page: Dashboard(kiosk: kiosk, debug: debug), mode: 2);
}