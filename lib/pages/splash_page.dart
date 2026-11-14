import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'splash/logo_painter.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _drawAnimation;
  late Animation<double> _fillAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  /// LOGO 下方的版本副标题。
  late Animation<double> _taglineInAnimation;
  late Animation<double> _taglineOutAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _drawAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.47, curve: Curves.easeOut),
      ),
    );

    _fillAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.375, 0.53, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 0.8), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 60), weight: 70),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.69, 1.0, curve: Curves.easeOut),
      ),
    );

    _opacityAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.69, 1.0, curve: Curves.easeOut),
      ),
    );

    _taglineInAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.42, 0.62, curve: Curves.easeOut),
      ),
    );

    _taglineOutAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        // 在 LOGO 开始"放大穿透"之前就退干净，避免文字叠在放大的图形上。
        curve: const Interval(0.55, 0.69, curve: Curves.easeIn),
      ),
    );

    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      body: SizedBox.expand(
        child: Stack(
          children: <Widget>[
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Opacity(
                        opacity: _opacityAnimation.value,
                        child: Transform.scale(
                          scale: _scaleAnimation.value,
                          child: SizedBox(
                            width: 120,
                            height: 120,
                            child: CustomPaint(
                              painter: LogoPainter(
                                drawProgress: _drawAnimation.value,
                                fillProgress: _fillAnimation.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Opacity(
                        opacity: _taglineInAnimation.value *
                            _taglineOutAnimation.value,
                        child: const Text(
                          'DNA ULTRA 1.0',
                          style: TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 13,
                            letterSpacing: 6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}