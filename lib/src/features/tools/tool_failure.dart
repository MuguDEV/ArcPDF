import 'dart:async';
import 'dart:io';

enum ToolFailureCode {
  permissionDenied,
  storageFull,
  encryptedPdf,
  corruptedPdf,
  unsupportedFile,
  missingInput,
  invalidSelection,
  outputExists,
  timedOut,
  unknown,
}

class ToolFailure implements Exception {
  const ToolFailure(this.code, this.message, {this.technicalDetails});

  final ToolFailureCode code;
  final String message;
  final String? technicalDetails;

  String get title => switch (code) {
        ToolFailureCode.permissionDenied => 'Storage access needed',
        ToolFailureCode.storageFull => 'Not enough storage',
        ToolFailureCode.encryptedPdf => 'Password-protected PDF',
        ToolFailureCode.corruptedPdf => 'Damaged PDF',
        ToolFailureCode.unsupportedFile => 'Unsupported file',
        ToolFailureCode.missingInput => 'File not found',
        ToolFailureCode.invalidSelection => 'Check page selection',
        ToolFailureCode.outputExists => 'Output already exists',
        ToolFailureCode.timedOut => 'Operation timed out',
        ToolFailureCode.unknown => 'Couldn’t complete operation',
      };

  factory ToolFailure.from(Object error, {String? path}) {
    if (error is ToolFailure) return error;
    if (error is FormatException) {
      return ToolFailure(
        ToolFailureCode.invalidSelection,
        error.message.toString().isEmpty
            ? 'Enter valid page numbers or ranges, such as 1, 3-5, 8.'
            : error.message.toString(),
      );
    }
    if (error is TimeoutException) {
      return const ToolFailure(
        ToolFailureCode.timedOut,
        'The PDF took too long to process. Try fewer pages or a smaller file.',
      );
    }
    if (error is FileSystemException) {
      final errno = error.osError?.errorCode;
      final lower = error.message.toLowerCase();
      if (errno == 13 || errno == 1 || lower.contains('permission')) {
        return const ToolFailure(
          ToolFailureCode.permissionDenied,
          'ArcPDF cannot read the source or write to this folder. Choose an accessible folder and try again.',
        );
      }
      if (errno == 28 || lower.contains('no space')) {
        return const ToolFailure(
          ToolFailureCode.storageFull,
          'Free some storage or choose another output folder, then try again.',
        );
      }
      if (lower.contains('already exists')) {
        return const ToolFailure(
          ToolFailureCode.outputExists,
          'A file with this output name already exists. Choose a new name.',
        );
      }
      if (errno == 2 || lower.contains('not found')) {
        return ToolFailure(
          ToolFailureCode.missingInput,
          path == null
              ? 'A selected source file is no longer available.'
              : 'The selected file is no longer available: $path',
        );
      }
    }
    final details = error.toString();
    final lower = details.toLowerCase();
    if (lower.contains('password') ||
        lower.contains('encrypted') ||
        lower.contains('/encrypt')) {
      return const ToolFailure(
        ToolFailureCode.encryptedPdf,
        'Unlock this PDF with its password before using this tool.',
      );
    }
    if (lower.contains('invalid pdf') ||
        lower.contains('corrupt') ||
        lower.contains('xref') ||
        lower.contains('pdf document')) {
      return const ToolFailure(
        ToolFailureCode.corruptedPdf,
        'This PDF is incomplete or damaged and could not be processed safely.',
      );
    }
    if (lower.contains('unsupported') || lower.contains('decode')) {
      return const ToolFailure(
        ToolFailureCode.unsupportedFile,
        'This file format or encoding is not supported by the selected tool.',
      );
    }
    return ToolFailure(
      ToolFailureCode.unknown,
      'The operation failed without changing the original file. Try another source file or output folder.',
      technicalDetails: details,
    );
  }

  @override
  String toString() => 'ToolFailure(${code.name}): $message';
}
