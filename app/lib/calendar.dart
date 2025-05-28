import 'package:duration_format/duration_format.dart';
import 'package:flutter/material.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:intl/intl.dart';
import 'package:localpkg/functions.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// for dynamic calendar
double tileWidth = 100;
double tilePadding = 4;
int yearOffset = 1; // how far back to load the past

ItemScrollController controller = ItemScrollController();
List months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

Future<void> updateCalendar() async {
  refreshingCalendar = true;
  DateTime now = DateTime.now();
  DateTime weeklater = now.add(Duration(days: 7));
  calendarForTheNextWeek = await request(endpoint: "calendar/get", body: {
    "start": {
      "year": now.year,
      "month": now.month,
      "day": now.day,
    },
    "end": {
      "year": weeklater.year,
      "month": weeklater.month,
      "day": weeklater.day,
    },
    "list": currentCalendarList,
  });
  calendarEventsTotal = (await request(endpoint: "calendar/get"))!["events"];
  refreshingCalendar = false;
}

enum CalendarRenderType {
  forTheNextWeek,
  all,
}

class CalendarForTheNextWeekRenderer extends StatefulWidget {
  final CalendarRenderType type;
  const CalendarForTheNextWeekRenderer({super.key, required this.type});

  @override
  State<CalendarForTheNextWeekRenderer> createState() => _CalendarForTheNextWeekRendererState();
}

class _CalendarForTheNextWeekRendererState extends State<CalendarForTheNextWeekRenderer> {
  @override
  Widget build(BuildContext context) {
    if (calendarForTheNextWeek == null || calendarLists == null) {
      return Center(child: CircularProgressIndicator());
    }

    int actualLength = calendarForTheNextWeek!["events"].length;
    int length = actualLength;
    if (length > 3) length = 3;

    return Column(
      children: [
        ...List.generate(length, (int i) {
          List events = calendarForTheNextWeek!["events"];
          Map event = events[i];
          DateRange range = generateRange(event["start"], event["end"]);
          Duration startsIn = range.start.difference(DateTime.now());
          Color hue = getHue(calendarLists!.indexOf(event["list"]) * 100);

          DateFormat generateFormatter({bool noTime = false}) {
            return DateFormat("M/dd/yyyy${noTime ? "" : " h:mm a"}");
          }

          bool showTimeDuration(DateRange range) {
            return range.endNoTime == false || range.startNoTime == false;
          }

          return Column(
            children: [
              Text("${event["name"]}", style: TextStyle(fontSize: 20, color: null)),
              Text("Starts in ${startsIn.format(DurationFormat.pretty())}\nFor ${range.duration.format(DurationFormat.pretty(showMinutes: showTimeDuration(range), showHours: showTimeDuration(range)))} - ${generateFormatter(noTime: range.startNoTime).format(range.start)} to ${generateFormatter(noTime: range.endNoTime).format(range.end)}"),
              SizedBox(height: 10),
            ],
          );
        }),
        if (actualLength > length)
        Text("And ${actualLength - length} more...", style: TextStyle(fontSize: 20)),
      ],
    );
  }
}

void jumpToCurrentMonth() {
  controller.scrollTo(
    index: monthsBetween(DateTime(DateTime.now().toUtc().year - yearOffset), DateTime.now()),
    duration: Duration(milliseconds: 1000),
    curve: Curves.easeInOut,
  );
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  @override
  void initState() {
    super.initState();
    showSectionDialogue(context: context, id: "calendar");
  }

  @override
  Widget build(BuildContext context) {
    DateTime time = DateTime(DateTime.now().toUtc().year - yearOffset).toUtc();

    return Container(
      height: MediaQuery.of(context).size.height - (kToolbarHeight * 2.5),
      child: ScrollablePositionedList.builder(itemScrollController: controller, itemCount: monthsBetween(time, DateTime.utc(DateTime.now().year + 3, 1, 1)), itemBuilder: (BuildContext context, int i) {
        return CalendarMonth(date: addMonths(time, i), start: DateTime.utc(time.year, 1, 1), isFirstInCalendar: i == 0);
      }),
    );
  }
}

