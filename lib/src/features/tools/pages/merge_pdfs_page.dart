import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../tools_service.dart';
import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';

class MergePdfsPage extends StatefulWidget {
  const MergePdfsPage({super.key});

  @override
  State<MergePdfsPage> createState() => _MergePdfsPageState();
}

class _MergePdfsPageState extends State<MergePdfsPage> {
  List<String> _selectedFiles = [];

  Future<void> _pickFiles() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: true);
    if (paths != null && paths.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(paths);
      });
    }
  }

  Future<void> _mergeFiles() async {
    if (_selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least 2 PDFs to merge.')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ToolActionDialog(title: 'Merging PDFs', message: 'Please wait...', isLoading: true),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    final outputPath = p.join(dir, 'Merged_${DateTime.now().millisecondsSinceEpoch}.pdf');

    final successPath = await ToolsService.mergePdfs(_selectedFiles, outputPath);

    if (!mounted) return;
    Navigator.of(context).pop();

    if (successPath != null) {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(title: 'Success', message: 'Saved to:\n$successPath', isLoading: false, outputPath: successPath),
      ).then((_) => Navigator.of(context).pop());
    } else {
      showDialog(
        context: context,
        builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to merge.', isLoading: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDFs')),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _selectedFiles.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _selectedFiles.removeAt(oldIndex);
                  _selectedFiles.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final path = _selectedFiles[index];
                return ListTile(
                  key: ValueKey(path),
                  leading: const Icon(Icons.picture_as_pdf),
                  title: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _selectedFiles.removeAt(index)),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickFiles,
                    child: const Text('Add Files'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _selectedFiles.length >= 2 ? _mergeFiles : null,
                    child: const Text('Merge'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
