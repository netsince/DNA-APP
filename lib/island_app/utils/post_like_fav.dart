import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/utils/auth_guard.dart';

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
  Future<void> togglePostLike(int postId) => _run(
        postId,
        () => ApiClient.instance.toggleTeahouseLike(postId),
        onPostLikeResult,
      );

  /// 切换收藏（已登录则调用，未登录弹「去登录」引导）。
  Future<void> togglePostFavorite(int postId) => _run(
        postId,
        () => ApiClient.instance.toggleTeahouseFavorite(postId),
        (id, r) => onPostFavoriteResult(id, r.favorited),
      );

  Future<void> _run<R>(
    int postId,
    Future<R> Function() call,
    void Function(int postId, R result) apply,
  ) async {
    await AuthGuard.run(context, () async {
      try {
        final r = await call();
        if (!mounted) return;
        apply(postId, r);
      } catch (_) {
        _postSnack('操作失败，请重试');
      }
    });
  }

  void _postSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
