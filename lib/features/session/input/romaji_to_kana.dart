/// ローマ字かな変換（INP-03）。
///
/// このハードウェアが直接打てる「かな」はJIS X0201半角カタカナだけであり
/// （`kana_key_table.dart`のコメント参照）、ひらがなの入力経路はコアに
/// 存在しない。そのためローマ字は常にカタカナへ変換する。清音・濁音・
/// 半濁音・拗音・促音・撥音「ん」・重母音表記の長音という、ローマ字入力の
/// 標準的な規則をカバーする。濁音・半濁音は、実機のキー配列どおり
/// 「清音キー」＋「濁点／半濁点キー」の2打鍵として表現するため、出力は
/// 濁点(`゛`)・半濁点(`゜`)を独立した文字として持つ分解済み表記
/// （例: "ga" → "カ゛"）にする。合成済みの濁音カタカナ
/// （例: "ガ" 1文字）ではない。
library;

const _dakuten = '゛';
const _handakuten = '゜';

/// ローマ字断片（小文字）→ 分解済みカタカナ出力。
///
/// 3文字（拗音）→2文字（清音・拗音の一部）→1文字（母音単体）の順に
/// 最長一致で引く。
final Map<String, String> _romajiTable = {
  // 母音
  'a': 'ア', 'i': 'イ', 'u': 'ウ', 'e': 'エ', 'o': 'オ',

  // か行
  'ka': 'カ', 'ki': 'キ', 'ku': 'ク', 'ke': 'ケ', 'ko': 'コ',
  'kya': 'キャ', 'kyu': 'キュ', 'kyo': 'キョ',
  'ga': 'カ$_dakuten', 'gi': 'キ$_dakuten', 'gu': 'ク$_dakuten',
  'ge': 'ケ$_dakuten', 'go': 'コ$_dakuten',
  'gya':
      'キ$_dakuten'
      'ャ',
  'gyu':
      'キ$_dakuten'
      'ュ',
  'gyo':
      'キ$_dakuten'
      'ョ',

  // さ行
  'sa': 'サ', 'shi': 'シ', 'si': 'シ', 'su': 'ス', 'se': 'セ', 'so': 'ソ',
  'sha': 'シャ', 'shu': 'シュ', 'sho': 'ショ',
  'sya': 'シャ', 'syu': 'シュ', 'syo': 'ショ',
  'za': 'サ$_dakuten', 'ji': 'シ$_dakuten', 'zi': 'シ$_dakuten',
  'zu': 'ス$_dakuten', 'ze': 'セ$_dakuten', 'zo': 'ソ$_dakuten',
  'ja':
      'シ$_dakuten'
      'ャ',
  'ju':
      'シ$_dakuten'
      'ュ',
  'jo':
      'シ$_dakuten'
      'ョ',
  'jya':
      'シ$_dakuten'
      'ャ',
  'jyu':
      'シ$_dakuten'
      'ュ',
  'jyo':
      'シ$_dakuten'
      'ョ',
  'zya':
      'シ$_dakuten'
      'ャ',
  'zyu':
      'シ$_dakuten'
      'ュ',
  'zyo':
      'シ$_dakuten'
      'ョ',

  // た行
  'ta': 'タ', 'chi': 'チ', 'ti': 'チ', 'tsu': 'ツ', 'tu': 'ツ', 'te': 'テ',
  'to': 'ト',
  'cha': 'チャ', 'chu': 'チュ', 'cho': 'チョ',
  'tya': 'チャ', 'tyu': 'チュ', 'tyo': 'チョ',
  'da': 'タ$_dakuten', 'di': 'チ$_dakuten', 'du': 'ツ$_dakuten',
  'de': 'テ$_dakuten', 'do': 'ト$_dakuten',
  'dya':
      'チ$_dakuten'
      'ャ',
  'dyu':
      'チ$_dakuten'
      'ュ',
  'dyo':
      'チ$_dakuten'
      'ョ',

  // な行
  'na': 'ナ', 'ni': 'ニ', 'nu': 'ヌ', 'ne': 'ネ', 'no': 'ノ',
  'nya': 'ニャ', 'nyu': 'ニュ', 'nyo': 'ニョ',

  // は行
  'ha': 'ハ', 'hi': 'ヒ', 'fu': 'フ', 'hu': 'フ', 'he': 'ヘ', 'ho': 'ホ',
  'hya': 'ヒャ', 'hyu': 'ヒュ', 'hyo': 'ヒョ',
  'fa':
      'フ'
      'ァ',
  'fi':
      'フ'
      'ィ',
  'fe':
      'フ'
      'ェ',
  'fo':
      'フ'
      'ォ',
  'ba': 'ハ$_dakuten', 'bi': 'ヒ$_dakuten', 'bu': 'フ$_dakuten',
  'be': 'ヘ$_dakuten', 'bo': 'ホ$_dakuten',
  'bya':
      'ヒ$_dakuten'
      'ャ',
  'byu':
      'ヒ$_dakuten'
      'ュ',
  'byo':
      'ヒ$_dakuten'
      'ョ',
  'pa': 'ハ$_handakuten', 'pi': 'ヒ$_handakuten', 'pu': 'フ$_handakuten',
  'pe': 'ヘ$_handakuten', 'po': 'ホ$_handakuten',
  'pya':
      'ヒ$_handakuten'
      'ャ',
  'pyu':
      'ヒ$_handakuten'
      'ュ',
  'pyo':
      'ヒ$_handakuten'
      'ョ',

  // ま行
  'ma': 'マ', 'mi': 'ミ', 'mu': 'ム', 'me': 'メ', 'mo': 'モ',
  'mya': 'ミャ', 'myu': 'ミュ', 'myo': 'ミョ',

  // や行
  'ya': 'ヤ', 'yu': 'ユ', 'yo': 'ヨ',

  // ら行
  'ra': 'ラ', 'ri': 'リ', 'ru': 'ル', 're': 'レ', 'ro': 'ロ',
  'rya': 'リャ', 'ryu': 'リュ', 'ryo': 'リョ',

  // わ行
  'wa': 'ワ', 'wo': 'ヲ',
};

