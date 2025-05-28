import 'dart:async';

import 'package:flutter/material.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/logger.dart';

Future<void> updateTvPowerState({required String id}) async {
  tvPowerStates[id] = (await request(endpoint: "devices/tvs/vizio/power/state", body: {"id": id}))?["status"];
}

Future<void> updateTvStates() async {
  refreshingTvStates = true;
  for (var entry in tvs.asMap().entries) {
    int i = entry.key;
    Map tv = entry.value;
    await updateTvState(id: tv["id"], standalone: false);
    if (i + 1 == tvs.length) refreshingTvStates = false;
  }
}

Future<void> updateTvState({required String id, bool standalone = true}) async {
  if (standalone) refreshingTvStates = true;
  print("updating state of tv: $id");
  await updateTvPowerState(id: id);
  if (standalone) refreshingTvStates = false;
}

Future<Map?> tvRequestGlobal({required String endpoint, required String id, Map? body}) async {
  body ??= {};
  body["id"] = id;
  return await request(endpoint: "devices/tvs/vizio/$endpoint", body: body);
}

class TVController extends StatefulWidget {
  final String id;
  final String name;
  const TVController({super.key, required this.id, required this.name});

  @override
  State<TVController> createState() => _TVControllerState();
}

class _TVControllerState extends State<TVController> {
  int screenMode = 0;
  List? sources;
  late Timer timer;

  Future<Map?> command({required String endpoint, Map? body}) {
    return tvRequestGlobal(endpoint: endpoint, body: body, id: widget.id);
  }

  void refresh() {
    setState(() {});
  }

  Future<void> update() async {
    await updateTvState(id: widget.id);
  }

