import 'dart:ui';

import 'package:flutter/material.dart';

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
      backgroundColor: const Color(0xFF1a1a1a),
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            return Opacity(
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
            );
          },
        ),
      ),
    );
  }
}

class LogoPainter extends CustomPainter {
  LogoPainter({
    required this.drawProgress,
    required this.fillProgress,
  });

  final double drawProgress;
  final double fillProgress;

  static const List<String> _svgPaths = [
    'M110.07,137.98c-1.75,1.59-3.57,3.14-5.21,4.88-.29.3-.42.04-.58-.12-1.89-1.94-3.55-4.06-4.97-6.38-1.7-2.78-2.94-5.75-3.73-8.91-.83-3.31-1.03-6.68-.77-10.05.31-3.92,1.47-7.63,3.34-11.09,1.17-2.16,2.6-4.15,4.16-6.06,1.33-1.62,2.74-3.17,4.24-4.63,2.63-2.56,5.24-5.13,7.93-7.62,2.08-1.92,4.02-3.96,5.62-6.3,2.11-3.07,3.67-6.39,4.37-10.1.5-2.69.51-5.4.36-8.1-.1-1.81,1.73-3.74,3.68-3.56,1.59.15,3.05,1.55,3.05,3.15,0,2.47.09,4.95-.06,7.42-.38,5.97-2.2,11.47-5.64,16.41-1.27,1.82-2.68,3.51-4.22,5.1-2.89,2.99-5.95,5.8-8.98,8.64-2.98,2.8-5.81,5.72-8,9.2-1.57,2.49-2.6,5.18-2.99,8.13-.12.92.01,1.84-.21,2.75-.07.27.15.45.41.5.16.03.34,0,.51,0,7.1,0,14.2,0,21.3.02.63,0,.79-.19.77-.79-.02-1.15-.1-2.29-.21-3.44-.05-.57-.27-.77-.88-.76-5.85.02-11.7.01-17.56,0-.34,0-.67,0-1.07,0,.48-1.37,1.3-2.47,1.97-3.65.17-.29.48-.19.74-.19,4.85,0,9.7,0,14.54-.01.91,0,.91,0,.53-.82-1.54-3.26-3.68-6.09-6.27-8.57-.37-.36-.35-.54.01-.88,1.58-1.46,3.14-2.94,4.7-4.42.25-.24.4-.3.69,0,5.01,5.05,8.52,10.93,9.51,18.06,1.12,8.05-.7,15.45-5.42,22.1-2.82,3.98-6.46,7.18-9.99,10.47-3.6,3.36-7.36,6.58-10.15,10.71-2.63,3.9-4.21,8.17-4.33,12.92-.04,1.61-.06,3.23,0,4.85.07,1.58-1.2,2.98-2.63,3.22-1.73.29-3.34-.58-3.9-2.12-.17-.46-.29-.93-.28-1.43.04-3.3-.14-6.61.42-9.88.56-3.26,1.52-6.39,3.02-9.34,2.01-3.98,4.78-7.4,7.99-10.46,3.11-2.97,6.34-5.81,9.42-8.8,3.35-3.24,6.27-6.81,7.91-11.26.08-.23.14-.47.21-.7.24-.79.16-.94-.63-.94-6-.01-12.01,0-18.01-.01-.6,0-1.19,0-1.79,0-.5,0-.73.13-.59.73.7,2.92,2.12,5.48,3.88,7.88.77,1.06,1.64,2.03,2.48,3.03.37.44.93.71,1.3,1.24Z',
    'M101.19,145.66c-2.41,2.3-4.5,4.71-6.15,7.51-1.95-1.61-3.77-3.33-5.64-4.99-3.85-3.41-7.63-6.9-11.37-10.43-2.99-2.82-5.9-5.71-8.63-8.79-2.71-3.05-5.23-6.24-7.41-9.69-2.94-4.65-5.2-9.57-5.83-15.1-.6-5.21.15-10.21,2.67-14.84,5.49-10.08,14.16-14.66,25.48-14.51,2.01.03,3.98.42,5.95.84.28.06.54.07.57.5.31,3.9,1.72,7.42,3.75,10.73.28.46.63.9.82,1.59-1.16-.8-2.2-1.53-3.34-2.12-5.13-2.64-10.46-3.27-15.85-1.04-5.99,2.48-9.6,7-10.53,13.51-.52,3.67.22,7.13,1.71,10.47,1.93,4.35,4.74,8.09,7.83,11.66,2.69,3.11,5.59,6.02,8.57,8.85,3.17,3,6.39,5.95,9.62,8.9,2.35,2.15,4.74,4.27,7.12,6.4.2.18.42.34.65.54Z',
    'M130.56,88.38c.51-.88.95-1.64,1.39-2.41,1.6-2.76,2.6-5.73,3.3-8.82.02-.09.06-.19.05-.28,0-.65.25-.9.95-1.09,2.65-.69,5.33-1.02,8.06-.97,3.6.07,7.03.92,10.32,2.36,3.46,1.52,6.46,3.7,9,6.49,3.25,3.56,5.34,7.74,6.21,12.48.48,2.6.49,5.23.22,7.88-.38,3.69-1.54,7.14-3.14,10.44-1.75,3.61-3.97,6.93-6.42,10.1-3.21,4.14-6.81,7.91-10.57,11.55-2.18,2.12-4.43,4.17-6.66,6.23-1.55,1.43-3.12,2.85-4.69,4.25-2.51,2.24-5.04,4.46-7.57,6.7-1.58-2.87-3.67-5.28-6.17-7.45,2.04-1.81,4.05-3.6,6.05-5.39.99-.89,1.99-1.77,2.97-2.67,2.66-2.45,5.36-4.88,8-7.36,2.62-2.46,5.2-4.97,7.64-7.6,2.63-2.83,5.08-5.84,7.12-9.15,1.85-2.99,3.35-6.16,3.93-9.65.72-4.36.06-8.5-2.46-12.24-2.87-4.26-6.9-6.68-11.93-7.54-4.75-.81-9.09.38-13.18,2.73-.77.44-1.54.89-2.42,1.4Z',
    'M94.48,66.04c.03-.65-.11-1.93.08-3.19.22-1.44,1.36-2.55,2.88-2.84,1.37-.26,2.74.38,3.48,1.63.51.86.37,1.8.32,2.72-.27,5,.37,9.85,2.49,14.43,1.02,2.2,2.43,4.16,4.03,5.98.61.7,1.21,1.41,1.91,2.02.28.25.38.43.04.75-1.62,1.53-3.21,3.08-4.8,4.63-.25.24-.42.25-.66,0-2.71-2.83-5.06-5.93-6.75-9.48-1.68-3.52-2.69-7.21-2.9-11.11-.09-1.64-.13-3.27-.12-5.53Z',
    'M131.53,172.6c0,1.65-.02,2.97,0,4.29.03,1.37-1.39,3.04-2.88,3.16-2.29.19-3.77-1.13-3.77-3.44,0-1.54.05-3.09,0-4.63-.18-4.86-1.55-9.31-4.55-13.21-1.33-1.72-2.63-3.47-4.24-4.95-.35-.32-.3-.51.02-.8,1.63-1.46,3.34-2.82,4.85-4.4.33-.34.54-.16.78.1,1.4,1.56,2.85,3.08,4.1,4.77,1.96,2.66,3.4,5.57,4.41,8.7.59,1.85.93,3.75,1.16,5.68.2,1.68.04,3.36.12,4.72Z',
    'M113.1,66.09c2.84,0,5.68.02,8.51-.01.56,0,.7.16.67.7-.05.8-.05,1.6-.02,2.4.03.72-.24.92-.96.91-3.62-.04-7.24-.02-10.86-.02-1.98,0-3.96-.01-5.94.01-.5,0-.68-.12-.65-.64.04-.9.04-1.81,0-2.71-.02-.49.13-.61.61-.61,2.89.02,5.77,0,8.66,0,0-.01,0-.02,0-.03Z',
    'M113.05,173.89c-2.84,0-5.68,0-8.51,0-.46,0-.71-.1-.64-.61.13-.97.07-1.95.06-2.93,0-.37.1-.51.49-.5,3.32.07,6.65-.02,9.98.06,2.41.06,4.83-.02,7.24-.05.45,0,.65.07.61.58-.07.95-.1,1.9-.07,2.85.02.54-.22.57-.65.57-2.84-.01-5.68,0-8.51,0v.02Z',
    'M120.96,165.07c-2.93-.12-5.77-.03-8.62-.08-2.11-.03-4.23,0-6.35.07-.5.02-.8.07-.39-.61.58-.97,1.26-1.87,1.82-2.85.2-.35.5-.45.95-.43,1.11.04,2.22-.13,3.33-.07,1.8.1,3.61-.18,5.41.1.05,0,.1.02.15,0,1.28-.54,1.71.39,2.24,1.25.52.83,1,1.67,1.46,2.63Z',
    'M105.07,75.12h15.42c-.61,1.26-1.43,2.33-2.18,3.45-.17.26-.39.25-.63.25-2.4,0-4.79.05-7.19-.04-1.05-.04-2.09-.05-3.14-.09-.2,0-.41.06-.56-.21-.61-1.09-1.2-2.18-1.73-3.36Z',
    'M119.12,130.04c-.94,1.24-1.81,2.35-2.63,3.49-.19.26-.38.24-.62.24-2.1,0-4.2-.01-6.3-.02-.24,0-.5.06-.68-.18-.86-1.1-1.74-2.2-2.41-3.54h12.64Z',
    'M117.48,107.72c-2.27.31-4.43.12-6.59.17-.13,0-.31.07-.37-.12-.02-.07.05-.18.11-.24.94-.92,1.81-1.91,2.83-2.75.39-.32.6-.33,1.05.05,1.02.87,1.92,1.85,2.96,2.89Z',
    'M114.65,82.75c-.57,1.06-1.59,1.56-2.28,2.37-.64-.63-1.27-1.25-1.89-1.86-.11-.11-.33-.19-.25-.4.08-.21.3-.11.45-.11,1.29,0,2.58,0,3.97,0Z',
    'M113.52,155.48c.4.31.93.72,1.46,1.14-.04.06-.09.11-.13.17h-2.82c.52-.46,1.06-.93,1.48-1.31Z',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 228;

    for (final String svgPath in _svgPaths) {
      final Path path = parseSvgPath(svgPath, scale);

      final Paint strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final Paint fillPaint = Paint()
        ..color = Color.lerp(
          Colors.transparent,
          Colors.white,
          fillProgress,
        )!
        ..style = PaintingStyle.fill;

      if (drawProgress < 1) {
        final PathMetrics metrics = path.computeMetrics();
        final Path extractedPath = Path();
        for (final PathMetric metric in metrics) {
          extractedPath.addPath(
            metric.extractPath(0, metric.length * drawProgress),
            Offset.zero,
          );
        }
        canvas.drawPath(extractedPath, strokePaint);
      } else {
        canvas.drawPath(path, fillPaint);
      }
    }
  }

