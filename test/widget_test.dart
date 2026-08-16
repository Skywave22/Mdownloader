// UI smoke tests: the design-system widgets must build without errors and the
// theme must be wired up correctly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdownloader/core/theme.dart';
import 'package:mdownloader/ui/widgets.dart';

void main() {
  testWidgets('theme builds and renders core widgets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(
          body: Column(
            children: [
              SectionHeader(title: 'Trending'),
              GradPill(text: '2024'),
              MetaPill(text: 'Movie'),
              RatingBadge(score: 8.4),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    expect(find.text('8.4'), findsOneWidget);
  });

  testWidgets('LoadingView and ErrorView render', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: LoadingView()),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ErrorView(message: 'boom', onRetry: () {}),
        ),
      ),
    );
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('GlassCard renders children', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(
          body: GlassCard(
            child: Text('hello', style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
    expect(find.text('hello'), findsOneWidget);
  });
}
