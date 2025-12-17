import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import '../providers.dart';

// Provider para dados detalhados de estatísticas
final vibeMusicalProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  
  try {
    final results = await Future.wait([
      dio.get('/users/me/analytics/summary', queryParameters: {'days': 30}),
      dio.get('/users/me/analytics/summary', queryParameters: {'days': 365}),
      dio.get('/users/me/analytics/top-tracks', queryParameters: {'limit': 5, 'days': 30}),
    ]);
    
    return {
      'monthly': results[0].data,
      'yearly': results[1].data,
      'topTracks': results[2].data,
    };
  } catch (e) {
    throw Exception('Erro ao carregar estatísticas: $e');
  }
});

class VibeMusicalScreen extends ConsumerWidget {
  const VibeMusicalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vibeData = ref.watch(vibeMusicalProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header com gradiente
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2), Colors.black],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Sua Vibe Musical",
                    style: GoogleFonts.firaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Descubra seus hábitos musicais",
                    style: GoogleFonts.firaSans(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            vibeData.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(50),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 50),
                      const SizedBox(height: 10),
                      Text(
                        "Erro ao carregar dados",
                        style: GoogleFonts.firaSans(color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        err.toString(),
                        style: GoogleFonts.firaSans(color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              data: (data) => _buildContent(context, data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> data) {
    final monthly = data['monthly'] as Map<String, dynamic>? ?? {};
    final yearly = data['yearly'] as Map<String, dynamic>? ?? {};
    final topTracks = data['topTracks'] as List? ?? [];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Estatísticas do Mês
          const SizedBox(height: 20),
          Text(
            "Este Mês",
            style: GoogleFonts.firaSans(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: _buildStatCard(
                icon: Icons.headphones,
                value: "${monthly['total_minutes'] ?? 0}",
                label: "minutos",
                color: const Color(0xFF4A00E0),
              )),
              const SizedBox(width: 15),
              Expanded(child: _buildStatCard(
                icon: Icons.music_note,
                value: "${monthly['total_plays'] ?? 0}",
                label: "músicas",
                color: const Color(0xFF8E2DE2),
              )),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: _buildStatCard(
                icon: Icons.people,
                value: "${monthly['unique_artists'] ?? 0}",
                label: "artistas",
                color: const Color(0xFFD4AF37),
              )),
              const SizedBox(width: 15),
              Expanded(child: _buildStatCard(
                icon: Icons.category,
                value: "${monthly['unique_genres'] ?? 0}",
                label: "gêneros",
                color: const Color(0xFF00B894),
              )),
            ],
          ),
          
          // Artista Top
          if (monthly['top_artist'] != null && monthly['top_artist'] != "Nenhum") ...[
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Icon(Icons.star, color: Colors.black, size: 30),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Artista do Mês",
                          style: GoogleFonts.firaSans(
                            fontSize: 14,
                            color: Colors.white54,
                          ),
                        ),
                        Text(
                          monthly['top_artist'],
                          style: GoogleFonts.firaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          "${monthly['top_artist_plays'] ?? 0} reproduções",
                          style: GoogleFonts.firaSans(
                            fontSize: 12,
                            color: const Color(0xFFD4AF37),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Top Músicas
          if (topTracks.isNotEmpty) ...[
            const SizedBox(height: 30),
            Text(
              "Mais Tocadas do Mês",
              style: GoogleFonts.firaSans(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            ...topTracks.asMap().entries.map((entry) {
              final index = entry.key;
              final track = entry.value;
              return _buildTrackTile(index + 1, track);
            }),
          ],
          
          // Estatísticas do Ano
          const SizedBox(height: 30),
          Text(
            "Este Ano",
            style: GoogleFonts.firaSans(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                _buildYearStat(Icons.schedule, "${yearly['total_minutes'] ?? 0} minutos", "tempo total"),
                const Divider(color: Colors.white24, height: 30),
                _buildYearStat(Icons.library_music, "${yearly['total_plays'] ?? 0}", "músicas reproduzidas"),
                const Divider(color: Colors.white24, height: 30),
                _buildYearStat(Icons.people_outline, "${yearly['unique_artists'] ?? 0}", "artistas diferentes"),
              ],
            ),
          ),
          
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.firaSans(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.firaSans(
              fontSize: 14,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackTile(int position, Map<String, dynamic> track) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: position <= 3 ? const Color(0xFFD4AF37) : Colors.grey[800],
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Text(
              "$position",
              style: GoogleFonts.firaSans(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: position <= 3 ? Colors.black : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track['display_name'] ?? 'Música',
                  style: GoogleFonts.firaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  track['artist'] ?? 'Artista',
                  style: GoogleFonts.firaSans(
                    fontSize: 12,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          Text(
            "${track['plays']}x",
            style: GoogleFonts.firaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFD4AF37),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearStat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFD4AF37), size: 24),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: GoogleFonts.firaSans(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.firaSans(
                fontSize: 12,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
