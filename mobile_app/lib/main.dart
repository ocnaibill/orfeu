import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'providers.dart';
import 'services/background_audio_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializa o serviço de áudio em segundo plano
  await initAudioService();
  
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
      theme: AppTheme.darkTheme,
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
