import 'package:flutter/material.dart';
import 'package:evangelism_caller_id/database/app_database.dart';
import 'package:evangelism_caller_id/screens/home_screen.dart';

void main() async {
  // Ensure Flutter engine bindings are initialized before accessing native channels or databases
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase();

  runApp(EvangelismCallerIdApp(database: database));
}

class EvangelismCallerIdApp extends StatelessWidget {
  final AppDatabase database;

  const EvangelismCallerIdApp({super.key, required this.database});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evangelism Caller ID',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo.shade700,
          secondary: Colors.teal.shade700,
        ),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.indigo.shade700,
          foregroundColor: Colors.white,
        ),
      ),
      home: HomeScreen(database: database),
    );
  }
}
