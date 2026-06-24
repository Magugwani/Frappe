import 'dart:math';
import 'package:flutter/material.dart';
import '../../features/timetable/models/timetable_entry.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';

/// University-style weekly timetable grid.
///
/// ## What this is
/// A **UI layout widget** that renders [TimetableEntry] objects as a
/// visual weekly calendar — rows are days, columns are hourly time slots,
/// and each entry card is positioned using Stack/Positioned so that
/// multi-hour sessions (e.g. 08:00–10:00) naturally span two columns.
///
/// The grid is NOT an Excel file. It does NOT import or export spreadsheets.
/// [TimetableEntry] objects fetched from the backend REST API are the
/// single source of truth for all timetable data.
///
/// ## Time range
/// The displayed time range is **derived dynamically from the entries list**:
/// - Start = floor of the earliest session start (e.g. entries start at 08:30 → 08:00 column shown)
/// - End   = ceiling of the latest session end  (e.g. entries end at 16:00 → 16:00 is last boundary)
/// No fixed academic schedule is assumed. Future phases will introduce
/// TeachingPeriod master data; until then the grid adapts to what is
/// actually scheduled.
/// Pass [fallbackStartHour] / [fallbackEndHour] to control the empty-state range.
///
/// ## Reusability
/// Designed for use across multiple phases:
/// - Phase 3: manual / generated timetable view
/// - Phase 4: validated / published timetable view
/// - Phase 5: emergency session overlay, lecturer confirmation flow
///
/// Colour logic is **not hard-coded** inside the widget. Callers pass an
/// optional [entryColorBuilder] to apply phase-specific colours
/// (e.g. CONFIRMED = green, EMERGENCY = red). The default colouring is
/// PUBLISHED = primary blue, anything else = orange.
///
/// ## Layout
/// - Fixed left column   → day labels (90 px wide, sticky)
/// - Scrollable right area → hourly slots (130 px per hour)
/// - Stack + Positioned per day row — entries span (duration / 60) × 130 px
class TimetableGridView extends StatelessWidget {
  final List<TimetableEntry> entries;

  /// Called when a cell card is tapped. Null = cards are not tappable.
  final void Function(TimetableEntry)? onEntryTap;

  /// Custom colour function. Override for emergency sessions, confirmations, etc.
  /// Defaults to: PUBLISHED → [AppColors.primary], else → [AppColors.statusInUse].
  final Color Function(TimetableEntry)? entryColorBuilder;

  /// When true, days with no entries are hidden.
  /// Useful for lecturer view where Saturday may be unused.
  final bool showOnlyDaysWithEntries;

  /// Extra legend entries shown below the grid (e.g. [CONFIRMED, green]).
  /// If null, the default PUBLISHED / DRAFT legend is shown.
  final List<TimetableLegendItem>? legends;

  /// Fallback start hour when [entries] is empty. Default: 08.
  final int fallbackStartHour;

  /// Fallback end hour (exclusive) when [entries] is empty. Default: 18.
  final int fallbackEndHour;

  const TimetableGridView({
    super.key,
    required this.entries,
    this.onEntryTap,
    this.entryColorBuilder,
    this.showOnlyDaysWithEntries = false,
    this.legends,
    this.fallbackStartHour = 8,
    this.fallbackEndHour = 18,
  });

  // ── Layout constants ────────────────────────────────────────────────────────
  static const double _dayLabelWidth = 90;
  static const double _slotWidth = 130; // 1 hour = 130 px
  static const double _headerHeight = 40;
  static const double _rowHeight = 100;
  static const double _cellPad = 2;

