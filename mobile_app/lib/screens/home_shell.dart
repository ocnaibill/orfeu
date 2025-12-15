import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import '../services/update_service.dart';
import 'dart:io' show Platform;

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const PlaceholderHome(),
    const SearchScreen(),
    const LibraryScreen(),
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
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37)),
              child: const Text('Baixar Agora',
                  style: TextStyle(color: Colors.black)),
              onPressed: () {
                print(
                    "🔗 Tentando abrir link de download: ${info.downloadUrl}");

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
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle:
              MaterialStateProperty.all(GoogleFonts.outfit(fontSize: 12)),
          indicatorColor: const Color(0xFFD4AF37).withOpacity(0.2),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          backgroundColor: Colors.black,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_filled), label: 'Início'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
            NavigationDestination(
                icon: Icon(Icons.library_music), label: 'Biblioteca'),
          ],
        ),
      ),
    );
  }
}

class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});
  @override
  Widget build(BuildContext context) {
    final updateService =
        ProviderScope.containerOf(context).read(updateServiceProvider);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_note, size: 80, color: Color(0xFFD4AF37)),
          const SizedBox(height: 20),
          Text("Bem-vindo ao Orfeu",
              style: GoogleFonts.outfit(fontSize: 24, color: Colors.white)),
          const SizedBox(height: 10),
          const Text("Sua jornada Hi-Fi começa aqui.",
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 10),
          Text("v1.0.0", style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}
