// Discord Service - Usa conditional export para selecionar implementação
// Web: stub vazio (discord_service_web.dart)
// Nativo: implementação real (discord_service_native.dart)
export 'discord_service_web.dart'
    if (dart.library.io) 'discord_service_io.dart';
