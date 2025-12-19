import 'dart:io' show Platform;

/// Retorna a chave da plataforma para updates
String? getPlatformKey() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return null;
}

bool get isDesktop => 
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

bool get isMobile => 
    Platform.isAndroid || Platform.isIOS;
