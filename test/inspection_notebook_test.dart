import 'package:flutter_test/flutter_test.dart';
import 'package:pushka/classifieds_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widget_test.dart' show seededTestStore, pumpClassifieds;
import 'package:flutter/material.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'inspection notes persist locally and adding the same listing preserves work',
    () async {
      final ad = seededTestStore().listings.first;
      final notebook = InspectionNotebook()..add(ad);
      notebook.entries.first.notes = 'Проверить батарею';
      notebook.entries.first.checked.add('operation');
      notebook.add(ad);
      expect(notebook.entries, hasLength(1));
      await notebook.save();
      final restored = InspectionNotebook();
      await restored.load();
      expect(restored.entries.single.notes, 'Проверить батарею');
      expect(restored.entries.single.checked, {'operation'});
      expect(restored.entries.single.price, ad.price);
    },
  );

  testWidgets('guest can save a checklist and compare real listing snapshots', (
    tester,
  ) async {
    final store = seededTestStore();
    final notebook = InspectionNotebook();
    for (final listing in store.listings) {
      notebook.add(listing);
    }
    await notebook.save();
    await pumpClassifieds(tester, store: store);
    await tester.tap(find.text('Мой блокнот осмотров'));
    await tester.pumpAndSettle();
    expect(find.text('iPhone 15 Pro 256 GB'), findsOneWidget);
    await tester.tap(find.text('Осмотр и заметки').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Осмотреть состояние и дефекты'));
    await tester.enterText(find.byType(TextField), 'Есть царапина на корпусе');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Сохранить осмотр'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Сохранить осмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Проверено: 1/6'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сравнить выбранные (2/3)'));
    await tester.pumpAndSettle();
    expect(find.text('Сравнение перед встречей'), findsOneWidget);
    expect(find.text('Есть царапина на корпусе'), findsOneWidget);
    expect(store.isAuthorized, isFalse);
  });

  testWidgets('guest can prepare a personal item without publishing it', (
    tester,
  ) async {
    final store = seededTestStore();
    await pumpClassifieds(tester, store: store);
    await tester.tap(find.text('Мой блокнот осмотров'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить вещь вручную'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Велосипед для осмотра',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '45000');
    await tester.tap(find.text('Добавить в блокнот'));
    await tester.pumpAndSettle();
    expect(find.text('Велосипед для осмотра'), findsOneWidget);
    expect(store.listings, hasLength(2));
    expect(store.isAuthorized, isFalse);
    final restored = InspectionNotebook();
    await restored.load();
    expect(restored.entries.single.price, 45000);
  });
}
