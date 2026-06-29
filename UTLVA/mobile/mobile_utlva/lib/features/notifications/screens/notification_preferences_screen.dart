import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../models/notification_preference.dart';
import '../services/notification_service.dart';

/// FR-50 — Notification Preferences Screen
/// Users control which delivery channels and which event types trigger alerts.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final _service = NotificationService();

  NotificationPreference? _prefs;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = await _service.getPreferences();
      if (mounted) setState(() => _prefs = p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_prefs == null) return;
    setState(() { _saving = true; _successMsg = null; _error = null; });
    try {
      final updated = await _service.updatePreferences(_prefs!);
      if (mounted) {
        setState(() {
          _prefs = updated;
          _successMsg = 'Preferences saved successfully.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Notification Settings',
        showBackButton: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _prefs == null
              ? _buildError()
              : _buildBody(),
      bottomNavigationBar: _prefs == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: AppColors.textOnPrimary, strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save Preferences'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_successMsg != null)
          _buildBanner(_successMsg!, AppColors.statusFree, Icons.check_circle_outline),
        if (_error != null)
          _buildBanner(_error!, AppColors.error, Icons.error_outline),

        // ── Delivery channels ────────────────────────────────────────────────
        _sectionHeader('Delivery Channels', Icons.settings_outlined),
        const SizedBox(height: 8),
        ReusableCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _channelTile(
              icon: Icons.notifications_outlined,
              label: 'In-App Notifications',
              subtitle: 'Alerts inside the UTLVA app',
              value: _prefs!.inAppEnabled,
              onChanged: (v) =>
                  setState(() => _prefs = _prefs!.copyWith(inAppEnabled: v)),
            ),
            const Divider(height: 1, indent: 56),
            _channelTile(
              icon: Icons.email_outlined,
              label: 'Email Notifications',
              subtitle: 'Sent to your registered email',
              value: _prefs!.emailEnabled,
              onChanged: (v) =>
                  setState(() => _prefs = _prefs!.copyWith(emailEnabled: v)),
            ),
            const Divider(height: 1, indent: 56),
            _channelTile(
              icon: Icons.push_pin_outlined,
              label: 'Push Notifications',
              subtitle: 'Device push alerts (requires app open once)',
              value: _prefs!.pushEnabled,
              onChanged: (v) =>
                  setState(() => _prefs = _prefs!.copyWith(pushEnabled: v)),
            ),
            const Divider(height: 1, indent: 56),
            _channelTile(
              icon: Icons.sms_outlined,
              label: 'SMS Notifications',
              subtitle: '+255 Tanzania numbers only · daily cap applies',
              value: _prefs!.smsEnabled,
              onChanged: (v) =>
                  setState(() => _prefs = _prefs!.copyWith(smsEnabled: v)),
              accentColor: _prefs!.smsEnabled ? AppColors.statusBooked : null,
            ),
          ]),
        ),

        if (_prefs!.smsEnabled) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.statusBooked.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.statusBooked.withAlpha(50)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 15, color: AppColors.statusBooked),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SMS is limited to 5 messages/day per user. '
                  'Bulk events (>50 recipients) require coordinator approval.',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.statusBooked),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 24),

        // ── Event types ──────────────────────────────────────────────────────
        _sectionHeader('Alert Me When…', Icons.tune_outlined),
        const SizedBox(height: 8),
        ReusableCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _eventTile(
              label: 'Timetable Changes',
              subtitle: 'Schedule updates or new timetable published',
              value: _prefs!.notifyTimetableChanges,
              onChanged: (v) => setState(
                  () => _prefs = _prefs!.copyWith(notifyTimetableChanges: v)),
            ),
            const Divider(height: 1, indent: 56),
            _eventTile(
              label: 'Venue Changes',
              subtitle: 'Session moved to a different venue',
              value: _prefs!.notifyVenueChanges,
              onChanged: (v) => setState(
                  () => _prefs = _prefs!.copyWith(notifyVenueChanges: v)),
            ),
            const Divider(height: 1, indent: 56),
            _eventTile(
              label: 'Emergency Sessions',
              subtitle: 'Extra sessions created or approved',
              value: _prefs!.notifyEmergencySessions,
              onChanged: (v) => setState(
                  () => _prefs = _prefs!.copyWith(notifyEmergencySessions: v)),
            ),
            const Divider(height: 1, indent: 56),
            _eventTile(
              label: 'Session Confirmed',
              subtitle: 'Lecturer has confirmed session is starting',
              value: _prefs!.notifySessionConfirmation,
              onChanged: (v) => setState(
                  () => _prefs = _prefs!.copyWith(notifySessionConfirmation: v)),
            ),
            const Divider(height: 1, indent: 56),
            _eventTile(
              label: 'Session Postponed',
              subtitle: 'Session rescheduled to new date/time',
              value: _prefs!.notifySessionPostponement,
              onChanged: (v) => setState(
                  () => _prefs = _prefs!.copyWith(notifySessionPostponement: v)),
            ),
            const Divider(height: 1, indent: 56),
            _eventTile(
              label: 'Session Cancelled',
              subtitle: 'Session has been cancelled',
              value: _prefs!.notifySessionCancellation,
              onChanged: (v) => setState(
                  () => _prefs = _prefs!.copyWith(notifySessionCancellation: v)),
            ),
          ]),
        ),

        const SizedBox(height: 80), // space for bottom button
      ],
    );
  }

  Widget _buildError() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text('Could not load preferences', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      );

  Widget _sectionHeader(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(title,
              style:
                  AppTypography.titleMedium.copyWith(color: AppColors.primary)),
        ]),
      );

  Widget _channelTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? accentColor,
  }) =>
      SwitchListTile(
        secondary: Icon(icon, color: accentColor ?? AppColors.textSecondary),
        title: Text(label, style: AppTypography.titleMedium),
        subtitle: Text(subtitle,
            style: AppTypography.caption
                .copyWith(color: AppColors.textSecondary)),
        value: value,
        onChanged: onChanged,
        activeColor: accentColor ?? AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      );

  Widget _eventTile({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
        secondary: const Icon(Icons.circle, size: 10, color: AppColors.primary),
        title: Text(label, style: AppTypography.titleMedium),
        subtitle: Text(subtitle,
            style: AppTypography.caption
                .copyWith(color: AppColors.textSecondary)),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      );

  Widget _buildBanner(String msg, Color color, IconData icon) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: AppTypography.bodySmall.copyWith(color: color))),
        ]),
      );
}
