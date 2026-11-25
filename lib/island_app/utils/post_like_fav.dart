import 'package:material_ui/material_ui.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/utils/auth_guard.dart';
import 'package:dna/utils/error_display.dart';

/// 茶馆帖子点赞/收藏统一逻辑（对齐审计 P2：抽掉 5~6 处重复的
/// 「登录守卫 + API 调用 + SnackBar」）。
///
/// 使用：`class X extends State<...> with PostLikeFavMixin`，并实现
/// [onPostLikeResult] / [onPostFavoriteResult] 把结果应用到本地状态。
mixin PostLikeFavMixin<T extends StatefulWidget> on State<T> {
  /// 点赞结果应用到本地（如更新帖子 stats）。
  void onPostLikeResult(int postId, ({bool liked, int count}) result);

  /// 收藏结果应用到本地。
  void onPostFavoriteResult(int postId, bool favorited);

  /// 切换点赞（已登录则调用，未登录弹「去登录」引导）。
  /// 未登录提示语（可覆盖，保持各页原文案）。
  String get likeLoginHint => '请先登录后再点赞';
  String get favoriteLoginHint => '请先登录后再收藏';

  /// 收藏成功后是否提示（原来只有茶馆这几处提示，默认保持）。
  bool get announceFavoriteChange => true;

  Future<void> togglePostLike(int postId) => _run(
    postId,
    () => ApiClient.instance.toggleTeahouseLike(postId),
    onPostLikeResult,
    message: likeLoginHint,
  );

  /// 切换收藏（已登录则调用，未登录弹「去登录」引导）。
  Future<void> togglePostFavorite(int postId) => _run(
    postId,
    () => ApiClient.instance.toggleTeahouseFavorite(postId),
    (id, r) {
      onPostFavoriteResult(id, r.favorited);
      if (announceFavoriteChange) {
        _postSnack(r.favorited ? '已收藏' : '已取消收藏');
      }
    },
    message: favoriteLoginHint,
  );

  Future<void> _run<R>(
    int postId,
    Future<R> Function() call,
    void Function(int postId, R result) apply, {
    required String message,
  }) async {
    await AuthGuard.run(context, message: message, () async {
      try {
        final r = await call();
        if (!mounted) return;
        apply(postId, r);
      } catch (e) {
        _postSnack('操作失败：${describeError(e)}');
      }
    });
  }

  void _postSnack(String msg) {
    if (!mounted) return;
    showSnack(context, msg);
  }
}
