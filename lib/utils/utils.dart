import 'dart:math';
import 'dart:ui' as ui;

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:canvas_danmaku/models/danmaku_option.dart';
import 'package:flutter/material.dart';

abstract final class DmUtils {
  static const maxRasterizeSize = 8192.0;

  static double devicePixelRatio = 1;
  static DanmakuStrokeType strokeType = DanmakuStrokeType.stroke;
  static double shadowOffset = 1.5;
  static double shadowOpacity = 0.5;
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.green;

  static void updateSelfSendPaint(double strokeWidth) {
    _selfSendPaint.strokeWidth = strokeWidth;
  }

  static ui.Paragraph generateParagraph({
    required DanmakuContentItem content,
    required double fontSize,
    required int fontWeight,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
      maxLines: 1,
    ));

    if (content.count case final count?) {
      builder
        ..pushStyle(ui.TextStyle(
          color: content.color,
          fontSize: fontSize * 0.6,
        ))
        ..addText('($count)')
        ..pop();
    }

    builder
      ..pushStyle(ui.TextStyle(color: content.color, fontSize: fontSize))
      ..addText(content.text);

    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  static ui.Image recordDanmakuImage({
    required ui.Paragraph contentParagraph,
    required DanmakuContentItem content,
    required double fontSize,
    required int fontWeight,
    required double strokeWidth,
  }) {
    final textWidth = contentParagraph.maxIntrinsicWidth;
    final textHeight = contentParagraph.height;

    final double extraW, extraH;
    final Offset textOffset;

    switch (strokeType) {
      case DanmakuStrokeType.none:
        extraW = 0;
        extraH = 0;
        textOffset = Offset.zero;
      case DanmakuStrokeType.stroke:
        extraW = strokeWidth;
        extraH = strokeWidth;
        textOffset = Offset(
          (strokeWidth / 2.0) + (content.selfSend ? 2.0 : 0.0),
          strokeWidth / 2.0,
        );
      case DanmakuStrokeType.heavy:
        extraW = strokeWidth * 2;
        extraH = strokeWidth * 2;
        textOffset = Offset(
          strokeWidth + (content.selfSend ? 2.0 : 0.0),
          strokeWidth,
        );
      case DanmakuStrokeType.shadow:
        extraW = shadowOffset;
        extraH = shadowOffset;
        textOffset = Offset.zero;
    }

    double w = textWidth + extraW;
    double h = textHeight + extraH;

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    if (devicePixelRatio != 1) {
      canvas.scale(devicePixelRatio);
    }

    switch (strokeType) {
      case DanmakuStrokeType.none:
        canvas.drawParagraph(contentParagraph, textOffset);
      case DanmakuStrokeType.stroke:
        _drawStrokeParagraph(canvas, content, fontSize, fontWeight,
            strokeWidth, w, h, textOffset);
        canvas.drawParagraph(contentParagraph, textOffset);
      case DanmakuStrokeType.heavy:
        _drawHeavyStroke(canvas, content, fontSize, fontWeight,
            strokeWidth, w, h, textOffset);
        canvas.drawParagraph(contentParagraph, textOffset);
      case DanmakuStrokeType.shadow:
        _drawShadowParagraph(canvas, content, fontSize, fontWeight,
            textOffset);
        canvas.drawParagraph(contentParagraph, textOffset);
    }

    if (content.selfSend) {
      w += 4;
      canvas.drawRect(Rect.fromLTRB(0, 0, w, h), _selfSendPaint);
    }

    final pic = rec.endRecording();
    final img = pic.toImageSync(
      (w * devicePixelRatio).ceil(),
      (h * devicePixelRatio).ceil(),
    );
    pic.dispose();
    return img;
  }