const _consonants = 'bcdfghjklmpqrstvwxyz';
const _vowels = 'aiueo';

/// 変換結果の直前の音がどの母音で終わるか（長音「ー」判定用）。
///
/// 表の右辺に現れうる最後の文字だけをカバーする。
final Map<String, String> _endingVowel = {
  'ア': 'a',
  'カ': 'a',
  'サ': 'a',
  'タ': 'a',
  'ナ': 'a',
  'ハ': 'a',
  'マ': 'a',
  'ヤ': 'a',
  'ラ': 'a',
  'ワ': 'a',
  'ャ': 'a',
  'イ': 'i',
  'キ': 'i',
  'シ': 'i',
  'チ': 'i',
  'ニ': 'i',
  'ヒ': 'i',
  'ミ': 'i',
  'リ': 'i',
  'ィ': 'i',
  'ウ': 'u',
  'ク': 'u',
  'ス': 'u',
  'ツ': 'u',
  'ヌ': 'u',
  'フ': 'u',
  'ム': 'u',
  'ユ': 'u',
  'ル': 'u',
  'ゥ': 'u',
  'ュ': 'u',
  'エ': 'e',
  'ケ': 'e',
  'セ': 'e',
  'テ': 'e',
  'ネ': 'e',
  'ヘ': 'e',
  'メ': 'e',
  'レ': 'e',
  'ェ': 'e',
  'オ': 'o',
  'コ': 'o',
  'ソ': 'o',
  'ト': 'o',
  'ノ': 'o',
  'ホ': 'o',
  'モ': 'o',
  'ヨ': 'o',
  'ロ': 'o',
  'ヲ': 'o',
  'ォ': 'o',
  'ョ': 'o',
};

/// 全角カタカナの濁音・半濁音（合成済み1文字）→ 分解済み表記。
/// クリップボードに生のカタカナ／ひらがな文が含まれる場合の正規化に使う
/// （`normalizeKanaText`）。
const _kRow = 'カキクケコ', _gRow = 'ガギグゲゴ';
const _sRow = 'サシスセソ', _zRow = 'ザジズゼゾ';
const _tRow = 'タチツテト', _dRow = 'ダヂヅデド';
const _hRow = 'ハヒフヘホ', _bRow = 'バビブベボ', _pRow = 'パピプペポ';

final Map<String, String> _decomposeDakuon = {
  for (var i = 0; i < 5; i++) _gRow[i]: '${_kRow[i]}$_dakuten',
  for (var i = 0; i < 5; i++) _zRow[i]: '${_sRow[i]}$_dakuten',
  for (var i = 0; i < 5; i++) _dRow[i]: '${_tRow[i]}$_dakuten',
  for (var i = 0; i < 5; i++) _bRow[i]: '${_hRow[i]}$_dakuten',
  for (var i = 0; i < 5; i++) _pRow[i]: '${_hRow[i]}$_handakuten',
  'ヴ': 'ウ$_dakuten',
};

