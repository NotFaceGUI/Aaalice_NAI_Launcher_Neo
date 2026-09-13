# 无限画布

生成页中央工作区可以在图像预览与无限画布之间切换。画布把生成结果、固定下来的种子
和手写便签摆到同一张可平移缩放的平面上，供用户排布、连线和标注。

## 定位与边界

- 画布是**工作台**，不是归档：节点数量由用户自己的整理习惯决定，不做数量上限。
- 画布**不复制图片字节**：图片节点只保存相对图库根目录的路径引用。
- 画布**不是新的生成入口**：连线是纯标注，不携带生成派生语义；消耗 Anlas 的操作
  仍走生成页既有的确认流程。

## 存储

| 内容 | 位置 | 是否参与云同步 |
|---|---|---|
| 节点、连线 | `<图库根>/.gallery_canvas.json` | 数据模型已按可同步设计，本版未接线 |
| 视口偏移/缩放、画布开关、自动加入开关 | Hive `settings` box（设备专属） | 否 |

sidecar 跟随图库根目录存储，与相册、分类的 `.gallery_*.json` 一致：拷贝整个图库
文件夹到其他设备时画布随之带走。写入使用 tmp + rename 原子提交，提交前把旧文件
转成 `.bak`；主文件损坏或提交中断时从 `.bak` 恢复。

`CanvasDocument.fromJson` 对未知版本返回 `null`（由调用方决定是否覆盖），并丢弃
缺少 id、重复 id、引用缺失节点和自连的条目，保证内存里的图始终自洽。

### 图片引用

图片节点只能指向图库内的真实文件：

- 生成图**已落盘**（默认自动保存，或用户手动保存过）→ 直接引用，不重复存储。
- 生成图**尚未落盘** → 「加入画布」先走既有保存链路落盘一次，提示会明确说明
  「已保存到图库并加入画布」。
- 文件被移动或删除 → 节点显示图像缺失占位，节点本身保留，参数快照仍可用于
  重新生成。

这样画布重启后可恢复、不产生第二份图片副本，后续云同步也只需同步这份轻量引用。

## 节点类型

| 类型 | 内容 | 可缩放 |
|---|---|---|
| 图片 | 图片 + 图片自带的 NovelAI 元数据快照 | 是（保持原图比例） |
| 种子待办 | 种子 + 参数快照 + 待生成/已完成状态 | 是 |
| 文本便签 | Markdown 标注 | 是 |

节点的参数快照只保存「把参数载回生成页」所需的字段（提示词、负向词、模型、采样器、
步数、CFG、尺寸），不含模型能力位、参考图与角色等大对象；种子由节点自身持有。

## 交互矩阵

画布视口用**原始指针事件**实现平移与缩放，不参与手势竞技场；节点与连接手柄在
`PointerDown` 时通过 `CanvasPointerRegistry` 认领指针。视口在按下和移动时检查归属，
工具栏也认领指针；滚动使用 Flutter 的 pointer signal resolver，避免节点、工具栏
与视口同时处理同一手势。

| 操作 | 精确指针 | 触屏 |
|---|---|---|
| 平移 | 拖空白、Shift + 滚轮横向平移 | 单指拖空白 |
| 缩放 | 滚轮、工具栏 | 双指捏合 |
| 焦点缩放 | 以指针位置为中心 | 以两指中点为焦点 |
| 选中节点 | 单击 | 单击 |
| 拖动节点 | 拖节点主体 | 拖节点主体 |
| 连线 | 从节点四边中点手柄拖到目标节点 | 同左（手柄常驻，不依赖 hover） |
| 连线模式 | 工具栏开关，依次点两个节点 | 同左 |
| 上下文菜单 | 右键 | 长按 |
| 查询信息 | hover 浮出信息条；延时 hover 展开完整提示词 | 选中后在菜单中查看参数 |
| 取消选择 | 点空白处 | 同左 |

拖动与调整节点尺寸共享 `CanvasDragTracker` 中唯一的画布空间预览矩形，节点布局与
连线路由实时读取它，不把逐帧状态写入文档。全局指针位置相对按下点求位移，只除一次
手势开始时的视口缩放；松手通过 `setNodeRect` 一次提交位置和尺寸，取消则丢弃预览。
提交带上开始时的画布 ID，切换画布后旧手势不能写入新画布。

