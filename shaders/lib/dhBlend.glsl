/*
    Blending implemented with help from DistortedDragon1o4
    https://github.com/DistortedDragon1o4

    Copyright (c) 2024 Josh Britain (jbritain)
    Licensed under the MIT license

      _____   __   _                          
     / ___/  / /  (_)  __ _   __ _  ___   ____
    / (_ /  / /  / /  /  ' \ /  ' \/ -_) / __/
    \___/  /_/  /_/  /_/_/_//_/_/_/\__/ /_/   

    By jbritain
    https://jbritain.net
                                            
*/

#ifndef DH_BLEND_GLSL
#define DH_BLEND_GLSL

// https://www.shadertoy.com/view/7sfXDn
// "Ordered Dithering" (Bayer) by Tech_

float bayer2(vec2 a) {
  a = floor(a);
  return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))
#define bayer8(a) (bayer4(0.5 * (a)) * 0.25 + bayer2(a))
#define bayer16(a) (bayer8(0.5 * (a)) * 0.25 + bayer2(a))
#define bayer32(a) (bayer16(0.5 * (a)) * 0.25 + bayer2(a))
#define bayer64(a) (bayer32(0.5 * (a)) * 0.25 + bayer2(a))

void dhBlend(vec3 viewPos) {
  float l = length(viewPos);
  if (l >= far - 15) {
    float opacity = sqrt(clamp((1 + far - l) / 16, 0.0, 1.0));

    #ifdef TEMPORAL_FILTER
    if (
      interleavedGradientNoise(floor(gl_FragCoord.xy), frameCounter) >
      opacity
    )
      discard;
    #else
    if (bayer8(floor(gl_FragCoord.xy)) > opacity) discard;
    #endif
  }

  // if (length(viewPos) > far)
  //     discard;

}

#endif
