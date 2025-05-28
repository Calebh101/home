import 'dart:async';

import 'package:flutter/material.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';

class NowPlayingPage extends StatefulWidget {
  final bool kiosk;
  const NowPlayingPage({super.key, required this.kiosk});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  Timer? timer;
  bool requesting = true;
  StreamSubscription? subscription;

  @override
  void initState() {
    super.initState();

    subscription = stateController.stream.listen((data) {
      refresh(mini: true);
    });

    requesting = false;
    refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    subscription?.cancel();
    super.dispose();
  }

  void refresh({bool mini = false}) {
    setState(() {});
  }

  Future<void> controlMusic({required String control}) async {
    requesting = true;
    refresh(mini: true);
    await request(endpoint: "music/$control", context: context, action: "control music", host: forceNativeSpotify ? Host.debug : null);
    requesting = false;
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(musicstatus["title"] ?? "Now Playing"),
        centerTitle: true,
        leading: IconButton(onPressed: () {
          Navigator.of(context).pop();
        }, icon: Icon(Icons.arrow_back)),
      ),
      body: Container(padding: EdgeInsets.all(8), child: musicstatus["status"] != 0 ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText("Song: ${musicstatus["title"]}"),
        SelectableText("Album: ${musicstatus["album"]}"),
        SelectableText("Author: ${musicstatus["artist"]}"),
        Spacer(),
        Row(
          children: [
            Text(musicstatus["position"]["formatted"]),
            SizedBox(width: 10),
            Expanded(child: LinearProgressIndicator(value: (musicstatus["length"]["raw"] - musicstatus["remaining"]["raw"]) / musicstatus["length"]["raw"])),
            SizedBox(width: 10),
            Text(musicstatus["length"]["formatted"]),
          ],
        ),
        Spacer(),
        TileRow(children: [
          TileBox(
            width: 2,
            rowPosition: TileRowPosition.both,
            child: Text(musicstatus["status"] == 1 ? "Pause" : "Play"),
            onPressed: requesting ? null : () async {
              controlMusic(control: musicstatus["status"] == 1 ? "pause" : "play");
            },
          ),
        ]),
        TileRow(
          children: [
            TileBox(
              child: Text("Back"),
              onPressed: requesting ? null : () async {
                controlMusic(control: "back");
              },
            ),
            TileBox(
              child: Text("Next"),
              onPressed: requesting ? null : () async {
                controlMusic(control: "next");
              },
            ),
          ],
        ),
        TileRow(
          children: [
            TileBox(
              width: 2,
              rowPosition: TileRowPosition.both,
              child: Text("Disconnect"),
              onPressed: requesting ? null : () async {
                controlMusic(control: "stop");
              },
            ),
          ],
        ),
      ]) : Center(child: Text("Nothing is playing right now."))),
    );
  }
}