节点层始终按屏幕单位定位，正文内部才缩放；预览矩形同时决定位置、布局约束与手柄
坐标，不能只在绘制时平移。手柄布局由 `CanvasNodeHandleLayout` 统一计算：常规鼠标
命中区 28px、触屏 48px；节点过小时分离到外侧，八个命中区不重叠。外扩区域的空白
不得遮挡相邻节点，曲线、箭头、标签和命中测试均遵循同一视口映射。

文档修改按 `persistDebounce`（300ms）合并写入，不改变 sidecar 格式和云同步边界。

## 生成结果如何进入画布

`CanvasGenerationBridge` 监听生成状态：

- 画布打开时立即在视口附近预留生成快照位置，每个并行流式槽位各占一处，并避开
  既有节点与其它快照。普通新增节点也避开这些预留区。
- 快照复用正常生成页的 `SelectableImageCard`，实时显示相同的流式图像、局部重绘
  合成、进度及后处理状态；不是左下角的独立进度条。缩放、平移与适应内容都包含快照。
- 只有画布**正在打开**且「自动加入新结果」开启时，新完成的结果才落成节点。
- 完成图写入预留的原画布、原位置；文件节点首帧出来前保留最后快照，不重新播放
  节点入场动画。切换画布不改变本批次归属，删除原画布后不回写其它画布。
- 未开启自动加入时仍展示实时快照，但完成后不自动持久化。取消会移除未完成快照，
  导入失败保留带失败标记的临时结果，下一批生成开始时清除这些失败项。
- 画布关闭时仍记录已见结果 id，避免下次打开画布把历史图一次性倒进画布。
- 快照帧和预留信息只在内存中，不写入 sidecar、Hive 或云备份。

画布未打开时也可以通过结果卡片的「加入画布」动作与种子栏的固定按钮写入节点。

载入参数与 AI TAG 共用 `GenerationParameterSelection`：左侧字段图标、字段名称与
具体值，右侧勾选框；缺失项禁用，支持全选和清除。画布保留默认勾选可用字段及
正负提示词的独立选择，不改变 AI TAG 默认仅发送提示词、不替换配置的行为。

## 代码入口

| 职责 | 路径 |
|---|---|
| 文档模型与落点计算 | `lib/data/models/canvas/` |
| sidecar 读写 | `lib/data/services/canvas/canvas_document_store.dart` |
| 图片引用准备 | `lib/data/services/canvas/canvas_image_importer.dart` |
| 文档状态 | `lib/presentation/providers/canvas/canvas_document_controller.dart` |
| 视口状态与坐标换算 | `lib/presentation/providers/canvas/canvas_view_controller.dart` |
| 选中、模式、连线草稿、指针认领 | `lib/presentation/providers/canvas/canvas_interaction_provider.dart` |
| 视图与手势 | `lib/presentation/screens/generation/canvas/infinite_canvas_view.dart` |
| 节点调整尺寸与手柄布局几何 | `lib/presentation/screens/generation/canvas/canvas_node_geometry.dart` |
| 节点手柄呈现与手势入口 | `lib/presentation/screens/generation/canvas/widgets/canvas_node_handles.dart` |
| 临时生成快照与落点 | `lib/presentation/providers/canvas/canvas_generation_preview.dart` |
| 快照显示 | `lib/presentation/screens/generation/canvas/widgets/canvas_generation_preview_layer.dart` |
| 共用参数选择面板 | `lib/presentation/widgets/common/generation_parameter_selection.dart` |
| 画布操作（载入参数、固定种子、加入图片） | `lib/presentation/screens/generation/canvas/canvas_actions.dart` |
| 预览 ↔ 画布切换 | `lib/presentation/screens/generation/widgets/generation_center_workspace.dart` |

## 状态保持

视口、选中与文档都活在 widget 树之外（provider 持有的 `ChangeNotifier` 与
`AsyncNotifier`）。Windows 最小化会以零尺寸重建面板子树、断点切换会重建 Central
Workspace，两者都不会重置画布状态。关闭画布时画布子树用 `Offstage + TickerMode`
保留而不卸载，并暂停其 ticker。

## 已知取舍

- 画布当前不做视口外节点裁剪：节点数很多时平移的固定成本随节点数增长。画布定位为
  工作台，规模由用户整理习惯决定；如果实际使用中出现明显掉帧，再按可见矩形裁剪。
- 画布打开时中央区不再显示常规流式预览；生成过程中的预览由画布承载。
- 云同步适配器本版未接线，接线点见 [cloud_sync.md](cloud_sync.md)。
