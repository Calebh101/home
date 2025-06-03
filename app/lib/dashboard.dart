import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:homeapp/announcements.dart';
import 'package:homeapp/calendar.dart';
import 'package:homeapp/fireplace.dart';
import 'package:homeapp/glucose.dart';
import 'package:homeapp/house.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/nowplaying.dart';
import 'package:homeapp/online.dart';
import 'package:homeapp/settings.dart';
import 'package:homeapp/tv.dart';
import 'package:intl/intl.dart';
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/error.dart';
import 'package:localpkg/functions.dart';
import 'package:localpkg/logger.dart';
import 'package:localpkg/theme.dart';
import 'package:localpkg/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

bool debugEveryInitStepWithPrompts = true;
bool nightmodeEnabled = false;
bool nightMode = false;
bool darkMode = false;
bool dashboardActive = false;
double tileWidth = 100;
double tileHeight = 70;
double kioskmultiplier = 1;
Map musicstatus = {"status": 0};
List alerts = [];
double prevvolume = 0;
List rooms = [];
List tvs = [];
List homekitDevices = [];
Map tvPowerStates = {};
Map homekitData = {};
int currentPage = 1;
bool refreshingHomekit = false;
bool refreshingTvStates = false;
List vizioapps = [];
List viziofavapps = [];
Map? weather;
Map? deviceStates;
Map? calendarForTheNextWeek;
List? calendarEventsTotal;
String? currentCalendarList;
List? calendarLists;
bool refreshingCalendar = false;

Map tabs = {
  "Home": {
    "icon": Icons.home,
  },
  "Devices": {
    "icon": Icons.tv,
  },
  "Calendar": {
    "icon": Icons.calendar_month,
  },
  if (useAutomation)
  "Automation": {
    "icon": Icons.av_timer,
  },
};

Future<void> updateHomekit() async {
  refreshingHomekit = true;
  for (String device in homekitDevices) {
    print("finding homekit data for $device...");
    Map? response = await request(endpoint: "devices/homekit/$device");
    print("got homekit data for $device: ${response.runtimeType}");
    homekitData[device] = response;
    print("set homekit data for $device");
    if (device == homekitDevices.last) {
      refreshingHomekit = false;
    }
  }
}

Future<void> updateWeather() async {
  weather = null;
  weather = await request(endpoint: "weather", silentLogging: true);
  print("weather: ${weather.runtimeType}");
}

int getSections(double width) {
  return width >= 800 ? 2 : 1;
}

