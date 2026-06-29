import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _resetToken; // dev-mode only — shown when email not configured

  @override
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final r = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/forgot-password/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _emailCtrl.text.trim().toLowerCase()}),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final body = jsonDecode(r.body) as Map<String, dynamic>;

      if (r.statusCode == 200) {
        // Dev mode: backend returns the token directly
        final token = body['reset_token'] as String?;
        if (token != null) {
          setState(() => _resetToken = token);
        } else {
          // Production: email sent — tell user to check inbox
          _showSnack(body['message'] ?? 'Reset link sent. Check your email.', success: true);
        }
      } else {
        _showSnack(body['detail'] ?? 'Request failed.', success: false);
      }
    } catch (e) {
      if (mounted) _showSnack('Network error: $e', success: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppColors.statusFree : AppColors.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'Forgot Password'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _resetToken != null ? _buildDevTokenPanel() : _buildRequestForm(),
      ),
    );
  }

  Widget _buildRequestForm() {
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        const Icon(Icons.lock_reset_outlined, size: 56, color: AppColors.primary),
        const SizedBox(height: 20),
        Text('Reset your password', style: AppTypography.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Enter your account email. A reset link will be sent to your inbox.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 28),
        TextFormField(
          controller: _emailCtrl,
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textOnPrimary, strokeWidth: 2))
                : const Text('Send Reset Link'),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => context.pop(),
            child: const Text('Back to Login'),
          ),
        ),
      ]),
    );
  }

  /// Shown in development when email is not configured.
  Widget _buildDevTokenPanel() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.statusInUse.withAlpha(15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.statusInUse.withAlpha(60)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.developer_mode, color: AppColors.statusInUse, size: 18),
            const SizedBox(width: 8),
            Text('Dev Mode — Email Not Configured',
                style: AppTypography.labelLarge.copyWith(color: AppColors.statusInUse)),
          ]),
          const SizedBox(height: 8),
          Text(
            'In production, this token is emailed. During development it is shown here. '
            'Add EMAIL_HOST to .env to send real emails.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text('Reset token:', style: AppTypography.labelMedium),
          const SizedBox(height: 4),
          SelectableText(
            _resetToken!,
            style: AppTypography.bodySmall.copyWith(
              fontFamily: 'monospace', color: AppColors.primary,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.lock_outline),
          label: const Text('Continue to Reset Password'),
          onPressed: () => context.push('/reset-password', extra: _resetToken),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
        ),
      ),
      const SizedBox(height: 12),
      Center(child: TextButton(onPressed: () => context.go('/login'), child: const Text('Back to Login'))),
    ]);
  }
}
