/// Discord Service - Exporta a implementação correta baseado na plataforma
///
/// Na Web: usa stub (no-op)
/// Em outras plataformas: usa implementação nativa com flutter_discord_rpc
export 'discord_service_stub.dart'
    if (dart.library.io) 'discord_service_native.dart';
