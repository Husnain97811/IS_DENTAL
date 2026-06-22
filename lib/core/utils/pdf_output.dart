import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Shows a "Save PDF / Print" chooser, checks for a printer, prints, and
/// surfaces any error in a dialog.
Future<void> showPdfOutput(
  BuildContext context, {
  required Future<Uint8List> Function() build,
  required String filename,
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Export'),
      content: const Text('Save as a PDF file, or send to a printer?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(ctx, 'pdf'),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: const Text('Save PDF'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, 'print'),
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text('Print'),
        ),
      ],
    ),
  );
  if (choice == null) return;

  try {
    final bytes = await build();

    if (choice == 'pdf') {
      await Printing.sharePdf(bytes: bytes, filename: filename);
      return;
    }

    // Print: confirm a printer exists first.
    final printers = await Printing.listPrinters();
    if (printers.isEmpty) {
      if (context.mounted) {
        _error(context, 'No printer found. Connect a printer and try again.');
      }
      return;
    }
    await Printing.layoutPdf(onLayout: (_) => bytes);
  } catch (e) {
    if (context.mounted) _error(context, 'Couldn’t complete that: $e');
  }
}

void _error(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Something went wrong'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
