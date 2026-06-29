import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../services/bulk_enrollment_service.dart';

/// FR-52–57 — Bulk User Enrollment Screen (Coordinator / Admin)
///
/// Two tabs: Students | Lecturers
/// Each tab has:
///   • CSV format guide + template download
///   • File picker
///   • Mode selector (Reject All / Import Valid Only)
///   • Upload button
///   • Results display with counts and error download
///   • Recent jobs history
class BulkEnrollmentScreen extends StatefulWidget {
  const BulkEnrollmentScreen({super.key});

  @override
  State<BulkEnrollmentScreen> createState() => _BulkEnrollmentScreenState();
}

class _BulkEnrollmentScreenState extends State<BulkEnrollmentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _service = BulkEnrollmentService();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Bulk Enrollment',
        showBackButton: true,
      ),
      body: Column(
        children: [
          // Tab bar
          Container(
            color: AppColors.secondary,
            child: TabBar(
              controller: _tabCtrl,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.textOnPrimary,
              unselectedLabelColor: AppColors.textOnPrimary.withAlpha(150),
              tabs: const [
                Tab(icon: Icon(Icons.school_outlined), text: 'Students'),
                Tab(icon: Icon(Icons.person_pin_outlined), text: 'Lecturers'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _RoleUploadTab(
                  role: 'STUDENT',
                  service: _service,
                  columns: 'full_name, email, registration_number, programme_code, phone_number',
                  columnNotes: [
                    'full_name — Student\'s full legal name',
                    'email — Valid email address (unique)',
                    'registration_number — e.g. 2021/CS/001',
                    'programme_code — Must match a registered programme (e.g. BSc-CS)',
                    'phone_number — +255 format (optional for SMS)',
                  ],
                ),
                _RoleUploadTab(
                  role: 'LECTURER',
                  service: _service,
                  columns: 'full_name, email, staff_number_id, lecturer_department, phone_number',
                  columnNotes: [
                    'full_name — Lecturer\'s full legal name',
                    'email — Valid email address (unique)',
                    'staff_number_id — Staff ID (e.g. STAFF-0042)',
                    'lecturer_department — Must match a registered department',
                    'phone_number — +255 format (optional for SMS)',
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single role upload tab ─────────────────────────────────────────────────────

class _RoleUploadTab extends StatefulWidget {
  final String role;
  final BulkEnrollmentService service;
  final String columns;
  final List<String> columnNotes;

  const _RoleUploadTab({
    required this.role,
    required this.service,
    required this.columns,
    required this.columnNotes,
  });

  @override
  State<_RoleUploadTab> createState() => _RoleUploadTabState();
}

class _RoleUploadTabState extends State<_RoleUploadTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  PlatformFile? _selectedFile;
  String _mode = 'REJECT_ALL';
  bool _uploading = false;
  BulkEnrollmentResult? _result;
  String? _error;
  List<BulkEnrollmentJob> _recentJobs = [];
  // ignore: unused_field — used to show loading in future extension
  bool _loadingJobs = false;

  @override
  void initState() {
    super.initState();
    _loadRecentJobs();
  }

  Future<void> _loadRecentJobs() async {
    setState(() => _loadingJobs = true);
    try {
      final jobs = await widget.service.listJobs();
      if (mounted) {
        setState(() => _recentJobs =
            jobs.where((j) => j.role == widget.role).take(5).toList());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingJobs = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _upload() async {
    if (_selectedFile == null || _selectedFile!.bytes == null) return;
    setState(() { _uploading = true; _error = null; _result = null; });
    try {
      final res = await widget.service.uploadCSV(
        fileBytes: _selectedFile!.bytes!,
        filename: _selectedFile!.name,
        role: widget.role,
        mode: _mode,
      );
      if (mounted) {
        setState(() => _result = res);
        _loadRecentJobs();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _downloadTemplate() async {
    final templateUrl = Uri.parse(widget.service.templateUrl(widget.role));
    if (await canLaunchUrl(templateUrl)) {
      await launchUrl(templateUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadErrorReport(int jobId) async {
    final baseUrl =
        '${AppConfig.baseUrl}/api/accounts/bulk-enroll/$jobId/error-report/';
    final uri = Uri.parse(baseUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _loadRecentJobs,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Format guide ────────────────────────────────────────────────────
          _FormatGuideCard(
            role: widget.role,
            columns: widget.columns,
            columnNotes: widget.columnNotes,
            onDownloadTemplate: _downloadTemplate,
          ),
          const SizedBox(height: 14),

          // ── File selection card ─────────────────────────────────────────────
          ReusableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.upload_file_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Select CSV File',
                      style: AppTypography.titleMedium
                          .copyWith(color: AppColors.primary)),
                ]),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _uploading ? null : _pickFile,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedFile != null
                            ? AppColors.primary
                            : AppColors.textSecondary.withAlpha(80),
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: _selectedFile != null
                          ? AppColors.primary.withAlpha(8)
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedFile != null
                              ? Icons.check_circle_outline
                              : Icons.cloud_upload_outlined,
                          size: 36,
                          color: _selectedFile != null
                              ? AppColors.statusFree
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedFile != null
                              ? _selectedFile!.name
                              : 'Tap to select a .csv file',
                          style: _selectedFile != null
                              ? AppTypography.bodyMedium
                                  .copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)
                              : AppTypography.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        if (_selectedFile != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB — Tap to change',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Mode selector (FR-55) ────────────────────────────────────────────
          ReusableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.rule_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('On Validation Error',
                      style: AppTypography.titleMedium
                          .copyWith(color: AppColors.primary)),
                ]),
                const SizedBox(height: 8),
                _ModeRadio(
                  value: 'REJECT_ALL',
                  groupValue: _mode,
                  label: 'Reject entire file (recommended)',
                  subtitle: 'No accounts created. Fix errors, then re-upload.',
                  onChanged: (v) => setState(() => _mode = v!),
                ),
                const SizedBox(height: 4),
                _ModeRadio(
                  value: 'IMPORT_VALID',
                  groupValue: _mode,
                  label: 'Import valid rows, skip invalid',
                  subtitle: 'Creates accounts for valid rows. Skipped rows in error report.',
                  onChanged: (v) => setState(() => _mode = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Upload button ────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_selectedFile == null || _uploading) ? null : _upload,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: AppColors.textOnPrimary, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_uploading
                  ? 'Processing...'
                  : 'Upload & Enroll ${widget.role == "STUDENT" ? "Students" : "Lecturers"}'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
            ),
          ),

          // ── Error banner ─────────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 12),
            _AlertBanner(
              message: _error!,
              color: AppColors.error,
              icon: Icons.error_outline,
            ),
          ],

          // ── Results card ─────────────────────────────────────────────────────
          if (_result != null) ...[
            const SizedBox(height: 14),
            _ResultCard(
              result: _result!,
              onDownloadErrors: () =>
                  _downloadErrorReport(_result!.jobId),
            ),
          ],

          // ── Recent jobs ──────────────────────────────────────────────────────
          if (_recentJobs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Recent Uploads', style: AppTypography.titleLarge),
            const SizedBox(height: 8),
            ..._recentJobs.map((j) => _JobHistoryTile(
                  job: j,
                  onDownload: j.errorCount > 0
                      ? () => _downloadErrorReport(j.id)
                      : null,
                )),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _FormatGuideCard extends StatefulWidget {
  final String role;
  final String columns;
  final List<String> columnNotes;
  final VoidCallback onDownloadTemplate;

  const _FormatGuideCard({
    required this.role,
    required this.columns,
    required this.columnNotes,
    required this.onDownloadTemplate,
  });

  @override
  State<_FormatGuideCard> createState() => _FormatGuideCardState();
}

class _FormatGuideCardState extends State<_FormatGuideCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ReusableCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline, color: AppColors.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text('CSV Format Guide',
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.accent))),
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Hide' : 'Show'),
            ),
          ]),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Required columns:\n${widget.columns}',
                style: AppTypography.caption
                    .copyWith(fontFamily: 'monospace', height: 1.6),
              ),
            ),
            const SizedBox(height: 8),
            ...widget.columnNotes.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('• ', style: TextStyle(color: AppColors.accent)),
                    Expanded(child: Text(n, style: AppTypography.caption)),
                  ]),
                )),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onDownloadTemplate,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(
                    'Download ${widget.role == "STUDENT" ? "Student" : "Lecturer"} Template'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeRadio extends StatelessWidget {
  final String value;
  final String groupValue;
  final String label;
  final String subtitle;
  final ValueChanged<String?> onChanged;

  const _ModeRadio({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => RadioListTile<String>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        title: Text(label, style: AppTypography.bodyMedium),
        subtitle: Text(subtitle, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        activeColor: AppColors.primary,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );
}

class _ResultCard extends StatelessWidget {
  final BulkEnrollmentResult result;
  final VoidCallback? onDownloadErrors;

  const _ResultCard({required this.result, this.onDownloadErrors});

  Color get _headerColor {
    if (result.isFailed) return AppColors.error;
    if (result.isRejected) return AppColors.statusBooked;
    return AppColors.statusFree;
  }

  IconData get _headerIcon {
    if (result.isFailed) return Icons.error_outline;
    if (result.isRejected) return Icons.warning_amber_outlined;
    return Icons.check_circle_outline;
  }

  @override
  Widget build(BuildContext context) {
    return ReusableCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _headerColor.withAlpha(20),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              Icon(_headerIcon, color: _headerColor),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Upload Result',
                      style: AppTypography.titleMedium
                          .copyWith(color: _headerColor))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.message, style: AppTypography.bodySmall),
                const SizedBox(height: 12),
                // Stats row
                Row(children: [
                  _StatChip('Total', result.totalRows, AppColors.primary),
                  const SizedBox(width: 8),
                  _StatChip('Created', result.createdRows, AppColors.statusFree),
                  const SizedBox(width: 8),
                  _StatChip('Errors', result.errorCount,
                      result.errorCount > 0 ? AppColors.error : AppColors.textSecondary),
                  if (result.skippedRows > 0) ...[
                    const SizedBox(width: 8),
                    _StatChip('Skipped', result.skippedRows, AppColors.statusBooked),
                  ],
                ]),
                // Welcome emails note
                if (result.createdRows > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.statusFree.withAlpha(10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.statusFree.withAlpha(50)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.email_outlined, size: 14, color: AppColors.statusFree),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Welcome emails with 48-hour password reset links are being sent in the background.',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.statusFree),
                        ),
                      ),
                    ]),
                  ),
                ],
                // Download errors button
                if (result.hasErrors && onDownloadErrors != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onDownloadErrors,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: Text('Download Error Report (${result.errorCount} errors)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                            color: AppColors.error.withAlpha(120)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatChip(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$value',
              style: AppTypography.titleMedium
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
          Text(label,
              style: AppTypography.caption.copyWith(color: color)),
        ]),
      );
}

class _JobHistoryTile extends StatelessWidget {
  final BulkEnrollmentJob job;
  final VoidCallback? onDownload;
  const _JobHistoryTile({required this.job, this.onDownload});

  Color get _statusColor => switch (job.status) {
        'COMPLETED' => AppColors.statusFree,
        'FAILED' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ReusableCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(Icons.description_outlined,
                size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.filename.isNotEmpty ? job.filename : 'No filename',
                      style: AppTypography.bodySmall
                          .copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${job.totalRows} rows · ${job.createdRows} created · ${job.errorCount} errors',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ]),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(job.status,
                  style: AppTypography.caption
                      .copyWith(color: _statusColor, fontSize: 10)),
            ),
            if (onDownload != null) ...[
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.download_outlined, size: 18),
                onPressed: onDownload,
                tooltip: 'Download error report',
                color: AppColors.error,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ]),
        ),
      );
}

class _AlertBanner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;
  const _AlertBanner(
      {required this.message, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style:
                      AppTypography.bodySmall.copyWith(color: color))),
        ]),
      );
}
