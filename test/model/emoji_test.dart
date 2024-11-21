import 'package:checks/checks.dart';
import 'package:test/scaffolding.dart';
import 'package:zulip/api/model/events.dart';
import 'package:zulip/api/model/model.dart';
import 'package:zulip/api/route/realm.dart';
import 'package:zulip/model/emoji.dart';
import 'package:zulip/model/store.dart';

import '../example_data.dart' as eg;

void main() {
  group('emojiDisplayFor', () {
    test('Unicode emoji', () {
      check(eg.store().emojiDisplayFor(emojiType: ReactionType.unicodeEmoji,
        emojiCode: '1f642', emojiName: 'smile')
      ).isA<UnicodeEmojiDisplay>()
        ..emojiName.equals('smile')
        ..emojiUnicode.equals('🙂');
    });

    test('invalid Unicode emoji -> no crash', () {
      check(eg.store().emojiDisplayFor(emojiType: ReactionType.unicodeEmoji,
        emojiCode: 'asdf', emojiName: 'invalid')
      ).isA<TextEmojiDisplay>()
        .emojiName.equals('invalid');
    });

    test('realm emoji', () {
      final store = eg.store(initialSnapshot: eg.initialSnapshot(realmEmoji: {
        '100': eg.realmEmojiItem(emojiCode: '100', emojiName: 'logo',
            sourceUrl: '/emoji/100.png'),
        '123': eg.realmEmojiItem(emojiCode: '123', emojiName: '100',
            sourceUrl: '/emoji/123.png'),
        '200': eg.realmEmojiItem(emojiCode: '200', emojiName: 'dancing',
            sourceUrl: '/emoji/200.png', stillUrl: '/emoji/200-still.png'),
      }));

      Subject<EmojiDisplay> checkDisplay({
          required String emojiCode, required String emojiName}) {
        return check(store.emojiDisplayFor(emojiType: ReactionType.realmEmoji,
          emojiCode: emojiCode, emojiName: emojiName)
        )..emojiName.equals(emojiName);
      }

      checkDisplay(emojiCode: '100', emojiName: 'logo').isA<ImageEmojiDisplay>()
        ..resolvedUrl.equals(eg.realmUrl.resolve('/emoji/100.png'))
        ..resolvedStillUrl.isNull();

      // Emoji code matches against emoji code, not against emoji name.
      checkDisplay(emojiCode: '123', emojiName: '100').isA<ImageEmojiDisplay>()
        ..resolvedUrl.equals(eg.realmUrl.resolve('/emoji/123.png'))
        ..resolvedStillUrl.isNull();

      // Unexpected name is accepted.
      checkDisplay(emojiCode: '100', emojiName: 'other').isA<ImageEmojiDisplay>()
        ..resolvedUrl.equals(eg.realmUrl.resolve('/emoji/100.png'))
        ..resolvedStillUrl.isNull();

      // Unexpected code falls back to text.
      checkDisplay(emojiCode: '99', emojiName: 'another')
        .isA<TextEmojiDisplay>();

      checkDisplay(emojiCode: '200', emojiName: 'dancing').isA<ImageEmojiDisplay>()
        ..resolvedUrl.equals(eg.realmUrl.resolve('/emoji/200.png'))
        ..resolvedStillUrl.equals(eg.realmUrl.resolve('/emoji/200-still.png'));

      // TODO test URLs not parsing
    });

    test(':zulip:', () {
      check(eg.store().emojiDisplayFor(emojiType: ReactionType.zulipExtraEmoji,
        emojiCode: 'zulip', emojiName: 'zulip')
      ).isA<ImageEmojiDisplay>()
        ..emojiName.equals('zulip')
        ..resolvedUrl.equals(eg.realmUrl.resolve(EmojiStoreImpl.kZulipEmojiUrl))
        ..resolvedStillUrl.isNull();
    });
  });

  Condition<Object?> isUnicodeCandidate(String? emojiCode, List<String>? names) {
    return (it_) {
      final it = it_.isA<EmojiCandidate>();
      it.emojiType.equals(ReactionType.unicodeEmoji);
      if (emojiCode != null) it.emojiCode.equals(emojiCode);
      if (names != null) {
        it.emojiName.equals(names.first);
        it.aliases.deepEquals(names.sublist(1));
      }
    };
  }

  Condition<Object?> isRealmCandidate({String? emojiCode, String? emojiName}) {
    return (it_) {
      final it = it_.isA<EmojiCandidate>();
      it.emojiType.equals(ReactionType.realmEmoji);
      if (emojiCode != null) it.emojiCode.equals(emojiCode);
      if (emojiName != null) it.emojiName.equals(emojiName);
      it.aliases.isEmpty();
    };
  }

  Condition<Object?> isZulipCandidate() {
    return (it) => it.isA<EmojiCandidate>()
      ..emojiType.equals(ReactionType.zulipExtraEmoji)
      ..emojiCode.equals('zulip')
      ..emojiName.equals('zulip')
      ..aliases.isEmpty();
  }

  group('allEmojiCandidates', () {
    // TODO test emojiDisplay of candidates matches emojiDisplayFor

    PerAccountStore prepare({
      Map<String, RealmEmojiItem> realmEmoji = const {},
      Map<String, List<String>>? unicodeEmoji,
    }) {
      final store = eg.store(
        initialSnapshot: eg.initialSnapshot(realmEmoji: realmEmoji));
      if (unicodeEmoji != null) {
        store.setServerEmojiData(ServerEmojiData(codeToNames: unicodeEmoji));
      }
      return store;
    }

    test('realm emoji overrides Unicode emoji', () {
      final store = prepare(realmEmoji: {
        '1': eg.realmEmojiItem(emojiCode: '1', emojiName: 'smiley'),
      }, unicodeEmoji: {
        '1f642': ['smile'],
        '1f603': ['smiley'],
      });
      check(store.allEmojiCandidates()).deepEquals([
        isUnicodeCandidate('1f642', ['smile']),
        isRealmCandidate(emojiCode: '1', emojiName: 'smiley'),
        isZulipCandidate(),
      ]);
    });

    test('Unicode emoji with overridden aliases survives with remaining names', () {
      final store = prepare(realmEmoji: {
        '1': eg.realmEmojiItem(emojiCode: '1', emojiName: 'tangerine'),
      }, unicodeEmoji: {
        '1f34a': ['orange', 'tangerine', 'mandarin'],
      });
      check(store.allEmojiCandidates()).deepEquals([
        isUnicodeCandidate('1f34a', ['orange', 'mandarin']),
        isRealmCandidate(emojiCode: '1', emojiName: 'tangerine'),
        isZulipCandidate(),
      ]);
    });

    test('Unicode emoji with overridden primary name survives with remaining names', () {
      final store = prepare(realmEmoji: {
        '1': eg.realmEmojiItem(emojiCode: '1', emojiName: 'orange'),
      }, unicodeEmoji: {
        '1f34a': ['orange', 'tangerine', 'mandarin'],
      });
      check(store.allEmojiCandidates()).deepEquals([
        isUnicodeCandidate('1f34a', ['tangerine', 'mandarin']),
        isRealmCandidate(emojiCode: '1', emojiName: 'orange'),
        isZulipCandidate(),
      ]);
    });

    test('updates on setServerEmojiData', () {
      final store = prepare();
      check(store.allEmojiCandidates()).deepEquals([
        isZulipCandidate(),
      ]);

      store.setServerEmojiData(ServerEmojiData(codeToNames: {
        '1f642': ['smile'],
      }));
      check(store.allEmojiCandidates()).deepEquals([
        isUnicodeCandidate('1f642', ['smile']),
        isZulipCandidate(),
      ]);
    });

    test('updates on RealmEmojiUpdateEvent', () {
      final store = prepare();
      check(store.allEmojiCandidates()).deepEquals([
        isZulipCandidate(),
      ]);

      store.handleEvent(RealmEmojiUpdateEvent(id: 1, realmEmoji: {
        '1': eg.realmEmojiItem(emojiCode: '1', emojiName: 'happy'),
      }));
      check(store.allEmojiCandidates()).deepEquals([
        isRealmCandidate(emojiCode: '1', emojiName: 'happy'),
        isZulipCandidate(),
      ]);
    });

    test('memoizes result', () {
      final store = prepare(realmEmoji: {
        '1': eg.realmEmojiItem(emojiCode: '1', emojiName: 'happy'),
      }, unicodeEmoji: {
        '1f642': ['smile'],
      });
      final candidates = store.allEmojiCandidates();
      check(store.allEmojiCandidates()).identicalTo(candidates);
    });
  });
}

extension EmojiDisplayChecks on Subject<EmojiDisplay> {
  Subject<String> get emojiName => has((x) => x.emojiName, 'emojiName');
}

extension UnicodeEmojiDisplayChecks on Subject<UnicodeEmojiDisplay> {
  Subject<String> get emojiUnicode => has((x) => x.emojiUnicode, 'emojiUnicode');
}

extension ImageEmojiDisplayChecks on Subject<ImageEmojiDisplay> {
  Subject<Uri> get resolvedUrl => has((x) => x.resolvedUrl, 'resolvedUrl');
  Subject<Uri?> get resolvedStillUrl => has((x) => x.resolvedStillUrl, 'resolvedStillUrl');
}

extension EmojiCandidateChecks on Subject<EmojiCandidate> {
  Subject<ReactionType> get emojiType => has((x) => x.emojiType, 'emojiType');
  Subject<String> get emojiCode => has((x) => x.emojiCode, 'emojiCode');
  Subject<String> get emojiName => has((x) => x.emojiName, 'emojiName');
  Subject<Iterable<String>> get aliases => has((x) => x.aliases, 'aliases');
  Subject<EmojiDisplay> get emojiDisplay => has((x) => x.emojiDisplay, 'emojiDisplay');
}
