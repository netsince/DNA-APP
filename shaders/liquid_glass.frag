#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// 液态玻璃（Paint.shader 版）。
// 光学模型参考公开实现：圆角 SDF 求离边距离 → 圆弧截面 (band/circle) 决定折射位移，
// 边缘沿法线方向做七通道色散采样，再用三圈高斯（outline/bloom/caustic）加双向
// Fresnel 出水光。所有量都是本地逻辑像素，采样坐标已换算到背景纹理空间。

uniform vec2 uSize;        // 玻璃自身尺寸（逻辑像素）
uniform vec2 uTexSize;     // 背景纹理尺寸（含 pixelRatio）
uniform vec2 uOrigin;      // 玻璃左上角在纹理中的位置
uniform float uScale;      // 逻辑像素 -> 纹理像素的比例
uniform float uRadius;     // 圆角半径
uniform float uBevel;      // 斜面高度（决定折射环宽度）
uniform float uAmount;     // 折射强度（位移像素）
uniform float uDispersion; // 色散强度
uniform float uSpecular;   // 边缘光强度
uniform float uTintAlpha;  // 染色强度
uniform float uDark;       // 0 浅色 / 1 深色
uniform float uSampleMaxY; // 采样 y 上限（纹理像素）：避免采到玻璃自身
uniform vec4 uTint;        // 染色
uniform sampler2D uScene;

out vec4 fragColor;

float sdRoundRect(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

vec2 normalAt(vec2 p, vec2 halfSize, float r) {
  const float e = 0.75;
  vec2 n = vec2(
    sdRoundRect(p + vec2(e, 0.0), halfSize, r) - sdRoundRect(p - vec2(e, 0.0), halfSize, r),
    sdRoundRect(p + vec2(0.0, e), halfSize, r) - sdRoundRect(p - vec2(0.0, e), halfSize, r)
  );
  float len = length(n);
  return len > 0.00001 ? n / len : vec2(0.0, -1.0);
}

vec3 scene(vec2 local) {
  // 纹理空间：原点 + 本地坐标 * 比例；y 方向与 Flutter 一致（向下为正）
  vec2 t = (uOrigin + local * uScale);
  float maxY = min(uSampleMaxY, uTexSize.y - 1.0);
  t.y = clamp(t.y, 0.0, maxY);
  vec2 uv = t / uTexSize;
  return texture(uScene, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
}

// outline / bloom / caustic 三圈高斯 + 双向 Fresnel
float surfaceLight(float d, vec2 n, float strength) {
  vec2 lightDir = normalize(vec2(-0.65, -1.0));
  float a = pow(max(dot(n, lightDir), 0.0), 7.0);
  float b = pow(max(dot(n, -lightDir), 0.0), 7.0) * 0.52;
  float edge = clamp(1.0 + d / 8.0, 0.0, 1.0);
  float slope = pow(edge, 1.65) * 0.94;
  float nz = sqrt(max(1.0 - slope * slope, 0.001));
  float fresnel = 0.04 + 0.96 * pow(1.0 - nz, 5.0);
  float outline = exp(-pow((d + 0.7) / 0.65, 2.0));
  float bloom = exp(-pow((d + 1.4) / 2.0, 2.0));
  float caustic = exp(-pow((d + 3.0) / 1.65, 2.0));
  return (outline * (0.04 + a * 0.62 + b * 0.32)
        + bloom * (a + b) * 0.12
        + caustic * b * 0.07
        + fresnel * 0.045) * strength;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 halfSize = uSize * 0.5;
  vec2 q = p - halfSize;

  float d = sdRoundRect(q, halfSize, uRadius);
  float cover = 1.0 - smoothstep(-0.7, 0.7, d);
  if (cover <= 0.002) {
    fragColor = vec4(0.0);
    return;
  }

  // 圆弧截面：离边越近 band 越小，circle 从 0 长到 1
  float band = clamp(1.0 + d / max(uBevel, 0.001), 0.0, 1.0);
  float circle = 1.0 - sqrt(max(0.0, 1.0 - band * band));

  vec2 n = normalAt(q, halfSize, uRadius);
  vec2 radial = length(q) > 0.0001 ? q / length(q) : vec2(0.0);
  vec2 rn = n + radial * 0.6;
  rn /= max(length(rn), 0.0001);

  // 负位移：把后景「吸进」斜面（与参考实现一致）
  vec2 offset = -rn * circle * uAmount;

  // 七通道色散：偏移量按象限放大，沿 ±split 各采一次
  float disp = uDispersion * (q.x * q.y) / max(halfSize.x * halfSize.y, 1.0);
  vec2 split = offset * disp;

  vec3 sR = scene(p + offset + split);
  vec3 sO = scene(p + offset + split * (2.0 / 3.0));
  vec3 sY = scene(p + offset + split * (1.0 / 3.0));
  vec3 sG = scene(p + offset);
  vec3 sC = scene(p + offset - split * (1.0 / 3.0));
  vec3 sB = scene(p + offset - split * (2.0 / 3.0));
  vec3 sV = scene(p + offset - split);

  vec3 col = vec3(
    (sR.r + sO.r + sY.r) / 3.5 + sV.r / 7.0,
    sO.g / 7.0 + (sY.g + sG.g + sC.g) / 3.5,
    (sC.b + sB.b + sV.b) / 3.0
  );

  // 染色：深色主题压暗，浅色主题提亮
  vec3 tinted = mix(col, uTint.rgb, uTintAlpha);
  col = mix(col, tinted, 0.85);
  float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = mix(vec3(luma), col, 1.08);

  // 厚度：中部略暗一点点，边缘靠高光提起来
  col *= 1.0 - 0.06 * (1.0 - band) * (1.0 - uDark);

  col += surfaceLight(d, n, uSpecular);

  fragColor = vec4(clamp(col, 0.0, 1.0), cover);
}
