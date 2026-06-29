import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? prefillToken;
  const ResetPasswordScreen({super.key, this.prefillToken});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tokenCtrl;
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading  = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void initState() {
    super.initState();
    _tokenCtrl = TextEditingController(text: widget.prefillToken ?? '');
  }

  @override
  void dispose() { _tokenCtrl.dispose(); _passCtrl.dispose(); _confirmCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final r = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/reset-password/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': _tokenCtrl.text.trim(), 'password': _passCtrl.text}),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final body = jsonDecode(r.body) as Map<String, dynamic>;

      if (r.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(body['message'] ?? 'Password reset successfully.'),
          backgroundColor: AppColors.statusFree,
        ));
        context.go('/login');
      } else {
        final detail = body['detail'];
        final msg = detail is List ? detail.join('\n') : '$detail';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: AppColors.error,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'Reset Password'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 12),
            const Icon(Icons.lock_outline, size: 56, color: AppColors.primary),
            const SizedBox(height: 20),
            Text('Set a new password', style: AppTypography.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Enter your reset token and choose a new password.',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'Reset Token',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Token is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passCtrl,
              decoration: InputDecoration(
                labelText: 'New Password (min 8 chars)',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscure1 ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _obscure1 = !_obscure1),
                ),
              ),
              obscureText: _obscure1,
              validator: (v) => (v == null || v.length < 8) ? 'Minimum 8 characters' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmCtrl,
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _obscure2 = !_obscure2),
                ),
              ),
              obscureText: _obscure2,
              validator: (v) => v != _passCtrl.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textOnPrimary, strokeWidth: 2))
                    : const Text('Reset Password'),
              ),
            ),
            const SizedBox(height: 12),
            Center(child: TextButton(onPressed: () => context.go('/login'), child: const Text('Back to Login'))),
          ]),
        ),
      ),
    );
  }
}
