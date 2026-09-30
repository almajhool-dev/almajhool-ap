import 'package:almajhool_app/utils/helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('username validation', () {
    expect(Validators.username('anon_dev'), isNull);
    expect(Validators.username('ab'), isNotNull);
    expect(Validators.username('Bad Name'), isNotNull);
  });

  test('email validation', () {
    expect(Validators.email('a@b.co'), isNull);
    expect(Validators.email('nope'), isNotNull);
  });
}
