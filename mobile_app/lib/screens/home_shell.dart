import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io' show Platform;
import 'search_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart'; // Importa a nova tela
import '../services/update_service.dart';
import '../providers.dart'; // Para acessar authProvider

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeTab(), // Aba 0: Início (Renomeado de PlaceholderHome)
    const SearchScreen(), // Aba 1: Buscar
    const LibraryScreen(), // Aba 2: Biblioteca
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  void _checkForUpdates() async {
    if (Platform.isIOS ||
        Platform.isAndroid ||
        Platform.isWindows ||
        Platform.isMacOS) {
      final updateService = ref.read(updateServiceProvider);
      final updateInfo = await updateService.checkForUpdate();

      if (updateInfo != null && mounted) {
        _showUpdateDialog(updateInfo);
      }
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text("Atualização Disponível!",
              style: GoogleFonts.outfit(color: const Color(0xFFD4AF37))),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text("Nova Versão: ${info.latestVersion}",
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 10),
                Text(info.releaseNotes,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Mais Tarde',
                  style: TextStyle(color: Colors.white54)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37)),
              child: const Text('Baixar Agora',
                  style: TextStyle(color: Colors.black)),
              onPressed: () {
                // Aqui entraria o url_launcher
                print("🔗 Link: ${info.downloadUrl}");
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      // AppBar condicional: Só aparece na Home (index 0)
      appBar: _selectedIndex == 0
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Row(
                children: [
                  const Icon(Icons.music_note, color: Color(0xFFD4AF37)),
                  const SizedBox(width: 8),
                  Text("Orfeu",
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.account_circle,
                      color: Colors.white, size: 28),
                  tooltip: "Perfil",
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()));
                  },
                ),
                const SizedBox(width: 16),
              ],
            )
          : null, // Nas outras telas, elas definem sua própria AppBar ou usam SafeArea

      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle:
              WidgetStateProperty.all(GoogleFonts.outfit(fontSize: 12)),
          indicatorColor: const Color(0xFFD4AF37).withOpacity(0.2),
          iconTheme: WidgetStateProperty.all(
              const IconThemeData(color: Colors.white70)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          backgroundColor: Colors.black,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_filled),
                label: 'Início',
                selectedIcon:
                    Icon(Icons.home_filled, color: Color(0xFFD4AF37))),
            NavigationDestination(
                icon: Icon(Icons.search),
                label: 'Buscar',
                selectedIcon: Icon(Icons.search, color: Color(0xFFD4AF37))),
            NavigationDestination(
                icon: Icon(Icons.library_music),
                label: 'Biblioteca',
                selectedIcon:
                    Icon(Icons.library_music, color: Color(0xFFD4AF37))),
          ],
        ),
      ),
    );
  }
}

// --- Home Tab (Dashboard) ---
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pega o nome do usuário do estado de Auth
    final username = ref.watch(authProvider).username ?? "Visitante";

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Bem-vindo de volta,",
              style: GoogleFonts.outfit(fontSize: 16, color: Colors.white54)),
          Text(username,
              style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),

          const SizedBox(height: 30),

          // Cartão de Destaque (Estático por enquanto)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFA08020)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, color: Colors.black, size: 30),
                const SizedBox(height: 10),
                Text("Sua Vibe Musical",
                    style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
                const SizedBox(height: 5),
                const Text(
                    "Descubra o que você tem ouvido ultimamente na sua retrospectiva.",
                    style: TextStyle(color: Colors.black87)),
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text("Ver Estatísticas"),
                )
              ],
            ),
          ),

          const SizedBox(height: 30),
          Text("Recentes",
              style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 10),
          const Center(
              child: Text("Seu histórico aparecerá aqui em breve.",
                  style: TextStyle(color: Colors.white24))),
        ],
      ),
    );
  }
}
