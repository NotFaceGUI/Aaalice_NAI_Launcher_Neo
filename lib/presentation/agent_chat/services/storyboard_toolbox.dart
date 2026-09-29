import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/agent/agent_types.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/utils/storyboard/storyboard_resolution_resolver.dart';
import '../../../../data/models/storyboard/storyboard_fit_mode.dart';
import '../../../../data/models/storyboard/storyboard_page.dart';
import '../../../../data/models/storyboard/storyboard_page_background.dart';
import '../../../../data/models/storyboard/storyboard_panel.dart';
import '../../../../data/models/storyboard/storyboard_panel_character.dart';
import '../../../../data/models/storyboard/storyboard_resolution.dart';
import '../../../../data/services/gallery/gallery_path_utils.dart';
import '../../../../data/services/storyboard/storyboard_generation_planner.dart';
import '../../../../data/services/storyboard/storyboard_page_exporter.dart';
import '../../providers/generation/generation_anlas_estimator_provider.dart';
import '../../providers/generation/generation_params_notifier.dart';
import '../../providers/local_gallery_provider.dart';
import '../../providers/storyboard/storyboard_document_controller.dart';
import '../../providers/storyboard/storyboard_generation_runner.dart';
import '../../providers/storyboard/storyboard_repository_provider.dart';
import 'agent_resource_resolver.dart';
import 'defined_agent_tool.dart';
import 'toolbox_json.dart';

/// 漫画分镜编辑器的 Agent 工具。
///
/// 页面坐标就是最终输出像素；请求尺寸默认按版面矩形推导（64 网格吸附），
/// 「禁止收费」页面会被钳进免费档。生成入口是计费工具，走应用统一的
/// 权限审批界面；批量生成在后台顺序执行，用 [get_storyboard_state] 轮询进度。
class StoryboardToolbox {
  StoryboardToolbox(this._ref);

  final Ref _ref;

  /// 单条提示词在列表结果里的截断长度；完整内容用 inspect 工具看。
  static const int _promptPreviewLength = 400;

  static const int _maxRects = 32;
  static const int _maxGridSide = 8;

  List<AgentTool> tools() => [
    _state(),
    _inspectPanel(),
    _updatePage(),
    _updateBackground(),
    _addPanels(),
    _updatePanel(),
    _removePanel(),
    _generate(),
    _export(),
  ];

  // ==================== 读取 ====================

