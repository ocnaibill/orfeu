import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'search_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const PlaceholderHome(), // Aba 0: Início
    const SearchScreen(), // Aba 1: Buscar
    const PlaceholderLibrary(), // Aba 2: Biblioteca
  ];

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
        ],
      ),
    );
  }
}

class PlaceholderLibrary extends StatelessWidget {
  const PlaceholderLibrary({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
        child: Text("Sua biblioteca aparecerá aqui",
            style: TextStyle(color: Colors.white54)));
  }
}
