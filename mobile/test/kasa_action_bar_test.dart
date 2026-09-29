import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/widgets/kasa_layout.dart';
import 'package:rental_manager/core/widgets/kasa_primitives.dart';

void main() {
  testWidgets('the action bar takes only the height of its button', (tester) async {
    // A Scaffold lets its bottomNavigationBar grow to the screen height, and
    // the bar once filled the whole screen with one coral button.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: KasaActionBar(children: [
          KasaButton(label: 'Record payment', onTap: () {}),
        ]),
      ),
    ));

    final bar = tester.getSize(find.byType(KasaActionBar));
    expect(bar.height, lessThan(120));
  });
}
