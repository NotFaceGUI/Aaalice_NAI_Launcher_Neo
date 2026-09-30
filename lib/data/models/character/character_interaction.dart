import 'package:flutter/foundation.dart';

import '../../../core/utils/nai_prompt_parser.dart';

/// 互动身份前缀：NovelAI 多角色语法里声明该角色在动作中的身份。
///
/// 官方说明：动作标签可以加前缀来指明"主动方"和"被动方"——发起动作的角色在
/// 自己的提示词里写 `source#hug`，承受动作的角色写 `target#hug`，双方互相则
/// 两边都写 `mutual#hug`。官方同时注明该语法并不总是可靠。
enum CharacterInteractionRole {
  /// 动作发起方，写在主动角色的提示词里。
  source('source'),

  /// 动作承受方，写在被动角色的提示词里。
  target('target'),

  /// 双方互相，双方提示词都写。
  mutual('mutual');

  const CharacterInteractionRole(this.prefix);

  /// 标签前缀，不含 `#`。
  final String prefix;

  /// 完整的标签前缀，例如 `source#`。
  String get tagPrefix => '$prefix#';

  static CharacterInteractionRole? fromPrefix(String prefix) {
    final normalized = prefix.toLowerCase();
    for (final role in values) {
      if (role.prefix == normalized) return role;
    }
    return null;
  }
}

/// 可选的互动动作。
///
/// 全部是 Danbooru 规范标签（NovelAI 图像模型按该词表训练），并且都描述两个
/// 角色之间的关系或动作；已排除别名（`handholding` → `holding_hands`）与只
/// 描述单体的标签（`carrying`、`dancing`、`licking`）。
enum CharacterInteractionAction {
  lookingAtAnother('looking_at_another'),
  hug('hug'),
  holdingHands('holding_hands'),
  kiss('kiss'),
  eyeContact('eye_contact'),
  hugFromBehind('hug_from_behind'),
  headpat('headpat'),
  frenchKiss('french_kiss'),
  princessCarry('princess_carry'),
  feeding('feeding'),
  lapPillow('lap_pillow'),
  piggyback('piggyback'),
  teasing('teasing'),
  tickling('tickling'),
  cheekPinching('cheek_pinching'),
  sharedUmbrella('shared_umbrella'),
  comforting('comforting');

  const CharacterInteractionAction(this.tag);

  /// 输出的 Danbooru 标签原文。
  final String tag;

  static CharacterInteractionAction? fromTag(String tag) {
    final normalized = normalizeTag(tag);
    for (final action in values) {
      if (normalizeTag(action.tag) == normalized) return action;
    }
    return null;
  }

  /// 自定义动作的最大长度，避免异常输入把提示词撑爆。
  static const int maxActionLength = 80;

  /// 比较用的归一化形式：下划线与空格等价、忽略大小写。
  static String normalizeTag(String tag) => tag
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  /// 自定义动作的清洗：允许直接粘贴完整标签，逗号会截断标签段因此统一去掉。
  ///
  /// 输入 `target#pointing at another`、`pointing  at  another` 都会得到
  /// `pointing at another`，超长输入按 [maxActionLength] 截断。
  static String normalizeAction(String raw) {
    var text = raw.trim();
    final hash = text.indexOf('#');
    if (hash >= 0) text = text.substring(hash + 1).trim();
    text = text
        .replaceAll(',', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length <= maxActionLength) return text;
    return text.substring(0, maxActionLength).trim();
  }
}

/// 角色提示词里的一条互动声明。
///
/// 动作不指定对象角色：配对由双方各自写的前缀决定（一方 source、另一方
/// target），因此只需要身份与动作两个字段。
@immutable
class CharacterInteraction {
  const CharacterInteraction({required this.role, required this.action});

  final CharacterInteractionRole role;

  /// 动作标签原文，允许自定义（官方示例里也有 `pointing at another` 这类多词动作）。
  final String action;

  /// 可直接写进角色提示词的片段。
  String get tag => '${role.tagPrefix}$action';

  /// 是否不在预设词表内（用户自定义或智能体写入的动作）。
  bool get isCustomAction => CharacterInteractionAction.fromTag(action) == null;

