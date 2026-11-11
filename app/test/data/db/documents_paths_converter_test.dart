import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/data/db/app_database.dart';

void main() {
  const c = DocumentsPathsConverter();
  const oldDocs = '/var/mobile/Containers/Data/Application/OLD/Documents';
  const newDocs = '/var/mobile/Containers/Data/Application/NEW/Documents';

  tearDown(() => DocumentsPathsConverter.documentsDir = null);

  test('stores paths relative to documents and resolves them after the '
      'container moves', () {
    DocumentsPathsConverter.documentsDir = oldDocs;
    final stored = c.toSql(['$oldDocs/keyframes/1_0.jpg']);
    expect(stored, '["keyframes/1_0.jpg"]');

    DocumentsPathsConverter.documentsDir = newDocs;
    expect(c.fromSql(stored), ['$newDocs/keyframes/1_0.jpg']);
  });

  test('re-roots legacy absolute rows into the current container', () {
    DocumentsPathsConverter.documentsDir = newDocs;
    expect(c.fromSql('["$oldDocs/keyframes/1_0.jpg"]'), [
      '$newDocs/keyframes/1_0.jpg',
    ]);
  });

  test('passes paths through when no documents dir is set (in-memory DB)', () {
    expect(c.fromSql('["/tmp/a.jpg"]'), ['/tmp/a.jpg']);
    expect(c.toSql(['/tmp/a.jpg']), '["/tmp/a.jpg"]');
  });
}
