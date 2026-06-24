import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/config/institution_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_utlva_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../../core/widgets/role_info_card.dart';
import '../../../core/widgets/utlva_footer.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    // On success: GoRouter's refreshListenable fires automatically when
    // AuthProvider calls notifyListeners() — router redirect handles navigation.
    // On failure: show the error snackbar.
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Login failed. Please try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      // CustomUTLVAAppBar on desktop — shows system name + institution name + logo.
      // Hidden on mobile; the stacked intro panel handles branding there.
      appBar: isWide
          ? const CustomUTLVAAppBar(settings: InstitutionSettings.defaults)
          : null,
      backgroundColor: AppColors.background,
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  // ── Desktop: split screen ──────────────────────────────────────────────────

  Widget _buildWideLayout() {
    return Column(
      children: [
        // Split body: intro (left) + form (right)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left — intro panel
              Expanded(
                flex: 5,
                child: Container(
                  color: AppColors.secondary,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 40),
                    child: _buildIntroPanel(isDark: true),
                  ),
                ),
              ),
              // Right — login form
              Expanded(
                flex: 4,
                child: Container(
                  color: AppColors.surface,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: _buildLoginForm(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Branding footer — full width below split
        const UtlvaFooter(),
      ],
    );
  }

  // ── Mobile: stacked ────────────────────────────────────────────────────────

  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stacked branding + intro
          Container(
            color: AppColors.secondary,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
            child: _buildIntroPanel(isDark: true),
          ),
          // Login form
          Padding(
            padding: const EdgeInsets.all(24),
            child: _buildLoginForm(),
          ),
          // Branding footer at the very bottom
          const UtlvaFooter(),
        ],
      ),
    );
  }

  // ── Intro panel ────────────────────────────────────────────────────────────

  Widget _buildIntroPanel({required bool isDark}) {
    final textColor = isDark ? AppColors.textOnPrimary : AppColors.textMain;
    final subTextColor = isDark
        ? AppColors.textOnPrimary.withAlpha(200)
        : AppColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'U',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'UTLVA',
              style: AppTypography.headlineLarge.copyWith(
                color: textColor,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Welcome to University Timetable and Local Venue Arrangement (UTLVA)',
          style: AppTypography.titleLarge.copyWith(color: textColor, height: 1.4),
        ),
        const SizedBox(height: 12),
        Text(
          'A centralized smart campus platform for timetable management, venue coordination, emergency sessions, navigation, and academic communication.',
          style: AppTypography.bodyMedium.copyWith(color: subTextColor, height: 1.6),
        ),
        const SizedBox(height: 28),
        _buildRoleCards(isDark: isDark),
      ],
    );
  }

  Widget _buildRoleCards({required bool isDark}) {
    final cards = [
      (
        Icons.school_outlined,
        'Lecturers',
        'Manage academic sessions, view assigned timetables, confirm teaching sessions, create emergency sessions, and receive important notifications.',
      ),
      (
        Icons.menu_book_outlined,
        'Students',
        'Access personal timetables, receive updates, locate classrooms using campus navigation, and stay informed about academic changes.',
      ),
      (
        Icons.event_note_outlined,
        'Timetable Coordinator',
        'Manage programmes, courses, venues, create and publish timetables, manage scheduling activities, and coordinate academic resources.',
      ),
      (
        Icons.admin_panel_settings_outlined,
        'System Administrator',
        'User management, system configuration, security monitoring, and audit management capabilities.',
      ),
    ];

    return Column(
      children: cards.map((c) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: isDark
              ? _DarkRoleCard(icon: c.$1, title: c.$2, description: c.$3)
              : RoleInfoCard(icon: c.$1, title: c.$2, description: c.$3),
        );
      }).toList(),
    );
  }

  // ── Login form ─────────────────────────────────────────────────────────────

  Widget _buildLoginForm() {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final isLoading = auth.isSubmitting;

        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sign in to your account',
                  style: AppTypography.headlineMedium),
              const SizedBox(height: 6),
              Text('Enter your institution credentials',
                  style: AppTypography.bodySmall),
              const SizedBox(height: 32),

              // Email
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'e.g. student@utlva.ac.tz',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  // Allows multi-part domains: user@domain.ac.tz, user@uni.edu
                  if (!RegExp(r'^[\w.+\-]+@[\w\-]+(\.[\w\-]+)+$')
                      .hasMatch(v.trim())) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => isLoading ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 8) return 'Password must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 8),

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: Text(
                    'Forgot Password?',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.accent,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Sign in button
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: AppColors.textOnPrimary,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('Sign In'),
              ),
              const SizedBox(height: 24),

              // Footer
              Center(
                child: Text(
                  'University Timetable & Local Venue Arrangement\nFor authorized university personnel only',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Dark variant of RoleInfoCard for the blue intro panel
class _DarkRoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _DarkRoleCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.accent.withAlpha(60),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textOnPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textOnPrimary.withAlpha(180),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
