import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/core/utils/responsive.dart';

void main() {
  group('Responsive Layout Tests', () {
    testWidgets('Responsive helper breakpoints on phone, tablet, and desktop', (tester) async {
      // 1. Phone screen size (360 x 800)
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final isPhone = Responsive.isPhone(context);
              final isTablet = Responsive.isTablet(context);
              final isDesktop = Responsive.isDesktop(context);
              final pickVal = Responsive.pick(
                context,
                phone: 'PhoneValue',
                tablet: 'TabletValue',
                desktop: 'DesktopValue',
              );

              return Scaffold(
                body: Column(
                  children: [
                    Text('Phone: $isPhone'),
                    Text('Tablet: $isTablet'),
                    Text('Desktop: $isDesktop'),
                    Text('Pick: $pickVal'),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Phone: true'), findsOneWidget);
      expect(find.text('Tablet: false'), findsOneWidget);
      expect(find.text('Desktop: false'), findsOneWidget);
      expect(find.text('Pick: PhoneValue'), findsOneWidget);

      // 2. Tablet screen size (768 x 1024)
      tester.view.physicalSize = const Size(768, 1024);
      await tester.pump();

      expect(find.text('Phone: false'), findsOneWidget);
      expect(find.text('Tablet: true'), findsOneWidget);
      expect(find.text('Desktop: false'), findsOneWidget);
      expect(find.text('Pick: TabletValue'), findsOneWidget);

      // 3. Desktop screen size (1200 x 900)
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pump();

      expect(find.text('Phone: false'), findsOneWidget);
      expect(find.text('Tablet: false'), findsOneWidget);
      expect(find.text('Desktop: true'), findsOneWidget);
      expect(find.text('Pick: DesktopValue'), findsOneWidget);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('MaxWidthBox constrains wide layout and centers content', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MaxWidthBox(
              maxWidth: 600,
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 100,
                child: Text('Constrained Box Content'),
              ),
            ),
          ),
        ),
      );

      final boxFinder = find.byType(ConstrainedBox);
      expect(boxFinder, findsWidgets);

      final renderBox = tester.renderObject<RenderBox>(find.text('Constrained Box Content'));
      // Content width should be at most 600 - (16*2) = 568
      expect(renderBox.size.width <= 600, true);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });
  });
}