class CalendarMonth extends StatefulWidget {
  final DateTime date; // utc
  final DateTime start;
  final bool isFirstInCalendar;
  const CalendarMonth({super.key, required this.date, required this.start, this.isFirstInCalendar = false});

  @override
  State<CalendarMonth> createState() => _CalendarMonthState();
}

class _CalendarMonthState extends State<CalendarMonth> {
  @override
  Widget build(BuildContext context) {
    DateTime first = DateTime.utc(widget.date.year, widget.date.month, 1);
    int tiles = getTilesAcross(context: context);
    int days = daysInMonth(widget.date);
    int offset = first.weekday % tiles;
    int rows = ((days + offset) / tiles).ceil();
    if (widget.isFirstInCalendar) offset = first.weekday;

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(tilePadding),
            child: Text(
              "${months[widget.date.month - 1]} ${widget.date.year}",
              style: TextStyle(fontSize: 20),
            ),
          ),
          ...List.generate(rows, (int i) {
            DateTime start = first.add(Duration(days: (tiles * i) - offset));
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(tiles, (int i2) {
                DateTime date = start.add(Duration(days: i2));
                return CalendarDay(date: date, month: widget.date.month);
              }),
            );
          }),
        ],
      ),
    );
  }
}

enum EventStatus {
  startsOn,
  endsOn,
  goesThrough,
  isOnlyOn,
}

class Event {
  final EventStatus status;
  final DateTime start;
  final DateTime end;
  final String? name;
  final String? description;
  final String? list;

  const Event({required this.status, required this.start, required this.end, required this.name, required this.description, required this.list});
}

class CalendarDay extends StatefulWidget {
  final DateTime date;
  final int month;
  const CalendarDay({super.key, required this.date, required this.month});

  @override
  State<CalendarDay> createState() => _CalendarDayState();
}

class _CalendarDayState extends State<CalendarDay> {
  @override
  Widget build(BuildContext context) {
    bool inTheMonth = widget.month == widget.date.month;
    bool isToday = DateTime.now().year == widget.date.year && DateTime.now().month == widget.date.month && DateTime.now().day == widget.date.day;
    Size screen = MediaQuery.of(context).size;
    int i = 0;

    List<Event> events = [];
    List<Widget> children = [];

    for (Map event in calendarEventsTotal!) {
      if (event["list"] != currentCalendarList && currentCalendarList != null) continue;
      DateTime start = DateTime.utc(event["start"]["year"], event["start"]["month"], event["start"]["day"]);
      DateTime end = DateTime.utc(event["end"]["year"], event["end"]["month"], event["end"]["day"]);
      bool startsOn = start == widget.date;
      bool endsOn = end == widget.date;
      EventStatus? status;


      if (startsOn && endsOn) {
        status = EventStatus.isOnlyOn;
      } else if (startsOn) {
        status = EventStatus.startsOn;
      } else if (endsOn) {
        status = EventStatus.endsOn;
      } else if (widget.date.isBefore(end) && widget.date.isAfter(start)) {
        status = EventStatus.goesThrough;
      }

      if (status != null) {
        events.add(Event(
          status: status,
          start: start,
          end: end,
          name: event["name"],
          description: event["description"],
          list: event["list"],
        ));
      }
    }

    double maxTileSize = 50;
    double size = ((screen.width > screen.height ? screen.height : screen.width) / 7) - 20;
    if (size > maxTileSize) size = maxTileSize;
    double tilePadding = size / 8;

    int maxLength = 7;
    int length = events.length;
    int currentLength = 0;
    if (length > maxLength) length = maxLength;

    while (true) {
      if (currentLength >= length) break;
      int thisLength = 1;
      Event event = events[i];
      currentLength = currentLength + thisLength;

      children.add(Container(
        width: size / (10 / thisLength),
        height: size / 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: getHue(calendarLists!.indexOf(event.list) * 100),
        ),
      ));

      i++;
    }

