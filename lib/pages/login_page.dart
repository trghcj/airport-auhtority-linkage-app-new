import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:airport_auhtority_linkage_app/pages/signup_page.dart';
import 'package:airport_auhtority_linkage_app/providers/auth_provider.dart';
import 'package:logger/logger.dart'; // Ensure this is imported

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  final Logger _logger = Logger(); // Initialize Logger instance

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError("Please enter both email and password");
      return;
    }

    _logger.d('Login button pressed: email=$email, password=$password');
    setState(() => _isLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.loginWithEmail(email, password);

      if (!mounted) return;

      if (success) {
        _logger.i('Login successful, navigating to dashboard');
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        _showError(authProvider.error ?? "Login failed");
      }
    } catch (e) {
      _logger.e('Unexpected login error: $e');
      _showError("An error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;

    _logger.d('Google Sign-In button pressed');
    setState(() => _isLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.signInWithGoogle();

      if (!mounted) return;

      if (success) {
        _logger.i('Google Sign-In successful, navigating to dashboard');
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        _showError(authProvider.error ?? "Google Sign-In failed");
      }
    } catch (e) {
      _logger.e('Unexpected Google Sign-In error: $e');
      _showError("An error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePhoneSignIn() async {
    if (_isLoading) return;

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError("Please enter a phone number");
      return;
    }
    if (!phone.startsWith('+')) {
      _showError("Phone number must include country code (e.g., +91)");
      return;
    }

    _logger.d('Phone Sign-In button pressed: phone=$phone');
    setState(() => _isLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.signInWithPhone(phone, context);

      if (!mounted) return;

      if (success) {
        _logger.i('Phone Sign-In successful, navigating to dashboard');
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        _showError(authProvider.error ?? "Phone Sign-In failed");
      }
    } catch (e) {
      _logger.e('Unexpected phone Sign-In error: $e');
      _showError("An error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/airplane.webp',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Center(child: Text('Background image not found')),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: const SizedBox(),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Welcome to",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "AIRPORT AUTHORITY OF INDIA ",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Login",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        errorText: null,
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Password",
                        errorText: null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: "Phone Number (e.g., +91xxxxxxxxxx)",
                        errorText: null,
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Login"),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                      icon: const Icon(Icons.login),
                      label: const Text("Sign in with Google"),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handlePhoneSignIn,
                      icon: const Icon(Icons.phone_android),
                      label: const Text("Sign in with Phone OTP"),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        _logger.d('Navigating to SignupPage');
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignupPage()),
                        );
                      },
                      child: const Text("Don't have an account? Sign up"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}