class Dashboard extends StatefulWidget {
  final bool kiosk;
  final bool debug;
  const Dashboard({super.key, required this.kiosk, required this.debug});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with TickerProviderStateMixin {
  TabController? tabController;
  TextEditingController announcementController = TextEditingController();
  ScrollController scrollController = ScrollController();
  bool? ready = false;
  Map? dexcomData;
  List contacts = [];
  List birthdays = [];
  double? volume;
  double? brightness;
  double minbrightness = 0;
  double maxbrightness = 0;
  double minvolume = 0;
  double maxvolume = 0;
  bool screenstate = false;
  StreamController currentDexcomController = StreamController<List>();
  Timer? dexcomTimer;
  Map? currentState;
  int currentremotefireplace = 0;
  List? remotefireplaces;
  StreamSubscription? stateStream;
  StreamSubscription? commandStream;
  StreamSubscription? updateStream;
  bool remotenightmode = false;
  int activeSlider = 0;

  @override
  void initState() {
    if (widget.kiosk) {
      tileWidth = tileWidth * kioskmultiplier;
      tileHeight = tileHeight * kioskmultiplier;
    }

    tabController = TabController(length: tabs.length, vsync: this);
    dashboardActive = true;
    activeFireplace = 0;
    super.initState();
    init();
    WakelockPlus.enable();

    updateStream = updateController.stream.listen((data) async {
      if (data["status"] == true) {
        print("update available");
        if (kIsWeb) {
          web.reload();
        } else {
          showDialogue(context: context, title: "A new update is available!", content: Text("A new update is available!\n\nCurrent version: $version\nNew version: ${data["version"]}"));
        }
      }
    });

    commandStream = commandController.stream.listen((data) {
      if (data.contains("refresh")) {
        init();
      } else if (data.contains("shutdown")) {
        int time = int.parse(data.split("shutdown")[1].trim());
        int tries = 0;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return PopScope(
              child: AlertDialog(
                title: Text("System Shutdown"),
                content: ShutdownText(seconds: time),
                actions: [
                  TextButton(
                    onPressed: () async {
                      print("cancelling shutdown...");
                      ProcessResult result = await Process.run('pkill', ['sleep']);
                      print("shutdown cancel result: ${result.exitCode}");
                      tries++;

                      if (result.exitCode == 0) {
                        showSnackBar(context, "System shutdown cancelled.");
                        Navigator.of(context).pop();
                      } else {
                        showSnackBar(context, "The system was unable to cancel shutdown.");
                        if (tries >= 3) {
                          Navigator.of(context).pop();
                        }
                      }
                    },
                    child: Text("Cancel"),
                  ),
                ],
              ),
            );
          },
        );
      } else if (data.contains("alert_message")) {
        String message = data.split("alert_message")[1].trim();
        print("received message: $message");
        showDialogue(context: context, title: "Alert Message", content: Text(message));
      } else if (data.contains("fireplace_on") && dashboardActive) {
        int type = int.tryParse(data.split("fireplace_on")[1].trim()) ?? 1;
        activateFireplace(context: context, kiosk: widget.kiosk, debug: widget.debug, type: type);
        dispose();
      } else if (data.contains("music_status")) {
        Map status = jsonDecode(data.split("music_status")[1].trim());
        musicstatus = status;
        refresh();
      } else if (data.contains("glucose_on")) {
        if (glucoseActive == false) {
          print("glucose called");
          navigate(context: context, page: GlucoseMonitor(debug: widget.debug, kiosk: widget.kiosk), mode: 2);
        }
      } else if (data.contains("nightmode_on")) {
        changeNightmode(true);
      } else if (data.contains("nightmode_off")) {
        changeNightmode(false);
      }
    });
  }

  @override
  void dispose() {
    disposer();
    super.dispose();
  }

  void disposer() {
    dashboardActive = false;
    stateStream?.cancel();
    commandStream?.cancel();
    updateStream?.cancel();
    currentDexcomController.close();
  }

  bool isSameDate(DateTime date) {
    DateTime now = DateTime.now();
    bool status = date.month == now.month && date.day == now.day;
    return status;
  }

  Future<bool> checkStatus() async {
    print("status: starting...");
    Map? status = await request(endpoint: 'system/status', context: context, action: "fetch status", showError: false);

    if (status != null) {
      print("status: server: good");
      if (status["app"] == true) {
        print("status: app: good");
      } else {
        warn("status: app: bad");
        showDialogue(context: context, title: "Unexpected Error", content: Text("The server is experiencing issues. Please report this incident. You may encounter unexpected issues or unresponsiveness.\n\nType: app status is bad\nCode: BAD_APP_STATUS"), copy: true, copyText: "BAD_APP_STATUS");
      }
    } else {
      warn("status: server: bad");
      showDialogue(context: context, title: "Unexpected Error", content: Text("The server is experiencing issues. Please report this incident.\n\nType: server status is unavailable\nCode: BAD_SERVER_STATUS_UNAVAILABLE"), copy: true, copyText: "BAD_SERVER_STATUS_UNAVAILABLE");
      return false;
    }

    print("status: continuing...");
    return true;
  }

  Future<void> initPrompt([String text = "Debugger pause called."]) async {
    if (debugEveryInitStepWithPrompts == false) return;
    await showDialogue(context: context, title: "Init Prompt (debugEveryInitStepWithPrompts)", content: Text(text));
  }

  Future<void> init() async {
    print("initializing...");
    initPrompt("Initializing...");
    ready = false;
    refresh(mini: true);

    if (!(await checkStatus())) {
      ready = null;
      refresh();
      return;
    }

    initPrompt("Setting variables...");
    remotefireplaces = (await request(endpoint: "fireplace/get/available", context: context))!["fireplaces"];
    tvs = (await request(endpoint: "devices/tvs"))!["devices"];
    rooms = (await request(endpoint: "devices/house"))!["rooms"];
    homekitDevices = (await request(endpoint: "devices/homekit"))!["devices"];
    vizioapps = (await request(endpoint: "devices/tvs/vizio/apps/get"))!["apps"];
    viziofavapps = (await request(endpoint: "devices/tvs/vizio/apps/favorites"))!["apps"];
    calendarLists = (await request(endpoint: "calendar/lists"))!["lists"];

    Map? limits = await request(endpoint: 'system/limits', context: context);
    await stateController.stream.first;

    tvPowerStates = {};
    vizioapps.sort((a, b) => a["name"].compareTo(b["name"]));

    initPrompt("Updating things...");
    updateTvStates();
    updateHomekit();
    updateWeather();
    updateDeviceStates();
    updateCalendar();
    checkForUpdates();

    if (limits == null) {
      warn("limits is null");
    } else {
      minbrightness = limits["brightness"]["min"].toDouble();
      maxbrightness = limits["brightness"]["max"].toDouble();
      minvolume = limits["volume"]["min"].toDouble();
      maxvolume = limits["volume"]["max"].toDouble();
      prevvolume = limits["volume"]["max"].toDouble();
    }

    try {
      print("initializing state stream...");
      initPrompt("Initializing state stream...");

      stateStream = stateController.stream.listen((data) {
        currentState = data["state"];
        currentremotefireplace = data["state"]["app"]?["fireplace"]?["active"] ?? 0;
        remotenightmode = data["state"]["app"]?["theme"]?["nightmode"];
        screenstate = data["state"]["screen"] == 1;
        musicstatus = data["music"]["status"];
        darkMode = data["state"]["app"]?["theme"]["current"] == 1;

        if (activeSlider == 0 || volume == null || brightness == null) {
          volume = data["state"]["volume"].toDouble();
          brightness = data["state"]["brightness"].toDouble();
        }

        if (!widget.kiosk && !globalDebug) {
          alerts = data["state"]["app"]["alerts"];
        }

        if (brightness! < minbrightness) brightness = minbrightness;
        if (brightness! > maxbrightness) brightness = maxbrightness;
        if (volume! < minvolume) volume = minvolume;
        if (volume! > maxvolume) volume = maxvolume;

        List contactsRequested = data["state"]["contacts"];
        birthdays = [];

        contacts = contactsRequested.isEmpty ? [] : contactsRequested.map((item) {
          if (item["birthday"] is! DateTime) item["birthday"] = DateTime.parse(item["birthday"]);
          return item;
        }).toList();

        for (var item in contacts) {
          if (isSameDate(item["birthday"])) {
            birthdays.add(item);
          }
        }

        refresh(mini: true);
      });

      print("state stream initialized");
      initPrompt("State stream initialized");
    } catch (e) {
      warn("state stream error: $e");
      initPrompt("State stream error: $e");
    }

    print("initialization finished");
    ready = true;
    showSectionDialogue(context: context, id: "main");
    refresh();
  }

  void refresh({bool mini = false}) {
    if (!mounted) return;
    if (mini) return setState(() {});

    print('refreshing... (mini: $mini)');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    bool lightMode = getBrightness(context: context) == Brightness.light;
    Color? selectedColor = getSeed(context);
    double size = 1 * (widget.kiosk ? kioskmultiplier : 1);
    if (verbose) print("building dashboard... (brightness: $brightness) (size: $size)");

    PreferredSizeWidget tabBar = TabBar(
      controller: tabController,
      onTap: (int i) {
        print("detected tab: $i");
        if (currentPage == i + 1) {
          if (currentPage == 2) {
            scrollController.animateTo(
              getSections(MediaQuery.of(context).size.width) >= 2 ? 823 : 945,
              duration: Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          } else if (currentPage == 3) {
            jumpToCurrentMonth();
          }
        } else {
          currentPage = i + 1;
          if (currentPage == 2) showSectionDialogue(context: context, id: "devices");
          refresh();
        }
      },
      indicatorColor: selectedColor,
      tabs: List.generate(tabs.length, (int i) {
        String name = tabs.keys.toList()[i];
        return Tab(child: useIconsForTabs ? Icon(tabs[name]["icon"], color: currentPage == i + 1 ? selectedColor : getThemeColor(context), size: 28) : Text(name), height: 36);
      }),
      isScrollable: false,
    );

    if (globalKiosk && noDashboardUiInKioskMode) {
      double getSize([int factor = 1]) {
        Size screen = MediaQuery.of(context).size;
        double size = screen.width;
        if (screen.width > screen.height) size = screen.height;
        return (size / 20) * factor;
      }

      return Scaffold(
        body: Stack(
          children: [
            Positioned(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: IconButton(
                  icon: Icon(Icons.settings, color: getThemeColor(context)),
                  onPressed: () {
                    print("settings");
                    navigate(context: context, page: Settings(kiosk: widget.kiosk, debug: widget.debug));
                  },
                  iconSize: 28,
                ),
              ),
              left: 0,
              top: 0,
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('h:mm a').format(DateTime.now()), style: TextStyle(fontSize: getSize(4))).gradient(colors: [GradientColor(darkMode ? Colors.white : Colors.black), GradientColor(darkMode ? Colors.grey : const Color.fromARGB(255, 21, 21, 21))]),
                  Text(DateFormat('MMMM d, y').format(DateTime.now()), style: TextStyle(fontSize: getSize(2))),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (!nightMode && ready != null) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Stack(
            children: [
              AnimatedOpacity(
                opacity: currentPage == 1 || currentPage == 3 ? 0 : 1,
                duration: Duration(milliseconds: 170),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.home_rounded, size: 35, color: getThemeColor(context)),
                    SizedBox(width: 6),
                    Text("Home", style: TextStyle(fontSize: 33)),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: currentPage != 3 ? 0 : 1,
                duration: Duration(milliseconds: 170),
                child: calendarLists == null ? CircularProgressIndicator() : IgnorePointer(
                  ignoring: currentPage != 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownButton<String?>(
                        value: currentCalendarList,
                        icon: Icon(Icons.arrow_drop_down),
                        onChanged: (newValue) {
                          currentCalendarList = newValue;
                          setState(() {});
                        },
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text("None"),
                          ),
                          ...calendarLists!.map((value) {
                            return DropdownMenuItem(
                              value: value,
                              child: Text(value ?? "None"),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottom: tabBar,
          leading: IconButton(
            icon: Icon(Icons.settings, color: getThemeColor(context)),
            onPressed: () {
              print("settings");
              navigate(context: context, page: Settings(kiosk: widget.kiosk, debug: widget.debug));
            },
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh, color: getThemeColor(context)),
              onPressed: () {
                print("refresh");
                init();
              },
            ),
          ],
        ),
        body: ready == true ? TabBarView(
          controller: tabController,
          children: [
            DashboardSection(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.home_rounded, size: 56, color: getThemeColor(context)),
                    SizedBox(width: 6),
                    Text("Welcome Home", style: TextStyle(fontSize: 48)),
                  ],
                ),
                ...List.generate(alerts.length, (int index) {
                  Map item = alerts[index];
                  int severity = item["severity"];
                  String severityString = getSeverityFromInt(severity);
                  DateTime date = DateTime.parse(item["date"]);
                    
                  if (item["show"] != true) {
                    return null;
                  }
                    
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      padding: EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: getColorFromSeverity(severity),
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                              icon: Icon(Icons.close),
                              onPressed: () {
                                request(endpoint: 'alert/dismiss', context: context, action: "dismiss alert", body: {"id": item["id"]});
                              },
                              color: getThemeColor(context),
                            ),
                          ),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("$severityString Severity Warning", style: TextStyle(fontSize: 24)),
                                Text(item["message"]),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(DateFormat('M/d').format(date)),
                                    SizedBox(width: 6),
                                    Text(DateFormat('h:mm a').format(date)),
                                  ],
                                ),
                                SelectableText(item["id"]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).where((e) => e != null).cast<Widget>(),
                TileArea(
                  children: [
                    if (widget.kiosk || alwaysShowTime)
                    TileRow(
                      takeUpEntireRow: true,
                      children: [
                        TileBox(
                          width: 3,
                          height: 2,
                          rowPosition: TileRowPosition.both,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(DateFormat('h:mm a').format(DateTime.now()), style: TextStyle(fontSize: 48)),
                              Text(DateFormat('MMMM d, y').format(DateTime.now()), style: TextStyle(fontSize: 20)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (announcements?.isNotEmpty ?? false)
                    TileRow(
                      takeUpEntireRow: true,
                      children: [
                        TileBox(
                          rowPosition: TileRowPosition.both,
                          height: 2.9,
                          width: 3,
                          child: Column(
                            children: [
                              Text("Announcements"),
                              Expanded(child: AnnouncementsBuilder(mini: true)),
                            ],
                          ),
                          onPressed: () {
                            navigate(context: context, page: AnnouncementsPage());
                          },
                        ),
                      ],
                    ),
                    if (showCalendarForTheNextWeekRenderer && (calendarForTheNextWeek?["events"] ?? [""]).isNotEmpty)
                    TileRow(
                      children: [
                        TileBox(
                          width: 3,
                          height: calendarForTheNextWeek == null ? 1 : ((calendarForTheNextWeek!["events"].length > 3 ? 3 : calendarForTheNextWeek!["events"].length) * 1.1) + 0.5,
                          rowPosition: TileRowPosition.both,
                          child: Column(
                            children: [
                              Text("Up Next"),
                              SizedBox(height: 6),
                              Expanded(child: Center(child: CalendarForTheNextWeekRenderer(type: CalendarRenderType.forTheNextWeek)))
                            ],
                          ),
                          onPressed: () {
                            tabController?.animateTo(2);
                            refresh();
                          },
                        ),
                      ],
                    ),
                    TileRow(
                      children: [
                        TileBox(
                          width: 3,
                          height: showRefreshOnWeatherWidget ? 2.5 : 1.75,
                          rowPosition: TileRowPosition.both,
                          child: Builder(
                            builder: (context) {
                              return Column(
                                mainAxisAlignment: showRefreshOnWeatherWidget ? MainAxisAlignment.start : MainAxisAlignment.center,
                                children: [
                                  if (showRefreshOnWeatherWidget)
                                  Row(
                                    children: [
                                      SizedBox(width: 44),
                                      Spacer(),
                                      Spacer(),
                                      IconButton(
                                        icon: Icon(Icons.refresh),
                                        onPressed: () {
                                          updateWeather();
                                          refresh(mini: true);
                                        },
                                        iconSize: 20,
                                        color: getThemeColor(context),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Builder(
                                          builder: (context) {
                                            if (weather == null) return Center(child: CircularProgressIndicator());
                                            Map location = weather!["data"]["location"];
                                            Map current = weather!["data"]["current"];
                                            DateTime lastUpdated = DateTime.fromMillisecondsSinceEpoch(current["last_updated_epoch"] * 1000, isUtc: true).toLocal();
                                        
                                            return Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Image.network("https:${current["condition"]["icon"]}", scale: 0.75),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text("${current["temp_f"]}°F", style: TextStyle(fontSize: 20)),
                                                    Text("Feels like ${current["feelslike_f"]}°F"),
                                                    Text("Wind: ${current["wind_mph"]} MPH ${current["wind_dir"]}"),
                                                    Text("${location["name"]}, ${location["region"]}"),
                                                    Text("Last Updated: ${DateFormat("M/dd/yyyy h:mm a").format(lastUpdated)}"),
                                                  ],
                                                ),
                                              ],
                                            );
                                          }
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }
                          ),
                        ),
                      ],
                    ),
                    TileRow(
                      children: [
                        TileBox(width: 3, height: 3.5, rowPosition: TileRowPosition.both, child: refreshingHomekit ? Center(child: CircularProgressIndicator()) : Column(
                          children: [
                            Builder(
                              builder: (context) {
                                Map? data = homekitData["ecobee3"];
                                String? name = data?["data"]["1.2"]["value"];

                                if (data == null) {
                                  return Center(child: CircularProgressIndicator());
                                }

                                return Row(
                                  children: [
                                    SizedBox(width: 32),
                                    Spacer(),
                                    Text(name!, style: TextStyle(fontSize: 20)),
                                    Spacer(),
                                    if (refreshingHomekit == false)
                                    IconButton(
                                      icon: Icon(Icons.refresh),
                                      onPressed: () async {
                                        await updateHomekit();
                                        refresh(mini: true);
                                      },
                                      iconSize: 20,
                                      color: getThemeColor(context),
                                    ),
                                    if (refreshingHomekit == true)
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                  ],
                                );
                              }
                            ),
                            Builder(
                              builder: (BuildContext context) {
                                Map data = homekitData["ecobee3"];
                                DateTime lastUpdated = DateTime.parse(data["lastUpdated"]).toLocal();

                                int heatingcoolingcurrent = data["data"]["1.17"]["value"];
                                int heatingcoolingtarget = data["data"]["1.18"]["value"];
                                num tempcurrent = getTemp(data["data"]["1.19"]["value"]);
                                num temptarget = getTemp(data["data"]["1.20"]["value"], roundMode: RoundMode.oneth);
                                num humidity = data["data"]["1.24"]["value"];
                                num fancurrent = data["data"]["1.76"]["value"];
                                num fantarget = data["data"]["1.75"]["value"];
                                                        
                                return Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text("$tempcurrent°F", style: TextStyle(fontSize: 48)).gradient(colors: getGradientForTemp(tempcurrent)),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: "Target: ",
                                              style: TextStyle(fontSize: 20),
                                            ),
                                            TextSpan(
                                              text: "$temptarget°F",
                                              style: TextStyle(fontSize: 20, color: getColorForOffset(tempcurrent, temptarget)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: "Mode: ",
                                              style: TextStyle(fontSize: 20),
                                            ),
                                            TextSpan(
                                              text: getModeForHeatCool(heatingcoolingtarget), style: TextStyle(fontSize: 20, color: getColorForHeatCool(heatingcoolingtarget)),
                                            ),
                                            TextSpan(
                                              text: " (Currently ",
                                              style: TextStyle(fontSize: 20),
                                            ),
                                            TextSpan(
                                              text: getModeForHeatCool(heatingcoolingcurrent), style: TextStyle(fontSize: 20, color: getColorForHeatCool(heatingcoolingcurrent)),
                                            ),
                                            TextSpan(
                                              text: ")",
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text("Fan: ${fantarget == 1 ? "Auto" : "On"} (Currently ${fancurrent == 1 ? "Off" : "On"})", style: TextStyle(fontSize: 16)),
                                      Text("Humidity: $humidity%", style: TextStyle(fontSize: 16)),
                                      Text("Last updated: ${DateFormat('M/d/yyyy h:mm a').format(lastUpdated)}", style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        )),
                      ],
                    ),
                    if (widget.kiosk == false)
                    TileRow(
                      children: [
                        TileBox(width: 2, rowPosition: TileRowPosition.none, child: TextField(
                          controller: announcementController,
                          decoration: InputDecoration(
                            labelText: "Message...",
                            border: OutlineInputBorder(),
                          ),
                        )),
                        TileBox(child: Icon(Icons.send, color: getThemeColor(context)), rowPosition: TileRowPosition.none, onPressed: () async {
                          final message = announcementController.text;
                          final body = {'message': message};
                
                          if (message == '') {
                            print("empty message");
                            return;
                          }
                
                          print("sending message: $message");
                          request(endpoint: "announce", body: body, context: context, action: "send message");
                        }),
                      ],
                    ),
                    TileRow(
                      children: [
                        TileBox(
                          rowPosition: TileRowPosition.both,
                          height: (birthdays.length / 1.15) + 1,
                          width: 3,
                          child: Column(
                            children: [
                              Text("Birthdays", style: TextStyle(fontSize: 20)),
                              birthdays.isEmpty ? Center(child: Text("No birthdays today.")) : Expanded(
                                child: ListView.builder(
                                  itemCount: birthdays.length,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemBuilder: (BuildContext context, int index) {
                                    Map item = birthdays[index];
                    
                                    return ListTile(
                                      title: Text("${item["name"]["first"]} ${item["name"]["last"]}"),
                                      subtitle: Text("Birthday: ${DateFormat('MM/dd/yyyy').format(item["birthday"])}"),
                                      leading: Icon(Icons.cake),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    TileRow(
                      children: [
                        TileBox(
                          width: 3,
                          height: 1.5,
                          rowPosition: TileRowPosition.both,
                          child: Builder(
                            builder: (context) {
                              if (musicstatus["status"] == null) return CircularProgressIndicator();
                              int statusnumber = musicstatus["status"];
                              bool notplaying = statusnumber == 0;
                              return Column(
                                children: [
                                  Text("Music", style: TextStyle(fontSize: 20)),
                                  Expanded(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: !notplaying && (statusnumber == 1 || statusnumber == 2) ? [
                                        Container(width: 250 * size, child: Text("${musicstatus["artist"]}: ${musicstatus["title"]}", maxLines: 1, softWrap: false, overflow: TextOverflow.fade, textAlign: TextAlign.center)),
                                      ] : [
                                        Center(child: Text("Not Playing")),
                                      ],
                                    ),
                                  ),
                                  if (!notplaying && (statusnumber == 1 || statusnumber == 2))
                                  Row(
                                    children: [
                                      IconButton(onPressed: () {
                                        request(endpoint: "music/${statusnumber == 1 ? "pause" : "play"}", context: context, action: "control music", host: forceNativeSpotify ? Host.debug : null);
                                      }, icon: Icon(statusnumber == 1 ? Icons.pause : Icons.play_arrow_rounded), color: getThemeColor(context)),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Text(musicstatus["position"]["formatted"]),
                                            SizedBox(width: 10),
                                            Expanded(child: LinearProgressIndicator(value: (musicstatus["length"]["raw"] - musicstatus["remaining"]["raw"]) / musicstatus["length"]["raw"])),
                                            SizedBox(width: 10),
                                            Text(musicstatus["length"]["formatted"]),
                                            SizedBox(width: 10),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }
                          ),
                          onPressed: musicstatus["status"] == 0 ? () {
                            showDialogue(context: context, title: "Not Playing", content: Text("Nothing is playing right now."));
                          } : () {
                            navigate(context: context, page: NowPlayingPage(kiosk: widget.kiosk));
                          },
                        ),
                      ],
                    ),
                    TileRow(children: [
                      TileBox(width: 3, height: 2, onPressed: () {
                        print("glucose navigated");
                        navigate(context: context, page: GlucoseMonitor(debug: widget.debug, kiosk: widget.kiosk), mode: 2);
                      }, child: dexcomCrash ? Center(child: Icon(Icons.warning_amber_rounded, color: getThemeColor(context), size: 64)) : Stack(
                        children: [
                          Column(
                            children: [
                              Text("Dexcom Readings", style: TextStyle(fontSize: 20)),
                              Expanded(
                                child: StreamBuilder(
                                  stream: dexcomController.stream,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting || (globalGlucoseLimits == null && showUncoloredGlucose == false)) {
                                      return Container(width: 64, height: 64, child: Center(child: const CircularProgressIndicator()));
                                    } else if (snapshot.hasError) {
                                      error("snapshot error: ${snapshot.error}");
                                      return Center(child: Text('No Data', style: TextStyle(color: Colors.red, fontSize: 48)));
                                    } else if (snapshot.hasData) {
                                      List data = snapshot.data as List;
                                      if (data.isEmpty) {
                                        return Center(child: Text('No Data', style: TextStyle(color: Colors.red, fontSize: 48)));
                                      }
                
                                      return Center(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '${data[0]["Value"]}',
                                              style: TextStyle(fontSize: 48 * size, color: getColorForValue(data[0]["Value"])),
                                            ),
                                            generateArrow(data[0]["Trend"], context: context),
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                data.length >= 2 ? Row(
                                                  children: [
                                                    Text(
                                                      "${data[1]["Value"]}",
                                                      style: TextStyle(fontSize: 20 * size, color: getColorForValue(data[1]["Value"])),
                                                    ),
                                                    generateArrow(data[1]["Trend"], size: 0.6, context: context),
                                                  ],
                                                ) : Text("No Data", style: TextStyle(fontSize: 20 * size, color: Colors.red)),
                                                if (dexcomTime != null)
                                                Text("-${(dexcomTime ?? 0) ~/ 60}:${((dexcomTime ?? 0) % 60).toString().padLeft(2, '0')}", style: TextStyle(
                                                  color: getColorForTime(dexcomTime ?? 0),
                                                  fontSize: 20 * size,
                                                )),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    } else {
                                      return Center(child: const CircularProgressIndicator());
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          StreamBuilder(
                            stream: dexcomRefresherController.stream,
                            builder: (context, snapshot) {
                              return dexcomRefresh == false && snapshot.connectionState != ConnectionState.waiting && snapshot.hasData ? SizedBox.shrink() : CircularProgressIndicator();
                            }
                          ),
                        ],
                      ), rowPosition: TileRowPosition.both),
                    ]),
                  ],
                ),
              ],
            ),
            DashboardSection(
              children: [
                TileArea(
                  children: [
                    ...List.generate(tvs.length, (int index) {
                      Map tv = tvs[index];
                      return TileRow(
                        children: [
                          TileBox(rowPosition: TileRowPosition.both, width: 3, height: 1.5, onPressed: () {
                            navigate(context: context, page: TVController(id: tv["id"], name: tv["name"]));
                          }, child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(tv["name"], style: TextStyle(fontSize: 24)),
                                    Text("${tv["id"]} - ${tvPowerStates[tv["id"]] == true ? "On" : (tvPowerStates[tv["id"]] == false ? "Off" : "Loading...")}"),
                                    Text("${tv["ip"]}:${tv["port"]}"),
                                  ],
                                ),
                              ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(icon: Icon(Icons.power_settings_new, color: getThemeColor(context)), onPressed: () {
                                    if (tvPowerStates[tv["id"]] == null) return;
                                    tvRequestGlobal(endpoint: "power/${tvPowerStates[tv["id"]] == true ? "off" : "on"}", id: tv["id"]);
                                  }),
                                ],
                              ),
                              SizedBox(width: 16),
                            ],
                          )),
                        ],
                      );
                    }),
                    TileRow(
                      takeUpEntireRow: true,
                      children: [
                        TileBox(
                          onPressed: () async {
                            await showDialogue(context: context, title: "Thermostat Settings", content: ThermostatSettings(id: "ecobee3", data: homekitData["ecobee3"]));
                            updateHomekit();
                            refresh(mini: true);
                          },
                          width: 3,
                          height: 4.5,
                          child: homekitData["ecobee3"] == null ? Center(child: CircularProgressIndicator()) : Builder(
                            builder: (context) {
                              num getTemp(num value, {RoundMode roundMode = RoundMode.tenth}) { // set to fahrenheit and round to nearest 10th
                                num value2 = ((value * 9/5) + 32);
                                if (roundMode == RoundMode.tenth) {
                                  return (value2 * 10).round() / 10;
                                } else if (roundMode == RoundMode.oneth) {
                                  return value2.round();
                                } else {
                                  throw Exception("Invalid roundMode: $roundMode");
                                }
                              }

                              Map data = homekitData["ecobee3"];
                              DateTime lastUpdated = DateTime.parse(data["lastUpdated"]).toLocal();

                              String manufacturer = data["data"]["1.3"]["value"];
                              String model = data["data"]["1.5"]["value"];
                              String name = data["data"]["1.2"]["value"];
                              String serial = data["data"]["1.4"]["value"];
                              String firmware = data["data"]["1.8"]["value"];
                              String version = data["data"]["1.31"]["value"];
                              int heatingcoolingcurrent = data["data"]["1.17"]["value"];
                              int heatingcoolingtarget = data["data"]["1.18"]["value"];
                              num tempcurrent = getTemp(data["data"]["1.19"]["value"]);
                              num temptarget = getTemp(data["data"]["1.20"]["value"], roundMode: RoundMode.oneth);
                              //num coolingthreshold = getTemp(data["data"]["1.22"]["value"]);
                              //num heatingthreshold = getTemp(data["data"]["1.23"]["value"]);
                              num humidity = data["data"]["1.24"]["value"];
                              num fancurrent = data["data"]["1.76"]["value"];
                              num fantarget = data["data"]["1.75"]["value"];

                              Widget Section({required List<Widget> children}) {
                                return Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: children,
                                  ),
                                );
                              }

                              return Row(
                                children: [
                                  Section(
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(width: 32),
                                          Spacer(),
                                          Text(name, style: TextStyle(fontSize: 24)),
                                          Spacer(),
                                          if (refreshingHomekit == false)
                                          IconButton(
                                            icon: Icon(Icons.refresh),
                                            onPressed: () async {
                                              await updateHomekit();
                                              refresh(mini: true);
                                            },
                                            iconSize: 20,
                                            color: getThemeColor(context),
                                          ),
                                          if (refreshingHomekit == true)
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
                                      Expanded(child: Center(child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text("$tempcurrent°F", style: TextStyle(fontSize: 48)).gradient(colors: getGradientForTemp(tempcurrent)),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: "Target: ",
                                                  style: TextStyle(fontSize: 20),
                                                ),
                                                TextSpan(
                                                  text: "$temptarget°F",
                                                  style: TextStyle(fontSize: 20, color: getColorForOffset(tempcurrent, temptarget)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: "Mode: ",
                                                  style: TextStyle(fontSize: 20),
                                                ),
                                                TextSpan(
                                                  text: getModeForHeatCool(heatingcoolingtarget), style: TextStyle(fontSize: 20, color: getColorForHeatCool(heatingcoolingtarget)),
                                                ),
                                                TextSpan(
                                                  text: " (Currently ",
                                                  style: TextStyle(fontSize: 20),
                                                ),
                                                TextSpan(
                                                  text: getModeForHeatCool(heatingcoolingcurrent), style: TextStyle(fontSize: 20, color: getColorForHeatCool(heatingcoolingcurrent)),
                                                ),
                                                TextSpan(
                                                  text: ")",
                                                  style: TextStyle(fontSize: 20),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text("Fan: ${fantarget == 1 ? "Auto" : "On"} (Currently ${fancurrent == 1 ? "Off" : "On"})", style: TextStyle(fontSize: 16)),
                                          Text("Humidity: $humidity%", style: TextStyle(fontSize: 16)),
                                        ],
                                      ))),
                                      Text("$manufacturer $model"),
                                      Text("$version - $firmware"),
                                      Text("Serial: $serial"),
                                      Text("Last Updated: ${DateFormat('M/d/yyyy h:mm a').format(lastUpdated)}")
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    TileRow(
                      takeUpEntireRow: true,
                      children: [
                        TileBox(
                          height: hostHasScreen ? 5 : 1.6,
                          width: 3,
                          rowPosition: TileRowPosition.both,
                          child: Center(
                            child: Column(
                              children: [
                                Text("Host", style: TextStyle(fontSize: 24)),
                                volume == null || brightness == null ? Center(child: CircularProgressIndicator()) : Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(icon: Icon(volume == 0 ? Icons.volume_off : ((volume ?? 0) < (maxvolume / 2) ? Icons.volume_down : Icons.volume_up), color: getThemeColor(context)), onPressed: () async {
                                            if (activeSlider > 0) return;
                                            if (volume != 0 && volume != null) prevvolume = volume!;
                                            await request(endpoint: "volume/set", body: {"volume": (volume == 0 ? prevvolume : 0)}, context: context, action: "set volume", host: Host.release);
                                          }),
                                          if (hostHasScreen)
                                          Column(
                                            children: [
                                              SizedBox(height: 9),
                                              Icon(Icons.wb_sunny, color: getThemeColor(context)),
                                              SizedBox(height: 10),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Slider(
                                            value: volume!,
                                            min: minvolume,
                                            max: maxvolume,
                                            divisions: (maxvolume - minvolume) ~/ 5 + 1,
                                            label: volume!.toStringAsFixed(0),
                                            onChanged: (double value) {
                                              volume = value;
                                              refresh(mini: true);
                                            },
                                            onChangeEnd: (double value) async {
                                              prevvolume = value;
                                              await request(endpoint: "volume/set", body: {"volume": volume!.round()}, context: context, action: "set volume", host: Host.release);
                                              activeSlider--;
                                            },
                                            onChangeStart: (double value) {
                                              activeSlider++;
                                            },
                                          ),
                                          if (hostHasScreen)
                                          Slider(
                                            value: brightness!,
                                            min: minbrightness,
                                            max: maxbrightness,
                                            divisions: (maxbrightness - minbrightness) ~/ 5 + 1,
                                            label: brightness!.toStringAsFixed(0),
                                            onChanged: (double value) {
                                              brightness = value;
                                              refresh(mini: true);
                                            },
                                            onChangeEnd: (double value) async {
                                              await request(endpoint: "brightness/set", body: {"brightness": brightness!.round()}, context: context, action: "set brightness", host: Host.release);
                                              activeSlider--;
                                            },
                                            onChangeStart: (double value) {
                                              activeSlider++;
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (hostHasScreen)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: TileBox(
                                        width: 1.5,
                                        child: Padding(
                                          padding: const EdgeInsets.all(6.0),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text("Fireplace", style: TextStyle(fontSize: 16)),
                                              if (!widget.kiosk)
                                              Text("Current: ${currentremotefireplace > 0 ? ((remotefireplaces?.firstWhere((obj) => obj['id'] == currentremotefireplace, orElse: () => {}))["name"] ?? "None") : "None"}", style: TextStyle(fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                        onPressed: () async {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (context) => FireplaceSelector(fireplaces: remotefireplaces!)),
                                          );
                                          disposer();
                                          init();
                                        },
                                      ),
                                    ),
                                    if (widget.kiosk == false)
                                    Padding(
                                      padding: const EdgeInsets.all(6.0),
                                      child: TileBox(
                                        width: 0.75,
                                        child: Text("Off", style: TextStyle(fontSize: 16)),
                                        onPressed: currentremotefireplace > 0 ? () {
                                          request(endpoint: "fireplace/off", context: context);
                                        } : null,
                                      ),
                                    ),
                                  ],
                                ),
                                if (hostHasScreen)
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: TileBox(
                                    width: 2.38,
                                    child: Text("Turn Screen ${screenstate ? "Off" : "On"}"),
                                    onPressed: () {
                                      request(endpoint: "screen/${screenstate ? "off" : "on"}", context: context, action: "turn screen ${screenstate ? "off" : "on"}", host: Host.release);
                                      screenstate = !screenstate;
                                      refresh(mini: true);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    ...generateRooms(context),
                  ],
                ),
              ],
            ),
            DashboardSection(children: refreshingCalendar ? [
              Center(child: CircularProgressIndicator()),
            ] : [
              CalendarPage(),
            ], scrollbar: false),
            if (useAutomation)
            DashboardSection(children: []),
          ]) : ready == false ? Center(
          child: CircularProgressIndicator(),
        ) : null,
      );
    } else if (ready != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () {
            changeNightmode(false);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.none,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Builder(
                  builder: (context) {
                    TextStyle style = TextStyle(fontSize: 116, wordSpacing: 12);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Goodnight,", style: style.copyWith(color: Colors.white)),
                        SizedBox(width: style.wordSpacing),
                        Text("Harpers", style: style).gradient(colors: [GradientColor(Colors.blue), GradientColor(Colors.purple), GradientColor(Colors.red)]),
                      ],
                    );
                  }
                ),
                Builder(
                  builder: (context) {
                    TextStyle style = TextStyle(fontSize: 32);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Night Mode ", style: style).gradient(colors: [GradientColor(Colors.white, intensity: 6), GradientColor(Colors.green)]),
                        Text("Engaged", style: style).gradient(colors: [GradientColor(Colors.green)]),
                      ],
                    );
                  }
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      CrashScreen(message: "The server is in a bad state.", description: "The server is currently unavailable. Please report this incident.", code: "BAD_SERVER_STATUS_UNAVAILABLE", close: true);
      return Scaffold();
    }
  }

  void changeNightmode(bool status) {
    nightMode = status;
    init();
  }

  Widget DashboardSection({required List<Widget> children, bool scrollbar = true}) {
    return ScrollWidget(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 12),
          ...children,
        ],
      ),
      showScrollbar: scrollbar,
      controller: scrollController,
    );
  }
}

// ignore: must_be_immutable
class TileRow extends StatelessWidget {
  List<TileBox> children;
  bool takeUpEntireRow;
  TileRow({super.key, required this.children, this.takeUpEntireRow = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        spacing: 16,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }
}

class TileArea extends StatefulWidget {
  final List<TileRow> children;
  const TileArea({super.key, required this.children});

  @override
  State<TileArea> createState() => _TileAreaState();
}

class _TileAreaState extends State<TileArea> {
  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    int sections = getSections(width);
    int offset = 0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate((widget.children.length).ceil(), (index) {
        int i = (index * sections) - offset;
        if ((widget.children.length - 1) < i) return null;
        if (i + 1 < widget.children.length && widget.children[i + 1].takeUpEntireRow == true) widget.children[i].takeUpEntireRow = true;

        if (widget.children[i].takeUpEntireRow == true && sections >= 2) {
          for (var item in widget.children[i].children) {
            item.width = item.width * 2;
            if (widget.children[i].children.length >= 2) {
              item.rowPosition = TileRowPosition.both;
            }
          }

          offset++;
          if (widget.children[i].children.length <= 1) widget.children[i].children[0].rowPosition = TileRowPosition.bothExpanded;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.children[i],
            ],
          );
        }

        int i1 = i + 1;
        int i2 = i + 2;

        if (sections >= 2 && widget.children.length >= i2) {
          double widthA = widget.children[i].children[0].height;
          double widthB = widget.children[i1].children[0].height;

          if (widthA >= widthB) {
            for (var item in widget.children[i1].children) {
              item.height = widthA;
            }
          } else {
            for (var item in widget.children[i].children) {
              item.height = widthB;
            }
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.children[i],
              widget.children[i + 1],
            ],
          );
        }

        if (widget.children[i].children.length <= 1) {
          widget.children[i].children[0].rowPosition = TileRowPosition.both;
        }

        if (sections >= 2) {
          for (var item in widget.children[i].children) {
            item.width = item.width * 2;
            if (widget.children[i].children.length >= 2) {
              item.rowPosition = TileRowPosition.both;
            }
          }

          if (widget.children[i].children.length <= 1) {
            widget.children[i].children[0].rowPosition = TileRowPosition.bothExpanded;
          }
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            widget.children[i],
          ],
        );
      }).where((number) => number != null).cast<Widget>().toList(),
    );
  }
}

// ignore: must_be_immutable
class TileBox extends StatefulWidget {
  double width;
  double height;
  Widget? child;
  VoidCallback? onPressed;
  TileRowPosition rowPosition;
  bool hover;
  bool active;

  TileBox({super.key, this.width = 1, this.height = 1, this.child, this.onPressed, this.rowPosition = TileRowPosition.none, this.hover = false, this.active = false});

  @override
  State<TileBox> createState() => _TileBoxState();
}

class _TileBoxState extends State<TileBox> {
  bool hover = false;
  bool canHover = false;

  @override
  Widget build(BuildContext context) {
    double width = widget.width * tileWidth;
    double height = widget.height * tileHeight;

    if (widget.onPressed != null || widget.hover) {
      canHover = true;
    }

    if (widget.rowPosition == TileRowPosition.both || widget.rowPosition == TileRowPosition.bothExpanded) {
      width += widget.rowPosition == TileRowPosition.bothExpanded ? 48 : 16;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: (hover && canHover) || widget.active ? Colors.grey.withAlpha(160) : Colors.grey.withAlpha(100),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: InkWell(onTap: widget.onPressed, child: Center(child: Padding(
          padding: EdgeInsets.all(8.0),
          child: widget.child,
        ))),
      ),
    );
  }
}

enum TileRowPosition {
  none,
  both,
  bothExpanded,
}

class ShutdownText extends StatefulWidget {
  final int seconds;
  const ShutdownText({super.key, this.seconds = 60});

  @override
  State<ShutdownText> createState() => _ShutdownTextState();
}

class _ShutdownTextState extends State<ShutdownText> {
  int remaining = 0;
  Timer? timer;

  @override
  void initState() {
    remaining = widget.seconds;
    super.initState();

    timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      if (remaining <= 0) {
        return;
      }

      remaining--;
      setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text("The system will shut down in $remaining seconds.");
  }
}

class ThermostatSettings extends StatefulWidget {
  final String id;
  final Map data;
  const ThermostatSettings({super.key, required this.id, required this.data});

  @override
  State<ThermostatSettings> createState() => _ThermostatSettingsState();
}

class _ThermostatSettingsState extends State<ThermostatSettings> {
  int heatingcoolingtarget = 0;
  num temptarget = 0;
  num coolingthreshold = 0;
  num heatingthreshold = 0;
  int fantarget = 0;

  num fToC(num value) {
    double temp = (value - 32) * 5 / 9;
    return (temp * 10).round() / 10;
  }

  Future<void> change({required String characteristic, required dynamic value}) async {
    await request(endpoint: "devices/homekit/${widget.id}/set", body: {
      "characteristic": characteristic,
      "value": value,
    });
  }

  num getTemp(num value, {RoundMode roundMode = RoundMode.tenth}) { // set to fahrenheit and round to nearest 10th
    num value2 = ((value * 9/5) + 32);
    if (roundMode == RoundMode.tenth) {
      return (value2 * 10).round() / 10;
    } else if (roundMode == RoundMode.oneth) {
      return value2.round();
    } else {
      throw Exception("Invalid roundMode: $roundMode");
    }
  }

  @override
  void initState() {
    super.initState();
    Map data = widget.data;
    heatingcoolingtarget = data["data"]["1.18"]["value"];
    temptarget = getTemp(data["data"]["1.20"]["value"], roundMode: RoundMode.oneth);
    coolingthreshold = getTemp(data["data"]["1.22"]["value"]);
    heatingthreshold = getTemp(data["data"]["1.23"]["value"]);
    fantarget = data["data"]["1.75"]["value"];
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SettingTitle(title: "Heating/Cooling Mode"),
          DropdownButton<int>(
            value: heatingcoolingtarget,
            hint: Text('Select an option'),
            items: [
              DropdownMenuItem(
                value: 1,
                child: Text("Heat", style: TextStyle(color: Colors.orange)),
              ),
              DropdownMenuItem(
                value: 2,
                child: Text("Cool", style: TextStyle(color: Colors.blue)),
              ),
              DropdownMenuItem(
                value: 3,
                child: Text("Auto", style: TextStyle(color: Colors.green)),
              ),
              DropdownMenuItem(
                value: 0,
                child: Text("Off"),
              ),
            ],
            onChanged: (int? value) {
              if (value == null) return;
              heatingcoolingtarget = value;
              change(characteristic: "1.18", value: fToC(value));
              setState(() {});
            },
          ),
          TempPicker(value: temptarget.round(), title: "Target Temperature", onChanged: (int? value) {
            if (value == null) return;
            temptarget = value;
            change(characteristic: "1.20", value: fToC(value));
            setState(() {});
          }),
          TempPicker(value: coolingthreshold.round(), title: "Cooling Threshold", onChanged: (int? value) {
            if (value == null) return;
            coolingthreshold = value;
            change(characteristic: "1.22", value: fToC(value));
            setState(() {});
          }),
          TempPicker(value: heatingthreshold.round(), title: "Heating Threshold", onChanged: (int? value) {
            if (value == null) return;
            heatingthreshold = value;
            change(characteristic: "1.23", value: fToC(value));
            setState(() {});
          }),
          SettingTitle(title: "Fan"),
          TileBox(
            width: 1.5,
            child: Text("On"),
            onPressed: fantarget != 1 ? null : () {
              fantarget = 0;
              change(characteristic: "1.75", value: 0);
              setState(() {});
            },
            active: fantarget != 1,
          ),
          SizedBox(height: 12),
          TileBox(
            width: 1.5,
            child: Text("Auto"),
            onPressed: fantarget == 1 ? null : () {
              fantarget = 1;
              change(characteristic: "1.75", value: 1);
              setState(() {});
            },
            active: fantarget == 1,
          ),
        ],
      ),
    );
  }

  List<GradientColor> getGradientForTemp(num value) {
    if (value < 70) {
      return [GradientColor(Colors.blue), GradientColor(Colors.lightBlueAccent)];
    } else if (value > 75) {
      return [GradientColor(Colors.deepOrange), GradientColor(Colors.yellow)];
    } else {
      return [GradientColor(Colors.white, intensity: 2)];
    }
  }

  Widget TempPicker({required int value, required String title, required Function(int?) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SettingTitle(title: title),
        DropdownButton<int>(
          value: value,
          hint: Text('Select an option'),
          items: List.generate(60, (int i) {
            int value = i + 40;
            return DropdownMenuItem(
              child: Text("$value°F").gradient(colors: getGradientForTemp(value)),
              value: value,
            );
          }),
          onChanged: onChanged,
        ),
      ],
    );
  }
}