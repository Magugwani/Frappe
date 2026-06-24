import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/reusable_card.dart';

/// Generic list screen shell used by all Phase 2 management screens.
/// Each screen provides its own [itemBuilder] and form logic.
class ManagementListScreen<T> extends StatefulWidget {
  final String title;
  final Future<List<T>> Function() loader;
  final Widget Function(T item, VoidCallback onEdit, VoidCallback onDelete) itemBuilder;
  final VoidCallback onAdd;
  final String emptyMessage;

  const ManagementListScreen({
    super.key,
    required this.title,
    required this.loader,
    required this.itemBuilder,
    required this.onAdd,
    this.emptyMessage = 'No items yet. Tap + to add one.',
  });

  @override
  State<ManagementListScreen<T>> createState() => _ManagementListScreenState<T>();
}

class _ManagementListScreenState<T> extends State<ManagementListScreen<T>> {
  List<T> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await widget.loader();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: widget.title),
      floatingActionButton: FloatingActionButton(
        onPressed: widget.onAdd,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: AppColors.textOnPrimary),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text('Failed to load', style: AppTypography.titleMedium),
            const SizedBox(height: 4),
            Text(_error!, style: AppTypography.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(widget.emptyMessage, style: AppTypography.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final item = _items[i];
          return widget.itemBuilder(
            item,
            () { widget.onAdd(); _load(); },
            () => _confirmDelete(i),
          );
        },
      ),
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); },
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

/// Reusable card tile for list items with title, subtitle, and action buttons.
class ManagementTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badge;
  final Color? badgeColor;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final List<Widget>? extra;

  const ManagementTile({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.badgeColor,
    this.icon,
    this.iconColor,
    required this.onEdit,
    required this.onDelete,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return ReusableCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.primary).withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor ?? AppColors.primary, size: 20),
            ),
          if (icon != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: AppTypography.titleMedium)),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (badgeColor ?? AppColors.accent).withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badge!,
                          style: AppTypography.caption.copyWith(
                            color: badgeColor ?? AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTypography.bodySmall),
                ],
                if (extra != null) ...extra!,
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: AppColors.primary,
                onPressed: onEdit,
                tooltip: 'Edit',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.error,
                onPressed: onDelete,
                tooltip: 'Delete',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
