import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

class AppTheme {
  static const Color pitchBlack = Color(0xFF000000);
  static const Color nearBlack = Color(0xFF0A0A0A);
  
  static ThemeData darkTheme(ColorScheme? dynamicColorScheme) {
    final ColorScheme colorScheme = dynamicColorScheme ?? ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    );
    
    final ColorScheme blackColorScheme = colorScheme.copyWith(
      surface: pitchBlack,
      onSurface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: blackColorScheme,
      scaffoldBackgroundColor: pitchBlack,
      
      appBarTheme: const AppBarTheme(
        backgroundColor: pitchBlack,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      
      cardTheme: CardThemeData(
        color: nearBlack,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: nearBlack,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: nearBlack,
        selectedItemColor: blackColorScheme.primary,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
      
      iconTheme: const IconThemeData(
        color: Colors.white,
      ),
      
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        bodySmall: TextStyle(color: Colors.white60),
      ),
    );
  }
  static Future<ThemeData> getDarkTheme() async {
    try {
      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (corePalette != null) {
        return darkTheme(
          ColorScheme.fromSeed(
            seedColor: Color(corePalette.primary.get(40)),
            brightness: Brightness.dark,
          ),
        );
      }
    } catch (e) {
      debugPrint('Dynamic colors not supported: $e');
    }
    return darkTheme(null);
  }
}
