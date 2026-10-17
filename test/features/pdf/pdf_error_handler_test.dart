import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_error_handler.dart';

void main() {
  testWidgets('PdfErrorHandler displays user error correctly', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () => PdfErrorHandler.show(context, Exception('Wrong password')),
            child: const Text('Show Error'),
          );
        },
      ),
    ));
    await tester.tap(find.text('Show Error'));
    await tester.pumpAndSettle();

    expect(find.text('User Error'), findsOneWidget);
  });

  testWidgets('PdfErrorHandler displays broken file correctly', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () => PdfErrorHandler.show(context, Exception('Format invalid pdf')),
            child: const Text('Show Error'),
          );
        },
      ),
    ));
    await tester.tap(find.text('Show Error'));
    await tester.pumpAndSettle();

    expect(find.text('Corrupted PDF'), findsOneWidget);
  });

  testWidgets('PdfErrorHandler displays unexpected correctly', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () => PdfErrorHandler.show(context, Exception('Some weird unknown error')),
            child: const Text('Show Error'),
          );
        },
      ),
    ));
    await tester.tap(find.text('Show Error'));
    await tester.pumpAndSettle();

    expect(find.text('Unexpected Error'), findsOneWidget);
  });
}
