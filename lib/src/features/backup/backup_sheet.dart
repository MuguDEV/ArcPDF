import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/logger.dart';
import '../../shared/theme/arc_colors.dart';
import '../../shared/utils/glass_bottom_sheet.dart';
import '../../shared/widgets/arc_progress_indicator.dart';
import '../../shared/widgets/sheet/app_components.dart';
import '../pdf/application/pdf_library_controller.dart';
import 'backup_service.dart';

/// Entry point used by Settings.
///
/// [service], [actions] and [onRestored] exist for tests; production callers
/// pass only the context.
Future<void> showBackupRestoreSheet(
  BuildContext context, {
  BackupService? service,
  BackupFileActions? actions,
  VoidCallback? onRestored,
}) async {
  final backupService = service ?? await BackupService.create();
  if (!context.mounted) return;
  ProviderContainer? container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    container = null;
  }
  await showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BackupRestoreSheet(
      service: backupService,
      actions: actions ?? const PlatformBackupFileActions(),
      onRestored: onRestored ??
          () => container?.invalidate(pdfLibraryControllerProvider),
    ),
  );
}

/// Platform interactions (share sheet, file dialogs), injectable for tests.
abstract class BackupFileActions {
  /// Returns false if the user dismissed the share sheet.
  Future<bool> share(BackupExport export, {Rect? origin});

  /// Returns false if the user cancelled.
  Future<bool> saveAs(BackupExport export);

  /// Returns the picked file's path, or null if cancelled.
  Future<String?> pickBackupPath();
}

class PlatformBackupFileActions implements BackupFileActions {
  const PlatformBackupFileActions();

  @override
  Future<bool> share(BackupExport export, {Rect? origin}) async {
    final result = await SharePlus.instance.share(ShareParams(
      files: [
        XFile(export.file.path,
            mimeType: 'application/json', name: export.fileName),
      ],
      fileNameOverrides: [export.fileName],
      sharePositionOrigin: origin,
    ));
    return result.status != ShareResultStatus.dismissed;
  }

  @override
  Future<bool> saveAs(BackupExport export) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save ArcPDF backup',
      fileName: export.fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: export.bytes,
    );
    return saved != null;
  }

  @override
  Future<String?> pickBackupPath() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Choose an ArcPDF backup',
      type: FileType.any,
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return null;
    return files.first.path;
  }
}

enum _Stage { idle, working, preview, result, error }

class BackupRestoreSheet extends StatefulWidget {
  const BackupRestoreSheet({
    super.key,
    required this.service,
    this.actions = const PlatformBackupFileActions(),
    this.onRestored,
  });

  final BackupService service;
  final BackupFileActions actions;
  final VoidCallback? onRestored;

  @override
  State<BackupRestoreSheet> createState() => _BackupRestoreSheetState();
}

class _BackupRestoreSheetState extends State<BackupRestoreSheet> {
  _Stage _stage = _Stage.idle;
  String _workingLabel = '';
  String? _status;
  String _errorMessage = '';
  BackupArchive? _archive;
  RestoreMode _mode = RestoreMode.merge;
  BackupRestoreResult? _result;

