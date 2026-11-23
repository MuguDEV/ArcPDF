import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../shared/theme/arc_icons.dart';
import '../application/open_tabs_provider.dart';
import '../application/pdf_library_controller.dart';
import '../data/native_pdf_scanner.dart';
import '../domain/pdf_file_item.dart';

class DuplicateCleanupPage extends ConsumerStatefulWidget {
  const DuplicateCleanupPage({super.key});

  @override
  ConsumerState<DuplicateCleanupPage> createState() =>
      _DuplicateCleanupPageState();
}

class _DuplicateCleanupPageState extends ConsumerState<DuplicateCleanupPage> {
  final Map<String, String> _keepPaths = {};
  final Set<String> _busyDigests = {};

  String _defaultKeepPath(
      PdfDuplicateGroup group, Map<String, PdfFileItem> items) {
    final paths = [...group.paths];
    paths.sort((a, b) {
      final aDate = items[a]?.lastModified;
      final bDate = items[b]?.lastModified;
      if (aDate == null && bDate == null) return a.compareTo(b);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return paths.first;
  }

  Future<void> _cleanGroup(PdfDuplicateGroup group, String keepPath) async {
    if (_busyDigests.contains(group.digest)) return;
    final removeCount = group.paths.length - 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Keep one and delete $removeCount?'),
        content: Text(
          'ArcPDF will keep ${p.basename(keepPath)} and permanently delete '
          '$removeCount exact ${removeCount == 1 ? 'copy' : 'copies'}. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete copies'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyDigests.add(group.digest));
    final result = await ref
        .read(pdfLibraryControllerProvider.notifier)
        .keepOnlyDuplicate(group, keepPath);
    if (!mounted) return;
    for (final path in result.deletedPaths) {
      final tabs = ref.read(openTabsProvider).tabs;
      final index = tabs.indexWhere((tab) => tab.path == path);
      if (index >= 0) ref.read(openTabsProvider.notifier).closeTab(index);
    }
    setState(() => _busyDigests.remove(group.digest));
    final failed = result.failedPaths.length;
    final message = failed == 0
        ? 'Removed ${result.deletedPaths.length} copies and freed '
            '${_formatBytes(result.reclaimedBytes)}.'
        : 'Removed ${result.deletedPaths.length} copies. $failed could not be deleted.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfLibraryControllerProvider);
    final groups = state.duplicateGroups;
    final items = {for (final item in state.items) item.path: item};
    final theme = Theme.of(context);
    final reclaimable =
        groups.fold<int>(0, (sum, group) => sum + group.reclaimableBytes);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage duplicates')),
      body: groups.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(ArcIcons.success,
                        size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('No exact duplicates',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Your PDF library is already clean.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  '${groups.length} exact-match ${groups.length == 1 ? 'group' : 'groups'} · ${_formatBytes(reclaimable)} reclaimable',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (var index = 0; index < groups.length; index++) ...[
                  _DuplicateGroupCard(
                    key: ValueKey('duplicate-group-${groups[index].digest}'),
                    index: index,
                    group: groups[index],
                    items: items,
                    keepPath: _keepPaths.putIfAbsent(
                      groups[index].digest,
                      () => _defaultKeepPath(groups[index], items),
                    ),
                    busy: _busyDigests.contains(groups[index].digest),
                    onKeepChanged: (path) =>
                        setState(() => _keepPaths[groups[index].digest] = path),
                    onClean: (path) => _cleanGroup(groups[index], path),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({
    super.key,
    required this.index,
    required this.group,
    required this.items,
    required this.keepPath,
    required this.busy,
    required this.onKeepChanged,
    required this.onClean,
  });

  final int index;
  final PdfDuplicateGroup group;
  final Map<String, PdfFileItem> items;
  final String keepPath;
  final bool busy;
  final ValueChanged<String> onKeepChanged;
  final ValueChanged<String> onClean;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Duplicate set ${index + 1}',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${group.paths.length} identical files · ${_formatBytes(group.reclaimableBytes)} reclaimable',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text('Choose the file to keep', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final path in group.paths)
              _KeepFileOption(
                item: items[path],
                path: path,
                selected: path == keepPath,
                enabled: !busy,
                onTap: () => onKeepChanged(path),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : () => onClean(keepPath),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(ArcIcons.remove),
                label: Text(busy
                    ? 'Deleting copies…'
                    : 'Keep selected · Delete ${group.paths.length - 1}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepFileOption extends StatelessWidget {
  const _KeepFileOption({
    required this.item,
    required this.path,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PdfFileItem? item;
  final String path;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: '${p.basename(path)}, ${selected ? 'keep' : 'do not keep'}',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(selected ? ArcIcons.radioSelected : ArcIcons.radio,
                  color: selected ? theme.colorScheme.primary : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item?.name ?? p.basename(path),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      item == null
                          ? path
                          : '${item!.locationLabel} · ${_formatBytes(item!.sizeBytes)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Text('Keep'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
