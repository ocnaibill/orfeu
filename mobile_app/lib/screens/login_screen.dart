import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isRegistering = false;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController(); // Apenas registro
  final _nameController = TextEditingController(); // Apenas registro

  void _submit() async {
    final auth = ref.read(authProvider.notifier);
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) return;

    bool success;
    if (_isRegistering) {
      final email = _emailController.text.trim();
      final name = _nameController.text.trim();
      success = await auth.register(username, email, password, name);
    } else {
      success = await auth.login(username, password);
    }

    if (!success && mounted) {
      final error = ref.read(authProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error ?? "Erro desconhecido"),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.music_note, size: 80, color: Color(0xFFD4AF37)),
              const SizedBox(height: 20),
              Text(
                "Orfeu",
                style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 40),
              if (_isRegistering) ...[
                _buildTextField(
                    _nameController, "Nome Completo", Icons.person_outline),
                const SizedBox(height: 16),
                _buildTextField(
                    _emailController, "E-mail", Icons.email_outlined),
                const SizedBox(height: 16),
              ],
              _buildTextField(
                  _usernameController, "Usuário", Icons.account_circle),
              const SizedBox(height: 16),
              _buildTextField(_passwordController, "Senha", Icons.lock_outline,
                  isPassword: true),
              const SizedBox(height: 32),
              if (authState.isLoading)
                const CircularProgressIndicator(color: Color(0xFFD4AF37))
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _isRegistering ? "Criar Conta" : "Entrar",
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  setState(() => _isRegistering = !_isRegistering);
                },
                child: Text(
                  _isRegistering
                      ? "Já tem conta? Entre aqui."
                      : "Não tem conta? Registre-se.",
                  style: const TextStyle(color: Colors.white54),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon,
      {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: const Color(0xFFD4AF37)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }
}
