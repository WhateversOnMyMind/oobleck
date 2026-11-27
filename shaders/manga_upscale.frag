// Edge-adaptive spatial upscaling (pass 1 of 2) for the manga reader.
//
// Port of the EASU pass of AMD FidelityFX Super Resolution 1.0 to Flutter's
// runtime-effect GLSL. Changes from the reference: no textureGather (12
// explicit taps at texel centres), exact reciprocals instead of the bit-trick
// approximations, all four premultiplied channels are filtered so pages with
// transparency survive, and the output position can be offset so that a tall
// page can be rendered in bands that sample across their own borders.
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

// Size of the source texture in texels.
uniform vec2 uTexSize;
// Top-left of the source region (texels) that maps to output pixel (0, 0).
uniform vec2 uSrcOrigin;
// Source texels per output pixel (below 1 when upscaling).
uniform vec2 uScale;
// Added to the fragment position to get the position in the whole output.
uniform vec2 uOutOffset;
uniform sampler2D uTex;

out vec4 fragColor;

vec4 tap(vec2 texel) {
  vec2 p = clamp(texel + 0.5, vec2(0.5), uTexSize - 0.5);
  return texture(uTex, p / uTexSize);
}

float luma(vec4 c) {
  return c.b * 0.5 + (c.r * 0.5 + c.g);
}

// Gradient direction (xy) and edge strength (z) around texel c, weighted by w.
//     a
//   b c d
//     e
vec3 edge(float w, float lA, float lB, float lC, float lD, float lE) {
  float dc = lD - lC;
  float cb = lC - lB;
  float dirX = lD - lB;
  float lenX = abs(dirX) / max(max(abs(dc), abs(cb)), 1.0e-5);
  lenX = clamp(lenX, 0.0, 1.0);
  float ec = lE - lC;
  float ca = lC - lA;
  float dirY = lE - lA;
  float lenY = abs(dirY) / max(max(abs(ec), abs(ca)), 1.0e-5);
  lenY = clamp(lenY, 0.0, 1.0);
  return vec3(dirX, dirY, lenX * lenX + lenY * lenY) * w;
}

// Weight of one tap at offset off under the rotated, stretched Lanczos-like
// kernel.
float weight(vec2 off, vec2 dir, vec2 len, float lob, float clp) {
  vec2 v = vec2(off.x * dir.x + off.y * dir.y, off.y * dir.x - off.x * dir.y);
  v *= len;
  float d2 = min(dot(v, v), clp);
  float wB = 0.4 * d2 - 1.0;
  float wA = lob * d2 - 1.0;
  wB *= wB;
  wA *= wA;
  wB = 1.5625 * wB - 0.5625;
  return wB * wA;
}

void main() {
  vec2 pp = (FlutterFragCoord().xy + uOutOffset) * uScale + uSrcOrigin - 0.5;
  vec2 fp = floor(pp);
  pp -= fp;

  //     b c
  //   e f g h
  //   i j k l
  //     n o
  vec4 b = tap(fp + vec2(0.0, -1.0));
  vec4 c = tap(fp + vec2(1.0, -1.0));
  vec4 e = tap(fp + vec2(-1.0, 0.0));
  vec4 f = tap(fp);
  vec4 g = tap(fp + vec2(1.0, 0.0));
  vec4 h = tap(fp + vec2(2.0, 0.0));
  vec4 i = tap(fp + vec2(-1.0, 1.0));
  vec4 j = tap(fp + vec2(0.0, 1.0));
  vec4 k = tap(fp + vec2(1.0, 1.0));
  vec4 l = tap(fp + vec2(2.0, 1.0));
  vec4 n = tap(fp + vec2(0.0, 2.0));
  vec4 o = tap(fp + vec2(1.0, 2.0));

  float bL = luma(b);
  float cL = luma(c);
  float eL = luma(e);
  float fL = luma(f);
  float gL = luma(g);
  float hL = luma(h);
  float iL = luma(i);
  float jL = luma(j);
  float kL = luma(k);
  float lL = luma(l);
  float nL = luma(n);
  float oL = luma(o);

  // Bilinear blend of the edge estimate at the four nearest texels.
  vec3 acc = edge((1.0 - pp.x) * (1.0 - pp.y), bL, eL, fL, gL, jL);
  acc += edge(pp.x * (1.0 - pp.y), cL, fL, gL, hL, kL);
  acc += edge((1.0 - pp.x) * pp.y, fL, iL, jL, kL, nL);
  acc += edge(pp.x * pp.y, gL, jL, kL, lL, oL);

  vec2 dir = acc.xy;
  float len = acc.z;
  float dirR = dot(dir, dir);
  if (dirR < 1.0 / 32768.0) {
    dir = vec2(1.0, 0.0);
  } else {
    dir *= inversesqrt(dirR);
  }

  len *= 0.5;
  len *= len;
  // Stretch the kernel along the edge and shrink it across the edge.
  float stretch = dot(dir, dir) / max(abs(dir.x), abs(dir.y));
  vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len);
  // Negative lobe: 0.5 on flat areas down to 0.21 on strong edges.
  float lob = 0.5 + (0.21 - 0.5) * len;
  float clp = 1.0 / lob;

  vec4 lo = min(min(f, g), min(j, k));
  vec4 hi = max(max(f, g), max(j, k));

  vec4 aC = vec4(0.0);
  float aW = 0.0;
  float w;
  w = weight(vec2(0.0, -1.0) - pp, dir, len2, lob, clp);
  aC += b * w;
  aW += w;
  w = weight(vec2(1.0, -1.0) - pp, dir, len2, lob, clp);
  aC += c * w;
  aW += w;
  w = weight(vec2(-1.0, 1.0) - pp, dir, len2, lob, clp);
  aC += i * w;
  aW += w;
  w = weight(vec2(0.0, 1.0) - pp, dir, len2, lob, clp);
  aC += j * w;
  aW += w;
  w = weight(-pp, dir, len2, lob, clp);
  aC += f * w;
  aW += w;
  w = weight(vec2(-1.0, 0.0) - pp, dir, len2, lob, clp);
  aC += e * w;
  aW += w;
  w = weight(vec2(1.0, 1.0) - pp, dir, len2, lob, clp);
  aC += k * w;
  aW += w;
  w = weight(vec2(2.0, 1.0) - pp, dir, len2, lob, clp);
  aC += l * w;
  aW += w;
  w = weight(vec2(2.0, 0.0) - pp, dir, len2, lob, clp);
  aC += h * w;
  aW += w;
  w = weight(vec2(1.0, 0.0) - pp, dir, len2, lob, clp);
  aC += g * w;
  aW += w;
  w = weight(vec2(1.0, 2.0) - pp, dir, len2, lob, clp);
  aC += o * w;
  aW += w;
  w = weight(vec2(0.0, 2.0) - pp, dir, len2, lob, clp);
  aC += n * w;
  aW += w;

  // Clamping to the four nearest texels removes ringing.
  fragColor = min(hi, max(lo, aC / aW));
}
