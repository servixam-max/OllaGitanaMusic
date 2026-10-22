import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olla_gitana_music/features/lyrics/lyrics_screen.dart';

/// Regresión: el modo karaoke hacía scroll con
/// `localToGlobal(...) + controller.offset`, que suma el desplazamiento actual
/// dos veces ⇒ cada línea empujaba más abajo y la letra acababa saltando al
/// final (`maxScrollExtent`) aunque la canción fuera por la mitad.
///
/// El offset correcto de una línea es SIEMPRE el mismo, se mida desde arriba o
/// desde abajo, porque se calcula en coordenadas de contenido.

const int _kLines = 60;
const double _kLineBox = 50;
const double _kItemPadding = 8; // 4 arriba + 4 abajo
const double _kItemHeight = _kLineBox + _kItemPadding;
const double _kTopPadding = 14;
const double _kViewport = 600;
const double _kAlignment = 0.35;

/// Offset esperado: la línea queda al 35 % del alto visible.
double _expectedFor(int i) => _kTopPadding + i * _kItemHeight - (_kViewport - _kItemHeight) * _kAlignment;

Future<(ScrollController, List<GlobalKey>)> _pumpLyricsList(WidgetTester tester) async {
  final controller = ScrollController();
  final keys = List<GlobalKey>.generate(_kLines, (_) => GlobalKey());

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: _kViewport,
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: _kTopPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List<Widget>.generate(_kLines, (i) {
                return Padding(
                  key: keys[i],
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    height: _kLineBox,
                    child: Text('linea $i'),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    ),
  );

  return (controller, keys);
}

void main() {
  testWidgets('el scroll del karaoke no acumula desplazamiento línea a línea', (tester) async {
    final (controller, keys) = await _pumpLyricsList(tester);
    addTearDown(controller.dispose);

    // El temporizador del karaoke avanza verso a verso aplicando el offset.
    for (int i = 5; i <= 45; i++) {
      final target = karaokeRevealOffset(controller, keys[i].currentContext!);
      expect(target, closeTo(_expectedFor(i), 1.0), reason: 'offset de la línea $i');
      controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
      await tester.pump();
    }

    final maxScroll = controller.position.maxScrollExtent;
    expect(maxScroll, closeTo(_kTopPadding * 2 + _kLines * _kItemHeight - _kViewport, 1.0));

    // Con el bug, la línea 45 ya estaba clavada en el final de la letra.
    expect(controller.offset, lessThan(maxScroll - 100));
    expect(controller.offset, closeTo(_expectedFor(45), 1.0));
  });

  testWidgets('el mismo verso da el mismo offset desde arriba y desde el final', (tester) async {
    final (controller, keys) = await _pumpLyricsList(tester);
    addTearDown(controller.dispose);

    final fromTop = karaokeRevealOffset(controller, keys[30].currentContext!);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final fromBottom = karaokeRevealOffset(controller, keys[30].currentContext!);

    expect(fromBottom, closeTo(fromTop, 1.0));
    expect(fromTop, closeTo(_expectedFor(30), 1.0));
  });

  testWidgets('sin viewport devuelve el offset actual en vez de romper', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    late BuildContext plainContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            plainContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(karaokeRevealOffset(controller, plainContext), 0.0);
  });
}