  static const List<String> _allDays = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY',
  ];

  static const Map<String, String> _dayLabel = {
    'MONDAY': 'Mon', 'TUESDAY': 'Tue', 'WEDNESDAY': 'Wed',
    'THURSDAY': 'Thu', 'FRIDAY': 'Fri', 'SATURDAY': 'Sat',
  };

  // ── Dynamic time range ────────────────────────────────────────────────────

  /// Earliest start hour across all entries; falls back when list is empty.
  int get _startHour {
    if (entries.isEmpty) return fallbackStartHour;
    return entries.map((e) => e.startMinutes ~/ 60).reduce(min);
  }

  /// Latest end hour (exclusive) across all entries; falls back when list is empty.
  /// Uses ceiling so an entry ending at 16:30 produces endHour = 17.
  int get _endHour {
    if (entries.isEmpty) return fallbackEndHour;
    return entries.map((e) {
      final h = e.endMinutes ~/ 60;
      final m = e.endMinutes % 60;
      return m > 0 ? h + 1 : h;
    }).reduce(max);
  }

  List<int> get _hours => List.generate(_endHour - _startHour, (i) => _startHour + i);

  List<String> get _visibleDays {
    if (!showOnlyDaysWithEntries) return _allDays;
    final daysWithEntries = entries.map((e) => e.dayOfWeek).toSet();
    return _allDays.where(daysWithEntries.contains).toList();
  }

  // ── Positioning helpers ───────────────────────────────────────────────────

  /// Left offset of an entry card within the time-slot area (px).
  double _entryLeft(TimetableEntry e) {
    return ((e.startMinutes - _startHour * 60) / 60) * _slotWidth + _cellPad;
  }

  /// Width of an entry card: duration in hours × slot width.
  double _entryWidth(TimetableEntry e) =>
      (e.durationMinutes / 60) * _slotWidth - _cellPad * 2;

  /// Card colour: delegate to caller or use sensible default.
  Color _colorFor(TimetableEntry e) {
    if (entryColorBuilder != null) return entryColorBuilder!(e);
    return e.status == 'PUBLISHED' ? AppColors.primary : AppColors.statusInUse;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty && _visibleDays.isEmpty) {
      return _buildEmptyState();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const Divider(height: 1, thickness: 1, color: AppColors.divider),
              ..._visibleDays.map(_buildDayRow),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildLegend(),
      ],
    );
  }

  // ── Header row ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        // Corner label
        Container(
          width: _dayLabelWidth,
          height: _headerHeight,
          color: AppColors.secondary,
          alignment: Alignment.center,
          child: Text('Day / Time',
              style: AppTypography.caption.copyWith(
                  color: AppColors.textOnPrimary, fontWeight: FontWeight.w700)),
        ),
        // Time-slot headers — generated from dynamic range
        ..._hours.map((hour) {
          final hStr = hour.toString().padLeft(2, '0');
          final nStr = (hour + 1).toString().padLeft(2, '0');
          return Container(
            width: _slotWidth,
            height: _headerHeight,
            decoration: BoxDecoration(
              color: AppColors.secondary.withAlpha(220),
              border: Border(left: BorderSide(color: AppColors.divider.withAlpha(80))),
            ),
            alignment: Alignment.center,
            child: Text(
              '$hStr:00–$nStr:00',
              style: AppTypography.caption.copyWith(
                color: AppColors.textOnPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Day row ───────────────────────────────────────────────────────────────

  Widget _buildDayRow(String day) {
    final dayEntries = entries
        .where((e) => e.dayOfWeek == day)
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    final totalWidth = _hours.length * _slotWidth;

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Day label (sticky)
          Container(
            width: _dayLabelWidth,
            height: _rowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(right: BorderSide(color: AppColors.divider, width: 2)),
              boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4, offset: const Offset(2, 0))],
            ),
            child: Text(
              _dayLabel[day] ?? day,
              style: AppTypography.titleMedium.copyWith(
                color: dayEntries.isNotEmpty ? AppColors.secondary : AppColors.textSecondary,
                fontWeight: dayEntries.isNotEmpty ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          // Time-slot area with Stack/Positioned entries
          SizedBox(
            width: totalWidth,
            height: _rowHeight,
            child: Stack(
              children: [
                // Background alternating slot cells
                Row(
                  children: _hours.map((hour) {
                    return Container(
                      width: _slotWidth,
                      height: _rowHeight,
                      decoration: BoxDecoration(
                        color: hour.isOdd ? AppColors.background : AppColors.surface,
                        border: Border(
                          left: BorderSide(color: AppColors.divider.withAlpha(120)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                // Entry cards — Positioned for multi-hour spanning
                ...dayEntries.map((entry) {
                  final left = _entryLeft(entry);
                  final width = _entryWidth(entry);
                  // Skip entries outside the visible range
                  if (left < 0 || width <= 0 ||
                      entry.startMinutes < _startHour * 60) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    left: left,
                    top: _cellPad,
                    width: width,
                    height: _rowHeight - _cellPad * 2,
                    child: _EntryCard(
                      entry: entry,
                      color: _colorFor(entry),
                      onTap: onEntryTap != null ? () => onEntryTap!(entry) : null,
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Legend ────────────────────────────────────────────────────────────────

  Widget _buildLegend() {
    final items = legends ??
        [
          const TimetableLegendItem(color: AppColors.primary, label: 'Published'),
          const TimetableLegendItem(color: AppColors.statusInUse, label: 'Draft'),
        ];
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: items
          .map((item) => _LegendDot(color: item.color, label: item.label))
          .toList(),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text('No timetable entries to display.',
                style: AppTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ── Legend item model ─────────────────────────────────────────────────────────

/// Describes one item in the TimetableGridView legend.
/// Callers can pass a custom list to [TimetableGridView.legends].
class TimetableLegendItem {
  final Color color;
  final String label;
  const TimetableLegendItem({required this.color, required this.label});
}

// ── Entry card ────────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final TimetableEntry entry;
  final Color color;
  final VoidCallback? onTap;

  const _EntryCard({required this.entry, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [BoxShadow(color: color.withAlpha(80), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Course code + time range
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    entry.courseCode,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textOnPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${entry.startHHMM}–${entry.endHHMM}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textOnPrimary.withAlpha(200),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
            // Course name
            Text(
              entry.courseName,
              style: AppTypography.caption.copyWith(
                color: AppColors.textOnPrimary.withAlpha(220),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            // Lecturer name
            Text(
              entry.lecturerName,
              style: AppTypography.caption.copyWith(
                color: AppColors.textOnPrimary.withAlpha(200),
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Venue + student group
            Row(
              children: [
                if (entry.venueCode != null)
                  Flexible(
                    child: Text(
                      entry.venueCode!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textOnPrimary.withAlpha(200), fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (entry.venueCode != null && entry.studentGroupName != null)
                  Text(' · ',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textOnPrimary.withAlpha(160), fontSize: 9)),
                if (entry.studentGroupName != null)
                  Flexible(
                    child: Text(
                      entry.studentGroupName!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textOnPrimary.withAlpha(200), fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Legend dot ────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 5),
      Text(label, style: AppTypography.caption.copyWith(fontSize: 11)),
    ]);
  }
}