/// 1文字を、自動キー入力が打てる表現へ正規化する。
///
/// ひらがな（U+3041〜U+3096）はUnicode上カタカナ（U+30A1〜U+30F6）と
/// 完全に並行した配置のため+0x60で変換できる。濁音・半濁音の合成済み
/// カタカナ（ガ等）は分解済み表記（カ+濁点）へ変換する。それ以外は
/// そのまま返す。
String _normalizeChar(String ch) {
  final code = ch.codeUnitAt(0);
  var katakana = ch;
  if (code >= 0x3041 && code <= 0x3096) {
    katakana = String.fromCharCode(code + 0x60);
  }
  return _decomposeDakuon[katakana] ?? katakana;
}

/// [kana]の最後の音がどの母音で終わるか（長音判定用）。濁点・半濁点は
/// それ自体に母音を持たないため、末尾にあれば無視して1つ前の文字を見る
/// （例: "ga"→"カ゛"の直後に長音判定を行う場合、"カ"のaを見る）。
String? _endingVowelOf(String kana) {
  if (kana.isEmpty) {
    return null;
  }
  var end = kana.length - 1;
  while (end > 0 && (kana[end] == _dakuten || kana[end] == _handakuten)) {
    end--;
  }
  return _endingVowel[kana[end]];
}

/// ローマ字かな変換がOFFのときに使う正規化。ローマ字はASCIIのまま残し、
/// クリップボードに元から含まれる生のひらがな／カタカナ・濁音・半濁音
/// だけを、自動キー入力が打てる分解済み表記へ変換する。
String normalizeKanaText(String input) {
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    buffer.write(_normalizeChar(input[i]));
  }
  return buffer.toString();
}

/// ローマ字文字列をカタカナへ変換する（ローマ字かな変換ON時に使う）。
///
/// ローマ字表にない断片（数字・記号・空白・すでにかな/カタカナの文字等）は
/// そのまま通す。英字として解釈できるがどの規則にも当たらない孤立した
/// 1文字（例: 単独の子音字）はASCII文字としてそのまま残す
/// （`AutoKeyEngine`側でASCII表から打鍵できる）。
String convertRomajiToKana(String input) {
  final buffer = StringBuffer();
  var i = 0;
  String? lastVowel;
  final lower = input.toLowerCase();

  bool isAsciiLetter(int index) {
    if (index < 0 || index >= input.length) return false;
    final c = lower.codeUnitAt(index);
    return c >= 0x61 && c <= 0x7a;
  }

  while (i < input.length) {
    if (isAsciiLetter(i) &&
        isAsciiLetter(i + 1) &&
        lower[i] == lower[i + 1] &&
        _consonants.contains(lower[i]) &&
        lower[i] != 'n') {
      // 促音（例: "kka" → ッ + "ka"）。
      buffer.write('ッ');
      lastVowel = null;
      i += 1;
      continue;
    }

    if (isAsciiLetter(i)) {
      String? matched;
      var matchedLen = 0;
      for (final len in [3, 2]) {
        if (i + len > lower.length) continue;
        final frag = lower.substring(i, i + len);
        final out = _romajiTable[frag];
        if (out != null) {
          matched = out;
          matchedLen = len;
          break;
        }
      }
      if (matched != null) {
        buffer.write(matched);
        lastVowel = _endingVowelOf(matched);
        i += matchedLen;
        continue;
      }

      if (lower[i] == 'n') {
        final next = i + 1 < lower.length ? lower[i + 1] : null;
        final nextIsVowelOrY =
            next != null && (_vowels.contains(next) || next == 'y');
        // "nn"は2つ目のnを次の音節（な行等）の先頭として残す必要がある
        // （例: "konnichiwa" → コン+ニチ+ワ）ため、特別扱いしない。
        // 2つ目のnも母音/yを伴わなければ、次のループでこの分岐が
        // 再び働き独立した「ン」になる。
        if (next == "'") {
          buffer.write('ン');
          lastVowel = null;
          i += 2;
          continue;
        }
        if (!nextIsVowelOrY) {
          buffer.write('ン');
          lastVowel = null;
          i += 1;
          continue;
        }
        // "na"等はこの後の1文字一致（母音単体）では拾えないため、ここで
        // 拾えない場合はASCII文字としてそのまま残す（未知の組合せ）。
      }

      final single = _romajiTable[lower[i]];
      if (single != null) {
        if (lastVowel != null && lastVowel == lower[i]) {
          buffer.write('ー');
        } else {
          buffer.write(single);
          lastVowel = lower[i];
        }
        i += 1;
        continue;
      }

      // 表にない孤立した英字はそのまま残す（元の大小文字を保つ）。
      buffer.write(input[i]);
      lastVowel = null;
      i += 1;
      continue;
    }

    final normalized = _normalizeChar(input[i]);
    buffer.write(normalized);
    lastVowel = _endingVowelOf(normalized);
    i += 1;
  }
  return buffer.toString();
}

