import 'nai_prompt_parser.dart';

/// 视角控制片段在提示词文本里的插入与移除。
///
/// 只做纯文本计算，不依赖控制器或 Provider，因此可以直接单测；
/// 片段本身使用下划线标签和 `weight::tag::` 语法，经过
/// [NaiPromptFormatter] 反复格式化后仍保持原样，往返移除不会失败。
class CameraAnglePromptInserter {

  static final RegExp _leadingWhitespace = RegExp(r'^\s*');

  /// 用 [RegExp.matchAsPrefix] 定位，因此不能带 `^` 锚点：锚点只匹配字符串
  /// 开头，无法在片段之后的偏移处匹配。
  static final RegExp _followingSeparator = RegExp(r'[ \t]*,[ \t]*');
  static final RegExp _precedingSeparator = RegExp(r'[ \t]*,[ \t]*$');

  /// 把 [fragment] 作为前置提示词插入 [prompt] 的开头。
  ///
  /// 片段已经完整出现在提示词里时原样返回，重复调用不会产生重复标签；
  /// 首行已有的缩进和空行会被保留。
  static String insert(String prompt, String fragment) {
    final target = fragment.trim();
    if (target.isEmpty) return prompt;
    if (NaiPromptParser.containsFragment(prompt, target)) return prompt;
    if (prompt.trim().isEmpty) return target;

    final start = _leadingWhitespace.matchAsPrefix(prompt)!.end;
    final head = prompt.substring(0, start);
    final tail = prompt.substring(start);
    return '$head$target, $tail';
  }

  /// 从 [prompt] 中移除此前插入的 [fragment]，并顺带清理一个相邻的逗号。
  ///
  /// 先按原文精确匹配；命中失败时退回到"整段归一化匹配"，因为开启自动格式化
  /// 后自然语言描述里的空格会被改写下划线，原文不再逐字存在。匹配不到任何
  /// 片段时返回原文，不做模糊匹配，避免误删用户内容。
  static String remove(String prompt, String fragment) {
    final target = fragment.trim();
    if (target.isEmpty) return prompt;

    final exact = prompt.indexOf(target);
    if (exact >= 0) {
      return _removeSpan(prompt, exact, exact + target.length);
    }

    final ranges = _segmentRanges(prompt);
    final fragmentSegments = NaiPromptParser.splitSegments(target)
        .map(_comparableSegment)
        .toList();
    if (fragmentSegments.isEmpty) return prompt;

    for (var start = 0; start < ranges.length; start++) {
      if (start + fragmentSegments.length > ranges.length) break;
      var matches = true;
      for (var offset = 0; offset < fragmentSegments.length; offset++) {
        final range = ranges[start + offset];
        final segment = _comparableSegment(
          prompt.substring(range.start, range.end),
        );
        if (segment != fragmentSegments[offset]) {
          matches = false;
          break;
        }
      }
      if (!matches) continue;
      return _removeSpan(
        prompt,
        ranges[start].start,
        ranges[start + fragmentSegments.length - 1].end,
      );
    }
    return prompt;
  }

  /// 比较用的片段形式：在 `NaiPromptParser` 的归一化之上把下划线与空格视为
  /// 等价，这样开启自动格式化（空格改写成下划线）后仍能匹配并移除。
  static String _comparableSegment(String segment) =>
      NaiPromptParser.normalizeSegment(
        segment,
      ).replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');

  /// 删除 [start]..[end] 这一段，并修好接缝处的逗号。
  static String _removeSpan(String prompt, int start, int end) {
    final following = _followingSeparator.matchAsPrefix(prompt, end);
    if (following != null) {
      end = following.end;
    } else {
      final preceding = _precedingSeparator.firstMatch(
        prompt.substring(0, start),
      );
      if (preceding != null) start = preceding.start;
    }
    return prompt.substring(0, start) + prompt.substring(end);
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
      final topLevel = braceDepth == 0 && bracketDepth == 0 && parenDepth == 0;
      if (char == ',' && topLevel) {
        ranges.add((start: start, end: i));
        start = i + 1;
      }
    }
    ranges.add((start: start, end: prompt.length));
    return ranges;
  }
}