  /// 从角色提示词里读出已有的互动声明；没有则返回 null。
  static CharacterInteraction? parse(String prompt) {
    for (final range in _segmentRanges(prompt)) {
      final match = _tagPattern.firstMatch(
        NaiPromptParser.stripWeightSyntax(
          prompt.substring(range.start, range.end),
        ),
      );
      if (match == null) continue;
      final role = CharacterInteractionRole.fromPrefix(match.group(1)!);
      final action = match.group(2)!.trim();
      if (role == null || action.isEmpty) continue;
      return CharacterInteraction(role: role, action: action);
    }
    return null;
  }

  /// 写入或替换互动声明；[interaction] 为 null 时清除已有声明。
  ///
  /// 只改动互动标签本身，提示词的其余文字、换行与分组原样保留；新标签放在
  /// 提示词最前面，让"谁主动、谁承受"排在显眼位置。
  static String write(String prompt, CharacterInteraction? interaction) {
    var text = prompt;
    for (final range in _segmentRanges(prompt)) {
      final segment = prompt.substring(range.start, range.end).trim();
      if (!_tagPattern.hasMatch(segment)) continue;
      text = _removeTag(prompt, range);
      break;
    }

    final lead = _leadingWhitespace.matchAsPrefix(text)?.end ?? 0;
    final head = text.substring(0, lead);
    final tail = text.substring(lead);
    if (interaction == null) {
      return tail.trim().isEmpty ? head.trimRight() : text;
    }
    if (tail.trim().isEmpty) return '$head${interaction.tag}';
    return '$head${interaction.tag}, $tail';
  }

  /// 智能体与 UI 共用的读取结果。
  Map<String, String> toJson() => {
    'role': role.prefix,
    'action': action,
    'tag': tag,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharacterInteraction &&
          other.role == role &&
          other.action == action;

  @override
  int get hashCode => Object.hash(role, action);

  @override
  String toString() => 'CharacterInteraction($tag)';

  static final RegExp _leadingWhitespace = RegExp(r'^\s*');
  static final RegExp _followingSeparator = RegExp(r'[ \t]*,[ \t]*');
  static final RegExp _precedingSeparator = RegExp(r'[ \t]*,[ \t]*$');

  /// 整段形式的互动标签：`source#hug`、`target#pointing at another`。
  static final RegExp _tagPattern = RegExp(
    r'^(source|target|mutual)#(.+)$',
    caseSensitive: false,
  );

  /// 删除一段互动标签，并修好接缝：不留 `alpha, , beta` 空位，也不把相邻标签
  /// 粘成 `alpha,beta`。
  static String _removeTag(String prompt, ({int start, int end}) range) {
    var start = range.start;
    final following = _followingSeparator.matchAsPrefix(prompt, range.end);
    if (following == null) {
      final preceding = _precedingSeparator.firstMatch(
        prompt.substring(0, start),
      );
      if (preceding != null) start = preceding.start;
      return prompt.substring(0, start) + prompt.substring(range.end);
    }

    // 连同标签自身的缩进一起收掉，再用一个空格接回后继内容。
    while (start > 0 &&
        (prompt[start - 1] == ' ' || prompt[start - 1] == '	')) {
      start--;
    }
    final before = prompt.substring(0, start);
    final after = prompt.substring(following.end);
    if (before.trim().isEmpty) return after;
    if (after.trim().isEmpty) return before.trimRight();
    return '$before $after';
  }

  /// 顶层逗号分隔的片段范围，忽略括号与转义内部的逗号。
  static List<({int start, int end})> _segmentRanges(String prompt) {
    final ranges = <({int start, int end})>[];
    var start = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var parenDepth = 0;
    for (var i = 0; i < prompt.length; i++) {
      final char = prompt[i];
      if (char == '\\' && i + 1 < prompt.length) {
        i++;
        continue;
      }
      if (char == '{') {
        braceDepth++;
      } else if (char == '}' && braceDepth > 0) {
        braceDepth--;
      } else if (char == '[') {
        bracketDepth++;
      } else if (char == ']' && bracketDepth > 0) {
        bracketDepth--;
      } else if (char == '(') {
        parenDepth++;
      } else if (char == ')' && parenDepth > 0) {
        parenDepth--;
      }
      final topLevel =
          braceDepth == 0 && bracketDepth == 0 && parenDepth == 0;
      if (char == ',' && topLevel) {
        ranges.add((start: start, end: i));
        start = i + 1;
      }
    }
    ranges.add((start: start, end: prompt.length));
    return ranges;
  }
}
