import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';

/// Generic in-app notification centre — works for all roles.
/// Shows the 50 most recent notifications, grouped by read/unread.
/// For coordinators, tapping an EMERGENCY_CREATED notification navigates
/// to the emergency sessions review screen.
/// For lecturers, tapping an EMERGENCY_APPROVED notification shows
/// the "Send notifications to students" dialog.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  List<AppNotification> _items = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // FR-51-A: Poll for new notifications every 30 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _silentRefresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _silentRefresh() async {
    try {
      final items = await _service.getNotifications();
      if (mounted && items.length != _items.length) {
        setState(() => _items = items);
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _service.getNotifications();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    await _service.markAllRead();
    setState(() {
      _items = _items.map((n) => AppNotification.fromJson({
        'id': n.id,
        'notification_type': n.notificationType,
        'type_display': n.typeDisplay,
        'title': n.title,
        'body': n.body,
        'related_object_type': n.relatedObjectType,
        'related_object_id': n.relatedObjectId,
        'sender': n.senderId,
        'sender_name': n.senderName,
        'is_read': true,
        'created_at': n.createdAt,
      })).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((n) => !n.isRead).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Notifications',
        showBackButton: true,
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.textOnPrimary)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textOnPrimary),
            onPressed: _load,
          ),
          // FR-50: Settings → notification preferences
          IconButton(
            icon: const Icon(Icons.tune_outlined, color: AppColors.textOnPrimary),
            tooltip: 'Notification Settings',
            onPressed: () => context.push('/notifications/preferences'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text('Could not load notifications', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.notifications_none_outlined,
              size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('No notifications yet',
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            'Emergency session requests, approvals,\n'
            'and session alerts will appear here.',
            style: AppTypography.bodySmall,
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) => _NotifTile(
          notif: _items[i],
          onTap: () => _handleTap(_items[i]),
        ),
      ),
    );
  }

  Future<void> _handleTap(AppNotification notif) async {
    // Mark as read on tap
    if (!notif.isRead) {
      await _service.markRead(notif.id);
      if (mounted) {
        setState(() {
          final idx = _items.indexWhere((n) => n.id == notif.id);
          if (idx >= 0) {
            _items[idx] = AppNotification.fromJson({
              'id': notif.id,
              'notification_type': notif.notificationType,
              'type_display': notif.typeDisplay,
              'title': notif.title,
              'body': notif.body,
              'related_object_type': notif.relatedObjectType,
              'related_object_id': notif.relatedObjectId,
              'sender': notif.senderId,
              'sender_name': notif.senderName,
              'is_read': true,
              'created_at': notif.createdAt,
            });
          }
        });
      }
    }

    if (!mounted) return;

    // Route to relevant screen
    if (notif.isEmergencyCreated && notif.relatedObjectType == 'EmergencySession') {
      // Coordinator: go to emergency session review
      context.push('/sessions/emergency');
    } else if (notif.isEmergencyApproved) {
      // Lecturer: show the "send student notifications" dialog
      _showApprovalDialog(notif);
    } else if (notif.isEmergencyRejected) {
      // Lecturer: show detail of rejection
      _showRejectionDetail(notif);
    }
  }

  void _showApprovalDialog(AppNotification notif) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ApprovalActionDialog(
        notif: notif,
        service: _service,
      ),
    );
  }

  void _showRejectionDetail(AppNotification notif) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Rejected'),
        content: Text(notif.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ── Notification tile ─────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onTap;

  const _NotifTile({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: notif.isRead ? null : AppColors.primary.withAlpha(8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _iconColor.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 20, color: _iconColor),
                ),
                if (!notif.isRead)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notif.title,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight:
                            notif.isRead ? FontWeight.w500 : FontWeight.w700,
                      )),
                  const SizedBox(height: 3),
                  Text(notif.body,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _relativeTime(notif.createdAt),
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      if (notif.senderName != null) ...[
                        const Text(' · ',
                            style: TextStyle(color: AppColors.textSecondary)),
                        Text(notif.senderName!,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Color get _iconColor => switch (notif.notificationType) {
        'EMERGENCY_CREATED' => AppColors.statusBooked,
        'EMERGENCY_APPROVED' => AppColors.statusFree,
        'EMERGENCY_REJECTED' => AppColors.error,
        'SESSION_CONFIRMED' => AppColors.statusFree,
        'SESSION_POSTPONED' => AppColors.statusBooked,
        'SESSION_CANCELLED' => AppColors.statusExpired,
        _ => AppColors.primary,
      };

  IconData get _icon => switch (notif.notificationType) {
        'EMERGENCY_CREATED' => Icons.warning_amber_rounded,
        'EMERGENCY_APPROVED' => Icons.check_circle_outline,
        'EMERGENCY_REJECTED' => Icons.cancel_outlined,
        'SESSION_CONFIRMED' => Icons.done_all,
        'SESSION_POSTPONED' => Icons.update,
        'SESSION_CANCELLED' => Icons.event_busy_outlined,
        _ => Icons.notifications_outlined,
      };

  String _relativeTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return iso;
    }
  }
}

// ── Approval action dialog for lecturers ─────────────────────────────────────

class _ApprovalActionDialog extends StatefulWidget {
  final AppNotification notif;
  final NotificationService service;

  const _ApprovalActionDialog({required this.notif, required this.service});

  @override
  State<_ApprovalActionDialog> createState() => _ApprovalActionDialogState();
}

class _ApprovalActionDialogState extends State<_ApprovalActionDialog> {
  bool _sending = false;
  String? _result;

  Future<void> _sendNotifications() async {
    final sessionId = widget.notif.relatedId;
    if (sessionId == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await widget.service.notifyStudents(sessionId);
      final count = res['students_notified'] ?? 0;
      if (mounted) {
        setState(() {
          _sending = false;
          _result = 'Notified $count students successfully.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _result = 'Failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return AlertDialog(
        title: const Text('Notification Sent'),
        content: Text(_result!),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.check_circle_outline, color: AppColors.statusFree),
        const SizedBox(width: 8),
        const Expanded(child: Text('Session Approved!')),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.notif.body,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withAlpha(40)),
            ),
            child: Text(
              'Would you like to notify your students about this emergency session?',
              style: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text("OK — Don't Notify"),
        ),
        ElevatedButton.icon(
          onPressed: _sending ? null : _sendNotifications,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: AppColors.textOnPrimary, strokeWidth: 2))
              : const Icon(Icons.send_outlined, size: 16),
          label: const Text('OK — Send Notification'),
        ),
      ],
    );
  }
}
