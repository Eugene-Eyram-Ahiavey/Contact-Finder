import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/widgets/create_call_center_dialog.dart';

void main() {
  testWidgets('CreateCallCenterDialog validates input and invokes onSave with full details',
      (WidgetTester tester) async {
    CallCenter? savedCenter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  savedCenter = await CreateCallCenterDialog.show(context);
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      ),
    );

    // Open the dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify dialog title and fields
    expect(find.text('New Call Center'), findsOneWidget);
    expect(find.text('Call Center Name'), findsOneWidget);
    expect(find.text('Area/ Location'), findsOneWidget);
    expect(find.text('Description/purpose (optional)'), findsOneWidget);
    expect(find.text('Theme:'), findsOneWidget);

    // Attempt to submit empty name
    await tester.tap(find.text('Create Center'));
    await tester.pumpAndSettle();
    expect(
      find.text('Please enter a name for the Call Center'),
      findsOneWidget,
    );
    expect(savedCenter, isNull);

    // Enter form details matching the Figma mock
    await tester.enterText(find.byType(TextField).at(0), 'Invasion');
    await tester.enterText(find.byType(TextField).at(1), 'GCTU');
    await tester.enterText(find.byType(TextField).at(2), 'Swollen Saturday');

    // Submit
    await tester.tap(find.text('Create Center'));
    await tester.pumpAndSettle();

    // Verify callback was called with entered details
    expect(savedCenter, isNotNull);
    expect(savedCenter!.name, 'Invasion');
    expect(savedCenter!.location, 'GCTU');
    expect(savedCenter!.description, 'Swollen Saturday');
    expect(savedCenter!.colorHex, isNotEmpty);
  });
}

