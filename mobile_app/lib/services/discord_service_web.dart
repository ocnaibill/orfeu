/// Stub do Discord Service para Web
/// Discord RPC não funciona em browsers
class DiscordService {
  static final DiscordService _instance = DiscordService._internal();
  factory DiscordService() => _instance;
  DiscordService._internal();

  Future<void> init() async {
    print("🌐 Discord RPC: Não disponível na Web");
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
    // No-op na web
  }

  void clear() {}
  void dispose() {}
}
