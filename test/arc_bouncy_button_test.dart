import 'package:arcpdf/src/shared/widgets/arc_bouncy_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget buttonApp({
  required VoidCallback? onPressed,
  bool disableAnimations = false,
  String? tooltip = 'Next page',
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: ArcBouncyButton(
            tooltip: tooltip,
            onPressed: onPressed,
            scaleDown: 0.75,
            child: const Icon(Icons.arrow_forward, size: 16),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Tab shows focus and Enter and Space activate exactly once',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(buttonApp(onPressed: () => calls++));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final ink = tester.widget<InkWell>(find.byType(InkWell));
    final decoration = tester
        .widget<DecoratedBox>(
          find.descendant(
            of: find.byType(ArcBouncyButton),
            matching: find.byType(DecoratedBox),
          ),
        )
        .decoration as BoxDecoration;
    expect(ink.canRequestFocus, isTrue);
    expect(
        decoration.border!.top.color,
        Theme.of(tester.element(find.byType(ArcBouncyButton)))
            .colorScheme
            .primary);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('small children have a stable 44 by 44 hit target and bounce',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(buttonApp(onPressed: () => calls++));
    final button = find.byType(ArcBouncyButton);
    final bounds = tester.getRect(button);
    expect(bounds.size, const Size(44, 44));

    final gesture =
        await tester.startGesture(bounds.topLeft + const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.75);
    expect(tester.getRect(button), bounds);
    expect(calls, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);

    final cancelled = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 100));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('tooltip supplies one button label and one semantic activation',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    await tester.pumpWidget(buttonApp(onPressed: () => calls++));

    expect(find.bySemanticsLabel('Next page'), findsOneWidget);
    final node = tester.getSemantics(find.byType(ArcBouncyButton));
    expect(
        node,
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
        ));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.renderViews.first.owner!.semanticsOwner!
        .performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.longPress(find.byType(ArcBouncyButton));
    await tester.pumpAndSettle();
    expect(find.text('Next page'), findsOneWidget);
    expect(calls, 1);
    semantics.dispose();
  });

  testWidgets('disabled buttons are dimmed, unfocusable and not actionable',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(buttonApp(onPressed: null));

    final node = tester.getSemantics(find.byType(ArcBouncyButton));
    expect(
        node,
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.38);
    expect(
        tester.widget<InkWell>(find.byType(InkWell)).canRequestFocus, isFalse);

    await tester.tap(find.byType(ArcBouncyButton));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(node, isSemantics(isFocused: false));
    semantics.dispose();
  });

  testWidgets('disabling during a press cancels activation and clears bounce',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(buttonApp(onPressed: () => calls++));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ArcBouncyButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(buttonApp(onPressed: null));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);

    await tester.pumpWidget(buttonApp(onPressed: () => calls++));
    await tester.tap(find.byType(ArcBouncyButton));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets(
      'reduced motion suppresses bounce and splash but keeps activation',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(buttonApp(
      onPressed: () => calls++,
      disableAnimations: true,
    ));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ArcBouncyButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
    expect(scale.duration, Duration.zero);
    expect(tester.widget<InkWell>(find.byType(InkWell)).splashFactory,
        NoSplash.splashFactory);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('child text remains the accessible label without a tooltip',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: ArcBouncyButton(
          onPressed: () {},
          child: const Text('Continue'),
        ),
      ),
    ));
    final node = tester.getSemantics(find.byType(ArcBouncyButton));
    expect(node.label, 'Continue');
    expect(node, isSemantics(isButton: true));
    semantics.dispose();
  });
}
