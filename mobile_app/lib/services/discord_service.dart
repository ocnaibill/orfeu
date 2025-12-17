import 'package:flutter_discord_rpc/flutter_discord_rpc.dart';
import 'dart:io';

class DiscordService {
  static final DiscordService _instance = DiscordService._internal();
  factory DiscordService() => _instance;
  DiscordService._internal();

  // Variável estática para saber se a LIB nativa já carregou (uma vez por app)
  static bool _isPluginInitialized = false;

  // Variável de instância para saber se estamos conectados ao cliente Discord
  bool _isConnected = false;

  final String _appId = '1449808556743200911';

  Future<void> init() async {
    // RPC só funciona em Desktop
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    // Se já estamos conectados, não faz nada
    if (_isConnected) return;

    try {
      // 1. Inicializa a biblioteca nativa (SÓ UMA VEZ)
      if (!_isPluginInitialized) {
        await FlutterDiscordRPC.initialize(_appId);
        _isPluginInitialized = true;
        print("👾 Discord RPC: Lib nativa inicializada.");
      }

      // 2. Conecta ao cliente Discord (Pode ser feito várias vezes)
      FlutterDiscordRPC.instance.connect();
      _isConnected = true;
      print("👾 Discord RPC: Conectado ao cliente.");
    } catch (e) {
      // Se o erro for "já inicializado", ignoramos e seguimos
      if (e.toString().contains("already been initialized")) {
        _isPluginInitialized = true;
        try {
          FlutterDiscordRPC.instance.connect();
          _isConnected = true;
        } catch (_) {}
      } else {
        print("⚠️ Aviso: Falha no Discord RPC: $e");
        if (Platform.isMacOS) {
          print("   DICA (macOS): Verifique o App Sandbox.");
        }
        _isConnected = false;
      }
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
    if (!_isConnected) return;

    try {
      // Retornado para milissegundos conforme versão funcional
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int start = now - position.inMilliseconds;
      final int end = start + duration.inMilliseconds;

      final timestamps = RPCTimestamps(
        start: isPlaying ? start : null,
        end: isPlaying ? end : null,
      );

      // --- LÓGICA DE CAPA ---
      String imageKey = 'logo'; // Fallback padrão

      if (coverUrl != null &&
          coverUrl.isNotEmpty &&
          coverUrl.startsWith('http')) {
        final int len = coverUrl.length;
        // O limite do Discord é 256 bytes para a string da chave
        if (len <= 256) {
          imageKey = coverUrl;
          print("[DiscordRPC] ✅ URL da Capa válida ($len chars): $coverUrl");
        } else {
          print("[DiscordRPC] ⚠️ URL da Capa muito longa ($len > 256 chars).");
          print("[DiscordRPC]    Usando fallback 'logo'.");
        }
      } else {
        print("[DiscordRPC] ℹ️ Nenhuma URL de capa fornecida. Usando logo.");
      }

      final assets = RPCAssets(
        largeImage: imageKey,
        largeText: album,
        smallImage: isPlaying ? 'play_icon' : 'pause_icon',
        smallText: isPlaying ? 'Tocando' : 'Pausado',
      );

      final buttons = [
        RPCButton(label: "Ouvir no Orfeu", url: "https://orfeu.ocnaibill.dev"),
      ];

      FlutterDiscordRPC.instance.setActivity(
        activity: RPCActivity(
          activityType: ActivityType.listening,
          state: artist,
          details: track,
          timestamps: timestamps,
          assets: assets,
          buttons: buttons,
        ),
      );
    } catch (e) {
      print("⚠️ Erro RPC Update: $e");
    }
  }

  void clear() {
    try {
      if (_isConnected) {
        FlutterDiscordRPC.instance.clearActivity();
      }
    } catch (_) {}
  }

  void dispose() {
    // Apenas desconectamos, NÃO desinicializamos a lib nativa
    if (_isConnected) {
      try {
        print("[DiscordRPC] Desconectando (mantendo lib ativa).");
        FlutterDiscordRPC.instance.disconnect();
      } catch (_) {}
      _isConnected = false;
    }
  }
}
