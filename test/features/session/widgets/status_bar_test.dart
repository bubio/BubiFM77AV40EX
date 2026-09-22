import 'package:flutter_test/flutter_test.dart';

import 'package:bubifm77av40ex/features/session/widgets/status_bar.dart';

void main() {
  group('shortenCmtMessage', () {
    test('テープ先頭での停止を0 %で表す', () {
      expect(shortenCmtMessage('Stop (Beginning-of-Tape)'), 'Stop (0 %)');
    });

    test('テープ終端での停止を100 %で表す', () {
      expect(shortenCmtMessage('Stop (End-of-Tape)'), 'Stop (100 %)');
    });

    test('それ以外の状態文字列はそのまま返す', () {
      expect(shortenCmtMessage('Stop (50 %)'), 'Stop (50 %)');
      expect(shortenCmtMessage('Play (3 %)'), 'Play (3 %)');
      expect(shortenCmtMessage('Stop'), 'Stop');
    });
  });
}
