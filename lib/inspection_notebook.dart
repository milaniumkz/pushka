part of 'classifieds_app.dart';

/// A private, on-device worksheet; never represents a seller's verification.
class InspectionNote {
  InspectionNote({
    required this.id,
    required this.title,
    required this.price,
    required this.city,
    required this.condition,
    required this.category,
    this.notes = '',
    Set<String>? checked,
  }) : checked = checked ?? {};
  final String id, title, city, condition, category;
  final int price;
  String notes;
  final Set<String> checked;

  factory InspectionNote.fromListing(ListingAd ad) => InspectionNote(
    id: ad.id,
    title: ad.title,
    price: ad.price,
    city: ad.city,
    condition: conditionLabel(ad.condition),
    category: ad.categoryId,
  );
  factory InspectionNote.fromJson(Map<String, dynamic> data) => InspectionNote(
    id: data['id'] as String,
    title: data['title'] as String,
    price: (data['price'] as num).toInt(),
    city: data['city'] as String,
    condition: data['condition'] as String,
    category: data['category'] as String,
    notes: data['notes'] as String? ?? '',
    checked: (data['checked'] as List? ?? []).whereType<String>().toSet(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'price': price,
    'city': city,
    'condition': condition,
    'category': category,
    'notes': notes,
    'checked': checked.toList(),
  };
}

class InspectionNotebook {
  static const storageKey = 'pushka_private_inspections_v1';
  final entries = <InspectionNote>[];
  Future<void> load() async {
    final raw = await const LocalPreferenceStore().getString(storageKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as List;
    final loaded = decoded
        .map(
          (e) => InspectionNote.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    entries
      ..clear()
      ..addAll(loaded);
  }

  Future<void> save() => const LocalPreferenceStore().setString(
    storageKey,
    jsonEncode(entries.map((e) => e.toJson()).toList()),
  );
  void add(ListingAd ad) {
    if (entries.any((e) => e.id == ad.id)) return;
    if (entries.length >= 10) throw StateError('notebook_full');
    entries.insert(0, InspectionNote.fromListing(ad));
  }
}

const inspectionChecks = <String, (String, String)>{
  'condition': ('Осмотреть состояние и дефекты', 'Күйі мен ақауларын тексеру'),
  'operation': (
    'Проверить работу при продавце',
    'Сатушының алдында жұмысын тексеру',
  ),
  'complete': (
    'Сверить комплект и описание',
    'Жинақ пен сипаттаманы салыстыру',
  ),
  'ownership': ('Уточнить происхождение вещи', 'Заттың шығу тегін анықтау'),
  'price': ('Согласовать итоговую цену', 'Соңғы бағаны келісу'),
  'meeting': (
    'Выбрать безопасное место встречи',
    'Қауіпсіз кездесу орнын таңдау',
  ),
};

class InspectionNotebookScreen extends StatefulWidget {
  const InspectionNotebookScreen({this.initialListing, super.key});
  final ListingAd? initialListing;
  @override
  State<InspectionNotebookScreen> createState() =>
      _InspectionNotebookScreenState();
}

class _InspectionNotebookScreenState extends State<InspectionNotebookScreen> {
  final notebook = InspectionNotebook();
  final selected = <String>{};
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      await notebook.load();
      final ad = widget.initialListing;
      if (ad != null) {
        notebook.add(ad);
        await notebook.save();
      }
    } catch (_) {
      error = 'load';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> addPersonalItem() async {
    final store = ClassifiedsScope.of(context);
    final title = TextEditingController();
    final price = TextEditingController();
    final city = TextEditingController(text: store.selectedCity);
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          store.tx('Личная вещь для осмотра', 'Тексеруге арналған жеке зат'),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  store.tx(
                    'Запись видна только вам. Это не публикация объявления.',
                    'Жазба тек сізге көрінеді. Бұл хабарландыру жариялау емес.',
                  ),
                ),
                TextFormField(
                  controller: title,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: store.tx('Название вещи', 'Зат атауы'),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? store.tx('Введите название', 'Атауын енгізіңіз')
                      : null,
                ),
                TextFormField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: InputDecoration(
                    labelText: store.tx('Цена, ₸', 'Бағасы, ₸'),
                  ),
                  validator: (v) => int.tryParse(v ?? '') == null
                      ? store.tx(
                          'Введите цену цифрами',
                          'Бағаны санмен енгізіңіз',
                        )
                      : null,
                ),
                TextFormField(
                  controller: city,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: store.tx('Город', 'Қала'),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? store.tx('Введите город', 'Қаланы енгізіңіз')
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(store.tx('Отмена', 'Бас тарту')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: Text(store.tx('Добавить в блокнот', 'Дәптерге қосу')),
          ),
        ],
      ),
    );
    if (accepted == true) {
      final entry = InspectionNote(
        id: 'personal_${DateTime.now().microsecondsSinceEpoch}',
        title: title.text.trim(),
        price: int.parse(price.text),
        city: city.text.trim(),
        condition: store.tx('Уточнить при осмотре', 'Тексеру кезінде нақтылау'),
        category: 'personal',
      );
      try {
        if (notebook.entries.length >= 10) throw StateError('notebook_full');
        notebook.entries.insert(0, entry);
        await notebook.save();
        error = null;
      } catch (_) {
        notebook.entries.remove(entry);
        error = 'save';
      }
      if (mounted) setState(() {});
    }
    // Dialog route animations can still hold the fields during this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      title.dispose();
      price.dispose();
      city.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(store.tx('Блокнот осмотров', 'Тексеру дәптері')),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  store.tx(
                    'Личные заметки перед встречей',
                    'Кездесу алдындағы жеке жазбалар',
                  ),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  store.tx(
                    'Блокнот хранится только на этом устройстве, доступен без входа и не отправляется продавцу. Снимки объявлений могут устареть. Отметки — ваши наблюдения, а не гарантия PUSHKA.',
                    'Дәптер тек осы құрылғыда сақталады, кірусіз қолжетімді және сатушыға жіберілмейді. Хабарландыру деректері ескіруі мүмкін. Белгілер — PUSHKA кепілдігі емес, жеке бақылауларыңыз.',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      store.tx(
                        'Не удалось сохранить блокнот или достигнут лимит 10 объявлений. Попробуйте снова.',
                        'Дәптер сақталмады немесе 10 хабарландыру шегіне жеттіңіз. Қайта көріңіз.',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: notebook.entries.length >= 10
                      ? null
                      : addPersonalItem,
                  icon: const Icon(Icons.add),
                  label: Text(
                    store.tx('Добавить вещь вручную', 'Затты қолмен қосу'),
                  ),
                ),
                const SizedBox(height: 12),
                if (notebook.entries.isEmpty) ...[
                  const Icon(Icons.fact_check_outlined, size: 64, color: cBlue),
                  const SizedBox(height: 12),
                  Text(
                    store.tx(
                      'Откройте объявление и нажмите «Подготовить осмотр и сравнить». Здесь появятся его цена, чек-лист и ваши заметки. Можно сохранить до 10 вариантов и сравнить любые 2–3.',
                      'Хабарландыруды ашып, «Тексеруге дайындалып, салыстыру» түймесін басыңыз. Баға, тексеру тізімі және жазбалар осында болады. 10 нұсқаға дейін сақтап, кез келген 2–3 нұсқаны салыстырыңыз.',
                    ),
                  ),
                ],
                if (notebook.entries.isNotEmpty) ...[
                  FilledButton.icon(
                    onPressed: selected.length < 2
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => InspectionCompareScreen(
                                notes: notebook.entries
                                    .where((e) => selected.contains(e.id))
                                    .toList(),
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(
                      store.tx(
                        'Сравнить выбранные (${selected.length}/3)',
                        'Таңдалғандарды салыстыру (${selected.length}/3)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final entry in notebook.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              entry.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${cMoney(entry.price)} · ${entry.city}\n${entry.condition}',
                            ),
                            value: selected.contains(entry.id),
                            onChanged: (value) => setState(() {
                              if (value == false) {
                                selected.remove(entry.id);
                              } else if (selected.length < 3) {
                                selected.add(entry.id);
                              }
                            }),
                          ),
                          Text(
                            store.tx(
                              'Проверено: ${entry.checked.length}/${inspectionChecks.length}',
                              'Тексерілді: ${entry.checked.length}/${inspectionChecks.length}',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => InspectionWorksheetScreen(
                                        entry: entry,
                                        notebook: notebook,
                                      ),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                                child: Text(
                                  store.tx(
                                    'Осмотр и заметки',
                                    'Тексеру және жазбалар',
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final index = notebook.entries.indexOf(entry);
                                  notebook.entries.remove(entry);
                                  try {
                                    await notebook.save();
                                    selected.remove(entry.id);
                                    error = null;
                                  } catch (_) {
                                    notebook.entries.insert(index, entry);
                                    error = 'save';
                                  }
                                  if (mounted) setState(() {});
                                },
                                child: Text(
                                  store.tx(
                                    'Убрать из блокнота',
                                    'Дәптерден алып тастау',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class InspectionWorksheetScreen extends StatefulWidget {
  const InspectionWorksheetScreen({
    required this.entry,
    required this.notebook,
    super.key,
  });
  final InspectionNote entry;
  final InspectionNotebook notebook;
  @override
  State<InspectionWorksheetScreen> createState() =>
      _InspectionWorksheetScreenState();
}

class _InspectionWorksheetScreenState extends State<InspectionWorksheetScreen> {
  late final notes = TextEditingController(text: widget.entry.notes);
  late final checked = {...widget.entry.checked};
  bool saving = false;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    final previousNotes = widget.entry.notes;
    final previousChecks = {...widget.entry.checked};
    widget.entry.notes = notes.text;
    widget.entry.checked
      ..clear()
      ..addAll(checked);
    try {
      await widget.notebook.save();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      widget.entry.notes = previousNotes;
      widget.entry.checked
        ..clear()
        ..addAll(previousChecks);
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ClassifiedsScope.of(context).tx(
                'Не удалось сохранить. Повторите попытку.',
                'Сақталмады. Қайталап көріңіз.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(store.tx('Лист осмотра', 'Тексеру парағы'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.entry.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Text(
            '${cMoney(widget.entry.price)} · ${widget.entry.city} · ${widget.entry.condition}',
          ),
          const SizedBox(height: 16),
          for (final item in inspectionChecks.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(store.tx(item.value.$1, item.value.$2)),
              value: checked.contains(item.key),
              onChanged: saving
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        checked.add(item.key);
                      } else {
                        checked.remove(item.key);
                      }
                    }),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            enabled: !saving,
            maxLength: 1000,
            minLines: 4,
            maxLines: 7,
            decoration: InputDecoration(
              labelText: store.tx('Мои заметки', 'Жеке жазбаларым'),
              hintText: store.tx(
                'Дефекты, вопросы продавцу, место встречи…',
                'Ақаулар, сатушыға сұрақтар, кездесу орны…',
              ),
            ),
          ),
          Text(
            store.tx(
              'Не переводите предоплату незнакомым людям. Проверяйте вещь до оплаты; не сообщайте коды и данные карты.',
              'Бейтаныс адамдарға алдын ала төлем жібермеңіз. Төлемге дейін затты тексеріңіз; кодтар мен карта деректерін бермеңіз.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(store.tx('Сохранить осмотр', 'Тексеруді сақтау')),
          ),
        ],
      ),
    );
  }
}

class InspectionCompareScreen extends StatelessWidget {
  const InspectionCompareScreen({required this.notes, super.key});
  final List<InspectionNote> notes;
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          store.tx('Сравнение перед встречей', 'Кездесу алдында салыстыру'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            store.tx(
              'Сравните состояние, цену и результаты собственного осмотра. Цена сохранена в момент добавления; уточните её у автора.',
              'Күйін, бағасын және жеке тексеру нәтижесін салыстырыңыз. Баға қосылған кезде сақталған; автордан нақтылаңыз.',
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(store.tx('Критерий', 'Өлшем'))),
                for (final note in notes)
                  DataColumn(
                    label: SizedBox(
                      width: 170,
                      child: Text(note.title, maxLines: 3),
                    ),
                  ),
              ],
              rows: [
                for (final row
                    in <(String, String, String Function(InspectionNote))>[
                      ('Цена', 'Баға', (n) => cMoney(n.price)),
                      ('Город', 'Қала', (n) => n.city),
                      ('Состояние', 'Күйі', (n) => n.condition),
                      (
                        'Проверено',
                        'Тексерілді',
                        (n) => '${n.checked.length}/${inspectionChecks.length}',
                      ),
                      for (final check in inspectionChecks.entries)
                        (
                          check.value.$1,
                          check.value.$2,
                          (n) => n.checked.contains(check.key)
                              ? store.tx('Да', 'Иә')
                              : '—',
                        ),
                    ])
                  DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 160,
                          child: Text(store.tx(row.$1, row.$2)),
                        ),
                      ),
                      for (final note in notes) DataCell(Text(row.$3(note))),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final note in notes)
            if (note.notes.isNotEmpty)
              CGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(note.notes),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
