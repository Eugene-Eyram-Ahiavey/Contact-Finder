import 'package:flutter/material.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/screens/landing_splash_screen.dart';
import 'package:qara/theme/app_theme.dart';

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
      title: 'Qara Call Centers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brandDarkTeal,
          primary: AppColors.brandDarkTeal,
          secondary: AppColors.brandLime,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: AppColors.brandDarkTeal,
          foregroundColor: Colors.white,
        ),
      ),
      home: LandingSplashScreen(database: database),
    );
  }
}
