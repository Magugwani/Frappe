import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/admin_user.dart';
import '../services/user_management_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _service = UserManagementService();
  List<AdminUser> _users = [];
  bool _loading = false;
  String? _roleFilter;
  bool? _activeFilter;
  final _searchCtrl = TextEditingController();

  static const _roles = [
    ('All Roles', null),
    ('Admin', 'SYSTEM_ADMIN'),
    ('Coordinator', 'COORDINATOR'),
    ('Lecturer', 'LECTURER'),
    ('Student', 'STUDENT'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _service.getUsers(
        role: _roleFilter,
        isActive: _activeFilter,
        search: _searchCtrl.text.trim(),
      );
      if (mounted) setState(() => _users = users);
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _roleColor(String role) => switch (role) {
        'SYSTEM_ADMIN' => AppColors.error,
        'COORDINATOR' => AppColors.accent,
        'LECTURER' => AppColors.primary,
        _ => AppColors.statusBooked,
      };

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthProvider>().user;
    final isAdmin = authUser?.role == 'SYSTEM_ADMIN';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'User Management',
        extraActions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined,
                color: AppColors.textOnPrimary),
            tooltip: 'Bulk Enroll',
            onPressed: () => context.push('/admin/bulk-enroll'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add_outlined, color: AppColors.textOnPrimary),
        label: const Text('New User', style: TextStyle(color: AppColors.textOnPrimary)),
        onPressed: () => _showUserForm(context, isAdmin: isAdmin),
      ),
      body: Column(children: [
        _buildFilterBar(),
        const Divider(height: 1),
        Expanded(child: _buildBody(isAdmin)),
      ]),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search name or email…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => _searchCtrl.clear())
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            filled: true, fillColor: AppColors.background,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ..._roles.map((r) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(r.$1, style: AppTypography.labelMedium.copyWith(
                  color: _roleFilter == r.$2 ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: _roleFilter == r.$2 ? FontWeight.w700 : FontWeight.normal,
                )),
                selected: _roleFilter == r.$2,
                onSelected: (_) { setState(() => _roleFilter = r.$2); _load(); },
                selectedColor: AppColors.primary.withAlpha(20),
                side: BorderSide(color: _roleFilter == r.$2 ? AppColors.primary : AppColors.divider),
                visualDensity: VisualDensity.compact,
              ),
            )),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('Active Only', style: AppTypography.labelMedium.copyWith(
                color: _activeFilter == true ? AppColors.statusFree : AppColors.textSecondary,
              )),
              selected: _activeFilter == true,
              onSelected: (v) { setState(() => _activeFilter = v ? true : null); _load(); },
              selectedColor: AppColors.statusFree.withAlpha(20),
              checkmarkColor: AppColors.statusFree,
              side: BorderSide(color: _activeFilter == true ? AppColors.statusFree : AppColors.divider),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildBody(bool isAdmin) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_users.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.group_off_outlined, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text('No users found', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text('Try adjusting the filters.', style: AppTypography.bodySmall),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _UserCard(
          user: _users[i],
          roleColor: _roleColor(_users[i].role),
          isAdmin: isAdmin,
          onEdit: () => _showUserForm(context, existing: _users[i], isAdmin: isAdmin),
          onToggleActive: () => _toggleActive(_users[i]),
          onChangePassword: () => _showChangePassword(context, _users[i]),
          // onDelete intentionally omitted — security: deactivate only
        ),
      ),
    );
  }

  Future<void> _toggleActive(AdminUser user) async {
    if (user.isActive && user.role.toUpperCase() == 'LECTURER') {
      // SRS §3.12: Warn that deactivating a lecturer may affect future sessions
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.statusBooked),
            SizedBox(width: 8),
            Expanded(child: Text('Deactivate Lecturer?')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Deactivating ${user.fullName} will:',
                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _bulletPoint('Set all their future PUBLISHED sessions to NEEDS_REASSIGNMENT'),
            _bulletPoint('Send urgent notification to all Coordinators'),
            _bulletPoint('Require each session to be reassigned or cancelled'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.statusBooked.withAlpha(10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.statusBooked.withAlpha(40)),
              ),
              child: Text(
                'The sessions will NOT be automatically cancelled. '
                'Coordinators must manually reassign or cancel them.',
                style: AppTypography.caption.copyWith(color: AppColors.statusBooked),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      if (user.isActive) {
        final r = await _service.deactivateUser(user.id);
        final count = (r['needs_reassignment_count'] as int?) ?? 0;
        _showSnack(
          count > 0
              ? '${user.fullName} deactivated. $count session(s) moved to NEEDS_REASSIGNMENT.'
              : '${user.fullName} deactivated.',
          success: false,
        );
      } else {
        await _service.activateUser(user.id);
        _showSnack('${user.fullName} activated.');
      }
      _load();
    } catch (e) {
      _showError('$e');
    }
  }

  Widget _bulletPoint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('• ', style: TextStyle(color: AppColors.statusBooked)),
      Expanded(child: Text(text, style: AppTypography.caption)),
    ]),
  );

  // Hard delete intentionally removed (security principle):
  // Users are deactivated, never deleted, so audit trails and
  // timetable references remain intact.

  void _showChangePassword(BuildContext context, AdminUser user) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset Password — ${user.fullName}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'New Password (min 8 chars)'),
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.length < 8) return;
              Navigator.pop(ctx);
              try {
                await _service.changePassword(user.id, ctrl.text);
                _showSnack('Password updated.');
              } catch (e) { _showError('$e'); }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUserForm(BuildContext context, {AdminUser? existing, required bool isAdmin}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _UserForm(
        existing: existing,
        isAdmin: isAdmin,
        onSaved: (email, fullName, role, phone, password) async {
          try {
            if (existing == null) {
              await _service.createUser(
                email: email, fullName: fullName, role: role,
                phoneNumber: phone, password: password ?? 'UTLVA@2025',
              );
            } else {
              await _service.updateUser(existing.copyWith(
                fullName: fullName, role: role, phoneNumber: phone,
              ));
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
              );
            }
          }
        },
      ),
    );
    if (result == true && mounted) { _load(); _showSnack(existing == null ? 'User created.' : 'User updated.'); }
  }

  void _showSnack(String msg, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppColors.statusFree : AppColors.statusExpired,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showError(String msg) => _showSnack(msg, success: false);
}

