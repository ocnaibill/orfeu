import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';

// Providers de Analytics
final userStatsProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, days) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio
      .get('/users/me/analytics/summary', queryParameters: {'days': days});
  return resp.data;
});

final topTracksProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/users/me/analytics/top-tracks?limit=5');
  return resp.data;
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Padrão 30 dias
    final statsAsync = ref.watch(userStatsProvider(30));
    final topTracksAsync = ref.watch(topTracksProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text("Seu Perfil",
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              Navigator.pop(context); // Fecha o modal/tela
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Cabeçalho do Usuário ---
            const CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFFD4AF37),
              child: Icon(Icons.person, size: 40, color: Colors.black),
            ),
            const SizedBox(height: 16),
            Text("Olá, Audiófilo!",
                style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const Text("Aqui está o seu resumo mensal.",
                style: TextStyle(color: Colors.white54)),

            const SizedBox(height: 30),

            // --- Cards de Estatísticas ---
            statsAsync.when(
              data: (stats) => Row(
                children: [
                  _buildStatCard(
                      "Minutos", "${stats['total_minutes']}", Icons.timer),
                  const SizedBox(width: 12),
                  _buildStatCard(
                      "Plays", "${stats['total_plays']}", Icons.play_arrow),
                ],
              ),
              loading: () =>
                  const LinearProgressIndicator(color: Color(0xFFD4AF37)),
              error: (err, _) =>
                  Text("Erro: $err", style: const TextStyle(color: Colors.red)),
            ),

            const SizedBox(height: 30),

            // --- Top Artista ---
            statsAsync.when(
              data: (stats) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFD4AF37), Color(0xFFA08020)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("ARTISTA DO MÊS",
                        style: TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    Text(stats['top_artist'] ?? "Ninguém... ainda",
                        style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.black)),
                    Text("${stats['top_artist_plays']} reproduções",
                        style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
            ),

            const SizedBox(height: 30),

            // --- Top Músicas ---
            Text("Mais Ouvidas",
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 10),

            topTracksAsync.when(
              data: (tracks) => Column(
                children: tracks
                    .map<Widget>((t) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text("${tracks.indexOf(t) + 1}",
                              style: const TextStyle(
                                  color: Color(0xFFD4AF37),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          title: Text(t['display_name'],
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(t['artist'],
                              style: const TextStyle(color: Colors.white54)),
                          trailing: Text("${t['plays']} plays",
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                        ))
                    .toList(),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Text("Sem dados."),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFD4AF37), size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
