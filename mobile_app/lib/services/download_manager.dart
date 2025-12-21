import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../providers.dart';

/// Gerencia downloads de músicas para uso offline.
/// Armazena arquivos na pasta do aplicativo e mantém metadados em JSON.
class DownloadManager {
  static const String _tracksDir = 'offline_tracks';
  static const String _metadataFile = 'downloads_metadata.json';
  
  final Ref ref;
  
  DownloadManager(this.ref);
  
  /// Obtém o diretório base de downloads
  Future<Directory> get _downloadDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_tracksDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
  
  /// Obtém o arquivo de metadados
  Future<File> get _metadataPath async {
    final dir = await _downloadDir;
    return File('${dir.path}/$_metadataFile');
  }
  
  /// Carrega metadados de downloads
  Future<List<Map<String, dynamic>>> loadMetadata() async {
    try {
      final file = await _metadataPath;
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> data = jsonDecode(content);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('⚠️ Erro ao carregar metadados de downloads: $e');
    }
    return [];
  }
  
  /// Salva metadados de downloads
  Future<void> _saveMetadata(List<Map<String, dynamic>> tracks) async {
    try {
      final file = await _metadataPath;
      await file.writeAsString(jsonEncode(tracks));
    } catch (e) {
      print('❌ Erro ao salvar metadados: $e');
    }
  }
  
  /// Verifica se uma track está baixada
  Future<bool> isDownloaded(String filename) async {
    final metadata = await loadMetadata();
    return metadata.any((t) => t['filename'] == filename || t['localPath'] != null);
  }
  
  /// Obtém o caminho local de uma track baixada
  Future<String?> getLocalPath(String filename) async {
    final metadata = await loadMetadata();
    final track = metadata.firstWhere(
      (t) => t['filename'] == filename,
      orElse: () => {},
    );
    final localPath = track['localPath'] as String?;
    if (localPath != null && await File(localPath).exists()) {
      return localPath;
    }
    return null;
  }
  
  /// Baixa uma track para armazenamento offline
  /// Retorna o caminho local do arquivo ou null em caso de erro
  Future<String?> downloadTrack(
    Map<String, dynamic> track, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dio = ref.read(dioProvider);
      final filename = track['filename'] as String?;
      
      if (filename == null || filename.isEmpty) {
        print('❌ Track sem filename, não pode baixar');
        return null;
      }
      
      // Verifica se já está baixada
      final existingPath = await getLocalPath(filename);
      if (existingPath != null) {
        print('✅ Track já baixada: $filename');
        return existingPath;
      }
      
      // Obtém URL do stream
      final encodedFilename = Uri.encodeComponent(filename);
      final streamUrl = '$baseUrl/stream?filename=$encodedFilename';
      
      // Define caminho local
      final dir = await _downloadDir;
      final safeFilename = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final localPath = '${dir.path}/$safeFilename';
      
      print('📥 Baixando: $filename');
      
      // Baixa o arquivo
      await dio.download(
        streamUrl,
        localPath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );
      
      // Adiciona aos metadados
      final metadata = await loadMetadata();
      metadata.add({
        'filename': filename,
        'localPath': localPath,
        'trackName': track['trackName'] ?? track['title'] ?? 'Música',
        'artistName': track['artistName'] ?? track['artist'] ?? 'Artista',
        'albumName': track['collectionName'] ?? track['album'] ?? '',
        'artworkUrl': track['artworkUrl'] ?? track['imageUrl'] ?? '',
        'durationMs': track['durationMs'] ?? 0,
        'downloadedAt': DateTime.now().toIso8601String(),
      });
      await _saveMetadata(metadata);
      
      print('✅ Download concluído: $filename');
      return localPath;
      
    } catch (e) {
      print('❌ Erro ao baixar track: $e');
      return null;
    }
  }
  
  /// Remove uma track baixada
  Future<bool> deleteDownload(String filename) async {
    try {
      final metadata = await loadMetadata();
      final index = metadata.indexWhere((t) => t['filename'] == filename);
      
      if (index == -1) return false;
      
      final track = metadata[index];
      final localPath = track['localPath'] as String?;
      
      // Remove o arquivo
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      // Remove dos metadados
      metadata.removeAt(index);
      await _saveMetadata(metadata);
      
      print('🗑️ Download removido: $filename');
      return true;
      
    } catch (e) {
      print('❌ Erro ao remover download: $e');
      return false;
    }
  }
  
  /// Obtém lista de todas as tracks baixadas
  Future<List<Map<String, dynamic>>> getDownloadedTracks() async {
    return await loadMetadata();
  }
  
  /// Calcula o espaço usado por downloads (em bytes)
  Future<int> getUsedSpace() async {
    try {
      final dir = await _downloadDir;
      int totalSize = 0;
      
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      
      return totalSize;
    } catch (e) {
      return 0;
    }
  }
  
  /// Limpa todos os downloads
  Future<void> clearAllDownloads() async {
    try {
      final dir = await _downloadDir;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(); // Recria vazia
      }
      await _saveMetadata([]);
      print('🗑️ Todos os downloads removidos');
    } catch (e) {
      print('❌ Erro ao limpar downloads: $e');
    }
  }
}

// ===================================================================
// PROVIDERS
// ===================================================================

/// Provider para o DownloadManager
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  return DownloadManager(ref);
});

/// Provider para lista de tracks baixadas (recarrega automaticamente)
final downloadedTracksProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final manager = ref.read(downloadManagerProvider);
  return manager.getDownloadedTracks();
});

/// Provider para espaço usado por downloads
final downloadedSpaceProvider = FutureProvider<int>((ref) async {
  final manager = ref.read(downloadManagerProvider);
  return manager.getUsedSpace();
});

/// State para progresso de download atual
class DownloadProgress {
  final String? filename;
  final double progress;
  final bool isDownloading;
  
  const DownloadProgress({
    this.filename,
    this.progress = 0,
    this.isDownloading = false,
  });
  
  DownloadProgress copyWith({String? filename, double? progress, bool? isDownloading}) {
    return DownloadProgress(
      filename: filename ?? this.filename,
      progress: progress ?? this.progress,
      isDownloading: isDownloading ?? this.isDownloading,
    );
  }
}

class DownloadProgressNotifier extends StateNotifier<DownloadProgress> {
  final Ref ref;
  
  DownloadProgressNotifier(this.ref) : super(const DownloadProgress());
  
  /// Inicia download de uma track
  Future<String?> downloadTrack(Map<String, dynamic> track) async {
    final filename = track['filename'] as String? ?? track['trackName'] ?? 'track';
    
    state = DownloadProgress(
      filename: filename,
      progress: 0,
      isDownloading: true,
    );
    
    final manager = ref.read(downloadManagerProvider);
    final result = await manager.downloadTrack(
      track,
      onProgress: (progress) {
        state = state.copyWith(progress: progress);
      },
    );
    
    state = const DownloadProgress(); // Reset
    
    // Invalida a lista de downloads para recarregar
    ref.invalidate(downloadedTracksProvider);
    ref.invalidate(downloadedSpaceProvider);
    
    return result;
  }
  
  /// Remove um download
  Future<bool> deleteDownload(String filename) async {
    final manager = ref.read(downloadManagerProvider);
    final result = await manager.deleteDownload(filename);
    
    if (result) {
      ref.invalidate(downloadedTracksProvider);
      ref.invalidate(downloadedSpaceProvider);
    }
    
    return result;
  }
}

final downloadProgressProvider = StateNotifierProvider<DownloadProgressNotifier, DownloadProgress>((ref) {
  return DownloadProgressNotifier(ref);
});
