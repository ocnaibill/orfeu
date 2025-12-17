import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import '../services/discord_service.dart';

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
    // Dados do usuário (do AuthProvider)
    final authState = ref.watch(authProvider);
    final userName = authState.username ?? "Usuário";
    final userImage = "https://ui-avatars.com/api/?name=${Uri.encodeComponent(userName)}&background=D4AF37&color=000&size=300";

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
              padding: const EdgeInsets.symmetric(horizontal: 33), // "33px de distancia de seus respectivos cantos"
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start, // Alinha pelo topo
                children: [
                  // --- CONTEINER 1: FOTO, NOME, BOTÃO ---
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center, // Centraliza botão em relação a foto+nome
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
                        onTap: () => _showEditProfileModal(context, userName),
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
                              _buildStatItem("Playlists", profileStats.playlistCount.toString()),
                              _buildStatSeparator(),
                              _buildStatItem("Gêneros", profileStats.genreCount.toString()),
                              _buildStatSeparator(),
                              _buildStatItem("Artistas", profileStats.artistCount.toString()),
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Em breve")));
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
                ],
              ),
            ),

            const SizedBox(height: 50), // "50px abaixo das opções"

            // --- 4. CARD VIBE MUSICAL ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 33),
              child: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Calculando sua vibe...")));
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
                      const Icon(Icons.auto_graph, color: Colors.white, size: 40),
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

  Widget _buildSettingsTile({required String label, required VoidCallback onTap}) {
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

  void _showEditProfileModal(BuildContext context, String currentName) {
    final nameCtrl = TextEditingController(text: currentName);
    final emailCtrl = TextEditingController(text: "usuario@email.com"); // Mock
    final passCtrl = TextEditingController();
    final oldPassCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Editar Perfil", style: GoogleFonts.firaSans(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              _buildTextField("Nome de Exibição", nameCtrl),
              _buildTextField("Email", emailCtrl),
              const Divider(color: Colors.white24, height: 30),
              Text("Alterar Senha", style: GoogleFonts.firaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 10),
              _buildTextField("Senha Atual", oldPassCtrl, isPassword: true),
              _buildTextField("Nova Senha", passCtrl, isPassword: true),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    // Implementar lógica de update no AuthController
                    Navigator.pop(context);
                  },
                  child: const Text("Salvar Alterações"),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isPassword = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD4AF37))),
        ),
      ),
    );
  }

  void _showPrivacyModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Privacidade", style: GoogleFonts.firaSans(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: Text("Histórico de Reprodução", style: GoogleFonts.firaSans(color: Colors.white)),
                    subtitle: Text("Usado para retrospectivas e rankings.", style: GoogleFonts.firaSans(color: Colors.white54, fontSize: 12)),
                    activeColor: const Color(0xFFD4AF37),
                    value: _shareHistory,
                    onChanged: (val) {
                      setState(() => _shareHistory = val); // Atualiza tela principal
                      setStateModal(() => _shareHistory = val); // Atualiza modal
                    },
                  ),
                  SwitchListTile(
                    title: Text("Discord Rich Presence", style: GoogleFonts.firaSans(color: Colors.white)),
                    subtitle: Text("Mostrar o que estou ouvindo no Discord (PC).", style: GoogleFonts.firaSans(color: Colors.white54, fontSize: 12)),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Qualidade do Streaming", style: GoogleFonts.firaSans(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              ...['low', 'medium', 'high', 'lossless'].map((q) {
                return RadioListTile<String>(
                  title: Text(q.toUpperCase(), style: GoogleFonts.firaSans(color: Colors.white)),
                  subtitle: Text(
                    q == 'lossless' ? "Original (FLAC)" : "MP3 (Compressão)", 
                    style: GoogleFonts.firaSans(color: Colors.white54, fontSize: 12)
                  ),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Downloads", style: GoogleFonts.firaSans(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.sd_storage, color: Colors.white),
                title: Text("Armazenamento Usado", style: GoogleFonts.firaSans(color: Colors.white)),
                trailing: Text("1.2 GB", style: GoogleFonts.firaSans(color: Colors.white54)),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text("Apagar todos os downloads", style: GoogleFonts.firaSans(color: Colors.redAccent)),
                onTap: () {
                  // Lógica futura de limpeza
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Downloads limpos (Simulação)")));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}