/// ローマ字かな変換の逐次（キー入力ごとの）版。
///
/// [convertRomajiToKana]は貼付けなど完成した文字列を一括で変換するのに対し、
/// こちらは物理キーを打つたびに1文字ずつ渡し、確定したかな断片を都度返す
/// 用途に使う（INP-03「Romaji to Kana」のライブ入力）。ASCII英字だけを
/// 対象とし、呼び出し側（`EmulatorController`）は英字キーだけをこの
/// バッファへ渡す。英字以外のキーは通常経路のまま変換をまたがない。
class LiveRomajiBuffer {
  final StringBuffer _pending = StringBuffer();

  /// 未確定の断片を持っていないか。
  bool get isEmpty => _pending.isEmpty;

  /// 英字1文字を追加する。
  ///
  /// 確定した出力（かな断片、または表のどの規則にも当たらない孤立文字の
  /// ASCII素通し）があればそれを返す。まだ確定できない場合は空文字を返し、
  /// 内部バッファへ保持する（次の[push]または[flush]まで）。
  String push(String ch) {
    final buf = '${_pending.toString()}${ch.toLowerCase()}';
    _pending.clear();
    return _resolve(buf);
  }

  /// バッファに残っている断片を、これ以上待たずにASCII文字としてそのまま
  /// 確定させる。変換モードOFF・英字以外のキー入力・フォーカス喪失時に
  /// 呼ぶ（バッファを持ち越さない）。
  String flush() {
    final remaining = _pending.toString();
    _pending.clear();
    return remaining;
  }

  String _resolve(String buf) {
    if (buf.isEmpty) {
      return '';
    }
    // 促音（例: バッファ"k" + 新規"k" → ッ、"k"を次の音節の先頭として残す）。
    if (buf.length == 2 &&
        buf[0] == buf[1] &&
        _consonants.contains(buf[0]) &&
        buf[0] != 'n') {
      _pending.write(buf[1]);
      return 'ッ';
    }
    // 最長一致（3→2→1文字）。表引きできた断片より後ろが残っていれば、
    // それは次の音節の先頭として再帰的に解決する。
    for (final len in [3, 2, 1]) {
      if (len > buf.length) {
        continue;
      }
      final head = buf.substring(0, len);
      final out = _romajiTable[head];
      if (out == null) {
        continue;
      }
      if (len == buf.length) {
        return out;
      }
      return out + _resolve(buf.substring(len));
    }
    // 孤立した「ん」。次の文字がまだ無いため確定できない。
    if (buf == 'n') {
      _pending.write(buf);
      return '';
    }
    // "n" + 母音/y/n以外 → 独立した「ン」。残りは次の音節の先頭として
    // 再帰的に解決する（"nn"の2つ目のnも、ここで単独の"n"として次回へ
    // 持ち越される）。
    if (buf[0] == 'n' &&
        !(_vowels.contains(buf[1]) || buf[1] == 'y' || buf[1] == 'n')) {
      return 'ン${_resolve(buf.substring(1))}';
    }
    if (buf.length >= 2 && buf[0] == 'n' && buf[1] == 'n') {
      return 'ン${_resolve(buf.substring(1))}';
    }
    // まだどの規則にも当たらないが、より長く続けば一致しうる（有効な
    // 接頭辞）なら、確定させずに待つ。
    if (_isValidPrefix(buf)) {
      _pending.write(buf);
      return '';
    }
    // 一致しない先頭1文字をASCII文字としてそのまま素通しし、残りを
    // 再試行する。
    return buf[0] + _resolve(buf.substring(1));
  }

  bool _isValidPrefix(String buf) {
    if (buf == 'n') {
      return true;
    }
    for (final key in _romajiTable.keys) {
      if (key.length > buf.length && key.startsWith(buf)) {
        return true;
      }
    }
    return false;
  }
}
