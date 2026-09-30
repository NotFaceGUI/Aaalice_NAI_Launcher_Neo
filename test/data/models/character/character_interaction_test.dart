import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/character/character_interaction.dart';

void main() {
  group('CharacterInteraction.parse', () {
    test('识别主动方标签', () {
      final interaction = CharacterInteraction.parse('source#hug, 1girl');

      expect(interaction, isNotNull);
      expect(interaction!.role, CharacterInteractionRole.source);
      expect(interaction.action, 'hug');
      expect(interaction.tag, 'source#hug');
    });

    test('识别位于中间或末尾的标签', () {
      expect(
        CharacterInteraction.parse('1girl, target#kiss, smile')?.role,
        CharacterInteractionRole.target,
      );
      expect(
        CharacterInteraction.parse('1girl, mutual#holding_hands')?.role,
        CharacterInteractionRole.mutual,
      );
    });

    test('支持多词动作与下划线写法', () {
      expect(
        CharacterInteraction.parse('target#pointing at another')?.action,
        'pointing at another',
      );
      expect(
        CharacterInteraction.parse('source#hug_from_behind')?.action,
        'hug_from_behind',
      );
    });

    test('前缀大小写不敏感', () {
      expect(
        CharacterInteraction.parse('SOURCE#hug')?.role,
        CharacterInteractionRole.source,
      );
    });

    test('没有互动标签时返回 null', () {
      expect(CharacterInteraction.parse(''), isNull);
      expect(CharacterInteraction.parse('1girl, smile, hug'), isNull);
    });

    test('括号内的逗号不会切断标签', () {
      expect(
        CharacterInteraction.parse('{source#hug, smile}, 1girl')?.action,
        'hug, smile',
      );
    });
  });

  group('CharacterInteraction.write', () {
    const hug = CharacterInteraction(
      role: CharacterInteractionRole.target,
      action: 'hug',
    );

    test('写入到提示词最前面', () {
      expect(
        CharacterInteraction.write('1girl, smile', hug),
        'target#hug, 1girl, smile',
      );
    });

    test('替换已有标签，不重复也不丢失其他内容', () {
      expect(
        CharacterInteraction.write('source#kiss, 1girl, smile', hug),
        'target#hug, 1girl, smile',
      );
    });

    test('写在中间的旧标签同样被替换并清理逗号', () {
      expect(
        CharacterInteraction.write('1girl, source#kiss, smile', hug),
        'target#hug, 1girl, smile',
      );
    });

    test('清除标签时连同相邻逗号一起清理', () {
      expect(
        CharacterInteraction.write('source#hug, 1girl, smile', null),
        '1girl, smile',
      );
      expect(
        CharacterInteraction.write('1girl, source#hug', null),
        '1girl',
      );
    });

    test('保留换行与首行缩进等排版', () {
      const prompt = '\n\n  1girl,\n  smile';

      expect(
        CharacterInteraction.write(prompt, hug),
        '\n\n  target#hug, 1girl,\n  smile',
      );
    });

    test('空提示词只得到标签本身', () {
      expect(CharacterInteraction.write('', hug), 'target#hug');
      expect(CharacterInteraction.write('   ', hug), '   target#hug');
    });

    test('写入后读取可以往返', () {
      final written = CharacterInteraction.write('1girl, smile', hug);

      expect(CharacterInteraction.parse(written), hug);
      expect(CharacterInteraction.write(written, null), '1girl, smile');
    });

    test('自定义动作原样写入', () {
      const custom = CharacterInteraction(
        role: CharacterInteractionRole.source,
        action: 'pointing at another',
      );

      expect(CharacterInteraction.write('1girl', custom), 'source#pointing at another, 1girl');
      expect(CharacterInteraction.parse('source#pointing at another, 1girl'), custom);
      expect(custom.isCustomAction, isTrue);
    });
  });

  group('CharacterInteractionAction.normalizeAction', () {
    test('允许直接粘贴完整标签', () {
      expect(
        CharacterInteractionAction.normalizeAction('target#pointing at another'),
        'pointing at another',
      );
      expect(CharacterInteractionAction.normalizeAction('hug'), 'hug');
    });

    test('压缩空白并去掉逗号', () {
      expect(
        CharacterInteractionAction.normalizeAction('  pointing   at, another '),
        'pointing at another',
      );
    });

    test('超长输入按上限截断', () {
      final long = 'a' * 200;

      expect(
        CharacterInteractionAction.normalizeAction(long).length,
        CharacterInteractionAction.maxActionLength,
      );
    });

    test('空输入得到空串', () {
      expect(CharacterInteractionAction.normalizeAction('   '), isEmpty);
      expect(CharacterInteractionAction.normalizeAction('source#'), isEmpty);
    });
  });

  group('CharacterInteractionAction', () {
    test('下划线与空格写法等价', () {
      expect(
        CharacterInteractionAction.fromTag('holding hands'),
        CharacterInteractionAction.holdingHands,
      );
      expect(
        CharacterInteractionAction.fromTag('HOLDING_HANDS'),
        CharacterInteractionAction.holdingHands,
      );
    });

    test('词表内全部是规范标签写法（小写下划线，无别名）', () {
      for (final action in CharacterInteractionAction.values) {
        expect(action.tag, matches(RegExp(r'^[a-z0-9_]+$')), reason: action.tag);
      }
      // 已确认的别名/不存在的写法不应出现在词表里
      expect(CharacterInteractionAction.fromTag('handholding'), isNull);
      expect(CharacterInteractionAction.fromTag('head_pat'), isNull);
      expect(CharacterInteractionAction.fromTag('embracing'), isNull);
    });

    test('预设动作不算自定义', () {
      expect(
        const CharacterInteraction(
          role: CharacterInteractionRole.source,
          action: 'hug',
        ).isCustomAction,
        isFalse,
      );
    });
  });
}
