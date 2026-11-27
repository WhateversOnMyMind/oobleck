// Contrast-adaptive sharpening (pass 2 of 2) for the manga reader.
//
// Based on the RCAS pass of AMD FidelityFX Super Resolution 1.0, rewritten
// for Flutter's runtime-effect GLSL and retuned for line art. It keeps the
// RCAS kernel (a negative lobe on the four direct neighbours) but replaces
// its limiter: RCAS shrinks the lobe so that the result cannot leave 0..1,
// which switches it off next to pure black and white, exactly where manga
// has its edges. Here the lobe is fixed by the sharpness and the result is
// clamped to the range of the five taps instead. Ramps across an edge get
// steeper, while nothing can overshoot: no halos, and an isolated speck or a
// screentone dot is never pushed beyond the values already around it.
// The input can be read at an offset so that a padded band can be sharpened
// without seams.
//
// Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

// Size of the input texture in texels.
uniform vec2 uTexSize;
// Texel of the input that maps to output pixel (0, 0).
uniform vec2 uOffset;
// 0 = no sharpening, 1 = strongest (the lobe RCAS uses at full strength).
uniform float uSharpness;
uniform sampler2D uTex;

out vec4 fragColor;

vec4 tap(vec2 texel) {
  vec2 p = clamp(texel + 0.5, vec2(0.5), uTexSize - 0.5);
  return texture(uTex, p / uTexSize);
}

void main() {
  vec2 ip = floor(FlutterFragCoord().xy) + uOffset;
  //     b
  //   d e f
  //     h
  vec4 e4 = tap(ip);
  vec3 b = tap(ip + vec2(0.0, -1.0)).rgb;
  vec3 d = tap(ip + vec2(-1.0, 0.0)).rgb;
  vec3 f = tap(ip + vec2(1.0, 0.0)).rgb;
  vec3 h = tap(ip + vec2(0.0, 1.0)).rgb;
  vec3 e = e4.rgb;

  vec3 lo = min(min(min(b, d), min(f, h)), e);
  vec3 hi = max(max(max(b, d), max(f, h)), e);
  float lobe = -0.1875 * clamp(uSharpness, 0.0, 1.0);
  vec3 rgb = (lobe * (b + d + h + f) + e) / (4.0 * lobe + 1.0);
  rgb = clamp(rgb, lo, hi);
  fragColor = vec4(min(rgb, vec3(e4.a)), e4.a);
}
