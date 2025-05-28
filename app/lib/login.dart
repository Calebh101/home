import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homeapp/dashboard.dart';
import 'package:homeapp/main.dart';
import 'package:homeapp/online.dart';
import 'package:http/http.dart' as http;
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/widgets.dart';

bool loginActive = false;

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

  @override
  void initState() {
    loginActive = true;
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Section(),
            Text("Please enter the password to log in to the Home app.", style: TextStyle(color: Colors.white, fontSize: 24)),
            SizedBox(height: 12),
            TextFormField(
              style: TextStyle(color: Colors.white),
              obscureText: obscure,
              controller: controller,
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
              print("sending access code of ${controller.text}");
              showSnackBar(context, "Loading...");
              var response = await http.post(Uri.parse("${getBaseUrl()}/api/system/check"), headers: {"authentication": controller.text});

              if (isInvalidPasswordResponse(response, jsonDecode(response.body))) { // invalid password
                showSnackBar(context, "Invalid password.");
              } else if (response.statusCode == 200) { // valid password
                runApp(MyApp(debug: widget.debug, kiosk: widget.kiosk));
              } else {
                showSnackBar(context, "An unknown error occurred. (Status code: ${response.statusCode})");
              }
            }),
            Section(),
          ],
        ),
      ),
    );
  }
}