// ── User card ─────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final AdminUser user;
  final Color roleColor;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onChangePassword;
  const _UserCard({
    required this.user, required this.roleColor, required this.isAdmin,
    required this.onEdit, required this.onToggleActive, required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    return ReusableCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: roleColor.withAlpha(25),
            child: Text(
              user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
              style: AppTypography.titleMedium.copyWith(color: roleColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.fullName, style: AppTypography.titleMedium),
            Text(user.email, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: roleColor.withAlpha(15), borderRadius: BorderRadius.circular(10)),
              child: Text(user.roleDisplay, style: AppTypography.caption.copyWith(color: roleColor, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (user.isActive ? AppColors.statusFree : AppColors.textSecondary).withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                user.isActive ? 'Active' : 'Inactive',
                style: AppTypography.caption.copyWith(
                  color: user.isActive ? AppColors.statusFree : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: const Text('Edit'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary, visualDensity: VisualDensity.compact),
            onPressed: onEdit,
          ),
          if (isAdmin) TextButton.icon(
            icon: Icon(user.isActive ? Icons.block_outlined : Icons.check_circle_outline, size: 14),
            label: Text(user.isActive ? 'Deactivate' : 'Activate'),
            style: TextButton.styleFrom(
              foregroundColor: user.isActive ? AppColors.statusExpired : AppColors.statusFree,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onToggleActive,
          ),
          if (isAdmin) TextButton.icon(
            icon: const Icon(Icons.lock_reset_outlined, size: 14),
            label: const Text('Password'),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent, visualDensity: VisualDensity.compact),
            onPressed: onChangePassword,
          ),
          // No delete button — users are deactivated, not deleted (security policy)
        ]),
      ]),
    );
  }
}

// ── Create / Edit form ────────────────────────────────────────────────────────

class _UserForm extends StatefulWidget {
  final AdminUser? existing;
  final bool isAdmin;
  final Future<void> Function(String email, String fullName, String role, String phone, String? password) onSaved;

  const _UserForm({this.existing, required this.isAdmin, required this.onSaved});
  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email, _fullName, _phone, _password;
  String _role = 'STUDENT';
  bool _saving = false;
  bool _obscure = true;

  static const _roles = [
    ('Student', 'STUDENT'),
    ('Lecturer', 'LECTURER'),
    ('Coordinator', 'COORDINATOR'),
    ('System Admin', 'SYSTEM_ADMIN'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _email    = TextEditingController(text: e?.email ?? '');
    _fullName = TextEditingController(text: e?.fullName ?? '');
    _phone    = TextEditingController(text: e?.phoneNumber ?? '');
    _password = TextEditingController();
    _role     = e?.role ?? 'STUDENT';
  }

  @override
  void dispose() { _email.dispose(); _fullName.dispose(); _phone.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.existing == null;
    return SingleChildScrollView(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isCreate ? 'Create User' : 'Edit User', style: AppTypography.headlineMedium),
        const SizedBox(height: 20),
        if (isCreate) ...[
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email *'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => v!.contains('@') ? null : 'Valid email required',
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _fullName,
          decoration: const InputDecoration(labelText: 'Full Name *'),
          validator: (v) => v!.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phone,
          decoration: const InputDecoration(labelText: 'Phone Number'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _role,
          decoration: const InputDecoration(labelText: 'Role *'),
          items: _roles.map((r) => DropdownMenuItem(value: r.$2, child: Text(r.$1))).toList(),
          onChanged: (v) => setState(() => _role = v!),
        ),
        if (isCreate) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            decoration: InputDecoration(
              labelText: 'Password (min 8 chars)',
              hintText: 'Leave blank for UTLVA@2025',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            obscureText: _obscure,
            validator: (v) => (v != null && v.isNotEmpty && v.length < 8) ? 'Min 8 characters' : null,
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : () async {
              if (!_formKey.currentState!.validate()) return;
              setState(() => _saving = true);
              await widget.onSaved(
                _email.text.trim(),
                _fullName.text.trim(),
                _role,
                _phone.text.trim(),
                _password.text.trim().isEmpty ? null : _password.text.trim(),
              );
              if (mounted) setState(() => _saving = false);
            },
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textOnPrimary, strokeWidth: 2))
                : Text(isCreate ? 'Create User' : 'Save Changes'),
          ),
        ),
      ])),
    );
  }
}
