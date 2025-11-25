// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'auth_page.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  late String supabaseUrl;
  late String supabaseAnonKey;

  if (kIsWeb) {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (url.isEmpty || key.isEmpty) {
      throw Exception("❌ Missing SUPABASE_URL or SUPABASE_ANON_KEY for web.\n"
          "Run with: flutter run -d chrome "
          "--dart-define=SUPABASE_URL=https://xxxx.supabase.co "
          "--dart-define=SUPABASE_ANON_KEY=your-anon-key");
    }

    supabaseUrl = url;
    supabaseAnonKey = key;
  } else {
    await dotenv.load(fileName: ".env");

    supabaseUrl = dotenv.env['SUPABASE_URL'] ?? "";
    supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? "";

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception("❌ Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env file");
    }
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bock Store',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.black.withOpacity(0.1),
          elevation: 0,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF141E30), Color(0xFF243B55)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SizedBox.expand(),
          ),
          supabase.auth.currentSession == null
              ? const LoginPage()
              : const HomePage(),
        ],
      ),
    );
  }
}
