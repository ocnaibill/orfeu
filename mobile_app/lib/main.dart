import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'providers.dart';

void main() {
  runApp(const ProviderScope(child: OrfeuApp()));
}

class OrfeuApp extends ConsumerWidget {
  const OrfeuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    // --- DEBUG LOGGING ---
    // Isso vai aparecer no seu terminal e nos dirá por que o app não muda de tela
    print("🔐 AuthState Alterado:");
    print("   IsLoading: ${authState.isLoading}");
    print("   IsAuthenticated: ${authState.isAuthenticated}");
    print("   Token: ${authState.token != null ? 'Presente' : 'Nulo'}");
    if (authState.error != null) {
      print("   ❌ ERRO CAPTURADO: ${authState.error}");
    }
    // ---------------------

    return MaterialApp(
      title: 'Orfeu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37),
          secondary: Color(0xFFD4AF37),
          surface: Color(0xFF121212),
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),
      // Lógica de Roteamento Simples
      home: authState.isLoading
          ? const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37))))
          : authState.isAuthenticated
              ? const HomeShell()
              : const LoginScreen(),
    );
  }
}