  static void _drawStrokeParagraph(
    ui.Canvas canvas,
    DanmakuContentItem content,
    double fontSize,
    int fontWeight,
    double strokeWidth,
    double w,
    double h,
    Offset offset,
  ) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
      maxLines: 1,
    ));
    final Paint strokePaint = Paint()
      ..shader = content.isColorful
          ? const LinearGradient(
                  colors: [Color(0xFFF2509E), Color(0xFF308BCD)])
              .createShader(Rect.fromLTWH(0, 0, w, h))
          : null
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (!content.isColorful) {
      strokePaint.color = Colors.black;
    }

    if (content.count case final count?) {
      builder
        ..pushStyle(ui.TextStyle(
          fontSize: fontSize * 0.6,
          foreground: strokePaint,
        ))
        ..addText('($count)')
        ..pop();
    }

    builder
      ..pushStyle(ui.TextStyle(fontSize: fontSize, foreground: strokePaint))
      ..addText(content.text);

    final strokeParagraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    canvas.drawParagraph(strokeParagraph, offset);
    strokeParagraph.dispose();
  }

  static void _drawHeavyStroke(
    ui.Canvas canvas,
    DanmakuContentItem content,
    double fontSize,
    int fontWeight,
    double strokeWidth,
    double w,
    double h,
    Offset offset,
  ) {
    // 8方向多层偏移叠加，产生B站风格"重墨"效果
    final offsets = [
      const Offset(-0.7, -0.7),
      const Offset(0, -0.7),
      const Offset(0.7, -0.7),
      const Offset(-0.7, 0),
      const Offset(0.7, 0),
      const Offset(-0.7, 0.7),
      const Offset(0, 0.7),
      const Offset(0.7, 0.7),
    ];
    final baseStroke = _buildStrokeParagraph(
      content, fontSize, fontWeight, strokeWidth, w, h,
    );
    for (final d in offsets) {
      canvas.drawParagraph(baseStroke, offset + d);
    }
    baseStroke.dispose();
  }

  static ui.Paragraph _buildStrokeParagraph(
    DanmakuContentItem content,
    double fontSize,
    int fontWeight,
    double strokeWidth,
    double w,
    double h,
  ) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
      maxLines: 1,
    ));
    final Paint strokePaint = Paint()
      ..shader = content.isColorful
          ? const LinearGradient(
                  colors: [Color(0xFFF2509E), Color(0xFF308BCD)])
              .createShader(Rect.fromLTWH(0, 0, w, h))
          : null
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (!content.isColorful) {
      strokePaint.color = Colors.black;
    }

    if (content.count case final count?) {
      builder
        ..pushStyle(ui.TextStyle(
          fontSize: fontSize * 0.6,
          foreground: strokePaint,
        ))
        ..addText('($count)')
        ..pop();
    }

    builder
      ..pushStyle(ui.TextStyle(fontSize: fontSize, foreground: strokePaint))
      ..addText(content.text);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    return paragraph;
  }

  static void _drawShadowParagraph(
    ui.Canvas canvas,
    DanmakuContentItem content,
    double fontSize,
    int fontWeight,
    Offset textOffset,
  ) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
      maxLines: 1,
    ));

    if (content.count case final count?) {
      builder
        ..pushStyle(ui.TextStyle(
          color: Colors.black.withValues(alpha: shadowOpacity),
          fontSize: fontSize * 0.6,
        ))
        ..addText('($count)')
        ..pop();
    }

    builder
      ..pushStyle(ui.TextStyle(
        color: Colors.black.withValues(alpha: shadowOpacity),
        fontSize: fontSize,
      ))
      ..addText(content.text);

    final shadowParagraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    // 在右下45°偏移位置画半透明投影
    canvas.drawParagraph(shadowParagraph, textOffset + Offset(shadowOffset, shadowOffset));
    shadowParagraph.dispose();
  }

  static ui.Image recordSpecialDanmakuImg({
    required SpecialDanmakuContentItem content,
    required int fontWeight,
    required double strokeWidth,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
      fontSize: content.fontSize,
    ))
      ..pushStyle(ui.TextStyle(
        color: content.color,
        fontSize: content.fontSize,
        shadows: content.hasStroke
            ? [Shadow(color: Colors.black, blurRadius: strokeWidth)]
            : null,
      ))
      ..addText(content.text);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    final strokeOffset = strokeWidth / 2;
    final totalWidth = paragraph.maxIntrinsicWidth + strokeWidth;
    final totalHeight = paragraph.height + strokeWidth;

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);

    Rect rect;

    if (content.rotateZ != 0 || content.matrix != null) {
      rect = _calculateRotatedBounds(
        totalWidth,
        totalHeight,
        content.rotateZ,
        content.matrix,
      );

      if (devicePixelRatio != 1) {
        canvas.scale(devicePixelRatio);
      }
      canvas.translate(strokeOffset - rect.left, strokeOffset - rect.top);

      if (content.matrix case final matrix?) {
        canvas.transform(matrix.storage);
      } else {
        canvas.rotate(content.rotateZ);
      }
      canvas.drawParagraph(paragraph, Offset.zero);
    } else {
      rect = Rect.fromLTRB(0, 0, totalWidth, totalHeight);

      if (devicePixelRatio != 1) {
        canvas.scale(devicePixelRatio);
      }
      canvas.drawParagraph(paragraph, Offset(strokeOffset, strokeOffset));
    }
    paragraph.dispose();

    double width = rect.width * devicePixelRatio;
    double height = rect.height * devicePixelRatio;
    if (width > maxRasterizeSize || height > maxRasterizeSize) {
      final scaledMaxSize = maxRasterizeSize / devicePixelRatio;
      final left = rect.left;
      final top = rect.top;
      double right = rect.right;
      double bottom = rect.bottom;

      if (width > maxRasterizeSize) {
        right = left + scaledMaxSize;
        width = maxRasterizeSize;
      }

      if (height > maxRasterizeSize) {
        bottom = top + scaledMaxSize;
        height = maxRasterizeSize;
      }

      rect = Rect.fromLTRB(left, top, right, bottom);
    }

    content.rect = rect;

    final pic = rec.endRecording();
    final img = pic.toImageSync(width.ceil(), height.ceil());
    pic.dispose();

    return img;
  }

  static Rect _calculateRotatedBounds(
    double w,
    double h,
    double rotateZ,
    Matrix4? matrix,
  ) {
    final double cosZ;
    final double cosY;
    final double sinZ;
    if (matrix == null) {
      cosZ = cos(rotateZ);
      sinZ = sin(rotateZ);
      cosY = 1;
    } else {
      cosZ = matrix[5];
      sinZ = matrix[1];
      cosY = matrix[10];
    }

    final wx = w * cosZ * cosY;
    final wy = w * sinZ;
    final hx = -h * sinZ * cosY;
    final hy = h * cosZ;

    final minX = _min4(0.0, wx, hx, wx + hx);
    final maxX = _max4(0.0, wx, hx, wx + hx);
    final minY = _min4(0.0, wy, hy, wy + hy);
    final maxY = _max4(0.0, wy, hy, wy + hy);

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @pragma("vm:prefer-inline")
  static double _min4(double a, double b, double c, double d) {
    final ab = a < b ? a : b;
    final cd = c < d ? c : d;
    return ab < cd ? ab : cd;
  }

  @pragma("vm:prefer-inline")
  static double _max4(double a, double b, double c, double d) {
    final ab = a > b ? a : b;
    final cd = c > d ? c : d;
    return ab > cd ? ab : cd;
  }
}
