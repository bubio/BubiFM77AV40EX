import 'package:bubifm77av40ex/features/session/input/romaji_to_kana.dart';
import 'package:flutter_test/flutter_test.dart';

/// ローマ字かな変換（INP-03）の変換規則。
void main() {
  test('清音', () {
    expect(convertRomajiToKana('ka'), 'カ');
    expect(convertRomajiToKana('shi'), 'シ');
    expect(convertRomajiToKana('si'), 'シ');
    expect(convertRomajiToKana('tsu'), 'ツ');
    expect(convertRomajiToKana('fu'), 'フ');
  });

  test('濁音・半濁音は清音キー+濁点/半濁点の分解表記になる', () {
    expect(convertRomajiToKana('ga'), 'カ゛');
    expect(convertRomajiToKana('ji'), 'シ゛');
    expect(convertRomajiToKana('pa'), 'ハ゜');
  });

  test('拗音', () {
    expect(convertRomajiToKana('kya'), 'キャ');
    expect(convertRomajiToKana('sha'), 'シャ');
    expect(convertRomajiToKana('cha'), 'チャ');
    expect(convertRomajiToKana('ja'), 'シ゛ャ');
    expect(convertRomajiToKana('pyo'), 'ヒ゜ョ');
  });

  test('促音（子音の重複）', () {
    expect(convertRomajiToKana('kka'), 'ッカ');
    expect(convertRomajiToKana('gakkou'), '${convertRomajiToKana('ga')}ッコウ');
  });

  test('撥音「ん」', () {
    expect(convertRomajiToKana('kon'), 'コン');
    expect(convertRomajiToKana('konnichiwa'), 'コンニチワ');
    expect(convertRomajiToKana("hon'ya"), 'ホンヤ');
    expect(convertRomajiToKana('na'), 'ナ'); // 母音直後のnはナ行として解釈
  });

  test('長音（重母音表記）', () {
    expect(convertRomajiToKana('kaa'), 'カー');
    expect(convertRomajiToKana('raamen'), 'ラーメン');
    expect(convertRomajiToKana('sensei'), 'センセイ'); // 異なる母音の連続はそのまま
  });

  test('数字・記号・空白はそのまま通す', () {
    expect(convertRomajiToKana('10 print "a"'), contains('10'));
    expect(convertRomajiToKana('1'), '1');
    expect(convertRomajiToKana(' '), ' ');
    expect(convertRomajiToKana('.'), '.');
  });

  test('既存のひらがな・カタカナ文字列はカタカナへ正規化される', () {
    expect(convertRomajiToKana('がっこう'), 'ガッコウ'.let(_decompose));
    expect(convertRomajiToKana('ガッコウ'), 'ガッコウ'.let(_decompose));
  });

  test('未知の子音単体はASCIIのまま残す', () {
    expect(convertRomajiToKana('xyz123').startsWith('x'), isTrue);
  });

  // 以降は[LiveRomajiBuffer]（INP-03のライブ入力）: キー入力ごとに1文字ずつ
  // 渡す逐次変換。
  test('清音は2文字目で確定する', () {
    final buf = LiveRomajiBuffer();
    expect(buf.push('k'), '');
    expect(buf.isEmpty, isFalse);
    expect(buf.push('a'), 'カ');
    expect(buf.isEmpty, isTrue);
  });

  test('拗音は3文字目で確定する', () {
    final buf = LiveRomajiBuffer();
    expect(buf.push('k'), '');
    expect(buf.push('y'), '');
    expect(buf.push('a'), 'キャ');
  });

  test('母音単体は1文字で確定する', () {
    final buf = LiveRomajiBuffer();
    expect(buf.push('a'), 'ア');
  });

  test('促音は子音の重複で即座に確定し、2文字目を次の音節へ持ち越す', () {
    final buf = LiveRomajiBuffer();
    expect(buf.push('k'), '');
    expect(buf.push('k'), 'ッ');
    expect(buf.isEmpty, isFalse); // 2つ目のkはまだ保持している
    expect(buf.push('a'), 'カ');
  });

  test('孤立した子音の後に母音/yを伴わない文字が来ると独立した「ン」', () {
    final buf = LiveRomajiBuffer();
    expect(buf.push('k'), '');
    expect(buf.push('o'), 'コ');
    expect(buf.push('n'), '');
    expect(buf.push('t'), 'ン'); // "t"はkonの続きにならないため確定
    expect(buf.isEmpty, isFalse); // "t"は次の音節の先頭として保持
    expect(buf.push('a'), 'タ');
  });

  test('"nn"は最初のnがンとして確定し、2つ目は次の音節へ持ち越す', () {
    final buf = LiveRomajiBuffer();
    expect(buf.push('n'), '');
    expect(buf.push('n'), 'ン');
    expect(buf.isEmpty, isFalse);
    expect(buf.push('i'), 'ニ');
  });

  test('flush()はバッファ中の断片をASCIIのまま確定して空にする', () {
    final buf = LiveRomajiBuffer();
    buf.push('k');
    expect(buf.isEmpty, isFalse);
    expect(buf.flush(), 'k');
    expect(buf.isEmpty, isTrue);
    expect(buf.flush(), '');
  });

  test('どの規則にも当たらない組合せは、確定できた分から順にASCII素通しする', () {
    final buf = LiveRomajiBuffer();
    expect(buf.push('q'), 'q'); // qで始まる規則が無いので即座に素通し
  });
}

/// テストの期待値を「合成済みカタカナ文字列」から書けるようにする、
/// 濁点・半濁点の分解ヘルパー（本体の`_decomposeDakuon`と同じ対応）。
String _decompose(String composed) {
  const map = {
    'ガ': 'カ゛',
    'ギ': 'キ゛',
    'グ': 'ク゛',
    'ゲ': 'ケ゛',
    'ゴ': 'コ゛',
    'ザ': 'サ゛',
    'ジ': 'シ゛',
    'ズ': 'ス゛',
    'ゼ': 'セ゛',
    'ゾ': 'ソ゛',
    'ダ': 'タ゛',
    'ヂ': 'チ゛',
    'ヅ': 'ツ゛',
    'デ': 'テ゛',
    'ド': 'ト゛',
    'バ': 'ハ゛',
    'ビ': 'ヒ゛',
    'ブ': 'フ゛',
    'ベ': 'ヘ゛',
    'ボ': 'ホ゛',
    'パ': 'ハ゜',
    'ピ': 'ヒ゜',
    'プ': 'フ゜',
    'ペ': 'ヘ゜',
    'ポ': 'ホ゜',
  };
  final buffer = StringBuffer();
  for (final rune in composed.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(map[ch] ?? ch);
  }
  return buffer.toString();
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
