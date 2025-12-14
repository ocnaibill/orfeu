import 'package:flutter_discord_rpc/flutter_discord_rpc.dart';
import 'dart:io';

class DiscordService {
  static final DiscordService _instance = DiscordService._internal();
  factory DiscordService() => _instance;
  DiscordService._internal();

  bool _isInitialized = false;

  // Substitua pelo SEU Application ID REAL
  final String _appId = '1449808556743200911'; 

  // Mudamos para Future<void> e async para poder usar await
  Future<void> init() async {
    // RPC só funciona em Desktop
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    
    if (_isInitialized) return;

    try {
      // CORREÇÃO CRÍTICA: Esperar a inicialização do Rust antes de conectar
      await FlutterDiscordRPC.initialize(_appId);
      
      // Conecta ao cliente Discord (O Discord Desktop PRECISA estar aberto no PC)
      FlutterDiscordRPC.instance.connect();
      
      _isInitialized = true;
      print("👾 Discord RPC Iniciado (Modo Moderno - Com Botões!)");
      
    } catch (e) {
      print("⚠️ Aviso: Falha ao iniciar Discord RPC: $e");
      if (Platform.isWindows) {
        print("   DICA: Verifique se o aplicativo Discord está aberto e logado.");
      }
      _isInitialized = false;
    }
  }

  void updateActivity({
    required String track,
    required String artist,
    required String album,
    required Duration duration,
    required Duration position,
    required bool isPlaying,
    String? coverUrl,
  }) {
    if (!_isInitialized) return;

    try {
      final int now = DateTime.now().millisecondsSinceEpoch;
      
      final int start = now - position.inMilliseconds;
      final int end = start + duration.inMilliseconds;

      // --- DEBUG LOGGING ---
      print("--------------------------------------------------");
      print("[DiscordRPC] Atualizando Presença:");
      print("   🎵 Track: $track");
      print("   👤 Artist: $artist");
      print("   💿 Album: $album");
      print("   ▶️ Status: ${isPlaying ? 'Tocando' : 'Pausado'}");
      print("   ⏱️ Duration: ${duration.inSeconds}s | Position: ${position.inSeconds}s");
      print("   🔢 Timestamps: Start=$start | End=$end");
      print("--------------------------------------------------");

      final timestamps = RPCTimestamps(
        start: isPlaying ? start : null,
        end: isPlaying ? end : null,
      );

      final assets = RPCAssets(
        largeImage: 'logo', 
        largeText: album,   
        smallImage: isPlaying ? 'play_icon' : 'pause_icon', 
        smallText: isPlaying ? 'Tocando' : 'Pausado',
      );
      
      final buttons = [
        RPCButton(
          label: "Ouvir no Orfeu", 
          url: "https://orfeu.ocnaibill.dev"
        ),
      ];

      FlutterDiscordRPC.instance.setActivity(
        activity: RPCActivity(
          // CORREÇÃO: O parâmetro correto é activityType
          activityType: ActivityType.listening, 
          // REMOVIDO O PREFIXO "Artista: "
          state: artist,
          details: track,
          timestamps: timestamps,
          assets: assets,
          buttons: buttons,
        ),
      );
    } catch (e) {
      print("⚠️ Erro RPC: $e");
    }
  }

  void clear() {
    try {
      print("[DiscordRPC] Limpando atividade.");
      if (_isInitialized) FlutterDiscordRPC.instance.clearActivity();
    } catch (_) {}
  }

  void dispose() {
    if (_isInitialized) {
        try {
          print("[DiscordRPC] Desconectando.");
          FlutterDiscordRPC.instance.disconnect();
        } catch (_) {}
        _isInitialized = false;
    }
  }
}