  DefinedAgentTool _state() => DefinedAgentTool(
    name: 'get_storyboard_state',
    label: 'Get Storyboard State',
    description:
        'Read the active comic storyboard page: size, spacing, background, '
        'and a bounded panel list in reading order. Panel rects are in final '
        'output pixels.',
    parameters: toolboxObject(
      properties: {
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50},
      },
    ),
    executeFn: (_, params) async {
      final page = _activePage();
      if (page == null) return agentToolError('not_ready', 'Storyboard page is not loaded yet.');
      final limit = ((params['limit'] as num?)?.toInt() ?? 20).clamp(1, 50);
      final panels = page.panelsByReadingOrder;
      return agentToolJsonResult({
        'ok': true,
        'page': {
          'page_id': page.id,
          'name': page.name,
          'width': page.width,
          'height': page.height,
          'margin': page.margin,
          'gutter': page.gutter,
          'free_only': page.freeOnly,
          'background': _backgroundJson(page.background),
          'panel_count': panels.length,
        },
        'panels': [
          for (final panel in panels.take(limit)) _panelSummary(panel),
        ],
        'panels_truncated': panels.length > limit,
        'generation_running': _ref
            .read(storyboardGenerationRunnerProvider)
            .isRunning,
      });
    },
  );

  DefinedAgentTool _inspectPanel() => DefinedAgentTool(
    name: 'inspect_storyboard_panel',
    label: 'Inspect Storyboard Panel',
    description:
        'Read one storyboard panel in full: rect, polygon vertices, prompt, '
        'characters, generation snapshot, images and flags.',
    parameters: toolboxObject(
      properties: {
        'panel_id': {'type': 'string', 'minLength': 1},
      },
      required: const ['panel_id'],
    ),
    executeFn: (_, params) async {
      final panel = _panelOf(params['panel_id'] as String);
      if (panel == null) {
        return agentToolError('not_found', 'Panel was not found.');
      }
      return agentToolJsonResult({
        'ok': true,
        'panel': {
          ..._panelSummary(panel),
          'points': [
            for (final point in panel.points)
              [point.dx, point.dy],
          ],
          // 编辑用页面像素顶点：与 rect 同一坐标系，可直接回传给 points。
          'pixel_points': [
            for (final point in panel.points)
              [
                (panel.x + point.dx * panel.width).round(),
                (panel.y + point.dy * panel.height).round(),
              ],
          ],
          'negative_prompt': panel.negativePrompt,
          'characters': [
            for (final character in panel.characters)
              {
                'prompt': character.prompt,
                'negative_prompt': character.negativePrompt,
                if (character.x != null) 'x': character.x,
                if (character.y != null) 'y': character.y,
              },
          ],
          'generation': {
            if (panel.generation.model != null) 'model': panel.generation.model,
            if (panel.generation.sampler != null)
              'sampler': panel.generation.sampler,
            if (panel.generation.steps != null) 'steps': panel.generation.steps,
            if (panel.generation.scale != null) 'scale': panel.generation.scale,
            if (panel.generation.smea != null) 'smea': panel.generation.smea,
            if (panel.generation.smeaDyn != null)
              'smea_dyn': panel.generation.smeaDyn,
          },
          'images': panel.images,
          'selected_image': panel.selectedImage,
        },
      });
    },
  );

  // ==================== 页面写入 ====================

  DefinedAgentTool _updatePage() => DefinedAgentTool(
    name: 'update_storyboard_page',
    label: 'Update Storyboard Page',
    description:
        'Update the active storyboard page: size (final output pixels, '
        'multiples of 64 recommended), margins, gutters, the free-only flag '
        '(clamps every request into the no-Anlas range) or the background '
        'prompt.',
    parameters: toolboxObject(
      properties: {
        'width': {'type': 'integer', 'minimum': 256, 'maximum': 4096},
        'height': {'type': 'integer', 'minimum': 256, 'maximum': 4096},
        'margin': {'type': 'number', 'minimum': 0},
        'gutter': {'type': 'number', 'minimum': 0},
        'free_only': {'type': 'boolean'},
        'background_prompt': {'type': 'string'},
      },
    ),
    executeFn: (_, params) async {
      final document = _ref.read(storyboardDocumentControllerProvider.notifier);
      await document.setPageSize(
        width: (params['width'] as num?)?.toInt() ?? _activePage()?.width ?? 0,
        height:
            (params['height'] as num?)?.toInt() ?? _activePage()?.height ?? 0,
      );
      final margin = params['margin'] as num?;
      final gutter = params['gutter'] as num?;
      if (margin != null || gutter != null) {
        final page = _activePage();
        await document.setPageSpacing(
          margin: margin?.toDouble() ?? page?.margin ?? 0,
          gutter: gutter?.toDouble() ?? page?.gutter ?? 0,
        );
      }
      final freeOnly = params['free_only'] as bool?;
      if (freeOnly != null) await document.setPageFreeOnly(freeOnly);
      final backgroundPrompt = params['background_prompt'] as String?;
      if (backgroundPrompt != null) {
        await document.setBackgroundPrompt(backgroundPrompt);
      }
      final page = _activePage();
      return agentToolJsonResult({
        'ok': true,
        'page': page == null
            ? null
            : {
                'page_id': page.id,
                'width': page.width,
                'height': page.height,
                'margin': page.margin,
                'gutter': page.gutter,
                'free_only': page.freeOnly,
              },
      });
    },
  );

  // ==================== 背景（整页第 0 格） ====================

  DefinedAgentTool _updateBackground() => DefinedAgentTool(
    name: 'update_storyboard_background',
    label: 'Update Storyboard Background',
    description:
        'Configure the page background — the full-page layer behind every '
        'panel. Only provided fields change. kind: none / color / image; color '
        'accepts #RRGGBB or #AARRGGBB; an image comes from an application '
        'resource_ref or an image_path (a gallery-relative path or any local '
        'file, which is copied into the gallery); prompt is the background '
        'generation prompt used by generate_storyboard_panels with '
        'scope=background; seed fixes the background seed; fit is cover / '
        'contain / stretch.',
    parameters: toolboxObject(
      properties: {
        'kind': {'type': 'string', 'enum': ['none', 'color', 'image']},
        'color': {
          'type': 'string',
          'description': 'Hex color, #RRGGBB or #AARRGGBB.',
        },
        'resource_ref': {
          'type': 'object',
          'description':
              'Application resource identity of the image to use; resolve a '
              'generated or gallery image reference instead of inventing one.',
        },
        'image_path': {
          'type': 'string',
          'description':
              'Gallery-relative path or a local file path; files outside the '
              'gallery are copied into the storyboard folder.',
        },
        'prompt': {'type': 'string'},
        'seed': {'type': 'integer', 'minimum': 0},
        'fit': {
          'type': 'string',
          'enum': ['cover', 'contain', 'stretch'],
        },
      },
    ),
    executeFn: (_, params) async {
      final page = _activePage();
      if (page == null) {
        return agentToolError('not_ready', 'Storyboard page is not loaded yet.');
      }
      final document = _ref.read(storyboardDocumentControllerProvider.notifier);
      var background = page.background;
      var changed = false;

      final rawReference = params['resource_ref'];
      final imagePath = params['image_path'] as String?;
      if (rawReference != null ||
          (imagePath != null && imagePath.isNotEmpty)) {
        final absolute = await _resolveBackgroundSource(rawReference, imagePath);
        if (absolute == null) {
          return agentToolError(
            'image_not_found',
            'The background image could not be resolved.',
          );
        }
        final relative = await _ref
            .read(storyboardImageImporterProvider)
            .importFromPath(absolute);
        if (relative == null) {
          return agentToolError(
            'import_failed',
            'The image could not be imported into the gallery.',
          );
        }
        background = background.copyWith(
          kind: StoryboardBackgroundKind.image,
          imagePath: relative,
        );
        changed = true;
      }

      final kind = params['kind'] as String?;
      if (kind != null) {
        final parsed = switch (kind) {
          'none' => StoryboardBackgroundKind.none,
          'color' => StoryboardBackgroundKind.color,
          'image' => StoryboardBackgroundKind.image,
          _ => null,
        };
        if (parsed == null) {
          return agentToolError(
            'invalid_arguments',
            'Unknown background kind "$kind".',
          );
        }
        background = background.copyWith(kind: parsed);
        changed = true;
      }

      final color = params['color'] as String?;
      if (color != null) {
        final argb = _parseArgb(color);
        if (argb == null) {
          return agentToolError(
            'invalid_arguments',
            'Color must be #RRGGBB or #AARRGGBB.',
          );
        }
        background = background.copyWith(colorArgb: argb);
        changed = true;
      }
      final prompt = params['prompt'] as String?;
      if (prompt != null) {
        background = background.copyWith(prompt: prompt);
        changed = true;
      }
      final seed = params['seed'] as num?;
      if (seed != null) {
        background = background.copyWith(seed: seed.toInt());
        changed = true;
      }
      final fit = params['fit'] as String?;
      if (fit != null) {
        background = background.copyWith(fit: _fitOf(fit));
        changed = true;
      }

      if (changed) await document.setBackground(background);
      final updated = _activePage();
      return agentToolJsonResult({
        'ok': true,
        'background': updated == null
            ? null
            : _backgroundJson(updated.background),
      });
    },
  );

  // ==================== 分镜写入 ====================

  DefinedAgentTool _addPanels() => DefinedAgentTool(
    name: 'add_storyboard_panels',
    label: 'Add Storyboard Panels',
    description:
        'Lay out storyboard panels: either a uniform rows/columns grid '
        '(reusing the page margin and gutter) or explicit entries in page '
        'pixels (for irregular comic layouts, listed in reading order). '
        'Each entry is either a rectangle (x, y, width, height) or a polygon '
        '(points with at least 3 [x, y] vertices; the rect becomes their '
        'bounding box). replace=true clears existing panels first.',
    parameters: toolboxObject(
      properties: {
        'rows': {'type': 'integer', 'minimum': 1, 'maximum': 8},
        'columns': {'type': 'integer', 'minimum': 1, 'maximum': 8},
        'rects': {
          'type': 'array',
          'maxItems': _maxRects,
          'items': {
            'type': 'object',
            'properties': {
              'x': {'type': 'number'},
              'y': {'type': 'number'},
              'width': {'type': 'number'},
              'height': {'type': 'number'},
              'points': {
                'type': 'array',
                'minItems': 3,
                'maxItems': 64,
                'description':
                    'Polygon vertices in page pixels, listed along the '
                    'outline; the panel frame becomes their bounding box.',
                'items': {
                  'type': 'array',
                  'minItems': 2,
                  'maxItems': 2,
                  'items': {'type': 'number'},
                },
              },
            },
            'additionalProperties': false,
          },
        },
        'replace': {'type': 'boolean'},
      },
    ),
    executeFn: (_, params) async {
      final page = _activePage();
      if (page == null) {
        return agentToolError('not_ready', 'Storyboard page is not loaded yet.');
      }
      final document = _ref.read(storyboardDocumentControllerProvider.notifier);
      final replace = params['replace'] as bool? ?? false;
      final rows = (params['rows'] as num?)?.toInt();
      final columns = (params['columns'] as num?)?.toInt();
      final rawRects = params['rects'] as List?;
      if (rawRects != null && rawRects.isNotEmpty) {
        final cells = <StoryboardLayoutCell>[];
        for (final raw in rawRects) {
          if (raw is! Map) {
            return agentToolError(
              'invalid_arguments',
              'Each rects entry must be an object.',
            );
          }
          final points = _parsePoints(raw['points']);
          if (points == null) {
            return agentToolError(
              'invalid_arguments',
              'Each polygon point must be [x, y] with at least 3 points.',
            );
          }
          if (points.isNotEmpty &&
              points.length < StoryboardPanel.minPolygonPoints) {
            return agentToolError(
              'invalid_arguments',
              'A polygon needs at least 3 points.',
            );
          }
          if (points.length >= StoryboardPanel.minPolygonPoints) {
            cells.add(StoryboardLayoutCell(rect: Rect.zero, points: points));
            continue;
          }
          final x = raw['x'];
          final y = raw['y'];
          final width = raw['width'];
          final height = raw['height'];
          if (x is! num || y is! num || width is! num || height is! num) {
            return agentToolError(
              'invalid_arguments',
              'Each rects entry needs x, y, width, height or at least 3 points.',
            );
          }
          cells.add(
            StoryboardLayoutCell(
              rect: Rect.fromLTWH(
                x.toDouble(),
                y.toDouble(),
                width.toDouble(),
                height.toDouble(),
              ),
            ),
          );
        }
        final created = await document.applyPanelLayout(
          cells,
          replace: replace,
        );
        return agentToolJsonResult({'ok': true, 'created': created});
      }
      if (rows == null || columns == null) {
        return agentToolError(
          'invalid_arguments',
          'Provide either rects or both rows and columns.',
        );
      }
      if (rows < 1 || rows > _maxGridSide || columns < 1 || columns > _maxGridSide) {
        return agentToolError(
          'invalid_arguments',
          'rows and columns must be within 1..$_maxGridSide.',
        );
      }
      final created = await document.applyGrid(
        rows: rows,
        columns: columns,
        margin: page.margin,
        gutter: page.gutter,
        replace: replace,
      );
      if (created == 0) {
        return agentToolError(
          'does_not_fit',
          'The page cannot fit this grid with the current spacing.',
        );
      }
      return agentToolJsonResult({'ok': true, 'created': created});
    },
  );

  DefinedAgentTool _updatePanel() => DefinedAgentTool(
    name: 'update_storyboard_panel',
    label: 'Update Storyboard Panel',
    description:
        'Edit one storyboard panel. Only provided fields change: rect (page '
        'pixels), polygon points (page pixels; the rect becomes their '
        'bounding box), shape (rect resets the panel to its rectangle), '
        'prompt, negative_prompt, seed, variants, fit, resolution '
        '(mode auto derives from the rect; explicit snaps to the 64 grid), '
        'characters (replaces the per-frame cast), enabled, locked, '
        'ignore_spacing.',
    parameters: toolboxObject(
      properties: {
        'panel_id': {'type': 'string', 'minLength': 1},
        'x': {'type': 'number'},
        'y': {'type': 'number'},
        'width': {'type': 'number', 'minimum': 8},
        'height': {'type': 'number', 'minimum': 8},
        'shape': {
          'type': 'string',
          'enum': ['rect', 'polygon'],
          'description':
              'rect resets the panel to its rectangle; polygon needs points '
              'for a rectangle panel (inspect_storyboard_panel returns the '
              'current pixel_points).',
        },
        'points': {
          'type': 'array',
          'minItems': 3,
          'maxItems': 64,
          'description':
              'Polygon vertices in page pixels, same coordinate space as the '
              'rect and listed along the outline. Convene them clockwise and '
              'keep the shape simple (no self-intersections).',
          'items': {
            'type': 'array',
            'minItems': 2,
            'maxItems': 2,
            'items': {'type': 'number'},
          },
        },
        'prompt': {'type': 'string'},
        'negative_prompt': {'type': 'string'},
        'seed': {'type': 'integer', 'minimum': 0},
        'variants': {'type': 'integer', 'minimum': 1, 'maximum': 16},
        'fit': {
          'type': 'string',
          'enum': ['cover', 'contain', 'stretch'],
        },
        'resolution_mode': {
          'type': 'string',
          'enum': ['auto', 'explicit'],
        },
        'resolution_width': {'type': 'integer', 'minimum': 64},
        'resolution_height': {'type': 'integer', 'minimum': 64},
        'characters': {
          'type': 'array',
          'maxItems': 6,
          'description':
              'Replace the panel characters (the per-frame cast). An empty '
              'array clears them so the page characters apply. x/y are '
              'normalized 0-1 positions for custom placement.',
          'items': {
            'type': 'object',
            'properties': {
              'prompt': {'type': 'string', 'minLength': 1},
              'negative_prompt': {'type': 'string'},
              'x': {'type': 'number', 'minimum': 0, 'maximum': 1},
              'y': {'type': 'number', 'minimum': 0, 'maximum': 1},
            },
            'required': const ['prompt'],
            'additionalProperties': false,
          },
        },
        'enabled': {'type': 'boolean'},
        'locked': {'type': 'boolean'},
        'ignore_spacing': {'type': 'boolean'},
      },
      required: const ['panel_id'],
    ),
    executeFn: (_, params) async {
      final id = params['panel_id'] as String;
      final panel = _panelOf(id);
      if (panel == null) {
        return agentToolError('not_found', 'Panel was not found.');
      }
      final document = _ref.read(storyboardDocumentControllerProvider.notifier);
      final hasRect =
          params.keys
              .where((key) => key == 'x' || key == 'y' || key == 'width' || key == 'height')
              .isNotEmpty;
      if (hasRect) {
        await document.setPanelRect(
          id,
          Rect.fromLTWH(
            (params['x'] as num?)?.toDouble() ?? panel.x,
            (params['y'] as num?)?.toDouble() ?? panel.y,
            (params['width'] as num?)?.toDouble() ?? panel.width,
            (params['height'] as num?)?.toDouble() ?? panel.height,
          ),
        );
      }
      // 多边形：顶点是页面像素坐标，写入后外接矩形随顶点走（与画布一致）。
      final rawPoints = params['points'];
      if (rawPoints != null) {
        final points = _parsePoints(rawPoints);
        if (points == null || points.isEmpty) {
          return agentToolError(
            'invalid_arguments',
            'Each polygon point must be [x, y].',
          );
        }
        if (points.length < StoryboardPanel.minPolygonPoints) {
          return agentToolError(
            'invalid_arguments',
            'A polygon needs at least 3 points.',
          );
        }
        await document.setPanelPolygon(id, points);
      }
      final shape = params['shape'] as String?;
      if (shape != null) {
        if (shape == 'rect') {
          await document.resetPanelShape(id);
        } else if (shape == 'polygon') {
          final current = _panelOf(id);
          if (current != null && !current.isPolygon) {
            return agentToolError(
              'invalid_arguments',
              'Provide points to turn a rectangle panel into a polygon.',
            );
          }
        } else {
          return agentToolError(
            'invalid_arguments',
            'shape must be rect or polygon.',
          );
        }
      }
      final prompt = params['prompt'] as String?;
      if (prompt != null) await document.setPanelPrompt(id, prompt);
      final negative = params['negative_prompt'] as String?;
      if (negative != null) await document.setPanelNegativePrompt(id, negative);
      final seed = params['seed'] as num?;
      if (seed != null) await document.setPanelSeed(id, seed.toInt());
      final variants = params['variants'] as num?;
      if (variants != null) await document.setPanelVariants(id, variants.toInt());
      final fit = params['fit'] as String?;
      if (fit != null) {
        await document.setPanelFit(id, _fitOf(fit));
      }
      final mode = params['resolution_mode'] as String?;
      if (mode == 'auto') {
        await document.setPanelResolution(id, const StoryboardResolution.auto());
      } else if (mode == 'explicit') {
        final width = (params['resolution_width'] as num?)?.toInt();
        final height = (params['resolution_height'] as num?)?.toInt();
        if (width == null || height == null) {
          return agentToolError(
            'invalid_arguments',
            'explicit resolution needs resolution_width and resolution_height.',
          );
        }
        await document.setPanelResolution(
          id,
          StoryboardResolution.explicit(width: width, height: height),
        );
      }
      final enabled = params['enabled'] as bool?;
      if (enabled != null) await document.setPanelEnabled(id, enabled);
      final locked = params['locked'] as bool?;
      if (locked != null) await document.setPanelLocked(id, locked);
      final ignoreSpacing = params['ignore_spacing'] as bool?;
      if (ignoreSpacing != null) {
        await document.setPanelIgnoreSpacing(id, ignoreSpacing);
      }
      final rawCharacters = params['characters'];
      if (rawCharacters is List) {
        await document.setPanelCharacters(id, [
          for (final raw in rawCharacters.take(StoryboardPanel.maxCharacters))
            if (raw is Map && raw['prompt'] is String)
              StoryboardPanelCharacter(
                prompt: raw['prompt'] as String,
                negativePrompt: raw['negative_prompt'] as String? ?? '',
                x: (raw['x'] as num?)?.toDouble(),
                y: (raw['y'] as num?)?.toDouble(),
              ),
        ]);
      }
      final updated = _panelOf(id);
      return agentToolJsonResult({
        'ok': true,
        'panel': updated == null ? null : _panelSummary(updated),
      });
    },
  );

  DefinedAgentTool _removePanel() => DefinedAgentTool(
    name: 'remove_storyboard_panel',
    label: 'Remove Storyboard Panel',
    description: 'Delete one storyboard panel from the active page.',
    parameters: toolboxObject(
      properties: {
        'panel_id': {'type': 'string', 'minLength': 1},
      },
      required: const ['panel_id'],
    ),
    executeFn: (_, params) async {
      final id = params['panel_id'] as String;
      if (_panelOf(id) == null) {
        return agentToolError('not_found', 'Panel was not found.');
      }
      await _ref.read(storyboardDocumentControllerProvider.notifier).removePanel(id);
      return agentToolJsonResult({'ok': true, 'removed': id});
    },
  );

  // ==================== 生成与导出 ====================

  DefinedAgentTool _generate() => DefinedAgentTool(
    name: 'generate_storyboard_panels',
    label: 'Generate Storyboard Panels',
    description:
        'CHARGED. Start a sequential batch that generates storyboard panels '
        '(or the page background with scope=background). Returns the request '
        'count and estimated Anlas immediately; the batch runs in the '
        'background. Poll get_storyboard_state for progress.',
    parameters: toolboxObject(
      properties: {
        'scope': {
          'type': 'string',
          'enum': ['all', 'ungenerated', 'selected', 'background'],
        },
        'panel_id': {'type': 'string'},
      },
    ),
    executeFn: (_, params) async {
      final runner = _ref.read(storyboardGenerationRunnerProvider.notifier);
      if (runner.isRunning) {
        return agentToolError(
          'busy',
          'A storyboard batch is already running.',
        );
      }
      final page = _activePage();
      if (page == null) {
        return agentToolError('not_ready', 'Storyboard page is not loaded yet.');
      }
      final scope = params['scope'] as String? ?? 'ungenerated';
      final isBackground = scope == 'background';
      final panelId = params['panel_id'] as String?;
      if (scope == 'selected' && panelId == null) {
        return agentToolError(
          'invalid_arguments',
          'scope=selected needs panel_id.',
        );
      }
      if (isBackground && page.background.prompt.trim().isEmpty) {
        return agentToolError(
          'nothing_to_generate',
          'The background has no prompt.',
        );
      }
      final base = _ref.read(generationParamsNotifierProvider);
      final requests = isBackground
          ? StoryboardGenerationPlanner.planBackground(page: page, base: base)
          : StoryboardGenerationPlanner.planPage(
              page: page,
              base: base,
              onlyPanelIds: scope == 'selected' ? [panelId!] : null,
              selectedImageOnly: scope == 'ungenerated',
            );
      if (requests.isEmpty) {
        return agentToolError(
          'nothing_to_generate',
          'No panel has a prompt for this scope.',
        );
      }
      final estimator = _ref.read(generationAnlasEstimatorProvider);
      var estimated = 0;
      var costKnown = true;
      for (final request in requests) {
        final cost = estimator.estimate(request.params, requestCount: 1);
        if (cost < 0) {
          costKnown = false;
          break;
        }
        estimated += cost;
      }
      unawaited(
        runner.start(
          page: page,
          base: base,
          onlyPanelIds: scope == 'selected' ? [panelId!] : null,
          selectedImageOnly: scope == 'ungenerated',
          background: isBackground,
        ),
      );
      return agentToolJsonResult({
        'ok': true,
        'started': true,
        'requests': requests.length,
        'estimated_anlas': costKnown ? estimated : null,
        'next': 'Poll get_storyboard_state to observe progress.',
      });
    },
  );

  DefinedAgentTool _export() => DefinedAgentTool(
    name: 'export_storyboard_page',
    label: 'Export Storyboard Page',
    description:
        'Composite the active storyboard page (background plus all finished '
        'panels) into one PNG and save it into the gallery. Returns the '
        'saved path.',
    parameters: toolboxObject(),
    executeFn: (_, params) async {
      final page = _activePage();
      final galleryRoot = await _ref
          .read(storyboardRepositoryProvider)
          .rootPath();
      if (page == null || galleryRoot == null || galleryRoot.isEmpty) {
        return agentToolError('not_ready', 'Storyboard or gallery is unavailable.');
      }
      final bytes = await StoryboardPageExporter.renderPage(
        page: page,
        galleryRoot: galleryRoot,
      );
      final path = await ImageSaveUtils.saveBytesToDatedPath(
        rootPath: galleryRoot,
        bytes: bytes,
        preferredFileName: 'storyboard-page',
      );
      final gallery = _ref.read(localGalleryNotifierProvider.notifier);
      await gallery.addNewlySavedImages([path]);
      unawaited(gallery.refresh());
      return agentToolJsonResult({'ok': true, 'path': path});
    },
  );

  // ==================== 供审批流程复用 ====================

  /// 估算 generate_storyboard_panels 的 Anlas 成本；规划不出请求时返回 null。
  static Future<int?> estimatePlannedAnlas(
    Ref ref, {
    required String? panelId,
    required String scope,
  }) async {
    final page = ref
        .read(storyboardDocumentControllerProvider)
        .valueOrNull
        ?.activePage;
    if (page == null) return null;
    final isBackground = scope == 'background';
    if (scope == 'selected' && panelId == null) return null;
    final base = ref.read(generationParamsNotifierProvider);
    final requests = isBackground
        ? StoryboardGenerationPlanner.planBackground(page: page, base: base)
        : StoryboardGenerationPlanner.planPage(
            page: page,
            base: base,
            onlyPanelIds: scope == 'selected' ? [panelId!] : null,
            selectedImageOnly: scope == 'ungenerated',
          );
    if (requests.isEmpty) return null;
    final estimator = ref.read(generationAnlasEstimatorProvider);
    var total = 0;
    for (final request in requests) {
      final cost = estimator.estimate(request.params, requestCount: 1);
      if (cost < 0) return null;
      total += cost;
    }
    return total;
  }

  // ==================== 内部 ====================

  StoryboardPage? _activePage() => _ref
      .read(storyboardDocumentControllerProvider)
      .valueOrNull
      ?.activePage;

  StoryboardPanel? _panelOf(String? id) {
    if (id == null || id.isEmpty) return null;
    return _activePage()?.panelById(id);
  }

  /// 背景的对外表示：背景就是覆盖整页的第 0 格，尺寸等于画幅大小。
  Map<String, dynamic> _backgroundJson(StoryboardPageBackground background) => {
    'kind': background.kind.name,
    'color': '#${background.colorArgb.toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'image_path': background.imagePath,
    'has_image': background.hasImage,
    'fit': background.fit.name,
    'prompt': background.prompt,
    'seed': background.seed,
    'generated_count': background.images.length,
  };

  /// 把 resource_ref 或 image_path 解析成可用于导入的绝对文件路径。
  Future<String?> _resolveBackgroundSource(
    Object? rawReference,
    String? imagePath,
  ) async {
    if (rawReference != null) {
      try {
        final resolver = AgentResourceResolver(_ref);
        final reference = resolver.decode(rawReference);
        await resolver.validateImageResource(reference);
        final resolved = await resolver.resolve(reference);
        if (resolved?.filePath != null) return resolved!.filePath;
      } on FormatException {
        // 引用格式错误按解析失败处理，由调用方给出统一错误。
        return null;
      }
    }
    if (imagePath == null || imagePath.isEmpty) return null;
    final root = await _ref.read(storyboardRepositoryProvider).rootPath();
    if (root != null &&
        root.isNotEmpty &&
        isValidGalleryRelativePath(imagePath)) {
      return toGalleryAbsolutePath(root, imagePath);
    }
    return imagePath;
  }

  /// 解析可选的多边形顶点：缺失返回空表，格式非法返回 null。
  static List<Offset>? _parsePoints(Object? rawPoints) {
    if (rawPoints == null) return const [];
    if (rawPoints is! List) return null;
    final points = <Offset>[];
    for (final raw in rawPoints.take(StoryboardPanel.maxPolygonPoints)) {
      if (raw is! List || raw.length < 2) return null;
      final x = raw[0];
      final y = raw[1];
      if (x is! num || y is! num) return null;
      points.add(Offset(x.toDouble(), y.toDouble()));
    }
    return points;
  }

  static int? _parseArgb(String value) {
    final hex = value.trim().replaceFirst('#', '');
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return hex.length == 6 ? (0xFF000000 | parsed) : parsed;
  }

  Map<String, dynamic> _panelSummary(StoryboardPanel panel) {
    final plan = StoryboardResolutionResolver.resolve(
      layoutWidth: panel.width,
      layoutHeight: panel.height,
      resolution: panel.resolution,
      fit: panel.fit,
      maxArea: _activePage()?.freeOnly ?? false
          ? StoryboardResolutionResolver.freeTierMaxPixels
          : null,
    );
    return {
      'panel_id': panel.id,
      'order': panel.order,
      'z_order': panel.zOrder,
      'rect': {
        'x': panel.x.round(),
        'y': panel.y.round(),
        'width': panel.width.round(),
        'height': panel.height.round(),
      },
      'shape': panel.shape.name,
      'vertex_count': panel.points.length,
      'request': {'width': plan.requestWidth, 'height': plan.requestHeight},
      'resolution': {
        'mode': panel.resolution.mode.name,
        if (panel.resolution.width != null) 'width': panel.resolution.width,
        if (panel.resolution.height != null) 'height': panel.resolution.height,
      },
      'fit': panel.fit.name,
      'variants': panel.variants,
      'seed': panel.seed,
      'status': panel.status.name,
      'enabled': panel.enabled,
      'locked': panel.locked,
      'ignore_spacing': panel.ignoreSpacing,
      'prompt': _truncate(panel.prompt),
      'has_image': panel.selectedImage != null,
      'image_count': panel.images.length,
    };
  }

  String _truncate(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= _promptPreviewLength) return trimmed;
    return '${trimmed.substring(0, _promptPreviewLength)}…';
  }

  StoryboardFitMode _fitOf(String value) => switch (value) {
    'contain' => StoryboardFitMode.contain,
    'stretch' => StoryboardFitMode.stretch,
    _ => StoryboardFitMode.cover,
  };
}
