import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// --- Card "Novidades dos seus favoritos" (190x230) ---
class FeatureAlbumCard extends StatelessWidget {
  final String title;
  final String artist;
  final String imageUrl;
  final Color vibrantColor; // Cor extraída da capa (vinda do backend)

  const FeatureAlbumCard({
    super.key,
    required this.title,
    required this.artist,
    required this.imageUrl,
    this.vibrantColor = const Color(0xFF4A00E0), // Cor padrão se não houver
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      height: 230,
      // Clip para arredondar bordas se necessário, ou manter reto conforme design
      child: Column(
        children: [
          // Capa (190x170)
          Container(
            width: 190,
            height: 170,
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Informações com efeito Liquid Glass (190x60)
          Container(
            width: 190,
            height: 60,
            decoration: BoxDecoration(
              // Cor baseada no destaque com 20% opacidade
              color: vibrantColor.withOpacity(0.2),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600, // SemiBold
                    color: Colors.white,
                  ),
                ),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400, // Regular
                    color: Colors.white70, // Levemente mais claro
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Card Padrão (Continue, Recomendados, Trajetória) ---
// Tamanho total estimado: 160 de largura por ~240 de altura (160 img + textos)
class StandardAlbumCard extends StatelessWidget {
  final String title;
  final String artist;
  final String imageUrl;

  const StandardAlbumCard({
    super.key,
    required this.title,
    required this.artist,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      // A altura é dinâmica baseada no conteúdo, mas o container pai limita
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Capa (160x160)
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // Borda suave padrão
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(height: 1), // "1px abaixo"

          // Título
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400, // Regular
              color: Colors.white,
            ),
          ),

          // Artista
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400, // Regular
              color: AppTheme.textGray, // #8D8D93
            ),
          ),
        ],
      ),
    );
  }
}
