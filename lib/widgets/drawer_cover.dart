import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../pages/splash/logo_painter.dart';
import '../theme/tokens.dart';

/// 侧边栏顶部的「封面」。
///
/// 与列表卡片同一套玻璃语言，但更强调品牌：深色星野 + 光晕 + 大 LOGO，
/// 左侧是英文小标与「与汝共奏」大字。
///
/// 三点设计约束：
/// * 不引任何位图：星点与光晕都是绘制出来的，跟着 [AppSurfaces] 的
///   界面配色一起变色（固定图片会和 6 套配色打架）。
/// * 静止零动画：只有抽屉滑入时整体位移，内部不做逐帧重绘。
/// * 窄抽屉优先：宽度不足时缩小 LOGO 与字号，而不是让它溢出。
class DrawerCover extends StatelessWidget {
  const DrawerCover({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320;
        final bool compact = width < 330;
        final double logo = compact ? 96 : 122;

        return SizedBox(
          height: compact ? 184 : 206,
          child: ClipRect(
            child: Stack(
              children: <Widget>[
                // 1. 深色画布：比正文再深一档，让卡片浮起来。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Color.lerp(
                            AppSurfaces.canvasDark,
                            Colors.white,
                            0.055,
                          )!,
                          AppSurfaces.canvasDark,
                          Color.lerp(
                            AppSurfaces.canvasDark,
                            Colors.black,
                            0.30,
                          )!,
                        ],
                        stops: const <double>[0, 0.58, 1],
                      ),
                    ),
                  ),
                ),
                // 2. 星野（确定性随机，静止不重建）。
                Positioned.fill(
                  child: CustomPaint(painter: const _StarfieldPainter()),
                ),
                // 3. 光晕：压在 LOGO 后面，颜色跟随强调色。
                Positioned(
                  right: -46,
                  top: -54,
                  child: IgnorePointer(
                    child: Container(
                      width: logo * 2.7,
                      height: logo * 2.7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: <Color>[
                            Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.20),
                            Colors.transparent,
                          ],
                          stops: const <double>[0, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                // 4. LOGO：复用启动页的 13 段路径，带一层模糊外发光。
                Positioned(
                  right: compact ? -2 : -6,
                  bottom: compact ? 22 : 28,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: logo,
                      height: logo,
                      child: CustomPaint(painter: const _GlowLogoPainter()),
                    ),
                  ),
                ),
                // 5. 文字。
                Positioned(
                  left: 20,
                  top: compact ? 30 : 36,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // 单行完整显示：先用 FittedBox 缩放兜底，窄抽屉也不会截字。
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'DUET NURTURING ALLY',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.50),
                            fontSize: 9.5,
                            letterSpacing: 1.9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'ULTRA',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 9.5,
                          letterSpacing: 4.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: compact ? 14 : 18),
                      Text(
                        '与汝共奏',
                        maxLines: 1,
                        style: TextStyle(
                          color: AppSurfaces.inkPrimary,
                          fontSize: compact ? 25 : 29,
                          height: 1.05,
                          letterSpacing: compact ? 5 : 7,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // 6. 下沿渐变，和导航列表自然衔接（不是一条生硬的边框）。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 46,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            AppSurfaces.canvasDark.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 星点：两层不同大小的点，确定性种子，绘制一次即可。
class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random random = math.Random(20261114);

    // 文字区（左侧 82%、纵向 8%–62%）不放星点：一颗亮点压在笔画上
    // 就会被读成脏点，而不是星空。
    final double bandRight = size.width * 0.82;
    final double bandTop = size.height * 0.08;
    final double bandBottom = size.height * 0.62;

    int placed = 0;
    int guard = 0;
    while (placed < 84 && guard < 400) {
      guard++;
      final double x = random.nextDouble() * size.width;
      final double y = random.nextDouble() * size.height * 0.92;
      final bool bright = placed % 7 == 0;
      final double radius = bright
          ? 0.9 + random.nextDouble() * 0.9
          : 0.35 + random.nextDouble() * 0.55;
      final double alpha = bright
          ? 0.24 + random.nextDouble() * 0.20
          : 0.09 + random.nextDouble() * 0.16;

      if (x < bandRight && y > bandTop && y < bandBottom) {
        continue;
      }
      placed++;

      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter oldDelegate) => false;
}

/// LOGO + 外发光。发光用同一路径画两遍：先模糊放大，再描清晰。
class _GlowLogoPainter extends CustomPainter {
  const _GlowLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final LogoPainter glow = LogoPainter(
      drawProgress: 1,
      fillProgress: 1,
      color: Colors.white,
    );

    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9)
        ..color = Colors.white.withValues(alpha: 0.55)
        ..blendMode = BlendMode.plus,
    );
    glow.paint(canvas, size);
    canvas.restore();

    glow.paint(canvas, size);
  }

  @override
  bool shouldRepaint(_GlowLogoPainter oldDelegate) => false;
}
