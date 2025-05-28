import 'package:flutter/material.dart';
import 'package:homeapp/main.dart';
import 'package:intl/intl.dart';

List? announcements;

class AnnouncementsBuilder extends StatefulWidget {
  final bool mini;
  const AnnouncementsBuilder({super.key, this.mini = false});

  @override
  State<AnnouncementsBuilder> createState() => _AnnouncementsBuilderState();
}

class _AnnouncementsBuilderState extends State<AnnouncementsBuilder> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return announcements == null ? Center(child: CircularProgressIndicator()) : announcements!.isNotEmpty ? (ListView.builder(
      itemCount: widget.mini ? 1 : announcements!.length,
      shrinkWrap: true,
      physics: widget.mini ? NeverScrollableScrollPhysics() : null,
      itemBuilder: (context, index) {
        Map item = announcements![index];
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: widget.mini ? null : BoxDecoration(
              border: Border.all(
                color: getThemeColor(context).withAlpha(70),
                width: 4,
              ),
              borderRadius: BorderRadius.all(Radius.circular(16))
            ),
            child: ListTile(
              title: Column(
                children: [
                  Text("${item["title"]}", maxLines: 2, overflow: widget.mini ? TextOverflow.ellipsis : null, textAlign: TextAlign.center),
                  SizedBox(height: 3),
                  Text(DateFormat("M/d/yy h:mm a").format(DateTime.parse(item["date"]).toLocal()), textAlign: TextAlign.center),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${item["description"]}", maxLines: widget.mini ? 3 : null, overflow: widget.mini ? TextOverflow.ellipsis : null),
                ],
              ),
            ),
          ),
        );
      },
    )) : Center(child: Text("No announcements for today."));
  }
}

class AnnouncementsPage extends StatelessWidget {
  const AnnouncementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Announcements"),
        centerTitle: true,
        leading: IconButton(onPressed: () {
          Navigator.of(context).pop();
        }, icon: Icon(Icons.arrow_back)),
      ),
      body: AnnouncementsBuilder(),
    );
  }
}