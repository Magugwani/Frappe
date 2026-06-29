import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../timetable/services/timetable_service.dart';

/// SRS §3.11 — Full System Configuration Screen
/// All 8 parameters from the SystemConfiguration table are editable.
/// Changes are saved via PATCH /api/system/config/ (Admin only).
class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});
  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final _ttService = TimetableService();
  bool _loading = false;
  bool _saving  = false;

  // ── Session lifecycle ──────────────────────────────────────────────────────
  final _capacityCtrl     = TextEditingController();
  final _confirmWinCtrl   = TextEditingController();
  final _reminderLeadCtrl = TextEditingController();

  // ── SMS protections ────────────────────────────────────────────────────────
  final _smsDailyCapCtrl      = TextEditingController();
  final _smsBulkThreshCtrl    = TextEditingController();

  // ── Account / enrollment ───────────────────────────────────────────────────
  final _pwdResetHoursCtrl    = TextEditingController();
  final _maxBulkRowsCtrl      = TextEditingController();

  // ── Celery Beat ────────────────────────────────────────────────────────────
  final _venueCheckIntervalCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _capacityCtrl.dispose();
    _confirmWinCtrl.dispose();
    _reminderLeadCtrl.dispose();
    _smsDailyCapCtrl.dispose();
    _smsBulkThreshCtrl.dispose();
    _pwdResetHoursCtrl.dispose();
    _maxBulkRowsCtrl.dispose();
    _venueCheckIntervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await _ttService.getSystemConfig();
      if (mounted) {
        _capacityCtrl.text       = ((cfg['capacity_overhead'] as num?) ?? 1.5).toDouble().toString();
        _confirmWinCtrl.text     = ((cfg['confirmation_window_minutes'] as num?) ?? 40).toInt().toString();
        _reminderLeadCtrl.text   = ((cfg['reminder_lead_minutes'] as num?) ?? 120).toInt().toString();
        _smsDailyCapCtrl.text    = ((cfg['sms_daily_cap_per_user'] as num?) ?? 5).toInt().toString();
        _smsBulkThreshCtrl.text  = ((cfg['sms_bulk_approval_threshold'] as num?) ?? 50).toInt().toString();
        _pwdResetHoursCtrl.text  = ((cfg['password_reset_link_hours'] as num?) ?? 48).toInt().toString();
        _maxBulkRowsCtrl.text    = ((cfg['max_bulk_upload_rows'] as num?) ?? 5000).toInt().toString();
        _venueCheckIntervalCtrl.text = ((cfg['venue_status_check_interval_seconds'] as num?) ?? 60).toInt().toString();
      }
    } catch (_) {
      // Apply SRS §3.11 defaults if load fails
      _capacityCtrl.text       = '1.5';
      _confirmWinCtrl.text     = '40';
      _reminderLeadCtrl.text   = '120';
      _smsDailyCapCtrl.text    = '5';
      _smsBulkThreshCtrl.text  = '50';
      _pwdResetHoursCtrl.text  = '48';
      _maxBulkRowsCtrl.text    = '5000';
      _venueCheckIntervalCtrl.text = '60';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    // ── Validation ──────────────────────────────────────────────────────────
    final cap     = double.tryParse(_capacityCtrl.text);
    final win     = int.tryParse(_confirmWinCtrl.text);
    final lead    = int.tryParse(_reminderLeadCtrl.text);
    final smsCap  = int.tryParse(_smsDailyCapCtrl.text);
    final smsBulk = int.tryParse(_smsBulkThreshCtrl.text);
    final pwdHrs  = int.tryParse(_pwdResetHoursCtrl.text);
    final maxRows = int.tryParse(_maxBulkRowsCtrl.text);
    final interval = int.tryParse(_venueCheckIntervalCtrl.text);

    if (cap   == null || cap   < 1.0  || cap   > 5.0)   { _snack('Capacity overhead: 1.0–5.0', error: true);   return; }
    if (win   == null || win   < 1    || win   > 120)    { _snack('Confirmation window: 1–120 min', error: true); return; }
    if (lead  == null || lead  < 1    || lead  > 480)    { _snack('Reminder lead: 1–480 min', error: true);     return; }
    if (smsCap  == null || smsCap  < 1 || smsCap  > 100) { _snack('SMS daily cap: 1–100', error: true);          return; }
    if (smsBulk == null || smsBulk < 1)                  { _snack('SMS bulk threshold must be ≥ 1', error: true); return; }
    if (pwdHrs  == null || pwdHrs  < 1 || pwdHrs  > 168) { _snack('Reset link expiry: 1–168 hours', error: true); return; }
    if (maxRows == null || maxRows < 1)                   { _snack('Max bulk rows must be ≥ 1', error: true);      return; }
    if (interval == null || interval < 10 || interval > 3600) { _snack('Venue check interval: 10–3600 s', error: true); return; }

    setState(() => _saving = true);
    try {
      await _ttService.updateSystemConfig({
        'capacity_overhead':           cap,
        'confirmation_window_minutes': win,
        'reminder_lead_minutes':       lead,
        'sms_daily_cap_per_user':      smsCap,
        'sms_bulk_approval_threshold': smsBulk,
        'password_reset_link_hours':   pwdHrs,
        'max_bulk_upload_rows':        maxRows,
        'venue_status_check_interval_seconds': interval,
      });
      if (mounted) _snack('All settings saved successfully.');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.statusFree,
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'System Settings', showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Info banner ────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withAlpha(40)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.admin_panel_settings_outlined,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SRS §3.11 — All configuration parameters are stored in the '
                        'database and applied system-wide without code changes.',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.primary),
                      ),
                    ),
                  ]),
                ),

                // ── Section 1: Session Lifecycle ───────────────────────────────
                _sectionHeader(
                  'Session Lifecycle',
                  Icons.timer_outlined,
                  AppColors.primary,
                ),
                const SizedBox(height: 8),
                ReusableCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _field(
                      icon: Icons.tune_outlined, color: AppColors.accent,
                      title: 'Capacity Overhead Multiplier',
                      description: 'Upper-bound for venue auto-allocation.\n'
                          '100 students → venues up to 150 seats at 1.5×',
                      controller: _capacityCtrl,
                      hint: '1.0 – 5.0',
                      isDecimal: true,
                      defaultVal: '1.5',
                    ),
                    _divider,
                    _field(
                      icon: Icons.hourglass_top_outlined, color: AppColors.statusBooked,
                      title: 'Confirmation Window (minutes)',
                      description: 'Minutes after session start before an unconfirmed '
                          'session is marked EXPIRED.',
                      controller: _confirmWinCtrl,
                      hint: '1–120',
                      defaultVal: '40',
                    ),
                    _divider,
                    _field(
                      icon: Icons.notifications_active_outlined, color: AppColors.primary,
                      title: 'Reminder Lead Time (minutes)',
                      description: 'Minutes before start_time when the reminder email '
                          'is sent (includes Confirm / Postpone / Cancel links).',
                      controller: _reminderLeadCtrl,
                      hint: '1–480',
                      defaultVal: '120',
                    ),
                  ]),
                ),

                const SizedBox(height: 20),

                // ── Section 2: SMS Protections ─────────────────────────────────
                _sectionHeader(
                  'SMS Protections (FR-51-B)',
                  Icons.sms_outlined,
                  AppColors.statusBooked,
                ),
                const SizedBox(height: 8),
                ReusableCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _field(
                      icon: Icons.person_pin_circle_outlined,
                      color: AppColors.statusBooked,
                      title: 'SMS Daily Cap Per User',
                      description: 'Maximum SMS a single user can receive per calendar '
                          'day. Excess messages fall back to push + in-app.',
                      controller: _smsDailyCapCtrl,
                      hint: '1–100',
                      defaultVal: '5',
                    ),
                    _divider,
                    _field(
                      icon: Icons.group_outlined, color: AppColors.statusBooked,
                      title: 'Bulk SMS Approval Threshold',
                      description: 'Number of recipients above which coordinator '
                          'approval is required before dispatching bulk SMS.',
                      controller: _smsBulkThreshCtrl,
                      hint: 'e.g. 50',
                      defaultVal: '50',
                    ),
                  ]),
                ),

                const SizedBox(height: 20),

                // ── Section 3: Account Management ──────────────────────────────
                _sectionHeader(
                  'Account & Enrollment (FR-52, FR-57)',
                  Icons.manage_accounts_outlined,
                  AppColors.statusFree,
                ),
                const SizedBox(height: 8),
                ReusableCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _field(
                      icon: Icons.link_outlined, color: AppColors.statusFree,
                      title: 'Password Reset Link Expiry (hours)',
                      description: 'How long welcome / reset links remain valid after '
                          'being sent. SRS default: 48 hours.',
                      controller: _pwdResetHoursCtrl,
                      hint: '1–168',
                      defaultVal: '48',
                    ),
                    _divider,
                    _field(
                      icon: Icons.upload_file_outlined, color: AppColors.statusFree,
                      title: 'Max Bulk Upload Rows',
                      description: 'Maximum rows per CSV upload before the system '
                          'rejects the file. SRS default: 5000.',
                      controller: _maxBulkRowsCtrl,
                      hint: 'e.g. 5000',
                      defaultVal: '5000',
                    ),
                  ]),
                ),

                const SizedBox(height: 20),

                // ── Section 4: Celery Beat ─────────────────────────────────────
                _sectionHeader(
                  'Background Tasks (Celery Beat)',
                  Icons.schedule_outlined,
                  AppColors.textSecondary,
                ),
                const SizedBox(height: 8),
                ReusableCard(
                  child: _field(
                    icon: Icons.loop_outlined, color: AppColors.textSecondary,
                    title: 'Venue Status Check Interval (seconds)',
                    description: 'How often Celery Beat checks for sessions whose '
                        'end_time has passed and releases venues to FREE.',
                    controller: _venueCheckIntervalCtrl,
                    hint: '10–3600',
                    defaultVal: '60',
                  ),
                ),

                const SizedBox(height: 24),

                // ── Save button ────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                color: AppColors.textOnPrimary, strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save All Settings'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  // ── Widget helpers ─────────────────────────────────────────────────────────

  Widget get _divider => const Divider(height: 24);

  Widget _sectionHeader(String title, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: AppTypography.titleMedium.copyWith(color: color)),
        ]),
      );

  Widget _field({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required TextEditingController controller,
    required String hint,
    required String defaultVal,
    bool isDecimal = false,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
              child: Text(title,
                  style:
                      AppTypography.labelLarge.copyWith(color: color))),
          GestureDetector(
            onTap: () => controller.text = defaultVal,
            child: Text(
              'Default: $defaultVal',
              style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.underline),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(description,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary, height: 1.4)),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(hintText: hint, isDense: true),
          keyboardType: isDecimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
        ),
      ]);
}
