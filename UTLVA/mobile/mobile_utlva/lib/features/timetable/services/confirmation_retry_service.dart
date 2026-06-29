import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'timetable_service.dart';

/// SRS §3.12 — Network loss during confirmation.
///
/// When a lecturer taps "Confirm Session" but the device is offline,
/// this service stores the pending confirmation and retries every 30 seconds
/// for up to 30 minutes.
///
/// If retry succeeds within the original 40-minute confirmation window,
/// the confirmation is accepted with its original timestamp.
/// After 30 minutes, pending items are discarded (the session has expired).
///
/// Usage:
///   final retry = ConfirmationRetryService();
///   retry.scheduleRetry(entryId, sessionDate);
///   retry.startPolling();  // call once on app start
class ConfirmationRetryService {
  static const _prefsKey   = 'pending_confirmations';
  static const _retryMs    = 30000;   // 30 seconds
  static const _maxAgeMs   = 1800000; // 30 minutes

  final TimetableService _ttService = TimetableService();
  Timer? _timer;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Store a pending confirmation that failed due to network loss.
  Future<void> scheduleRetry(int entryId, String sessionDate) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final items = raw != null
        ? (jsonDecode(raw) as List<dynamic>)
            .cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    // Avoid duplicate entries for the same (entryId, sessionDate)
    items.removeWhere(
      (m) => m['entry_id'] == entryId && m['session_date'] == sessionDate,
    );
    items.add({
      'entry_id':    entryId,
      'session_date': sessionDate,
      'queued_at':   DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(_prefsKey, jsonEncode(items));
  }

  /// Start the 30-second background polling loop.
  /// Call once from main.dart or the app state init.
  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: _retryMs),
      (_) => _retryPending(),
    );
  }

  void stopPolling() => _timer?.cancel();

  /// Returns true if there are any pending confirmations in the queue.
  Future<bool> hasPending() async {
    final items = await _loadItems();
    return items.isNotEmpty;
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _retryPending() async {
    final items = await _loadItems();
    if (items.isEmpty) return;

    final now    = DateTime.now().millisecondsSinceEpoch;
    final keep   = <Map<String, dynamic>>[];

    for (final item in items) {
      final queuedAt = item['queued_at'] as int? ?? 0;
      final age      = now - queuedAt;

      // Discard items older than 30 minutes — session already expired
      if (age > _maxAgeMs) continue;

      final entryId = item['entry_id'] as int;

      try {
        final result = await _ttService.confirmSession(entryId);
        final success = result['success'] == true;
        final alreadyConfirmed = result['already_confirmed'] == true;
        if (success || alreadyConfirmed) {
          // Confirmed — remove from queue
          continue;
        }
        // Failed for a non-network reason (e.g., EXPIRED, CONFLICT)
        // Stop retrying this item
        if (result['error_code'] == 'CONFLICT' || result['message']?.contains('EXPIRED') == true) {
          continue;
        }
        // Keep retrying — probably still a network error
        keep.add(item);
      } catch (_) {
        // Network error — keep for next retry
        keep.add(item);
      }
    }

    await _saveItems(keep);
  }

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveItems(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(items));
    }
  }
}
