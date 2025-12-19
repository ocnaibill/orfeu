/// Stub do Discord Service para plataformas que não suportam (Web)
class DiscordService {
  static final DiscordService _instance = DiscordService._internal();
  factory DiscordService() => _instance;
  DiscordService._internal();

  Future<void> init() async {
    // No-op na web
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

  void clear() {
    // No-op na web
  }

  void dispose() {
    // No-op na web
  }
}
