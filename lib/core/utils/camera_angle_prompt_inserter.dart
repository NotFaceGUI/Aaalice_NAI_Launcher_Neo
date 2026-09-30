import 'nai_prompt_parser.dart';

/// 视角控制片段在提示词文本里的插入与移除。
///
/// 只做纯文本计算，不依赖控制器或 Provider，因此可以直接单测；
/// 片段本身使用下划线标签和 `weight::tag::` 语法，经过
/// [NaiPromptFormatter] 反复格式化后仍保持原样，往返移除不会失败。
class CameraAnglePromptInserter {
  CameraAnglePromptInserter._();

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
  /// 片段已被用户改写或删除时返回原文，不做模糊匹配，避免误删用户内容。
  static String remove(String prompt, String fragment) {
    final target = fragment.trim();
    if (target.isEmpty) return prompt;

    final index = prompt.indexOf(target);
    if (index < 0) return prompt;

    var start = index;
    var end = index + target.length;
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
}
