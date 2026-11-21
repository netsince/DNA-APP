#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// 液态玻璃 logo 开场动画（单 pass 移植）。
//
// 来源：reactdrops 的 liquid-glass-logo（MIT）。原实现是 three.js + 两段 GLSL：
// 主渲染写进离屏纹理，再用 mipmap 做 bloom 合成。Flutter 这边：
// * 没有多渲染目标/离屏纹理链，所以只保留主 pass，bloom 用「logo 的多点低频
//   采样 + 边缘光」近似（见文件末 main 里的 glow），避免每帧一次离屏渲染；
// * 光谱从 32 档减到 12 档：视觉上色散条数差别看不出来，但采样量降到 37%；
// * 只做 logo 模式（1.8s 定版），不移植 wordmark 排版分支。
//
// 所有距离都用逻辑像素（与原实现一致），所以换屏幕 / DPI 不会变形。

uniform vec2 uResolution;   // 画布物理像素
uniform float uDpr;         // 物理/逻辑比
uniform float uUnit;        // 玻璃基准尺寸（逻辑像素）
uniform vec2 uLogoBox;      // logo 在玻璃坐标系里的边长
uniform vec2 uLogoTexSize;  // logo 纹理像素尺寸
uniform float uTime;        // 0..1.8 秒
uniform float uSettle;      // 0..1 定版进度
uniform float uArtScale;    // logo 在玻璃里的缩放
uniform vec3 uTile;         // 底板颜色
uniform float uTileEnabled; // 底板开关
uniform float uPageLight;   // 背景亮度（0 深 / 1 浅）
uniform float uDepth;
uniform float uDispersion;
uniform float uRelief;
uniform float uCaustics;
uniform float uHighlights;
uniform float uEchoTint;
uniform float uInnerWallFocus;
uniform float uDropSize;
uniform float uDropStrength;
uniform float uDecay;
uniform vec4 uDrop;         // (半径, 核心, 拉伸, 核心中心)
uniform vec4 uDropLens;     // (边缘放大, 核心指数, 涟漪振幅, 涟漪波长)
uniform vec4 uDropWave;     // (相位, 内圈淡出, 外圈振幅, 保留)
uniform float uBloom;
uniform float uDropOpacity;
uniform sampler2D uLogo;

out vec4 fragColor;

const float PI = 3.14159265359;
const int BANDS = 12;

float sq(float x) { return x * x; }
float bell(float x, float width) { return exp(-sq(x / max(width, 0.001))); }
float ease(float a, float b, float x) { return smoothstep(a, b, x); }

// 超椭圆（n=2 圆，n→大 圆角方）：形状靠它连续变形，而不是交叉淡出两张图。
float superRadius(vec2 p, float n) {
  vec2 a = max(abs(p), vec2(0.00001));
  return pow(pow(a.x, n) + pow(a.y, n), 1.0 / n);
}
vec2 superNormal(vec2 p, float n) {
  return normalize(sign(p) * pow(max(abs(p), vec2(0.00001)), vec2(n - 1.0)) + vec2(0.000001));
}

// 400–700nm → RGB 权重（原实现同一张表）。
vec3 spectrum(float s) {
  float wavelength = 400.0 + 300.0 * s;
  vec3 rgb = vec3(0.0);
  if (wavelength < 440.0) rgb = vec3((440.0 - wavelength) / 120.0, 0.0, 1.0);
  else if (wavelength < 490.0) rgb = vec3(0.0, (wavelength - 440.0) / 50.0, 1.0);
  else if (wavelength < 510.0) rgb = vec3(0.0, 1.0, (510.0 - wavelength) / 20.0);
  else if (wavelength < 580.0) rgb = vec3((wavelength - 510.0) / 70.0, 1.0, 0.0);
  else if (wavelength < 645.0) rgb = vec3(1.0, (645.0 - wavelength) / 65.0, 0.0);
  else rgb = vec3(1.0, 0.0, 0.0);
  return rgb * mix(0.2, 1.0, ease(400.0, 430.0, wavelength)) * mix(1.0, 0.65, ease(650.0, 700.0, wavelength));
}
// Cauchy 近似：波长越短折射越强 —— 色散就是这么来的，不是给 RGB 加偏移。
float glassIor(float s, float spread) {
  float wavelength = 0.4 + 0.3 * s;
  return 1.38 + (0.04 / (wavelength * wavelength) - 0.12) * spread;
}

