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
#include "/lib/sway.glsl"

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normal;
flat out int materialID;
out vec3 viewPos;

#include "/lib/dh.glsl"

void main() {
  materialID = convertDHMaterialIDs(dhMaterialId);
  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
  lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
  glcolor = gl_Color;

  normal = normalize(gl_NormalMatrix * gl_Normal);

  viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

  gl_Position = dhProjection * vec4(viewPos, 1.0);
}

#endif

// ===========================================================================================

#ifdef fsh
#include "/lib/lighting/shading.glsl"
#include "/lib/util/packing.glsl"
#include "/lib/lighting/directionalLightmap.glsl"

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;
flat in int materialID;
in vec3 viewPos;

/* RENDERTARGETS: 0,1 */

layout(location = 0) out vec4 color;
layout(location = 1) out vec4 outData1;

void main() {
  vec3 playerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
  if (length(viewPos) < far - 16) {
    discard;
    return;
  }

  if (texture(depthtex0, gl_FragCoord.xy / resolution).r < 1.0) {
    discard;
  }

  vec2 lightmap = lmcoord * 33.05 / 32.0 - 1.05 / 32.0;

  #ifdef WORLD_THE_END
  lightmap.y = 1.0;
  #endif

  vec4 albedo = glcolor;

  if (albedo.a < alphaTestRef) {
    discard;
  }

  int materialID = materialID;
  if (materialIsWater(materialID) && albedo.a >= 0.99) {
    materialID = 0;
  }

  vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
  vec3 worldPos = feetPlayerPos + cameraPosition;
  vec3 noisePos = mod(worldPos * 4.0, 64.0);
  vec3 worldNormal = mat3(gbufferModelViewInverse) * normal;
  ivec2 noiseCoord;
  if (abs(worldNormal.x) > 0.5) {
    noiseCoord = ivec2(noisePos.yz);
  } else if (abs(worldNormal.y) > 0.5) {
    noiseCoord = ivec2(noisePos.xz);
  } else {
    noiseCoord = ivec2(noisePos.xy);
  }

  albedo.rgb *= 1.1;
  if (materialIsLeaves(materialID)) {
    albedo.rgb *= mix(0.7, 1.2, texelFetch(noisetex, noiseCoord, 0).r);
  } else {
    albedo.rgb *= mix(0.95, 1.05, texelFetch(noisetex, noiseCoord, 0).r);
  }

  albedo.rgb = pow(albedo.rgb, vec3(2.2));

  Material material;
  material.albedo = albedo.rgb;
  material.roughness = 1.0;
  material.f0 = vec3(0.4);
  material.metalID = NO_METAL;
  material.porosity = 0.0;
  material.sss = 0.0;
  material.emission = 0.0;
  material.ao = 1.0;

  if (materialIsPlant(materialID)) {
    material.sss = 1.0;
    material.f0 = vec3(0.04);
    material.roughness = 0.5;
  }

  if (materialIsLava(materialID)) {
    material.emission = 1.0;
  }

  #ifdef PATCHY_LAVA
  if (materialIsLava(materialID)) {
    vec3 worldPos = playerPos + cameraPosition;
    float noise = texture(
      perlinNoiseTex,
      mod(worldPos.xz / 100 + vec2(0.0, frameTimeCounter * 0.005), 1.0)
    ).r;
    noise *= texture(
      perlinNoiseTex,
      mod(worldPos.xz / 200 + vec2(frameTimeCounter * 0.005, 0.0), 1.0)
    ).r;
    material.albedo.rgb *= noise;
    material.albedo.rgb *= 4.0;
  }
  #endif

  if (materialIsWater(materialID)) {
    material.f0 = vec3(0.02);
    material.roughness = 0.0;
    color = vec4(0.0);
  } else {
    color.rgb = getShadedColor(
      material,
      normal,
      normal,
      lightmap,
      viewPos,
      1.0,
      1.0
    );
    color.a = albedo.a;
  }

  dhBlend(viewPos);

  outData1.xy = encodeNormal(mat3(gbufferModelViewInverse) * normal);
  outData1.z = lightmap.y;
  outData1.a = clamp01(float(materialID - 1000) * rcp(255.0));
}

#endif
