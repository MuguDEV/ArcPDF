import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../tools_service.dart';
import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';

class SplitPdfPage extends StatefulWidget {
  const SplitPdfPage({super.key});

  @override
  State<SplitPdfPage> createState() => _SplitPdfPageState();
}

class _SplitPdfPageState extends State<SplitPdfPage> {
  String? _selectedFile;
  int _startPage = 1;
  int _endPage = 1;

  Future<void> _pickFile() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: false);
    if (paths != null && paths.isNotEmpty) {
      setState(() => _selectedFile = paths.first);
    }
  }

  Future<void> _splitPdf() async {
    if (_selectedFile == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ToolActionDialog(title: 'Splitting PDF', message: 'Please wait...', isLoading: true),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    final successPath = await ToolsService.splitPdf(_selectedFile!, dir, _startPage, _endPage);

    if (!mounted) return;
    Navigator.of(context).pop();

    if (successPath != null) {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(title: 'Success', message: 'Saved to:\n$successPath', isLoading: false, outputPath: successPath),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to split. Check ranges.', isLoading: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split PDF')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedFile != null)
               Text('Selected: ${p.basename(_selectedFile!)}')
            else
               const Text('No file selected.'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _pickFile, child: const Text('Select PDF')),
            const SizedBox(height: 32),
            TextField(
              decoration: const InputDecoration(labelText: 'Start Page'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _startPage = int.tryParse(v) ?? 1,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(labelText: 'End Page'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _endPage = int.tryParse(v) ?? 1,
            ),
            const Spacer(),
            FilledButton(
              onPressed: _selectedFile != null ? _splitPdf : null,
              child: const Text('Split PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
