// -*- compile-command: "cd .. && ./df.sh"; -*-

import 'package:gep/gep.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for GEP', () {
    GEP gep;

    setUp(() {
      gep = GEP();
      print('gep=$gep');
    });
  });
}
