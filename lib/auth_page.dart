// lib/auth_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_page.dart'; // <- your tree shows HomePage here

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _gradientController;
  late final Animation<double> _gradientAnim;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  bool _loading = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _gradientAnim = CurvedAnimation(
      parent: _gradientController,
      curve: Curves.easeInOut,
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _gradientController.dispose();
    _fadeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _toast("Please enter email and password");
      return;
    }

    setState(() => _loading = true);
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast("Something went wrong. Please try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _toast("Please enter email and password");
      return;
    }

    setState(() => _loading = true);
    try {
      await _supabase.auth.signUp(email: email, password: password);

      if (!mounted) return;
      // After sign up, go straight to app (session may or may not be confirmed depending on your project settings)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast("Could not sign up. Please try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF243B55)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Animated BOCK STORE text
                  AnimatedBuilder(
                    animation: _gradientAnim,
                    builder: (context, _) {
                      return ShaderMask(
                        shaderCallback: (bounds) {
                          final v = _gradientAnim.value;
                          return LinearGradient(
                            colors: [
                              Colors.blueAccent,
                              Colors.cyanAccent,
                              Colors.purpleAccent
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: [v, (v + 0.2).clamp(0.0, 1.0), (v + 0.4).clamp(0.0, 1.0)],
                            tileMode: TileMode.mirror,
                          ).createShader(bounds);
                        },
                        child: const Text(
                          "BOCK STORE",
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  // Glass card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 350,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            _field(
                              controller: _emailController,
                              hint: "Email",
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 15),
                            _field(
                              controller: _passwordController,
                              hint: "Password",
                              isPassword: true,
                            ),
                            const SizedBox(height: 20),

                            // Sign In
                            ElevatedButton(
                              onPressed: _loading ? null : _signIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                minimumSize: const Size(double.infinity, 50),
                                elevation: 6,
                                shadowColor: Colors.blueAccent.withOpacity(0.4),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                                  : const Text("Sign In", style: TextStyle(fontSize: 16)),
                            ),

                            const SizedBox(height: 10),

                            // Sign Up
                            OutlinedButton(
                              onPressed: _loading ? null : _signUp,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white70),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: const Text(
                                "Sign Up",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
      autocorrect: false,
      enableSuggestions: !isPassword,
      style: const TextStyle(color: Colors.white),
      onSubmitted: (_) => isPassword ? _signIn() : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
