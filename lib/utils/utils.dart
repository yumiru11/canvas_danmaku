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

  /// 根据文字颜色亮度计算阴影颜色（B站 outlineColor 还原）
  static Color _computeShadowColor(Color textColor) {
    final brightness = 0.299 * textColor.r + 0.587 * textColor.g + 0.114 * textColor.b;
    return brightness > 0.5 ? Colors.black : const Color(0xFF808080);
  }

  /// 根据描边类型构建阴影列表（B站 getShadow 函数还原）
  static List<Shadow> _buildShadows(
    DanmakuStrokeType type,
    Color shadowColor,
    double strokeWidth,
    double shadowOffset,
    double shadowOpacity,
  ) {
    // 以 strokeWidth=1.5 为基准缩放 B站默认效果
    final scale = strokeWidth / 1.5;

    switch (type) {
      case DanmakuStrokeType.heavy:
        // B站 fontBorder=0：四方向各偏移1px，模糊1px
        return [
          Shadow(offset: Offset(scale, 0), blurRadius: scale, color: shadowColor),
          Shadow(offset: Offset(0, scale), blurRadius: scale, color: shadowColor),
          Shadow(offset: Offset(0, -scale), blurRadius: scale, color: shadowColor),
          Shadow(offset: Offset(-scale, 0), blurRadius: scale, color: shadowColor),
        ];

      case DanmakuStrokeType.stroke:
        // B站 fontBorder=1：零偏移三层相同模糊叠加
        return [
          Shadow(offset: Offset.zero, blurRadius: scale, color: shadowColor),
          Shadow(offset: Offset.zero, blurRadius: scale, color: shadowColor),
          Shadow(offset: Offset.zero, blurRadius: scale, color: shadowColor),
        ];

      case DanmakuStrokeType.shadow:
        // B站 fontBorder=2：偏移投影(2px模糊) + 基础描边(1px模糊)
        return [
          Shadow(
            offset: Offset(shadowOffset, shadowOffset),
            blurRadius: 2 * scale,
            color: Colors.black.withValues(alpha: shadowOpacity),
          ),
          Shadow(offset: Offset.zero, blurRadius: scale, color: shadowColor),
        ];

      case DanmakuStrokeType.none:
        return [];
    }
  }

  /// 计算阴影所需的额外边距，防止 shadow 被裁剪
  static double calcPadding(
    DanmakuStrokeType type,
    double strokeWidth,
    double shadowOffset,
  ) => switch (type) {
    DanmakuStrokeType.none => 0,
    DanmakuStrokeType.stroke => strokeWidth * 2,
    DanmakuStrokeType.heavy => strokeWidth * 3,
    DanmakuStrokeType.shadow => (shadowOffset + strokeWidth * 3).clamp(strokeWidth * 2, 20),
  };

  /// 构建带阴影的 Paragraph（替代旧的 stroke+fill 两层）
  static ui.Paragraph _buildParagraphWithShadows({
    required DanmakuContentItem content,
    required double fontSize,
    required int fontWeight,
    required List<Shadow> shadows,
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
          shadows: shadows,
        ))
        ..addText('($count)')
        ..pop();
    }

    builder
      ..pushStyle(ui.TextStyle(
        color: content.color,
        fontSize: fontSize,
        shadows: shadows,
      ))
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
    final bool useShadow = strokeWidth > 0 && strokeType != DanmakuStrokeType.none;

    final ui.Paragraph renderParagraph;
    final bool shouldDispose;
    final double padding;

    if (useShadow) {
      final shadowColor = _computeShadowColor(content.color);
      final shadows = _buildShadows(
        strokeType, shadowColor, strokeWidth, shadowOffset, shadowOpacity,
      );
      renderParagraph = _buildParagraphWithShadows(
        content: content,
        fontSize: fontSize,
        fontWeight: fontWeight,
        shadows: shadows,
      );
      shouldDispose = true;
      padding = calcPadding(strokeType, strokeWidth, shadowOffset);
    } else {
      renderParagraph = contentParagraph;
      shouldDispose = false;
      padding = 0;
    }

    final double w = renderParagraph.maxIntrinsicWidth + padding * 2;
    final double h = renderParagraph.height + padding * 2;

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    if (devicePixelRatio != 1) {
      canvas.scale(devicePixelRatio);
    }

    canvas.drawParagraph(renderParagraph, Offset(padding, padding));

    if (content.selfSend) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, w + 4, h),
        _selfSendPaint..strokeWidth = strokeWidth,
      );
    }

    final pic = rec.endRecording();
    final img = pic.toImageSync(
      (w * devicePixelRatio).ceil(),
      (h * devicePixelRatio).ceil(),
    );
    pic.dispose();

    if (shouldDispose) {
      renderParagraph.dispose();
    }

    return img;
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
