import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:version/version.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers.dart';

class UpdateInfo {
  final Version latestVersion;
  final String releaseNotes;
  final String downloadUrl;

  UpdateInfo(
      {required this.latestVersion,
      required this.releaseNotes,
      required this.downloadUrl});
}

final updateServiceProvider = Provider((ref) => UpdateService(ref));

class UpdateService {
  final Ref ref;
  UpdateService(this.ref);

  /// Verifica se há atualização disponível
  Future<UpdateInfo?> checkForUpdate() async {
    final dio = ref.read(dioProvider);

    late PackageInfo packageInfo;
    try {
      packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      print("❌ [UpdateService] Falha ao obter package info: $e");
      return null;
    }

    // Derminar a plataforma
    String platformKey;
    if (Platform.isAndroid) {
      platformKey = 'android';
    } else if (Platform.isWindows) {
      platformKey = 'windows';
    } else if (Platform.isMacOS) {
      platformKey = 'macos';
    } else {
      return null; // Não suporta esta plataforma ou é iOS/Web
    }

    try {
      final response = await dio.get('/app/latest_version');
      final config = response.data as Map<String, dynamic>;

      final latestVersionString = config['latest_version'] as String;
      final latestVersion = Version.parse(latestVersionString);

      final currentVersion = Version.parse(packageInfo.version);

      print(
          "🚀 [UpdateService] Versão Local: $currentVersion, Versão Remota: $latestVersion");

      if (latestVersion > currentVersion) {
        final platformConfig =
            config['platforms'][platformKey] as Map<String, dynamic>?;

        if (platformConfig != null && platformConfig.containsKey('url')) {
          return UpdateInfo(
            latestVersion: latestVersion,
            releaseNotes: config['release_notes_pt'] as String? ??
                'Nova versão disponível.',
            downloadUrl: platformConfig['url'] as String,
          );
        }
      }
    } on DioException catch (e) {
      print("❌ Erro ao buscar updates: ${e.message}");
    } catch (e) {
      print("❌ Erro de parse/comparação: $e");
    }

    return null; // Nenhuma atualização ou falha
  }

  /// Abre o link de download no navegador
  Future<bool> openDownloadPage(String? url) async {
    // Se não tem URL específica, usa a rota /latest que detecta o SO
    final downloadUrl = url ?? 'https://orfeu.ocnaibill.dev/latest';
    
    try {
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        print("❌ [UpdateService] Não foi possível abrir: $downloadUrl");
        return false;
      }
    } catch (e) {
      print("❌ [UpdateService] Erro ao abrir URL: $e");
      return false;
    }
  }
}
