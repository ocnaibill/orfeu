import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor:
        const Color.fromARGB(255, 0, 0, 0), // Fundo padrão escuro
    primaryColor: const Color(0xFFD4AF37), // Dourado Orfeu

    // Configuração de Tipografia Global (Fira Sans)
    textTheme: GoogleFonts.firaSansTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),

    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFD4AF37),
      secondary: Color(0xFFD4AF37),
      surface: Color.fromARGB(255, 0, 0, 0),
      onSurface: Colors.white,
    ),

    useMaterial3: true,
  );

  // Cores específicas do Figma
  static const Color textGray = Color(0xFF8D8D93);
  static const Color glassBackground =
      Color.fromRGBO(255, 255, 255, 0.2); // Base para o glass
}
