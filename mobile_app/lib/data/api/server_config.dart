/// Endereço do servidor. Troque no build com
/// `--dart-define=ORFEU_BASE_URL=https://meu-servidor.exemplo`.
class ServerConfig {
  static const String defaultBaseUrl = String.fromEnvironment(
    'ORFEU_BASE_URL',
    defaultValue: 'https://orfeu.ocnaibill.dev',
  );
}