    return Padding(
      padding: EdgeInsets.all(tilePadding),
      child: Container(
        height: dynamicCalendar ? (tileWidth - tilePadding) : size,
        width: dynamicCalendar ? (tileWidth - tilePadding) : size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          color: getCalendarColor(context: context, inTheMonth: inTheMonth, isToday: isToday),
        ),
        child: InkWell(
          child: Padding(
            padding: EdgeInsets.all(tilePadding),
            child: Column(
              children: [
                Text("${widget.date.day}", style: TextStyle(fontSize: size / 2.5)),
                Spacer(),
                Row(
                  children: children,
                ),
              ],
            ),
          ),
          onTap: () {
            navigate(context: context, page: CalendarDayPage(day: widget.date));
          },
        ),
      ),
    );
  }
}

class CalendarDayPage extends StatefulWidget {
  final DateTime day;
  const CalendarDayPage({super.key, required this.day});

  @override
  State<CalendarDayPage> createState() => _CalendarDayPageState();
}

class _CalendarDayPageState extends State<CalendarDayPage> {
  @override
  void initState() {
    super.initState();
    showSectionDialogue(context: context, id: "calendar-day");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text("${months[widget.day.month]} ${widget.day.day}, ${widget.day.year}"),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}

Color getCalendarColor({required BuildContext context, bool inTheMonth = false, bool isToday = false}) {
  double alpha = 0;

  if (getBrightness(context: context) == Brightness.light) {
    if (inTheMonth) {
      if (isToday) {
        alpha = 0.9;
      } else {
        alpha = 0.8;
      }
    } else {
      alpha = 0.7;
    }
  } else {
    if (inTheMonth) {
      if (isToday) {
        alpha = 0.45;
      } else {
        alpha = 0.3;
      }
    } else {
      alpha = 0.1;
    }
  }

  return Color.alphaBlend(Colors.white.withValues(alpha: alpha), Colors.black);
}

DateTime addMonths(DateTime time, int monthsToAdd) {
  int newYear = time.year + ((time.month - 1 + monthsToAdd) ~/ 12);
  int newMonth = ((time.month - 1 + monthsToAdd) % 12) + 1;
  int newDay = time.day;
  int lastDayOfNewMonth = DateTime(newYear, newMonth + 1, 0).day;

  if (newDay > lastDayOfNewMonth) newDay = lastDayOfNewMonth;
  return DateTime(newYear, newMonth, newDay, time.hour, time.minute, time.second, time.millisecond, time.microsecond);
}

int monthsBetween(DateTime from, DateTime to) {
  int yearDiff = to.year - from.year;
  int monthDiff = to.month - from.month;
  int totalMonths = yearDiff * 12 + monthDiff;

  if (to.day < from.day) {
    totalMonths -= 1;
  }

  return totalMonths;
}

int getTilesAcross({required BuildContext context}) {
  double width = MediaQuery.of(context).size.width;
  int tiles = (width / (tileWidth + tilePadding + 10)).floor();
  if (tiles > 7) tiles = 7;
  return dynamicCalendar ? tiles : 7;
}

int daysInMonth(DateTime date) {
  DateTime beginningNextMonth = (date.month < 12) ? DateTime(date.year, date.month + 1, 1) : DateTime(date.year + 1, 1, 1);
  DateTime lastDayOfMonth = beginningNextMonth.subtract(Duration(days: 1));
  return lastDayOfMonth.day;
}

DateRange generateRange(Map start, Map end) {
  DateTime transformRange(Map range) {
    return DateTime(range["year"], range["month"], range["day"], range["hour"] ?? 0, range["minute"] ?? 0);
  }

  Duration duration = (transformRange(end).difference(transformRange(start)));
  if (duration == Duration.zero) duration = Duration(days: 1);
  return DateRange(transformRange(start), transformRange(end), duration: duration, startNoTime: start["hour"] == null || start["minute"] == null, endNoTime: end["hour"] == null || end["minute"] == null);
}

class DateRange {
  final DateTime start;
  final DateTime end;
  final bool startNoTime;
  final bool endNoTime;
  final Duration duration;
  const DateRange(this.start, this.end, {required this.duration, this.startNoTime = false, this.endNoTime = false});
}