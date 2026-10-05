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

  group('Bajar un tono = 2 semitonos (caso de la banda: Gm -> Fm)', () {
    test('Gm baja un tono completo a Fm', () {
      expect(transposeChordName('Gm', -2), 'Fm');
    });

    test('todos los acordes de la progresión cambian de raíz', () {
      final original = ['Gm', 'A#', 'G7', 'Cm', 'D7', 'D#'];
      final lowered = original.map((c) => transposeChordName(c, -2)).toList();
      // Ninguna raíz se queda igual
      expect(lowered, ['Fm', 'G#', 'F7', 'A#m', 'C7', 'C#']);
    });

    test('la tonalidad también baja (Gm -> Fm) y se escribe con bemoles', () {
      final newKey = transposeChordName('Gm', -2);
      expect(newKey, 'Fm');
      expect(keyPrefersFlats(newKey), isTrue);
      // En Fm los acordes se escriben estándar-mente con bemoles
      expect(spellChordForKey('G#', newKey), 'Ab');
      expect(spellChordForKey('C#', newKey), 'Db');
      expect(spellChordForKey('A#', newKey), 'Bb');
      expect(spellChordForKey('D#', newKey), 'Eb');
    });
  });

  group('grafía de acordes por tonalidad', () {
    test('F#m se escribe con sostenidos (no los cambia)', () {
      expect(keyPrefersFlats('F#m'), isFalse);
      expect(spellChordForKey('A#', 'F#m'), 'A#');
      expect(spellChordForKey('C#', 'F#m'), 'C#');
    });

    test('Gm y Fm se escriben con bemoles', () {
      expect(keyPrefersFlats('Gm'), isTrue);
      expect(keyPrefersFlats('Fm'), isTrue);
      expect(spellChordForKey('A#', 'Gm'), 'Bb');
      expect(spellChordForKey('G#m', 'Bbm'), 'Abm');
    });

    test('chordRootName extrae la raíz correctamente', () {
      expect(chordRootName('A#m7'), 'A#');
      expect(chordRootName('C'), 'C');
      expect(chordRootName('C#7'), 'C#');
    });
  });

  group('equivalencias enharmónicas para diagramas', () {
    test('sostenidos -> bemoles', () {
      expect(kSharpToFlat['A#'], 'Bb');
      expect(kSharpToFlat['D#'], 'Eb');
      expect(kSharpToFlat['G#'], 'Ab');
    });

    test('bemoles -> sostenidos', () {
      expect(kFlatToSharp['Bb'], 'A#');
      expect(kFlatToSharp['Eb'], 'D#');
      expect(kFlatToSharp['Ab'], 'G#');
    });
  });
}
