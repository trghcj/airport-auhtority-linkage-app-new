import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart'; // Ensure this is imported

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _logger = Logger(); // Initialize Logger instance

  User? get user => _auth.currentUser;

  bool isLoading = false;
  String? error;

  void _setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void _setError(String? msg) {
    error = msg;
    notifyListeners();
  }

  /// Sign up with email and password
  Future<bool> signUpWithEmail(String email, String password) async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Attempting signup with email: $email');
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _logger.i('Signup successful: ${userCredential.user?.uid}');
      return true;
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'The email is already registered.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email format.';
          break;
        case 'weak-password':
          errorMessage = 'Password is too weak.';
          break;
        default:
          errorMessage = e.message ?? 'Signup failed.';
      }
      _logger.e('Signup error: $errorMessage (Code: ${e.code})');
      _setError(errorMessage);
      return false;
    } catch (e) {
      _logger.e('Unexpected signup error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Login with email and password
  Future<bool> loginWithEmail(String email, String password) async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Attempting login with email: $email');
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _logger.i('Login successful: ${userCredential.user?.uid}');
      return true;
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'invalid-email':
          errorMessage = 'Invalid email format.';
          break;
        case 'user-not-found':
          errorMessage = 'User not found.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password.';
          break;
        case 'user-disabled':
          errorMessage = 'User is disabled.';
          break;
        default:
          errorMessage = e.message ?? 'Login failed.';
      }
      _logger.e('Login error: $errorMessage (Code: ${e.code})');
      _setError(errorMessage);
      return false;
    } catch (e) {
      _logger.e('Unexpected login error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Google Sign-In
  Future<bool> signInWithGoogle() async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Starting Google Sign-In');
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        _logger.d('Google Sign-In aborted by user');
        _setError('Google Sign-In aborted');
        return false;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      _logger.i('Google Sign-In successful: ${userCredential.user?.uid}');
      return true;
    } catch (e) {
      _logger.e('Google Sign-In error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Send OTP for phone authentication
  Future<void> sendOTP(
    String phoneNumber,
    Function(String verificationId) onCodeSent,
    Function(String error) onError,
  ) async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Sending OTP to phone number: $phoneNumber');
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          _logger.d('Phone auto-verification completed');
          UserCredential userCredential = await _auth.signInWithCredential(credential);
          _logger.i('Phone auto-login successful: ${userCredential.user?.uid}');
        },
        verificationFailed: (FirebaseAuthException e) {
          String errorMessage = e.message ?? 'Phone verification failed.';
          _logger.e('Phone verification failed: $errorMessage (Code: ${e.code})');
          _setError(errorMessage);
          onError(errorMessage);
        },
        codeSent: (String verificationId, int? resendToken) {
          _logger.d('OTP sent successfully, verificationId: $verificationId');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _logger.d('Auto-retrieval timeout for verificationId: $verificationId');
        },
      );
    } catch (e) {
      _logger.e('Unexpected error sending OTP: $e');
      _setError(e.toString());
      onError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Verify OTP
  Future<bool> verifyOTP(String verificationId, String smsCode) async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Verifying OTP with verificationId: $verificationId, smsCode: $smsCode');
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      _logger.i('OTP verification successful: ${userCredential.user?.uid}');
      return true;
    } catch (e) {
      _logger.e('OTP verification error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Sign in with Phone (interactive prompt)
  Future<bool> signInWithPhone(String phone, BuildContext context) async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Starting phone authentication for: $phone');

      String? smsCode;
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          _logger.d('Phone auto-verification completed');
          UserCredential userCredential = await _auth.signInWithCredential(credential);
          _logger.i('Phone auto-login successful: ${userCredential.user?.uid}');
        },
        verificationFailed: (FirebaseAuthException e) {
          String errorMessage = e.message ?? 'Phone verification failed.';
          _logger.e('Phone verification failed: $errorMessage (Code: ${e.code})');
          _setError(errorMessage);
        },
        codeSent: (String verificationId, int? resendToken) async {
          _logger.d('OTP sent for verificationId: $verificationId');
          smsCode = await _showOTPDialog(context);
          if (smsCode != null) {
            _logger.d('Verifying OTP: $smsCode');
            final credential = PhoneAuthProvider.credential(
              verificationId: verificationId,
              smsCode: smsCode!,
            );
            UserCredential userCredential = await _auth.signInWithCredential(credential);
            _logger.i('Phone login successful: ${userCredential.user?.uid}');
          } else {
            _logger.d('OTP dialog cancelled or no code entered');
            _setError('No OTP entered');
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _logger.d('Auto-retrieval timeout for verificationId: $verificationId');
        },
      );

      bool success = user != null;
      _logger.d('Phone authentication result: $success');
      return success;
    } catch (e) {
      _logger.e('Unexpected phone authentication error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Show OTP dialog
  Future<String?> _showOTPDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Enter OTP"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: "6-digit code"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Verify"),
          ),
        ],
      ),
    );
  }

  /// Sign out
  Future<void> logout() async {
    try {
      _logger.d('Signing out user');
      await _auth.signOut();
      _logger.i('Sign out successful');
      _setError(null);
      notifyListeners();
    } catch (e) {
      _logger.e('Sign out error: $e');
      _setError(e.toString());
    }
  }
}