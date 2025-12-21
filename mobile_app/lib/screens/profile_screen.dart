import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../providers.dart';
import 'vibe_musical_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Estados locais para configurações (Simulação de persistência)
  bool _shareHistory = true;
  bool _discordRpc = true;
  String _streamQuality = 'lossless'; // low, medium, high, lossless

  @override
  Widget build(BuildContext context) {
    // Dados do usuário do backend
    final userProfile = ref.watch(userProfileProvider);
    final userName = userProfile.username.isNotEmpty
        ? userProfile.username
        : (ref.watch(authProvider).username ?? "Usuário");
    final userImage = userProfile.avatarUrl;

    // Estatísticas reais do backend
    final profileStats = ref.watch(profileStatsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 45), // Espaço seguro topo

            // --- 0. TOP BAR (Voltar + Logout) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    alignment: Alignment.centerLeft,
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    tooltip: "Sair",
                    onPressed: () {
                      ref.read(authProvider.notifier).logout();
                      Navigator.pop(context); // Fecha a tela atual
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    alignment: Alignment.centerRight,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20), // "20px abaixo do botão de voltar"

            // --- BLOCO TOPO: PERFIL (ESQ) + ESTATÍSTICAS (DIR) ---
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal:
                      33), // "33px de distancia de seus respectivos cantos"
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Alinha pelo topo
                children: [
                  // --- CONTEINER 1: FOTO, NOME, BOTÃO ---
                  Column(
                    crossAxisAlignment: CrossAxisAlignment
                        .center, // Centraliza botão em relação a foto+nome
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              image: DecorationImage(
                                image: NetworkImage(userImage),
                                fit: BoxFit.cover,
                              ),
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(width: 10), // "10px a direita da foto"

                          Text(
                            userName,
                            style: GoogleFonts.firaSans(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10), // "10px abaixo da foto"

                      // Botão Editar Perfil
                      GestureDetector(
                        onTap: () =>
                            _showEditProfileModal(context, ref, userProfile),
                        child: Container(
                          width: 130,
                          height: 35,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9D9D9).withOpacity(0.60),
                            borderRadius: BorderRadius.circular(17.5),
                          ),
                          child: Text(
                            "Editar perfil",
                            style: GoogleFonts.firaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w600, // SemiBold
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // --- CONTEINER 2: ESTATÍSTICAS ---
                  // Usamos Flexible/FittedBox para garantir que caiba em telas estreitas
                  Flexible(
                    child: profileStats.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFD4AF37),
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildStatItem("Playlists",
                                    profileStats.playlistCount.toString()),
                                _buildStatSeparator(),
                                _buildStatItem("Gêneros",
                                    profileStats.genreCount.toString()),
                                _buildStatSeparator(),
                                _buildStatItem("Artistas",
                                    profileStats.artistCount.toString()),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 70), // "70px abaixo"

            // --- 3. CONFIGURAÇÕES ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 33),
              child: Column(
                children: [
                  _buildSettingsTile(
                    label: "Privacidade",
                    onTap: () => _showPrivacyModal(context),
                  ),
                  const SizedBox(height: 15),
                  _buildSettingsTile(
                    label: "Idioma",
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Em breve")));
                    },
                  ),
                  const SizedBox(height: 15),
                  _buildSettingsTile(
                    label: "Qualidade do Streaming",
                    onTap: () => _showQualityModal(context),
                  ),
                  const SizedBox(height: 15),
                  _buildSettingsTile(
                    label: "Downloads",
                    onTap: () => _showDownloadsModal(context),
                  ),
                  const SizedBox(height: 15),
                  // Last.fm Integration
                  Consumer(
                    builder: (context, ref, _) {
                      final lastfmStatus = ref.watch(lastfmStatusProvider);
                      return _buildSettingsTile(
                        label: lastfmStatus.when(
                          data: (status) => status['connected'] == true 
                              ? "Last.fm ✓ ${status['username']}"
                              : "Conectar Last.fm",
                          loading: () => "Last.fm...",
                          error: (_, __) => "Conectar Last.fm",
                        ),
                        onTap: () => _showLastfmModal(context, ref),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 50), // "50px abaixo das opções"

            // --- 4. CARD VIBE MUSICAL ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 33),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const VibeMusicalScreen()));
                },
                child: Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Sua Vibe Musical",
                            style: GoogleFonts.firaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "Ver estatísticas",
                            style: GoogleFonts.firaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.auto_graph,
                          color: Colors.white, size: 40),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 50), // Margem final
          ],
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildStatItem(String label, String count) {
    return Column(
      children: [
        Text(
          count,
          style: GoogleFonts.firaSans(
            fontSize: 24,
            fontWeight: FontWeight.w600, // SemiBold
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.firaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600, // SemiBold
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildStatSeparator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10), // "10 de gap"
      height: 40,
      width: 2,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2), // "Arredondada"
      ),
    );
  }

  Widget _buildSettingsTile(
      {required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50, // Altura estimada para clique confortável
        color: Colors.transparent, // Hitbox
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.firaSans(
                fontSize: 16,
                fontWeight: FontWeight.normal, // Regular
                color: Colors.white,
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  // --- MODAIS ---

  void _showEditProfileModal(
      BuildContext context, WidgetRef ref, UserProfile profile) {
    final fullNameCtrl = TextEditingController(text: profile.fullName);
    final emailCtrl = TextEditingController(text: profile.email);
    final passCtrl = TextEditingController();
    final oldPassCtrl = TextEditingController();

    String? selectedImagePath;
    String? selectedImageBase64;
    String? selectedImageType;
    Uint8List? selectedImageBytes; // Para preview cross-platform
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 20,
                  right: 20,
                  top: 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Editar Perfil",
                        style: GoogleFonts.firaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 20),

                    // --- FOTO DE PERFIL ---
                    Center(
                      child: GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 512,
                            maxHeight: 512,
                            imageQuality: 85,
                          );

                          if (image != null) {
                            final bytes = await image.readAsBytes();
                            final base64 = base64Encode(bytes);
                            final extension =
                                image.path.split('.').last.toLowerCase();

                            String contentType;
                            if (extension == 'gif') {
                              contentType = 'image/gif';
                            } else if (extension == 'png') {
                              contentType = 'image/png';
                            } else if (extension == 'webp') {
                              contentType = 'image/webp';
                            } else {
                              contentType = 'image/jpeg';
                            }

                            setModalState(() {
                              selectedImagePath = image.path;
                              selectedImageBase64 = base64;
                              selectedImageType = contentType;
                              selectedImageBytes = bytes;
                            });
                          }
                        },
                        child: Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[800],
                                image: selectedImageBytes != null
                                    ? DecorationImage(
                                        image: MemoryImage(selectedImageBytes!),
                                        fit: BoxFit.cover,
                                      )
                                    : (profile.profileImageUrl != null &&
                                            profile.profileImageUrl!.isNotEmpty)
                                        ? DecorationImage(
                                            image: NetworkImage(
                                                profile.profileImageUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : DecorationImage(
                                            image:
                                                NetworkImage(profile.avatarUrl),
                                            fit: BoxFit.cover,
                                          ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFD4AF37),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.black, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        "Toque para alterar a foto",
                        style: GoogleFonts.firaSans(
                            fontSize: 12, color: Colors.white54),
                      ),
                    ),

                    const SizedBox(height: 20),
                    // Username (somente leitura)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: TextEditingController(text: profile.username),
                        enabled: false,
                        style: const TextStyle(color: Colors.white54),
                        decoration: const InputDecoration(
                          labelText: "Nome de Usuário",
                          labelStyle: TextStyle(color: Colors.white54),
                          disabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white12)),
                          suffixIcon: Icon(Icons.lock_outline, color: Colors.white24, size: 18),
                        ),
                      ),
                    ),
                    _buildTextField("Nome Completo", fullNameCtrl),
                    _buildTextField("Email", emailCtrl),
                    const Divider(color: Colors.white24, height: 30),
                    Text("Alterar Senha",
                        style: GoogleFonts.firaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 10),
                    _buildTextField("Senha Atual", oldPassCtrl,
                        isPassword: true),
                    _buildTextField("Nova Senha", passCtrl, isPassword: true),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: isUploading
                            ? null
                            : () async {
                                setModalState(() => isUploading = true);

                                try {
                                  final notifier =
                                      ref.read(userProfileProvider.notifier);

                                  // Upload da imagem se foi selecionada
                                  if (selectedImageBase64 != null &&
                                      selectedImageType != null) {
                                    final url =
                                        await notifier.uploadProfileImage(
                                      selectedImageBase64!,
                                      selectedImageType!,
                                    );
                                    if (url == null) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text("Erro ao enviar imagem"),
                                            backgroundColor: Colors.red),
                                      );
                                    }
                                  }

                                  // Atualiza nome, email e senha se foram alterados
                                  final success = await notifier.updateProfile(
                                    fullName:
                                        fullNameCtrl.text != profile.fullName
                                            ? fullNameCtrl.text
                                            : null,
                                    email: emailCtrl.text != profile.email
                                        ? emailCtrl.text
                                        : null,
                                    currentPassword: oldPassCtrl.text.isNotEmpty 
                                        ? oldPassCtrl.text 
                                        : null,
                                    newPassword: passCtrl.text.isNotEmpty 
                                        ? passCtrl.text 
                                        : null,
                                  );

                                  if (success || selectedImageBase64 != null) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text("Perfil atualizado!")),
                                    );
                                  }
                                } finally {
                                  if (mounted)
                                    setModalState(() => isUploading = false);
                                }
                              },
                        child: isUploading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Text("Salvar Alterações"),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool isPassword = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFD4AF37))),
        ),
      ),
    );
  }

  void _showPrivacyModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Privacidade",
                      style: GoogleFonts.firaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: Text("Histórico de Reprodução",
                        style: GoogleFonts.firaSans(color: Colors.white)),
                    subtitle: Text("Usado para retrospectivas e rankings.",
                        style: GoogleFonts.firaSans(
                            color: Colors.white54, fontSize: 12)),
                    activeColor: const Color(0xFFD4AF37),
                    value: _shareHistory,
                    onChanged: (val) {
                      setState(
                          () => _shareHistory = val); // Atualiza tela principal
                      setStateModal(
                          () => _shareHistory = val); // Atualiza modal
                    },
                  ),
                  SwitchListTile(
                    title: Text("Discord Rich Presence",
                        style: GoogleFonts.firaSans(color: Colors.white)),
                    subtitle: Text(
                        "Mostrar o que estou ouvindo no Discord (PC).",
                        style: GoogleFonts.firaSans(
                            color: Colors.white54, fontSize: 12)),
                    activeColor: const Color(0xFFD4AF37),
                    value: _discordRpc,
                    onChanged: (val) {
                      setState(() => _discordRpc = val);
                      setStateModal(() => _discordRpc = val);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showQualityModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Qualidade do Streaming",
                  style: GoogleFonts.firaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 20),
              ...['low', 'medium', 'high', 'lossless'].map((q) {
                return RadioListTile<String>(
                  title: Text(q.toUpperCase(),
                      style: GoogleFonts.firaSans(color: Colors.white)),
                  subtitle: Text(
                      q == 'lossless' ? "Original (FLAC)" : "MP3 (Compressão)",
                      style: GoogleFonts.firaSans(
                          color: Colors.white54, fontSize: 12)),
                  activeColor: const Color(0xFFD4AF37),
                  value: q,
                  groupValue: _streamQuality,
                  onChanged: (val) {
                    setState(() => _streamQuality = val!);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showDownloadsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final spaceAsync = ref.watch(downloadedSpaceProvider);
            final tracksAsync = ref.watch(downloadedTracksProvider);
            
            String formatBytes(int bytes) {
              if (bytes < 1024) return '$bytes B';
              if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
              if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
              return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
            }
            
            return Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Downloads",
                      style: GoogleFonts.firaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(Icons.sd_storage, color: Colors.white),
                    title: Text("Armazenamento Usado",
                        style: GoogleFonts.firaSans(color: Colors.white)),
                    trailing: spaceAsync.when(
                      data: (bytes) => Text(formatBytes(bytes),
                          style: GoogleFonts.firaSans(color: Colors.white54)),
                      loading: () => const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
                      ),
                      error: (_, __) => Text("Erro",
                          style: GoogleFonts.firaSans(color: Colors.redAccent)),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.music_note, color: Colors.white),
                    title: Text("Músicas Baixadas",
                        style: GoogleFonts.firaSans(color: Colors.white)),
                    trailing: tracksAsync.when(
                      data: (tracks) => Text("${tracks.length}",
                          style: GoogleFonts.firaSans(color: Colors.white54)),
                      loading: () => const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
                      ),
                      error: (_, __) => Text("0",
                          style: GoogleFonts.firaSans(color: Colors.white54)),
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: Text("Apagar todos os downloads",
                        style: GoogleFonts.firaSans(color: Colors.redAccent)),
                    onTap: () async {
                      Navigator.pop(context);
                      final downloadManager = ref.read(downloadManagerProvider);
                      await downloadManager.clearAllDownloads();
                      ref.invalidate(downloadedTracksProvider);
                      ref.invalidate(downloadedSpaceProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Downloads limpos!"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLastfmModal(BuildContext context, WidgetRef ref) {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool isLoading = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final lastfmStatus = ref.watch(lastfmStatusProvider);
            
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 20,
                  right: 20,
                  top: 20),
              child: lastfmStatus.when(
                data: (status) {
                  // Se já conectado, mostra opção de desconectar
                  if (status['connected'] == true) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD51007),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.music_note, color: Colors.white, size: 30),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Last.fm Conectado",
                                      style: GoogleFonts.firaSans(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                  Text("@${status['username']}",
                                      style: GoogleFonts.firaSans(
                                          fontSize: 14,
                                          color: Colors.white54)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "Suas músicas serão enviadas automaticamente para o Last.fm enquanto você ouve.",
                          style: GoogleFonts.firaSans(color: Colors.white70),
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[900],
                              foregroundColor: Colors.white,
                            ),
                            onPressed: isLoading ? null : () async {
                              setModalState(() => isLoading = true);
                              final success = await ref.read(lastfmAuthProvider.notifier).disconnect();
                              if (success) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Last.fm desconectado")),
                                );
                              }
                              setModalState(() => isLoading = false);
                            },
                            child: isLoading
                                ? const SizedBox(
                                    height: 20, width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text("Desconectar"),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    );
                  }
                  
                  // Formulário de login
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD51007),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.music_note, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 15),
                          Text("Conectar Last.fm",
                              style: GoogleFonts.firaSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Text(
                        "Envie automaticamente suas músicas para o Last.fm e acompanhe seu histórico de scrobbles.",
                        style: GoogleFonts.firaSans(color: Colors.white70),
                      ),
                      const SizedBox(height: 20),
                      if (errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(
                            color: Colors.red[900]!.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(errorMessage!, style: GoogleFonts.firaSans(color: Colors.red[200])),
                        ),
                      TextField(
                        controller: usernameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: "Usuário Last.fm",
                          labelStyle: TextStyle(color: Colors.white54),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFD51007))),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: "Senha",
                          labelStyle: TextStyle(color: Colors.white54),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFD51007))),
                        ),
                      ),
                      const SizedBox(height: 25),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD51007),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: isLoading ? null : () async {
                            if (usernameCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
                              setModalState(() => errorMessage = "Preencha todos os campos");
                              return;
                            }
                            
                            setModalState(() {
                              isLoading = true;
                              errorMessage = null;
                            });
                            
                            final result = await ref.read(lastfmAuthProvider.notifier)
                                .authenticate(usernameCtrl.text, passwordCtrl.text);
                            
                            if (result != null) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result['message'] ?? "Last.fm conectado!")),
                              );
                            } else {
                              setModalState(() {
                                isLoading = false;
                                errorMessage = "Usuário ou senha inválidos";
                              });
                            }
                          },
                          child: isLoading
                              ? const SizedBox(
                                  height: 20, width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text("Conectar"),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFFD51007)),
                  ),
                ),
                error: (_, __) => const Text("Erro ao carregar status", style: TextStyle(color: Colors.red)),
              ),
            );
          },
        );
      },
    );
  }
}
