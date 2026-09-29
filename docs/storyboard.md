# 漫画分镜编辑器

生成页中央工作区的第三种模式（与「预览」「无限画布」并列）。用户在一张页面上排布分镜格子，为每个格子独立设置提示词、分辨率与生成参数，然后批量生成并把结果合成回页面。

| 主题 | 入口 |
|---|---|
| 模式切换 | `lib/presentation/providers/generation/generation_center_mode_provider.dart` |
| 文档模型 | `lib/data/models/storyboard/`（document / page / panel / background / resolution） |
| 存储 | `lib/data/services/storyboard/storyboard_document_store.dart`（原子写 tmp + rename + `.bak`） |
| 几何与间距约束 | `lib/core/utils/storyboard/storyboard_geometry.dart` |
| 分辨率解析 | `lib/core/utils/storyboard/storyboard_resolution_resolver.dart` |
| 画布与工具条 | `lib/presentation/screens/generation/storyboard/` |
| 左侧参数面板分组 | `lib/presentation/widgets/storyboard/storyboard_settings_section.dart` |
| 批量生成 | `lib/data/services/storyboard/storyboard_generation_planner.dart` + `lib/presentation/providers/storyboard/storyboard_generation_runner.dart` |
| 导出 | `lib/data/services/storyboard/storyboard_page_exporter.dart` |
| Agent 工具 | `lib/presentation/agent_chat/services/storyboard_toolbox.dart` |
| 云同步 | `lib/data/cloud_sync/storyboard_cloud_sync_adapter.dart` |

## 文档与坐标约定

- 分镜文档是图库根目录下的 sidecar JSON `.gallery_storyboard.json`，与无限画布同构：整篇读写、原子提交、容错解析（坏文档返回 null 而不是抛异常）。
- **页面坐标就是最终输出像素**。页面尺寸在页面设置里改，导出结果与排版坐标一一对应。
- 每个分镜的 `rect` 同时是版面矩形和多边形的外接矩形；`points` 归一化到 rect 的 0..1，移动/缩放矩形时形状自动跟随。
- 多边形分镜在生成阶段仍按外接矩形请求（NovelAI 只输出矩形），多边形只影响画布裁剪与整页合成。

## 间距语义

页边距与分镜间距是**拖拽约束**而不是布局生成器：分镜移动/缩放不得越过页边距，也不得小于与相邻分镜的间距。单个分镜可以用「分镜设置 → 不受间距钳制」豁免。网格工具生成时使用当时的页面间距。

## 分辨率与计费

- `auto` 模式：按版面矩形面积吸附到 64 网格；版面面积低于免费档的 3/4（`autoQualityFloorArea`）时**放大到免费档满额面积出图**再缩回贴合分镜；接近或超过免费档的版面保持原样，不多花钱；超过单张上限（3,145,728 像素）时按比例收敛。
- **质量下限对所有模式生效**：显式分辨率低于下限（例如旧的 320×512）同样同比例放大到免费档满额——任何入口都不出小图，Opus 下放大不产生 Anlas。放大后若 64 网格吸附把面积顶回免费上限之上，会同比例再收一格，保证放大始终免费。
- `explicit` 模式：用户在左侧改了画幅就固化为显式分辨率（64 网格）。
- 页面设置的「禁止收费」把所有请求（含显式分辨率与整页背景）钳进 Opus 免费档（≤1,048,576 像素、≤28 步），同比例缩小出图后再由适配方式贴合分镜。左栏「画幅大小」显示的就是钳制后的请求尺寸。
- 左侧「生成」按钮在分镜模式下接管：选中分镜 → 生成该分镜；选中背景 → 生成页面背景；未选中 → 打开批量范围对话框。生成前编辑器内容会写回分镜快照。流式预览实时显示在对应分镜格内。

## 生成回填

批量走 `ImageGenerationService.generateSingle()`（与生成页同一套重试、429 退避与取消），结果经 `GenerationResultLifecycleService` 落盘入图库后按 `panelId` 回填到 `panel.images`；页面背景用保留 id `@background` 回填。

生成前 runner 会执行与生成页一致的参数装配：别名解析 → 角色块解析 → **固定词** → **质量标签预设 / UC 预设**（`StoryboardPromptAssembly`，套在每个分镜最终使用的提示词上），并把编辑器当前**角色快照**与 **Vibe 编码**带入 base——分镜自带角色时整体覆盖，没有时回落到编辑器角色。流式预览实时显示在对应分镜格内；DLSS 自动增强按设计不参与分镜批量。

## 导出

工具条「导出」菜单：整页合成（背景 + 全部分镜按 zOrder 合成，页面像素直出）与单个分镜（外接矩形出图，多边形外透明）。产物经 `ImageSaveUtils.saveBytesToDatedPath` 进入图库当日目录。dart:ui 渲染在根 isolate 执行，面板原图逐张解码-绘制-释放。

## Agent 工具

权限域 `storyboard`（`AgentPermissionDomain.storyboard`）。`get_storyboard_state`、`inspect_storyboard_panel` 为读；`update_storyboard_page`、`update_storyboard_background`（整页背景：类型/颜色/图片/提示词/种子/适配）、`add_storyboard_panels`（网格或显式条目，矩形与多边形都可以）、`update_storyboard_panel`（含多边形 `points` 与 `shape`）、`export_storyboard_page` 为写；`remove_storyboard_panel` 为删除；`generate_storyboard_panels` 计费（审批界面展示预估 Anlas，批量后台顺序执行，用状态工具轮询进度）。多边形编辑与画布同一条几何链路：顶点是页面像素，外接框取顶点包围盒；`inspect_storyboard_panel` 回传 `pixel_points` 供直接改写。工具契约由 `business_toolbox_contract_test.dart` 守护。

## 云同步

`storyboard-document` 适配器只同步 sidecar 文档本身（版面、提示词与相对路径引用），图片本体永不同步。归入图库内容组，默认开启；v2 及更早的旧快照可继续解码。恢复时整篇覆盖本地文档，删除墓碑不会清空本地排版。

## 验证

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/test_affected.ps1 -Path "lib/data/models/storyboard,lib/core/utils/storyboard,lib/data/services/storyboard"
flutter test test/data/cloud_sync/storyboard_cloud_sync_adapter_test.dart
flutter test test/presentation/agent_chat/services/business_toolbox_contract_test.dart
```

顶栏与画布回归注意：修改分镜交互后按 AGENTS.md 的热重载约定刷新已启动会话，并在 `700/840/1180/1600` 宽度下检查工具条不溢出。
