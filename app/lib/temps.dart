import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:localpkg/dialogue.dart';

class TemperatureMonitor extends StatefulWidget {
  const TemperatureMonitor({super.key});

  @override
  State<TemperatureMonitor> createState() => _TemperatureMonitorState();
}

class _TemperatureMonitorState extends State<TemperatureMonitor> {
  StreamSubscription? stream;
  List temperatures = [];
  Map? temps;

  @override
  void initState() {
    super.initState();
    init();
    showSectionDialogue(context: context, id: "temps");
  }

  @override
  void dispose() {
    stream?.cancel();
    super.dispose();
  }

  void init() {
    stream = tempController.stream.listen((data) {
      temps = data;
      temperatures = data["temperatures"];
      refresh();
    });
  }

  void refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Temperature Monitor"),
        centerTitle: true,
        leading: IconButton(onPressed: () {
          Navigator.of(context).pop();
        }, icon: Icon(Icons.arrow_back)),
        actions: [
          IconButton(onPressed: () {
            Clipboard.setData(ClipboardData(text: JsonEncoder.withIndent('\t').convert(temps))).then((_) {
              showSnackBar(context, "Temperature data copied to clipboard!");
            });
          }, icon: Icon(Icons.copy)),
        ],
      ),
      body: temps == null ? Center(child: CircularProgressIndicator()) : Padding(
        padding: const EdgeInsets.all(8.0),
        child: Builder(
          builder: (context) {
            List items = temps!["items"];
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("General Temps", style: TextStyle(fontSize: 20)),
                  Builder(
                    builder: (context) {
                      List items = temperatures;
                      return ListView.builder(physics: NeverScrollableScrollPhysics(), shrinkWrap: true, itemBuilder: (BuildContext context, int index) {
                        Map item = items[index];
                        return Container(
                          padding: EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Text("${item["name"]}: ", style: TextStyle(fontSize: 16)),
                              SizedBox(width: 6),
                              Text("${item["value"]}°C", style: TextStyle(color: getColorForTemp(item["value"]))),
                            ],
                          ),
                        );
                      }, itemCount: items.length);
                    },
                  ),
                  ListView.builder(physics: NeverScrollableScrollPhysics(), shrinkWrap: true, itemBuilder: (BuildContext context, int index) {
                    Map? item = items[index];
                    if (item == null) {
                      return Column(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 72, color: getThemeColor(context)),
                          Text("There was an error getting the system temperatures.")
                        ],
                      );
                    }
                    return Container(
                      padding: EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${item["adapter"]} - ${item["id"]}", style: TextStyle(fontSize: 20)),
                          Builder(
                            builder: (context) {
                              List items = item["sensors"];
                              return ListView.builder(physics: NeverScrollableScrollPhysics(), shrinkWrap: true, itemBuilder: (BuildContext context, int index) {
                                Map item = items[index];
                                return Container(
                                  padding: EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("${item["name"]}", style: TextStyle(fontSize: 18)),
                                      Builder(
                                        builder: (context) {
                                          List items = item["values"];
                                          return ListView.builder(physics: NeverScrollableScrollPhysics(), shrinkWrap: true, itemBuilder: (BuildContext context, int index) {
                                            Map item = items[index];
                                            return Container(
                                              padding: EdgeInsets.all(8),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text("${item["name"]}: ${item["value"]}", style: TextStyle(fontSize: 16)),
                                                ],
                                              ),
                                            );
                                          }, itemCount: items.length);
                                        }
                                      ),
                                    ],
                                  ),
                                );
                              }, itemCount: items.length);
                            }
                          ),
                        ],
                      ),
                    );
                  }, itemCount: items.length),
                  Text("Fan Speed", style: TextStyle(fontSize: 20)),
                  Row(
                    children: [
                      IconButton(onPressed: () {}, icon: Icon(Icons.more_horiz), color: getThemeColor(context)),
                      Text("General: ${temps?["fans"]?["speed"] ?? "0"}%"),
                    ],
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