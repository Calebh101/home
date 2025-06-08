import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:http/http.dart' as http;
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/logger.dart';
import 'package:localpkg/theme.dart';
import 'package:localpkg/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool loginActive = false;
int loginStage = 0;
String? accountPassword;

class LoginApp extends StatefulWidget {
  final bool debug;
  final bool kiosk;
  const LoginApp({super.key, required this.debug, required this.kiosk});

  @override
  State<LoginApp> createState() => _LoginAppState();
}

class _LoginAppState extends State<LoginApp> {
  @override
  Widget build(BuildContext context) {
    print("building login app...");
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home',
      theme: ThemeData(
        textTheme: GoogleFonts.robotoTextTheme(),
        colorScheme: ColorScheme.dark(primary: Colors.deepOrange),
      ),
      themeMode: ThemeMode.dark,
      home: LoginWidget(debug: widget.debug, kiosk: widget.kiosk),
    );
  }
}

class LoginWidget extends StatefulWidget {
  final bool debug;
  final bool kiosk;
  const LoginWidget({super.key, required this.debug, required this.kiosk});

  @override
  State<LoginWidget> createState() => _LoginWidgetState();
}

class _LoginWidgetState extends State<LoginWidget> {
  bool obscure = true;
  TextEditingController controller = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController codeController = TextEditingController();

  @override
  void initState() {
    loginActive = true;
    loginStage = 1;
    super.initState();
  }

  @override
  void dispose() {
    loginActive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Welcome Back!"),
        centerTitle: true,
        leading: loginStage >= 2 ? IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            print("setting loginStage from $loginStage to ${1}");
            loginStage = 1;
            setState(() {});
          },
        ) : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: loginStage == 2 ? [
            Text("Please enter the two factor authentication code sent to your email.", style: TextStyle(color: Colors.white, fontSize: 24)),
            SizedBox(height: 12),
            TextFormField(
              style: TextStyle(color: Colors.white),
              controller: codeController,
              decoration: InputDecoration(
                labelText: '2FA',
                border: OutlineInputBorder(),
              ),
            ),
            Section(),
            Section(),
            TileBox(child: Text("OK", style: TextStyle(color: Colors.white)), onPressed: () async {
              String text = codeController.text;
              if (text.length != 6) return showSnackBar(context, "Invalid 2FA code.");
              print("sending 2fa code of $text");
              showSnackBar(context, "Loading...");
              http.Response response = await http.post(Uri.parse("${getBaseUrl()}/auth/approve"), headers: {"Content-Type": "application/json"}, body: jsonEncode({"code": text}));

              if (response.statusCode == 403) { // invalid password
                print("auth error: ${response.body}");
                showSnackBar(context, jsonDecode(response.body)["message"] ?? "Invalid code.");
              } else if (response.statusCode == 200) { // valid password
                String id = jsonDecode(response.body)["id"];
                SharedPreferences prefs = await SharedPreferences.getInstance();
                prefs.setString("session", id);
                print("set session to $id");
                reinit(debug: widget.debug, kiosk: widget.kiosk);
              } else {
                warn("2fa.response: ${response.body}");
                showSnackBar(context, "An unknown error occurred. (Status code: ${response.statusCode})");
              }
            }),
            Section(),
          ] : ((loginStage == 1) ? [
            Section(),
            Text("Please log in to use the Home app.", style: TextStyle(color: Colors.white, fontSize: 24)),
            SizedBox(height: 12),
            TextFormField(
              style: TextStyle(color: Colors.white),
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextFormField(
              style: TextStyle(color: Colors.white),
              obscureText: obscure,
              controller: passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    obscure = !obscure;
                    setState(() {});
                  },
                ),
              ),
            ),
            Section(),
            Section(),
            TileBox(child: Text("OK", style: TextStyle(color: Colors.white)), onPressed: () async {
              print("sending username:password of ${controller.text}:${passwordController.text}");
              showSnackBar(context, "Loading...");
              http.Response response = await http.post(Uri.parse("${getBaseUrl()}/auth/login"), headers: {"Content-Type": "application/json"}, body: jsonEncode({"email": controller.text, "password": passwordController.text}));

              if (response.statusCode == 403) { // invalid password
                print("auth error: ${response.body}");
                showSnackBar(context, jsonDecode(response.body)["message"] ?? "Invalid password.");
              } else if (response.statusCode == 200) { // valid password
                loginStage = 2;
                setState(() {});
              } else {
                warn("username:password.response: ${response.body}");
                showSnackBar(context, "An unknown error occurred. (Status code: ${response.statusCode})");
              }
            }),
            Section(),
          ] : [
            Center(
              child: CircularProgressIndicator(),
            ),
          ]),
        ),
      ),
    );
  }
}

class AccountManager extends StatefulWidget {
  const AccountManager({super.key});

  @override
  State<AccountManager> createState() => _AccountManagerState();
}

class _AccountManagerState extends State<AccountManager> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Welcome, ",
                  style: TextStyle(fontSize: 24),
                ),
                Text(
                  "$name",
                  style: TextStyle(fontSize: 24),
                ).gradient(colors: [GradientColor(Colors.white, intensity: 1), GradientColor(getSeed(context, brightness: Brightness.dark))]),
              ],
            ),
            Setting(title: "Manage Sessions", desc: "Manage and sign out of other devices you might be logged into.", action: () async {
              await showDialogue(context: context, title: "Manage Sessions", content: SessionManager());
              setState(() {});
            }),
          ],
        ),
      ),
    );
  }
}

class SessionManager extends StatefulWidget {
  const SessionManager({super.key});

  @override
  State<SessionManager> createState() => _SessionManagerState();
}

class _SessionManagerState extends State<SessionManager> {
  List? sessions;
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() async {
    sessions = null;
    setState(() {});
    Map? data = await request(endpoint: "user/getSessions", body: {"password": accountPassword}, context: context, action: "get sessions");
    if (data != null) sessions = data["sessions"];
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return sessions == null ? Center(child: CircularProgressIndicator()) : ListView.builder(itemBuilder: (BuildContext context, int i) {
      Map session = sessions![i];
      Map location = session["location"];

      return ListTile(
        title: Text("Location: ${location["city"] ?? "Unknown"}, ${location["region"] ?? "Unknown"}, ${location["country"] ?? "Unknown"}"),
        subtitle: Text("Created: ${DateTime.parse(session["created"]).toLocal()}"),
      );
    }, itemCount: sessions!.length);
  }
}

class AccountPasswordInput extends StatefulWidget {
  const AccountPasswordInput({super.key});

  @override
  State<AccountPasswordInput> createState() => _AccountPasswordInputState();
}

class _AccountPasswordInputState extends State<AccountPasswordInput> {
  TextEditingController controller = TextEditingController(text: accountPassword);
  bool obscure = true;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextFormField(
        style: TextStyle(color: Colors.white),
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: 'Password',
          border: OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
            ),
            onPressed: () {
              obscure = !obscure;
              setState(() {});
            },
          ),
        ),
        onChanged: (String input) {
          setState(() {
            accountPassword = input;
          });
        },
      ),
    );
  }
}