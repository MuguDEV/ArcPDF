import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/logger.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  List<LogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() {
    setState(() {
      _logs = AppLogger.getLogs();
    });
  }

  Future<void> _clearLogs() async {
    await AppLogger.clearLogs();
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Diagnostics & Logs', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear logs',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Logs?'),
                  content: const Text('This will permanently delete all diagnostic logs.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _clearLogs();
              }
            },
          ),
        ],
      ),
      body: _logs.isEmpty
          ? Center(
              child: Text(
                'No logs available.',
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _logs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final log = _logs[index];
                return _LogEntryCard(log: log);
              },
            ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({required this.log});

  final LogEntry log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = log.level == 'ERROR';
    final isWarning = log.level == 'WARNING';

    final borderColor = isError
        ? theme.colorScheme.error
        : (isWarning ? Colors.orange : theme.colorScheme.outlineVariant.withValues(alpha: 0.5));

    final iconColor = isError
        ? theme.colorScheme.error
        : (isWarning ? Colors.orange : theme.colorScheme.onSurfaceVariant);

    final icon = isError
        ? Icons.error_outline_rounded
        : (isWarning ? Icons.warning_amber_rounded : Icons.info_outline_rounded);

    final timeStr = DateFormat('MMM d, y HH:mm:ss').format(log.timestamp);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Text(
                log.level,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            log.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (log.stackTrace != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                log.stackTrace!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
