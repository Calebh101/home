import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/glucose.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:localpkg/functions.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

int fireplaces = 0;
int activeFireplace = 0;
bool fireplaceSound = false;

void activateFireplace({required BuildContext context, required bool kiosk, required bool debug, required int type}) {
  navigate(context: context, page: Fireplace(kiosk: kiosk, debug: debug, type: type), mode: 2);
}

class Fireplace extends StatefulWidget {
  final bool debug;
  final bool kiosk;
  final int type;
  const Fireplace({super.key, required this.debug, required this.kiosk, this.type = 1});

  @override
  State<Fireplace> createState() => _FireplaceState();
}

class _FireplaceState extends State<Fireplace> {
  late Player player = Player(configuration: PlayerConfiguration(title: "Fireplace"));
  late VideoController controller = VideoController(player, configuration: VideoControllerConfiguration());
  bool ready = false;
  StreamSubscription? stream;
  AudioPlayer? audio;

  double getVolume() {
    double volume = fireplaceSound ? 1 : 0;
    print("fireplace: volume: $volume");
    return volume;
  }

  @override
  void initState() {
    fireplaces++;
    print("starting fireplace ($fireplaces active)");

    super.initState();
    init();
  }

  void init() async {
    List fireplaces = (await getConfig())["fireplaces"];
    Map currentfireplace = fireplaces.firstWhere((obj) => obj['id'] == widget.type, orElse: () => {});
    String path = '$homedir/assets/fireplace/${currentfireplace["file"]}';

    print("loading video with path $path");
    Media media = Media(path);
    Source audioSource = DeviceFileSource("$homedir/assets/fireplace.mp3");

    audio = AudioPlayer();
    audio!.setReleaseMode(ReleaseMode.loop);
    playAudio(audioSource);

    player.setPlaylistMode(PlaylistMode.single);
    player.setVolume(0);
    activeFireplace = widget.type;
    await player.open(media);
    await player.play();
    ready = true;
    refresh();

    stream = commandController.stream.listen((data) {
      if (data.contains("fireplace_off")) {
        print("exiting fireplace ($fireplaces active)");
        navigate(context: context, page: Dashboard(kiosk: widget.kiosk, debug: widget.debug), mode: 2);
      } else if (data.contains("fireplace_on")) {
        int type = int.tryParse(data.split("fireplace_on")[1].trim()) ?? 1;
        navigate(context: context, page: Fireplace(kiosk: widget.kiosk, debug: widget.debug, type: type), mode: 2);
        dispose();
      } else if (data.contains("fireplace_update")) {
        refresh();
      } else if (data.contains("glucose_on")) {
        if (glucoseActive == false) {
          print("fireplace: glucose called");
          navigate(context: context, page: GlucoseMonitor(debug: widget.debug, kiosk: widget.kiosk), mode: 2);
        }
      }
    });
  }

  void playAudio(Source source) {
    print("fireplace: playing audio...");
    audio!.play(source, volume: getVolume());
  }

  void refresh() {
    print("fireplace: refreshing...");
    audio?.setVolume(getVolume());
    setState(() {});
  }

  @override
  void dispose() {
    fireplaces--;
    player.dispose();
    stream?.cancel();
    audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(child: MouseRegion(child: Video(controller: controller, controls: NoVideoControls), cursor: SystemMouseCursors.none), onTap: () {
      dispose();
      navigate(context: context, page: Dashboard(kiosk: widget.kiosk, debug: widget.debug), mode: 2);
    });
  }
}

class FireplaceSelector extends StatefulWidget {
  final List fireplaces;
  const FireplaceSelector({super.key, required this.fireplaces});

  @override
  State<FireplaceSelector> createState() => _FireplaceSelectorState();
}

class _FireplaceSelectorState extends State<FireplaceSelector> {
  @override
  Widget build(BuildContext context) {
    print("current fireplace: $activeFireplace");
    return Scaffold(
      appBar: AppBar(
        title: Text("Fireplaces"),
        centerTitle: true,
        leading: IconButton(onPressed: () {
          Navigator.of(context).pop();
        }, icon: Icon(Icons.arrow_back)),
        actions: [
          StreamBuilder(
            stream: stateController.stream,
            builder: (context, snapshot) {
              if (snapshot.data == null) return Center(child: CircularProgressIndicator());
              bool status = (snapshot.data as Map)["state"]["app"]["fireplace"]["sound"];

              return IconButton(
                icon: Icon(status ? Icons.volume_up : Icons.volume_off),
                onPressed: () {
                  request(endpoint: "fireplace/sound/${status ? "off" : "on"}", action: "change fireplace volume", context: context);
                },
              );
            }
          ),
        ],
      ),
      body: ListView.builder(itemCount: widget.fireplaces.length + 1, itemBuilder: (context, index) {
        bool off = index >= widget.fireplaces.length;
        Map item = off ? {"name": "Off", "id": 0} : widget.fireplaces[index];
        bool active = activeFireplace == item["id"];
        return ListTile(
          leading: Icon(off ? (active ? Icons.close : Icons.close_outlined) : (active ? Icons.star : Icons.star_outline)),
          title: Text(item["name"]),
          onTap: () {
            if (off) {
              request(endpoint: "fireplace/off", context: context, action: "deactivate fireplace");
              activeFireplace = 0;
              setState(() {});
            } else {
              request(endpoint: "fireplace/on", context: context, action: "activate fireplace", body: {"type": item["id"]});
              activeFireplace = item["id"];
              setState(() {});
            }
          },
        );
      }),
    );
  }
}