  Rect? _origin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_stage == _Stage.working) return;
    setState(() {
      _stage = _Stage.working;
      _workingLabel = label;
      _status = null;
    });
    try {
      await action();
    } on BackupException catch (error) {
      _fail(error.message);
    } catch (error, stack) {
      await AppLogger.error('backup.action.failed', error, stack);
      _fail('Something went wrong. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.error;
      _errorMessage = message;
    });
  }

  Future<void> _share() => _run('Preparing backup…', () async {
        final export = await widget.service.createExport();
        if (!mounted) return;
        final shared = await widget.actions.share(export, origin: _origin());
        if (!mounted) return;
        setState(() {
          _stage = _Stage.idle;
          _status = shared ? 'Backup ready. Keep it private.' : null;
        });
      });

  Future<void> _save() => _run('Preparing backup…', () async {
        final export = await widget.service.createExport();
        if (!mounted) return;
        final saved = await widget.actions.saveAs(export);
        if (!mounted) return;
        setState(() {
          _stage = _Stage.idle;
          _status = saved ? 'Backup saved. Keep it private.' : null;
        });
      });

  Future<void> _pick() => _run('Reading backup…', () async {
        final path = await widget.actions.pickBackupPath();
        if (!mounted) return;
        if (path == null) {
          setState(() => _stage = _Stage.idle);
          return;
        }
        final archive = await widget.service.readFile(path);
        if (!mounted) return;
        setState(() {
          _archive = archive;
          _mode = RestoreMode.merge;
          _stage = _Stage.preview;
        });
      });

  Future<void> _confirmRestore() async {
    final archive = _archive;
    if (archive == null || _stage != _Stage.preview) return;
    if (_mode == RestoreMode.replace) {
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Replace data on this device?',
          actions: [
            _DialogButton(
                label: 'Cancel',
                onPressed: () => Navigator.pop(dialogContext, false)),
            _DialogButton(
                label: 'Replace',
                onPressed: () => Navigator.pop(dialogContext, true)),
          ],
          child: const Text(
              'Favorites, tags and reading progress on this device that are '
              'not in the backup will be removed.'),
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run('Restoring…', () async {
      final result = await widget.service.restore(archive, mode: _mode);
      widget.onRestored?.call();
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _Stage.result;
      });
    });
  }

  void _backToStart() => setState(() {
        _stage = _Stage.idle;
        _archive = null;
        _result = null;
      });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage != _Stage.working,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: ArcColors.space16),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: switch (_stage) {
            _Stage.idle => _buildIdle(context),
            _Stage.working => _buildWorking(context),
            _Stage.preview => _buildPreview(context),
            _Stage.result => _buildResult(context),
            _Stage.error => _buildError(context),
          },
        ),
      ),
    );
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title('Backup & restore', theme: theme),
        _Body(
          'Saves your favorites, tags, reading progress and lock preferences. '
          'PDF files, vault contents, PINs, patterns and biometric data are '
          'never included.',
          theme: theme,
        ),
        const SheetSectionHeader(title: 'Back up', first: true),
        SheetActionRow(
          icon: Icons.ios_share_rounded,
          label: 'Share backup',
          onTap: _share,
        ),
        SheetActionRow(
          icon: Icons.save_alt_rounded,
          label: 'Save to device',
          onTap: _save,
        ),
        const SheetSectionHeader(title: 'Restore'),
        SheetActionRow(
          icon: Icons.settings_backup_restore_rounded,
          label: 'Restore from backup file',
          onTap: _pick,
        ),
        if (_status != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ArcColors.screenPadding,
                ArcColors.space12,
                ArcColors.screenPadding,
                0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded,
                      size: 20, color: theme.colorScheme.onSurface),
                  const SizedBox(width: ArcColors.space8),
                  Expanded(
                      child: Text(_status!, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ),
        _Body(
          'A backup lists the locations of your PDFs, so treat it like a '
          'private document.',
          theme: theme,
          top: ArcColors.space16,
        ),
      ],
    );
  }

  Widget _buildWorking(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: _workingLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ArcColors.screenPadding,
          vertical: ArcColors.space32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArcProgressIndicator(),
            const SizedBox(height: ArcColors.space16),
            Text(_workingLabel,
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _archive!.preview;
    final created =
        DateFormat.yMMMd().add_jm().format(preview.createdAt.toLocal());
    final merge = _mode == RestoreMode.merge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title('Restore backup', theme: theme),
        _Body('Created $created with ArcPDF ${preview.appVersion}.',
            theme: theme),
        const SizedBox(height: ArcColors.space8),
        _CountRow(label: 'Favorites', value: '${preview.favorites}'),
        _CountRow(
            label: 'Tagged documents', value: '${preview.taggedDocuments}'),
        _CountRow(label: 'Reading progress', value: '${preview.progress}'),
        _CountRow(
          label: 'Lock preferences',
          value: preview.hasSecurityPreferences ? 'Included' : 'None',
        ),
        const SheetSectionHeader(title: 'How to restore'),
        Semantics(
          inMutuallyExclusiveGroup: true,
          checked: merge,
          child: SheetRadioRow<RestoreMode>(
            value: RestoreMode.merge,
            groupValue: _mode,
            label: 'Merge with this device',
            onChanged: (value) => setState(() => _mode = value),
          ),
        ),
        Semantics(
          inMutuallyExclusiveGroup: true,
          checked: !merge,
          child: SheetRadioRow<RestoreMode>(
            value: RestoreMode.replace,
            groupValue: _mode,
            label: 'Replace data on this device',
            onChanged: (value) => setState(() => _mode = value),
          ),
        ),
        _Body(
          merge
              ? 'Adds favorites and tags from the backup. Reading positions '
                  'already on this device are kept.'
              : 'Removes favorites, tags and reading progress that are not in '
                  'the backup.',
          theme: theme,
          top: ArcColors.space8,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ArcColors.screenPadding,
            ArcColors.space16,
            ArcColors.screenPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: _buttonStyle,
                onPressed: _confirmRestore,
                child: Text(merge ? 'Merge backup' : 'Replace data'),
              ),
              const SizedBox(height: ArcColors.space8),
              TextButton(
                style: _buttonStyle,
                onPressed: _backToStart,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;
    final notes = <String>[
      if (result.keptLocalProgress > 0)
        '${result.keptLocalProgress} reading '
            '${result.keptLocalProgress == 1 ? 'position' : 'positions'} '
            'already on this device ${result.keptLocalProgress == 1 ? 'was' : 'were'} kept.',
      if (result.skipped > 0)
        '${result.skipped} ${result.skipped == 1 ? 'item' : 'items'} for the '
            'private vault ${result.skipped == 1 ? 'was' : 'were'} ignored.',
      if (result.securityApplied)
        'Lock preferences apply the next time ArcPDF starts. Your PIN or '
            'pattern was not changed.',
      'Files that are missing now will reappear in your library if they '
          'return to the same location.',
    ];
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title('Restore complete', theme: theme),
          _CountRow(label: 'Favorites', value: '${result.favorites}'),
          _CountRow(
              label: 'Tagged documents', value: '${result.taggedDocuments}'),
          _CountRow(label: 'Reading progress', value: '${result.progress}'),
          for (final note in notes)
            _Body(note, theme: theme, top: ArcColors.space8),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ArcColors.screenPadding,
              ArcColors.space16,
              ArcColors.screenPadding,
              0,
            ),
            child: FilledButton(
              style: _buttonStyle,
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title('Backup problem', theme: theme),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: ArcColors.screenPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: theme.colorScheme.error),
                const SizedBox(width: ArcColors.space12),
                Expanded(
                    child:
                        Text(_errorMessage, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ArcColors.screenPadding,
              ArcColors.space20,
              ArcColors.screenPadding,
              0,
            ),
            child: FilledButton(
              style: _buttonStyle,
              onPressed: _backToStart,
              child: const Text('Back'),
            ),
          ),
        ],
      ),
    );
  }
}

final _buttonStyle = FilledButton.styleFrom(
  minimumSize:
      const Size(ArcColors.minTouchTarget * 2, ArcColors.minTouchTarget),
  tapTargetSize: MaterialTapTargetSize.padded,
);

class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(
          minimumSize:
              const Size(ArcColors.minTouchTarget, ArcColors.minTouchTarget),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}

class _Title extends StatelessWidget {
  const _Title(this.text, {required this.theme});
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ArcColors.screenPadding,
            ArcColors.space4,
            ArcColors.screenPadding,
            ArcColors.space8,
          ),
          child: Text(text, style: theme.textTheme.titleLarge),
        ),
      );
}

class _Body extends StatelessWidget {
  const _Body(this.text, {required this.theme, this.top = 0});
  final String text;
  final ThemeData theme;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            ArcColors.screenPadding, top, ArcColors.screenPadding, 0),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ArcColors.minTouchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ArcColors.screenPadding, vertical: ArcColors.space8),
          // Wrap: at large text sizes the value drops below its label.
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: ArcColors.space12,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge),
                  Text(value,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