  @override
  void initState() {
    super.initState();
    update();
    showSectionDialogue(context: context, id: "tv");

    timer = Timer.periodic(Duration(milliseconds: 500), (Timer timer) {
      refresh();
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  VoidCallback KeyCallback(int set, int code) {
    return Key([KeyCode(set, code)], command: command);
  }

  @override
  Widget build(BuildContext context) {
    double screenThreshold = 440;
    int sections = 1;
    screenMode = (getScreen(context: context).width / screenThreshold).ceil();

    if (screenMode > sections) {
      screenMode = sections;
    }

    List<Widget> children = [
      Section(context: context, index: 1, rows: 8, children: [
        TileRow(context: context, columns: 3, children: [
          TileButton(child: ButtonContent(icon: Icons.keyboard_arrow_left), onPressed: KeyCallback(4, 0)),
          TileButton(child: ButtonContent(icon: Icons.home), onPressed: KeyCallback(4, 3)),
          TileButton(child: ButtonContent(icon: Icons.remove), onPressed: KeyCallback(7, 1)),
        ]),
        TileRow(context: context, columns: 3, children: [
          TileButton(child: ButtonContent(icon: Icons.keyboard_arrow_up, text: "Vol"), onPressed: KeyCallback(5, 1)),
          TileButton(child: ButtonContent(icon: Icons.arrow_upward), elevated: true, onPressed: KeyCallback(3, 8)),
          TileButton(child: ButtonContent(icon: Icons.keyboard_arrow_up, text: "Ch"), onPressed: KeyCallback(8, 1)),
        ]),
        TileRow(context: context, columns: 3, children: [
          TileButton(child: ButtonContent(icon: Icons.arrow_back), elevated: true, onPressed: KeyCallback(3, 1)),
          TileButton(child: ButtonContent(text: "OK"), elevated: true, onPressed: KeyCallback(3, 2)),
          TileButton(child: ButtonContent(icon: Icons.arrow_forward), elevated: true, onPressed: KeyCallback(3, 7)),
        ]),
        TileRow(context: context, columns: 3, children: [
          TileButton(child: ButtonContent(icon: Icons.keyboard_arrow_down, text: "Vol"), onPressed: KeyCallback(5, 0)),
          TileButton(child: ButtonContent(icon: Icons.arrow_downward), elevated: true, onPressed: KeyCallback(3, 0)),
          TileButton(child: ButtonContent(icon: Icons.keyboard_arrow_down, text: "Ch"), onPressed: KeyCallback(8, 0)),
        ]),
        TileRow(context: context, columns: 3, children: [
          TileButton(child: ButtonContent(icon: Icons.settings), onPressed: KeyCallback(4, 8)),
          TileButton(child: ButtonContent(icon: Icons.volume_off), onPressed: KeyCallback(5, 2)),
          TileButton(child: ButtonContent(text: "*", increasedSize: true), onPressed: KeyCallback(4, 17)),
        ]),
        TileRow(context: context, columns: 6, children: [
          TileButton(child: ButtonContent(icon: Icons.skip_previous), onPressed: KeyCallback(2, 11)),
          TileButton(child: ButtonContent(icon: Icons.fast_rewind), onPressed: KeyCallback(2, 1)),
          TileButton(child: ButtonContent(icon: Icons.pause), onPressed: KeyCallback(2, 2)),
          TileButton(child: ButtonContent(icon: Icons.play_arrow), onPressed: KeyCallback(2, 3)),
          TileButton(child: ButtonContent(icon: Icons.fast_forward), onPressed: KeyCallback(2, 5)),
          TileButton(child: ButtonContent(icon: Icons.skip_next), onPressed: KeyCallback(2, 10)),
        ]),
        TileRow(context: context, columns: 3, children: [
          TileButton(child: ButtonContent(icon: Icons.numbers), onPressed: () {
            showDialogue(context: context, title: "Send Number", content: TvNumberSelector(command: command));
          }),
          TileButton(child: ButtonContent(icon: Icons.keyboard), onPressed: () {
            showDialogue(context: context, title: "Send Text", content: TvTextSelector(command: command));
          }),
          TileButton(child: ButtonContent(icon: Icons.apps), onPressed: () {
            showDialogue(context: context, title: "Open App", content: TvAppSelector(command: command));
          }),
        ]),
      ]),
    ];

    if (sections != children.length) {
      throw Exception("Unexpected amount of Sections.");
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        actions: [
          if (tvPowerStates[widget.id] != null)
          IconButton(
            icon: Icon(Icons.power_settings_new),
            onPressed: () {
              command(endpoint: "power/off");
            },
            iconSize: 20,
            color: getThemeColor(context),
          ),
          if (refreshingTvStates == false)
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              update();
            },
            iconSize: 20,
            color: getThemeColor(context),
          ),
          if (refreshingTvStates == true)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      ),
      body: screenMode == 0 || tvPowerStates[widget.id] == null ? Center(child: CircularProgressIndicator()) : (tvPowerStates[widget.id] == false && allowTvControlsWhenTvIsOff == false ? Center(child: IconButton(icon: Icon(Icons.power_settings_new), color: getThemeColor(context), onPressed: () {
        command(endpoint: "power/on");
      }, iconSize: 72)) : Row(children: children, mainAxisAlignment: MainAxisAlignment.center)),
    );
  }

  Widget ButtonContent({IconData? icon, String? text, bool increasedSize = false}) {
    return Stack(
      children: [
        if (text != null && icon != null)
        Row(
          children: [
            Text(text, style: TextStyle(fontSize: 20, color: getThemeColor(context))),
            Spacer(),
          ],
        ),
        if (icon != null || text != null)
        Center(child: icon != null ? Icon(icon, size: 32, color: getThemeColor(context)) : Text(text!, style: TextStyle(fontSize: increasedSize ? 48 : 20, color: getThemeColor(context)))),
      ],
    );
  }

  Widget Section({required BuildContext context, required int index, required int rows, required List<Widget> children}) {
    Screen ui = getScreen(context: context);
    double width = ui.width / screenMode;
    if (width > 500) width = 500;
    if (screenMode < index) return SizedBox.shrink();
    Screen screen = Screen(width, ui.height);

    for (Widget widget in children) {
      if (widget is Row) {
        for (Widget tile in widget.children) {
          if (tile is TileButton) {
            tile.rows = rows;
            tile.screen = screen;
          } else {
            throw Exception("Widget was not TileButton in Row, in Section.");
          }
        }
      } else if (widget is TileButton) {
        widget.rows = rows;
        widget.screen = screen;
      } else {
        throw Exception("Widget was not TileButton or Row in Section.");
      }
    }

    return Container(
      width: width,
      height: screen.height,
      padding: EdgeInsets.all(4),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget TileRow({required BuildContext context, required int columns, required List<TileButton> children}) {
    for (TileButton widget in children) {
      widget.columns = columns;
    }
    return Row(
      children: children,
    );
  }
}

Screen getScreen({required BuildContext context}) {
  return Screen(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height);
}

double buttonHeight({required int rows, required double height, required double padding}) {
  double actualHeight = height - ((padding * rows) + padding);
  double buttonHeight = actualHeight / rows;
  return buttonHeight;
}

double buttonWidth({required int columns, required double width, required double padding}) {
  double actualWidth = width - ((padding * columns) + padding);
  double buttonWidth = actualWidth / columns;
  return buttonWidth;
}

class Screen {
  final double width;
  final double height;
  const Screen(this.width, this.height);
}

// ignore: must_be_immutable
class TileButton extends StatefulWidget {
  int? rows;
  int? columns;
  Widget? child;
  VoidCallback? onPressed;
  TileRowPosition rowPosition;
  bool hover;
  bool active;
  bool elevated;
  Screen? screen;

  TileButton({super.key, this.rows, this.columns, this.child, this.onPressed, this.rowPosition = TileRowPosition.none, this.hover = false, this.active = false, this.elevated = false, this.screen});

  @override
  State<TileButton> createState() => _TileButtonState();
}

class _TileButtonState extends State<TileButton> {
  bool hover = false;
  bool canHover = false;

  @override
  Widget build(BuildContext context) {
    if (widget.rows == null) throw Exception("The amount of rows present must be specified in _TileButtonState.");
    if (widget.columns == null) throw Exception("The amount of columns present must be specified in _TileButtonState.");
    if (widget.screen == null) throw Exception("The screen properties must be specified in _TileButtonState.");

    double width = buttonWidth(columns: widget.columns!, width: widget.screen!.width, padding: 8);
    double height = buttonHeight(rows: widget.rows!, height: widget.screen!.height, padding: 8);

    if (widget.onPressed != null || widget.hover) {
      canHover = true;
    }

    if (widget.rowPosition == TileRowPosition.both || widget.rowPosition == TileRowPosition.bothExpanded) {
      width += widget.rowPosition == TileRowPosition.bothExpanded ? 48 : 16;
    }

    if (widget.onPressed != null || widget.hover) {
      canHover = true;
    }

    if (widget.rowPosition == TileRowPosition.both || widget.rowPosition == TileRowPosition.bothExpanded) {
      width += widget.rowPosition == TileRowPosition.bothExpanded ? 48 : 16;
    }

    return Padding(
      padding: const EdgeInsets.all(4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: (hover && canHover) || widget.active ? Colors.grey.withAlpha(widget.elevated ? 220 : 160) : Colors.grey.withAlpha(widget.elevated ? 160 : 100),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: InkWell(onTap: widget.onPressed, child: Center(child: Padding(
            padding: EdgeInsets.all(8.0),
            child: widget.child,
          ))),
        ),
      ),
    );
  }
}

class KeyCode {
  final int set;
  final int code;
  const KeyCode(this.set, this.code);

  Map<String, int> transform() {
    return {
      "set": set,
      "code": code,
    };
  }
}

List<KeyCode> generateAscii(String text) {
  List<KeyCode> output = [];
  for (int code in text.codeUnits) {
    output.add(KeyCode(0, code));
  }
  return output;
}

VoidCallback Key(List<KeyCode> keys, {required Function({required String endpoint, Map? body}) command}) {
  List<Map<String, int>> newkeys = keys.map((KeyCode key) => key.transform()).toList();
  return () {
    command(endpoint: "key", body: {
      "keys": newkeys,
    });
  };
}

class TvTextSelector extends StatefulWidget {
  final Function({required String endpoint, Map? body}) command;
  const TvTextSelector({super.key, required this.command});

  @override
  State<TvTextSelector> createState() => _TvTextSelectorState();
}

class _TvTextSelectorState extends State<TvTextSelector> {
  final TextEditingController controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Text...',
            border: OutlineInputBorder(),
          ),
        ),
        SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.backspace),
              color: getThemeColor(context),
              onPressed: () {
                Key(generateAscii("\b"), command: widget.command)();
              },
            ),
            IconButton(
              icon: Icon(Icons.keyboard_return),
              color: getThemeColor(context),
              onPressed: () {
                Key(generateAscii("\n"), command: widget.command)();
              },
            ),
            IconButton(
              icon: Icon(Icons.send),
              color: getThemeColor(context),
              onPressed: () {
                if (controller.text == "") return;
                Key(generateAscii(controller.text), command: widget.command)();
                controller.text = "";
              },
            ),
          ],
        ),
      ],
    );
  }
}

