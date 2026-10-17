import 'package:deskaone_sdk/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

typedef TestRecord = ({int id, String name});

class TestRecordSpec implements EngineSpec<TestRecord, int> {
  @override
  String get table => 'items';
  @override
  List<String> get columns => ['id', 'name'];
  @override
  List<String> get conflictColumns => ['id'];
  @override
  List<String> get keyColumns => ['id'];
  @override
  String? get intPrimaryKey => 'id';
  @override
  List<Object?> values(TestRecord item) => [item.id, item.name];
  @override
  List<Object?> keyArgs(int id) => [id];
  @override
  TestRecord fromRow(Map<String, Object?> row) =>
      (id: row['id'] as int, name: row['name'] as String);
}

void main() {
  test('query builder validates identifiers and supports dialects', () {
    final sqlite = SqlDialect(DatabaseDialect.sqlite);
    final postgres = SqlDialect(DatabaseDialect.postgres);

    expect(
      sqlite.insert('items', ['id'], mode: InsertMode.ignore),
      contains('INSERT OR IGNORE'),
    );
    expect(
      postgres.insert('items', ['id'], mode: InsertMode.ignore),
      contains('ON CONFLICT DO NOTHING'),
    );
    expect(
      postgres.insert(
        'items',
        ['id', 'name'],
        mode: InsertMode.upsert,
        conflictColumns: ['id'],
      ),
      contains('ON CONFLICT ("id") DO UPDATE'),
    );
    expect(() => sqlite.quote('items;DROP TABLE users'), throwsArgumentError);
  });

  test('BaseEngine CRUD, upsert, batch and keyset on SQLite', () async {
    final db = Database.sqlite(':memory:');
    await db.open();
    try {
      await db.execute(
        'CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)',
      );
      final engine = BaseEngine<TestRecord, int>(
        driver: db,
        dialect: DatabaseDialect.sqlite,
        spec: TestRecordSpec(),
      );

      await engine.save((id: 1, name: 'alpha'));
      await engine.saveBatch([(id: 2, name: 'beta'), (id: 3, name: 'gamma')]);
      expect(await engine.count(), 3);
      expect((await engine.find(2))?.name, 'beta');

      await engine.upsert((id: 2, name: 'updated'));
      expect((await engine.find(2))?.name, 'updated');

      await engine.save((id: 2, name: 'ignored'), mode: InsertMode.ignore);
      expect((await engine.find(2))?.name, 'updated');

      final page = await engine.loadKeyset(lastId: 1, limit: 2);
      expect(page.map((item) => item.id), [2, 3]);

      await engine.delete(1);
      expect(await engine.count(), 2);
      await engine.deleteAll();
      expect(await engine.isEmptyFast(), isTrue);
    } finally {
      await db.close();
    }
  });
}
