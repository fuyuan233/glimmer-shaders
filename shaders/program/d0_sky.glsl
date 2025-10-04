/*
    Copyright (c) 2024 Josh Britain (jbritain)
    Licensed under the MIT license

      _____   __   _                          
     / ___/  / /  (_)  __ _   __ _  ___   ____
    / (_ /  / /  / /  /  ' \ /  ' \/ -_) / __/
    \___/  /_/  /_/  /_/_/_//_/_/_/\__/ /_/   
    
    By jbritain
    https://jbritain.net
                                            
*/

#include "/lib/common.glsl"

#ifdef vsh

out vec2 texcoord;

void main() {
  gl_Position = ftransform();
  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}

#endif

// ===========================================================================================

#ifdef fsh
#include "/lib/atmosphere/sky/sky.glsl"
#include "/lib/atmosphere/clouds.glsl"

in vec2 texcoord;

#include "/lib/dh.glsl"

#if GODRAYS > 0
/* RENDERTARGETS: 0,4 */
#else
/* RENDERTARGETS: 0 */
#endif

layout(location = 0) out vec4 color;

#if GODRAYS > 0
layout(location = 1) out vec3 occlusion;
#endif

void main() {
  color = texture(colortex0, texcoord);

  float depth = texture(depthtex0, texcoord).r;
  if (depth == 1.0) {
    vec3 viewPos = screenSpaceToViewSpace(vec3(texcoord, depth));
    dhOverride(depth, viewPos, false);
    if (dhMask) {
      return;
    }

    vec3 worldDir = mat3(gbufferModelViewInverse) * normalize(viewPos);

    color.rgb = getSky(color.rgb, worldDir, true);
    #ifdef WORLD_OVERWORLD
    vec3 transmittance;

    vec3 scattering = getClouds(vec3(0.0), worldDir, transmittance);

    color.rgb = color.rgb * transmittance + scattering;

    #if GODRAYS > 0
    occlusion = pow2(transmittance);
    #endif
    #endif

  }

}

#endif