  Path parseSvgPath(String svgPath, double scale) {
    final Path path = Path();
    final List<String> commands = _parseCommands(svgPath);

    double currentX = 0;
    double currentY = 0;
    double startX = 0;
    double startY = 0;

    for (final String command in commands) {
      final String type = command[0];
      final List<double> args = _parseNumbers(command.substring(1));

      switch (type) {
        case 'M':
          currentX = args[0] * scale;
          currentY = args[1] * scale;
          startX = currentX;
          startY = currentY;
          path.moveTo(currentX, currentY);
          break;
        case 'm':
          currentX += args[0] * scale;
          currentY += args[1] * scale;
          startX = currentX;
          startY = currentY;
          path.moveTo(currentX, currentY);
          break;
        case 'L':
          for (int i = 0; i < args.length; i += 2) {
            currentX = args[i] * scale;
            currentY = args[i + 1] * scale;
            path.lineTo(currentX, currentY);
          }
          break;
        case 'l':
          for (int i = 0; i < args.length; i += 2) {
            currentX += args[i] * scale;
            currentY += args[i + 1] * scale;
            path.lineTo(currentX, currentY);
          }
          break;
        case 'H':
          currentX = args[0] * scale;
          path.lineTo(currentX, currentY);
          break;
        case 'h':
          currentX += args[0] * scale;
          path.lineTo(currentX, currentY);
          break;
        case 'V':
          currentY = args[0] * scale;
          path.lineTo(currentX, currentY);
          break;
        case 'v':
          currentY += args[0] * scale;
          path.lineTo(currentX, currentY);
          break;
        case 'C':
          for (int i = 0; i < args.length; i += 6) {
            path.cubicTo(
              args[i] * scale,
              args[i + 1] * scale,
              args[i + 2] * scale,
              args[i + 3] * scale,
              args[i + 4] * scale,
              args[i + 5] * scale,
            );
            currentX = args[i + 4] * scale;
            currentY = args[i + 5] * scale;
          }
          break;
        case 'c':
          for (int i = 0; i < args.length; i += 6) {
            path.cubicTo(
              currentX + args[i] * scale,
              currentY + args[i + 1] * scale,
              currentX + args[i + 2] * scale,
              currentY + args[i + 3] * scale,
              currentX + args[i + 4] * scale,
              currentY + args[i + 5] * scale,
            );
            currentX += args[i + 4] * scale;
            currentY += args[i + 5] * scale;
          }
          break;
        case 'S':
          for (int i = 0; i < args.length; i += 4) {
            path.cubicTo(
              currentX,
              currentY,
              args[i] * scale,
              args[i + 1] * scale,
              args[i + 2] * scale,
              args[i + 3] * scale,
            );
            currentX = args[i + 2] * scale;
            currentY = args[i + 3] * scale;
          }
          break;
        case 's':
          for (int i = 0; i < args.length; i += 4) {
            path.cubicTo(
              currentX,
              currentY,
              currentX + args[i] * scale,
              currentY + args[i + 1] * scale,
              currentX + args[i + 2] * scale,
              currentY + args[i + 3] * scale,
            );
            currentX += args[i + 2] * scale;
            currentY += args[i + 3] * scale;
          }
          break;
        case 'Q':
          for (int i = 0; i < args.length; i += 4) {
            path.quadraticBezierTo(
              args[i] * scale,
              args[i + 1] * scale,
              args[i + 2] * scale,
              args[i + 3] * scale,
            );
            currentX = args[i + 2] * scale;
            currentY = args[i + 3] * scale;
          }
          break;
        case 'q':
          for (int i = 0; i < args.length; i += 4) {
            path.quadraticBezierTo(
              currentX + args[i] * scale,
              currentY + args[i + 1] * scale,
              currentX + args[i + 2] * scale,
              currentY + args[i + 3] * scale,
            );
            currentX += args[i + 2] * scale;
            currentY += args[i + 3] * scale;
          }
          break;
        case 'Z':
        case 'z':
          path.close();
          currentX = startX;
          currentY = startY;
          break;
      }
    }

    return path;
  }

  List<String> _parseCommands(String svgPath) {
    final List<String> commands = <String>[];
    final RegExp regExp = RegExp(r'([MmZzLlHhVvCcSsQqTtAa])([^MmZzLlHhVvCcSsQqTtAa]*)');
    final Iterable<RegExpMatch> matches = regExp.allMatches(svgPath);

    for (final RegExpMatch match in matches) {
      commands.add('${match.group(1)}${match.group(2)}');
    }

    return commands;
  }

  List<double> _parseNumbers(String str) {
    final List<double> numbers = <double>[];
    final RegExp regExp = RegExp(r'-?\d*\.?\d+(?:[eE][+-]?\d+)?');
    final Iterable<RegExpMatch> matches = regExp.allMatches(str);

    for (final RegExpMatch match in matches) {
      numbers.add(double.parse(match.group(0)!));
    }

    return numbers;
  }

  @override
  bool shouldRepaint(LogoPainter oldDelegate) {
    return drawProgress != oldDelegate.drawProgress ||
        fillProgress != oldDelegate.fillProgress;
  }
}