class TvNumberSelector extends StatefulWidget {
  final Function({required String endpoint, Map? body}) command;
  const TvNumberSelector({super.key, required this.command});

  @override
  State<TvNumberSelector> createState() => _TvNumberSelectorState();
}

class _TvNumberSelectorState extends State<TvNumberSelector> {
  String text = '';
  Screen screen = Screen(0, 0);
  Screen ui = Screen(0, 0);

  @override
  Widget build(BuildContext context) {
    screen = getScreen(context: context);
    ui = Screen(screen.width * 0.65, screen.height * 0.3);

    return Container(
      height: screen.height,
      width: screen.width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(text, style: TextStyle(fontSize: 32)),
          SizedBox(height: 10),
          Section(
            children: [
              Tile(1),
              Tile(2),
              Tile(3),
            ],
          ),
          Section(
            children: [
              Tile(4),
              Tile(5),
              Tile(6),
            ],
          ),
          Section(
            children: [
              Tile(7),
              Tile(8),
              Tile(9),
            ],
          ),
          Section(
            children: [
              Tile("#"),
              Tile(0),
              Tile("-"),
            ],
          ),
          Section(
            children: [
              TileButton(rows: 3, columns: 3, screen: ui, child: Icon(Icons.backspace, color: getThemeColor(context), size: 26), onPressed: () {
                text = text.substring(0, text.length - 1);
                setState(() {});
              }),
              TileButton(rows: 3, columns: 3, screen: ui, child: Icon(Icons.send, color: getThemeColor(context), size: 26), onPressed: () {
                if (text == "") return;
                Key(generateAscii(text), command: widget.command)();
                text = "";
                setState(() {});
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget Tile(dynamic input, {dynamic actual}) {
    return TileButton(rows: 3, columns: 3, screen: ui, child: Text("$input", style: TextStyle(fontSize: 32)), onPressed: () {
      text += "${actual ?? input}";
      setState(() {});
    });
  }

  Widget Section({List<Widget>? children}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: children ?? [],
    );
  }
}

class TvSourceSelector extends StatelessWidget {
  final List sources;
  final String id;
  const TvSourceSelector({super.key, required this.id, required this.sources});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(itemCount: sources.length, itemBuilder: (BuildContext context, int i) {
      Map item = sources[i];
      return ListTile(
        title: Text("${item["name"]}"),
        subtitle: Text("${item["cname"]} - ${item["hash"]}"),
        onTap: () {
          print("activating source for ${item["name"]}");
          tvRequestGlobal(endpoint: "source/input/change", id: id, body: {
            "input": item["cname"],
            "hash": item["hash"],
          });
        },
      );
    });
  }
}

class TvAppSelector extends StatefulWidget {
  final Function({required String endpoint, Map? body}) command;
  const TvAppSelector({super.key, required this.command});

  @override
  State<TvAppSelector> createState() => _TvAppSelectorState();
}

class _TvAppSelectorState extends State<TvAppSelector> {
  TextEditingController controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      height: MediaQuery.of(context).size.height * 0.9,
      child: SingleChildScrollView(
        child: Column(
          children: [
            ...List.generate(viziofavapps.length, (int i) {
              String name = viziofavapps[i];
              Map vizioapp = vizioapps.firstWhere((item) => item["name"] == name);
              String? id = vizioapp["id"][0];
              List countries = getCountries(vizioapp);
            
              return ListTile(
                leading: Icon(Icons.star),
                title: Text(name),
                subtitle: Text("#$id - ${countries.join(", ")}"),
                onTap: () => openApp(name, context: context, command: widget.command),
              );
            }),
            Divider(
              color: Colors.grey,
              thickness: 1,
            ),
            ...List.generate(vizioapps.length, (int i) {
              String name = vizioapps[i]["name"];
              String? id = vizioapps[i]["id"][0];
              List countries = getCountries(vizioapps[i]);
        
              return ListTile(
                title: Text(name),
                subtitle: Text("#$id - ${countries.join(", ")}"),
                onTap: () => openApp(name, context: context, command: widget.command),
              );
            }),
          ],
        ),
      ),
    );
  }
}

void openApp(String name, {required BuildContext context, required Function({required String endpoint, Map? body}) command}) {
  command(endpoint: "apps/launch", body: {
    "name": name,
  });
}

List getCountries(Map item) {
  return (item["country"] as List).map((item) => item == "*" ? "all" : item).map((item) => item == "all" ? "All" : item.toUpperCase()).toList();
}