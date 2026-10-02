import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/app.dart';

void main() {
  testWidgets('shows the Mohsen Tripo home shell', (tester) async {
    await tester.pumpWidget(const MohsenTripoApp());

    expect(find.text('Mohsen Tripo'), findsOneWidget);
  });
}
