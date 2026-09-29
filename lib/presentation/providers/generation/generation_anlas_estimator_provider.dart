import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent_chat/services/generation_anlas_estimator.dart';

/// Anlas 预估器。
///
/// 预估需要读订阅状态（Opus 档位与免费额度是否用尽），而预估器本身要求一个
/// [Ref]；界面侧只有 `WidgetRef`，所以在这里统一构造一次复用。
final generationAnlasEstimatorProvider = Provider<GenerationAnlasEstimator>(
  (ref) => GenerationAnlasEstimator(ref),
);
