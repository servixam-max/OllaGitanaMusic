import 'package:flutter_test/flutter_test.dart';
import 'package:olla_gitana_music/features/chords/chords_screen.dart';

void main() {
  group('transposeChordName (opción Bajar el tono)', () {
    test('baja la tónica conservando la calidad', () {
      expect(transposeChordName('Gm', -2), 'Fm');
      expect(transposeChordName('A#', -3), 'G');
      expect(transposeChordName('D7', -2), 'C7');
      expect(transposeChordName('Cm', -2), 'A#m');
    });

    test('sube la tónica conservando la calidad', () {
      expect(transposeChordName('Fm', 2), 'Gm');
      expect(transposeChordName('A', 2), 'B');
      expect(transposeChordName('G7', 3), 'A#7');
    });

    test('da la vuelta completa con 12 semitonos', () {
      expect(transposeChordName('Gm', 12), 'Gm');
      expect(transposeChordName('Gm', -12), 'Gm');
    });

    test('soporta etiquetas no musicales sin romper', () {
      expect(transposeChordName('N/A', -2), 'N/A');
    });

    test('conserva raíces con sostenido', () {
      expect(transposeChordName('F#m', -2), 'Em');
      expect(transposeChordName('C#7', 1), 'D7');
    });
  });

  group('equivalencias enarmónicas para diagramas', () {
    test('A# se dibuja como Bb, D# como Eb, G# como Ab', () {
      expect(kEnharmonicEquivalents['A#'], 'Bb');
      expect(kEnharmonicEquivalents['D#'], 'Eb');
      expect(kEnharmonicEquivalents['G#'], 'Ab');
    });
  });
}