float hash1(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }
float contourNoise(float u) {
  float i = floor(u);
  float f = fract(u);
  float a = hash1(i);
  float b = hash1(i + 1.0);
  return mix(a, b, f * f * (3.0 - 2.0 * f));
}

// 采样 logo 纹理：p 是玻璃坐标系里的点，box 是内容边长。
vec4 imageAt(vec2 p, vec2 box) {
  vec2 uv = 0.5 + p / box;
  vec4 ink = texture(uLogo, clamp(uv, vec2(0.0), vec2(1.0)));
  return ink * step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

vec3 refractedCoverage = vec3(0.0);

// 玻璃里的 logo：按法线折射 → 每档波长各自采样 → 光谱加权合成。
vec4 refractedLogo(vec2 p, vec2 normalXY, float lensScale, float glass, float chromaticScale, float surfaceDistance) {
  float t = uTime;
  vec3 normal = normalize(vec3(normalXY, 1.0));
  vec3 color = vec3(0.0);
  vec3 weights = vec3(0.0);
  float alpha = 0.0;
  float minCoverage = 1.0;
  float maxCoverage = 0.0;
  refractedCoverage = vec3(0.0);
  float spread = uDispersion * chromaticScale *
      mix(0.85, mix(2.2, 1.5, ease(0.28, 0.9, t)), ease(0.25, 0.33, t));
  vec3 neutralRay = refract(vec3(0.0, 0.0, -1.0), normal, 1.0 / glassIor(0.5, spread));
  vec2 neutralOffset = neutralRay.xy / max(-neutralRay.z, 0.25) * uUnit * uDepth * 0.80 * lensScale;
  for (int i = 0; i < BANDS; i++) {
    float s = float(i) / float(BANDS - 1);
    float ior = glassIor(s, spread);
    vec3 ray = refract(vec3(0.0, 0.0, -1.0), normal, 1.0 / ior);
    vec2 offset = ray.xy / max(-ray.z, 0.25) * uUnit * uDepth * 0.80 * lensScale;
    // 开场的圆顶把画面边缘卷成月牙，再展开成桶形畸变。
    float sphereRadius = uUnit * lensScale * 0.5;
    float sphereFocus = 1.0 - ease(0.225, 0.335, t);
    float bubbleQ = min(length(p) / max(sphereRadius, 1.0), 1.0);
    float openingFocus = 1.0 - ease(0.19, 0.265, t);
    float focusProfile = mix(0.7 + 0.6 * sq(bubbleQ), 1.0 - 0.9 * sq(bubbleQ), openingFocus);
    vec2 bubbleSample = p * focusProfile + offset * mix(0.35, 0.12, openingFocus);
    bubbleSample += vec2(0.025, 0.10) * uUnit * openingFocus;
    bubbleSample += (offset - neutralOffset) * openingFocus * 1.6;
    vec2 sourcePoint = mix(p + offset, bubbleSample, sphereFocus);
    vec4 ink = imageAt(sourcePoint, uLogoBox * uArtScale);
    ink *= mix(1.0, 1.0 - ease(0.72, 0.86, bubbleQ), openingFocus);
    // 边缘按波长错开成「红黄在外、青蓝在内」的色边，而不是给墨色染色。
    float edgeShift = (s - 0.5) * uUnit * lensScale * 0.011 * uDispersion * chromaticScale;
    ink *= 1.0 - smoothstep(-0.8 / uDpr, 0.8 / uDpr, surfaceDistance - edgeShift);
    minCoverage = min(minCoverage, ink.a);
    maxCoverage = max(maxCoverage, ink.a);
    vec3 w = spectrum(s);
    color += ink.rgb * w;
    alpha += ink.a * (w.r + w.g + w.b);
    refractedCoverage += ink.a * w;
    weights += w;
  }
  color /= weights;
  refractedCoverage /= weights;
  float coating = ease(-uUnit * lensScale * 0.022, 0.0, surfaceDistance);
  color.g *= 1.0 - 0.65 * coating * (maxCoverage - minCoverage);
  float youngFilm = (maxCoverage - minCoverage) * (1.0 - ease(0.19, 0.30, t));
  youngFilm *= 1.0 - ease(-uUnit * lensScale * 0.08, -uUnit * lensScale * 0.025, surfaceDistance);
  color.r += color.b * youngFilm * 0.80;
  color.b += color.r * youngFilm * 0.60;
  color.g *= 1.0 - youngFilm * 0.55;
  alpha /= weights.r + weights.g + weights.b;
  float diffuse = max(dot(normal, normalize(vec3(-0.4, 0.6, 1.0))), 0.0);
  vec3 earlyWhite = mix(vec3(0.90, 0.93, 0.95), vec3(0.84, 0.86, 0.89), ease(0.21, 0.40, t));
  vec3 whiteBalance = mix(earlyWhite, vec3(0.87, 0.88, 0.885), ease(0.75, 1.22, t));
  color *= whiteBalance * ((0.90 + 0.10 * diffuse + glass * uCaustics * 0.04) *
      (0.975 + 0.025 * sin(p.y / uUnit * PI)));
  return vec4(color, alpha);
}
// 第一层玻璃：球 → 圆角方，里面是被折射的 logo。
vec4 iconLens(vec2 p) {
  float t = uTime;
  float settle = uSettle;
  float enter = ease(0.025, 0.16, t);
  vec4 source = imageAt(p, uLogoBox * uArtScale);
  // 1.45 之后直接给原图（纯 logo 模式的定版点；原实现是 1.58，那是给 wordmark 留的收尾）。
  if (t > 1.45) return source * settle;
  if (enter < 0.001) return vec4(0.0);
  float shape = 2.0 + 3.0 * ease(0.29, 0.36, t);
  // 球先快速出现，方角在之后才继续长开：两段运动同时结束会显得很硬。
  float expand = enter * (0.64 + 0.41 * (1.0 - exp(-max(t - 0.16, 0.0) * 5.8)));
  float collapse = 1.0 - ease(1.33, 1.52, t);
  float lensScale = max(0.001, mix(expand * mix(0.48, 1.0, collapse), 1.0, settle));
  float halfSize = uUnit * 0.5 * lensScale;
  float radius = superRadius(p / halfSize, shape);
  float sd = (radius - 1.0) * halfSize;
  float aa = 0.65;
  float mask = 1.0 - smoothstep(-aa, aa, sd);
  float glass = (1.0 - ease(1.05, 1.4, t)) * collapse * (1.0 - settle);
  float shown = ease(0.12, 0.165, t) * (1.0 - ease(1.39, 1.53, t));
  if (sd > uUnit * 0.10) return vec4(0.0);
  vec2 outward = superNormal(p / halfSize, shape);
  vec2 radial = normalize(p + vec2(0.001));
  float diagonal = max(0.0, 2.0 * radial.x * radial.y);
  // 平的中央滚成厚的肩部；法线把光线连续弯进板里，再在边缘折返。
  float shoulderStart = 0.6 + 0.18 * ease(0.66, 1.15, t) * (1.0 - diagonal) + 0.16 * ease(1.0, 1.22, t) * diagonal;
  float shoulder = ease(shoulderStart, 1.0, radius);
  float slope = (0.04 * radius + (0.85 + 0.2 * (1.0 - ease(0.28, 0.75, t))) * shoulder * shoulder) * glass * uDropStrength;
  slope += (1.0 - ease(0.18, 0.42, t)) * radius * 0.32 * uDropStrength;
  vec2 opticalDirection = normalize(mix(outward, radial, 0.95));
  float astigmatism = 0.8 + 0.4 * radial.x * radial.y;
  vec2 n = opticalDirection * slope * astigmatism * (1.0 - settle);
  vec4 ink = refractedLogo(p, n, lensScale, glass, 1.0, sd);
  float illumination = 0.5 + 0.5 * dot(outward, normalize(vec2(-0.5, 0.9)));
  vec3 inkCoverage = refractedCoverage;
  float plateLight = ease(0.3, 0.8, dot(uTile, vec3(0.299, 0.587, 0.114)));
  vec3 body = uTile * (mix(0.55, 0.96, plateLight) + mix(0.45, 0.04, plateLight) * (1.0 - min(radius, 1.0)));
  body += vec3(0.004, 0.007, 0.01) * bell(radius - 0.75, 0.5);
  vec3 color = ink.rgb + body * (1.0 - inkCoverage) * glass * uTileEnabled;
  float plateFade = mix((1.0 - ease(1.08, 1.36, t)) * (1.0 - settle), glass, uPageLight);
  float alpha = max(ink.a, plateFade * uTileEnabled);
  // 球面在弧形正面反射一块棚灯；面变平后熄灭，露出底下的暗玻璃。
  vec2 spherePoint = p / halfSize;
  vec3 sphereNormal = normalize(vec3(spherePoint, sqrt(max(0.001, 1.0 - dot(spherePoint, spherePoint)))));
  vec3 sphereRay = reflect(vec3(0.0, 0.0, -1.0), sphereNormal);
  float lightTravel = mix(-0.12, 0.20, ease(0.13, 0.30, t));
  float softbox = bell(sphereRay.x - lightTravel, 1.05) * bell(sphereRay.y - 0.56, 0.52);
  float sphericalLight = softbox * (1.0 - ease(0.245, 0.36, t)) * glass * uHighlights * 0.70;
  color += vec3(0.50, 0.61, 0.72) * sphericalLight * (1.0 - ink.a * 0.85);
  alpha = max(alpha, sphericalLight);
  // 三层细边：外侧的亮线、内圈两条随中心先消失的线（液态边不是刻出来的）。
  float arc = atan(p.y, p.x) * uUnit * 0.5;
  float grainScale = uUnit * 0.03;
  float developed = ease(0.23, 0.48, t);
  float cornerExposure = ease(0.12, 0.8, -2.0 * radial.x * radial.y);
  float reliefScale = lensScale * developed * (0.2 + 0.8 * cornerExposure);
  float sharedWarp = (contourNoise(arc / (uUnit * 0.02)) - 0.5) * 2.0 * reliefScale;
  float rimSd = sd + sharedWarp;
  float innerSd = sd + sharedWarp * 0.7 + (contourNoise(arc / (uUnit * 0.02) + 41.0) - 0.5) * 2.0 * reliefScale * 0.4;
  float inner2Sd = sd + sharedWarp * 0.45 + (contourNoise(arc / (uUnit * 0.02) + 83.0) - 0.5) * 2.0 * reliefScale * 0.6;
  float thickness = 0.75 + 0.5 * contourNoise(arc / (uUnit * 0.013) + 13.0);
  float around = arc / (uUnit * 0.5);
  float rimBob = uUnit * 0.0025 * developed *
      (0.6 * sin(7.0 * around + 0.4) * sin(t * 6.3 + 1.0) +
       0.4 * sin(3.0 * around + 2.0) * sin(t * 4.1));
  float shimmer = mix(contourNoise(arc / grainScale),
                      contourNoise(arc / grainScale + 211.0),
                      0.5 + 0.5 * sin(t * 5.0 + 6.2832 * contourNoise(arc / (grainScale * 3.0) + 7.0)));
  float rim = bell(rimSd + rimBob + uUnit * 0.002, uUnit * 0.0018 * thickness + aa * 0.3) * (0.6 + 0.8 * shimmer);
  float centerFade = 1.0 - ease(0.62, 0.92, t);
  float inner = centerFade * bell(innerSd + uUnit * 0.012, uUnit * 0.0025 / thickness + aa * 0.2) *
      (0.55 + 0.9 * contourNoise(arc / grainScale + 41.0));
  float inner2 = centerFade * bell(inner2Sd + uUnit * 0.022, uUnit * 0.0018 / thickness + aa * 0.1) *
      (0.5 + contourNoise(arc / grainScale + 83.0));
  float key = pow(illumination, 5.0);
  float rimVisibility = 1.0 - 0.55 * ease(0.75, 1.22, t);
  float lowerRight = pow(0.5 + 0.5 * dot(outward, normalize(vec2(0.8, -0.6))), 5.0);
  lowerRight *= ease(-0.25, -0.05, p.x / uUnit) * (1.0 - ease(-0.22, -0.02, p.y / uUnit));
  vec3 insetLight = vec3(0.60, 0.78, 0.91) * rim * (key * 0.8 + lowerRight * 0.7) * uHighlights * rimVisibility * shown;
  vec3 lineLight = vec3(0.72, 0.84, 0.96) * (inner * 0.5 + inner2 * 0.35) * uHighlights * shown;
  // 边缘色散：沿法线两侧取两条谱线，做出「红黄在外 / 青蓝在内」的细彩边。
  vec2 spectralDir = outward * uUnit * 0.004 * (0.4 + 0.6 * uDispersion);
  float rimSide = bell(rimSd + uUnit * 0.0015, uUnit * 0.0022 + aa * 0.4);
  vec3 spectralRim = vec3(0.0);
  spectralRim += spectrum(0.08) * bell(rimSd + uUnit * 0.0015 - uUnit * 0.0022, uUnit * 0.0025);
  spectralRim += spectrum(0.92) * bell(rimSd + uUnit * 0.0015 + uUnit * 0.0022, uUnit * 0.0025);
  spectralRim *= uDispersion * 0.35 * uHighlights * rimVisibility * shown;
  color += insetLight + lineLight + spectralRim;
  alpha = max(alpha, max(max(insetLight.r, insetLight.g), insetLight.b));
  alpha = max(alpha, max(max(spectralRim.r, spectralRim.g), spectralRim.b));
  // 双壁：内壁比外壁内缩 5.5%，中间留一条透光通道。
  float wallGap = (0.055 - 0.023 * ease(0.18, 0.34, t)) +
      0.050 * ease(0.14, 0.50, t) * (1.0 - 0.5 * ease(0.80, 1.22, t));
  float insetHalf = halfSize - wallGap * uUnit * lensScale;
  float insetShape = max(2.0, 2.0 + (shape - 2.0) * ease(0.20, 0.55, t) - 0.45);
  float insetRadius = superRadius(p / max(insetHalf, 1.0), insetShape);
  float insetSd = (insetRadius - 1.0) * insetHalf;
  float wall = (1.0 - smoothstep(-aa, aa, insetSd)) * (1.0 - mask);
  color += uTile * wall * (0.08 + 0.06 * uRelief) * (1.0 - settle * 0.5);
  alpha = max(alpha, wall * 0.35);
  // 玻璃外的「回音」：一圈更淡的轮廓，随定版淡出。
  float echo = bell(sd - uUnit * 0.012, uUnit * 0.02 + aa) * (1.0 - settle) * uEchoTint;
  vec3 echoTint = mix(vec3(0.43, 0.62, 0.79), uTile + (vec3(1.0) - uTile) * 0.4, 0.5 * uEchoTint);
  color += echoTint * echo * 0.35 * uHighlights;
  alpha = max(alpha, echo * 0.4);
  return vec4(color, alpha) * mask * uTileEnabled + vec4(color, alpha) * (1.0 - uTileEnabled) * shown;
}

// 第二滴：一滴水落上来，把画面掰弯，再摊平成涟漪。
vec4 dropLens(vec2 p) {
  float t = uTime;
  float r = length(p);
  float radius = uDrop.x;
  if (radius < 0.001 || r > radius + uUnit * 0.10) return vec4(0.0);
  float q = r / max(radius, 1.0);
  float edge = (1.0 - q) * radius;
  float aa = 0.65;
  float mask = ease(-aa, aa, edge);
  float young = 1.0 - ease(1.72, 2.02, t);
  float core = min(uDrop.y, radius);
  float coreQ = r / max(core, 1.0);
  float edgeLanding = core / max(uDropLens.x, 0.01);
  float center = uDrop.w;
  float landing = r < core
      ? edgeLanding * coreQ * (center + (1.0 - center) * pow(coreQ, uDropLens.y))
      : edgeLanding + (r - core) * uDrop.z;
  float rimZone = ease(core * 0.9, core, r);
  float k = 2.0 * PI / max(uDropLens.w, 1.0);
  landing += uDropLens.z * sin(k * r - uDropWave.x) * ease(0.0, uDropLens.w, r) * mix(uDropWave.y, 1.0, rimZone);
  vec2 outward = normalize(p + vec2(0.0001));
  vec2 bend = outward * (landing - r);
  float spread = uDropWave.z * uDispersion * (0.15 + 0.85 * rimZone);
  vec3 color = vec3(0.0);
  vec3 weights = vec3(0.0);
  float alpha = 0.0;
  float opacity = uDropOpacity;
  for (int i = 0; i < BANDS; i++) {
    float s = float(i) / float(BANDS - 1);
    vec2 source = p + bend * (1.0 + spread * (s - 0.5));
    vec4 ink = imageAt(source, uLogoBox * uArtScale);
    vec3 w = spectrum(s);
    color += ink.rgb * w;
    alpha += ink.a * (w.r + w.g + w.b);
    weights += w;
  }
  color /= weights;
  alpha /= weights.r + weights.g + weights.b;
  color *= 1.0 + uCaustics * bell(edge, uUnit * 0.06) * 0.15;
  color *= mask;
  alpha *= mask;
  // 新落下的水滴里全是散射光：墨色过曝、身体发白、周身一圈冷色溢出。
  float fresh = 1.0 - ease(1.50, 1.78, t);
  color = min(color * (1.0 + 0.6 * fresh), vec3(1.0));
  // 白度压小：原版水滴落下时更像「透明的水」，不是一团白云。
  float milk = mask * fresh * 0.08 * (0.6 + 0.4 * q) * uCaustics;
  color += vec3(0.75, 0.82, 0.9) * milk * (1.0 - alpha);
  float spill = exp(-max(r - radius, 0.0) / (uUnit * 0.17)) * (1.0 - mask) * fresh * 0.04;
  spill += exp(-max(r - radius, 0.0) / (uUnit * 0.4)) * (1.0 - fresh) * 0.035 *
      exp(-max(t - 1.95, 0.0) / 0.45) * (1.0 - ease(2.8, 3.1, t));
  color += vec3(0.32, 0.6, 1.0) * spill;
  alpha = max(alpha, max(milk, spill));
  vec3 sphereNormal = normalize(vec3(p / max(radius, 1.0), sqrt(max(0.005, 1.0 - q * q))));
  vec3 reflected = reflect(vec3(0.0, 0.0, -1.0), sphereNormal);
  float softbox = bell(reflected.x + 0.3, 0.2) * bell(reflected.y - 0.55, 0.15);
  float smallLight = bell(reflected.x - 0.25, 0.14) * bell(reflected.y - 0.65, 0.08);
  float broadLight = bell(reflected.x + 0.35, 0.65) * bell(reflected.y - 0.6, 0.45);
  float surface = (softbox * 0.35 + smallLight * 0.22 + broadLight * 0.10) * young * uHighlights * mask;
  color += vec3(0.85, 0.95, 1.0) * surface;
  alpha = max(alpha, surface);
  float key = pow(0.5 + 0.5 * dot(outward, normalize(vec2(-0.6, 0.8))), 7.0);
  float rings = 0.0;
  for (int i = 0; i < 4; i++) {
    float j = float(i);
    float ringRadius = radius + (j - 1.0) * uUnit * 0.022 * (1.0 + 0.55 * ease(1.8, 3.1, t));
    rings += bell(r - ringRadius, uUnit * (0.003 + j * 0.001)) * (0.11 / (1.0 + j));
  }
  float age = max(0.0, t - 1.46);
  float fade = exp(-age / max(uDecay, 0.1)) * (1.0 - ease(2.65, 3.3, t));
  float sideLight = pow(abs(outward.x), 10.0) * mix(1.0, 0.72, step(0.0, p.x));
  vec3 reflection = vec3(0.4, 0.62, 0.79) * rings * (0.3 + key * 2.0 + sideLight * 1.8) * fade * uHighlights;
  color += reflection;
  alpha = max(alpha, max(reflection.r, max(reflection.g, reflection.b)));
  return vec4(color, alpha) * opacity;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = (frag - uResolution * 0.5) / uDpr;
  vec4 icon = iconLens(p);
  vec4 drop = dropLens(p);
  vec4 result = drop + icon * (1.0 - drop.a);
  // bloom 近似：单 pass 里没有离屏纹理，用「logo 的低频多点采样 + 边缘光」
  // 凑出大半径辉光，避免每帧再做一次离屏渲染（那会拖慢冷启动首帧）。
  // 只用径向辉光：早先拿「放大采样的 logo」当 bloom，结果在玻璃内外各留下
  // 一个放大的 logo 虚影 —— 单 pass 里没有低频纹理可用，宁可用保守的径向光。
  float halo = bell(length(p), uUnit * 0.62) * 0.5 + bell(length(p), uUnit * 1.05) * 0.2;
  float glow = halo * (0.6 + 0.4 * uSettle);
  vec3 glowColor = vec3(0.55, 0.74, 0.95) * glow * uBloom * (1.0 - uPageLight * 0.6);
  // 只让辉光贴着玻璃（用 icon 的覆盖度加权）：否则放大采样的 logo 会在整块
  // 画布上留下一个巨大的虚影 —— 那是单 pass 近似 bloom 最容易踩的坑。
  result.rgb += glowColor * (0.30 * icon.a + 0.04) * (1.0 - result.a * 0.5);
  result.a = clamp(max(result.a, max(result.r, max(result.g, result.b))), 0.0, 1.0);
  float dither = (fract(sin(dot(frag, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
  fragColor = vec4(clamp(result.rgb + dither * result.a, vec3(0.0), vec3(result.a)), result.a);
}

