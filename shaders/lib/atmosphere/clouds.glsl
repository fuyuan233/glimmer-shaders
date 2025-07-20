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

#ifndef CLOUDS_GLSL
#define CLOUDS_GLSL

#include "/lib/atmosphere/fog.glsl"

// https://al-ro.github.io/projects/curl/
vec2 curl(vec2 pos) {
  const float eps = rcp(maxVec2(textureSize(perlinNoiseTex, 0)));

  float n1 = texture(perlinNoiseTex, vec2(pos.x + eps, pos.y)).r;
  float n2 = texture(perlinNoiseTex, vec2(pos.x - eps, pos.y)).r;

  float a = (n1 - n2) / (2.0 * eps);

  n1 = texture(perlinNoiseTex, vec2(pos.x, pos.y + eps)).r;
  n2 = texture(perlinNoiseTex, vec2(pos.x, pos.y - eps)).r;

  float b = (n1 - n2) / (2.0 * eps);

  return vec2(b, -a);
}

float remap(float val, float oMin, float oMax, float nMin, float nMax) {
  return mix(nMin, nMax, smoothstep(oMin, oMax, val));
}

vec3 multipleScattering(
  float density,
  float costh,
  float g1,
  float g2,
  vec3 extinction,
  int octaves,
  float lobeWeight,
  float attenuation,
  float contribution,
  float phaseAttenuation
) {
  vec3 radiance = vec3(0.0);

  // float attenuation = 0.9;
  // float contribution = 0.5;
  // float phaseAttenuation = 0.7;

  float a = 1.0;
  float b = 1.0;
  float c = 1.0;

  for (int n = 0; n < octaves; n++) {
    float phase = dualHenyeyGreenstein(g1 * c, g2 * c, costh, lobeWeight);
    radiance += b * phase * exp(-density * extinction * a);

    a *= attenuation;
    b *= contribution;
    c *= 1.0 - phaseAttenuation;
  }

  return radiance;
}

float getCloudDensity(vec2 pos, bool highSamples) {
  float density = 0.0;
  float weight = 0.0;

  pos = pos / 100000;

  pos += curl(pos * 0.9 - vec2(worldTimeCounter * 0.0001, 0.0)) / 5000.0;

  for (int i = 0; i < 16; i++) {
    float sampleWeight = exp2(-float(i));
    pos.y += worldTimeCounter * 0.000025 * sqrt(i + 1);
    vec2 samplePos = pos * exp2(float(i));
    #ifdef BLOCKY_CLOUDS
    density +=
      texelFetch(
        perlinNoiseTex,
        ivec2(fract(samplePos) * textureSize(perlinNoiseTex, 0)),
        0
      ).r *
      sampleWeight;
    #else
    density += texture(perlinNoiseTex, fract(samplePos)).r * sampleWeight;
    #endif
    weight += sampleWeight;

    if (!highSamples) {
      break;
    }
  }

  density /= weight;

  density = smoothstep(
    mix(
      0.47,
      0.99,
      exp(-5 * humiditySmooth) - wetness * 0.2 - thunderStrength * 0.3
    ),
    1.0,
    density
  );

  density *= 0.005;

  return density;
}

vec3 getCloudShadow(vec3 origin) {
  origin += cameraPosition;

  vec3 point = vec3(0.0);
  if (!rayPlaneIntersection(origin, worldLightDir, CLOUD_PLANE_ALTITUDE, point))
    return vec3(1.0);
  vec3 exitPoint = vec3(0.0);
  rayPlaneIntersection(
    origin,
    worldLightDir,
    CLOUD_PLANE_ALTITUDE + CLOUD_PLANE_HEIGHT,
    exitPoint
  );
  float totalDensityAlongRay =
    getCloudDensity(point.xz, false) * distance(point, exitPoint);
  return clamp01(
    mix(
      exp(-totalDensityAlongRay * CLOUD_EXTINCTION_COLOR),
      vec3(1.0),
      1.0 - smoothstep(0.1, 0.2, worldLightDir.y)
    )
  );

}

vec3 getClouds(vec3 origin, vec3 worldDir, out vec3 transmittance) {
  transmittance = vec3(1.0);
  #ifndef CLOUDS
  return vec3(0.0);
  #endif

  origin += cameraPosition;

  vec3 point;
  if (!rayPlaneIntersection(origin, worldDir, CLOUD_PLANE_ALTITUDE, point))
    return vec3(0.0);

  float jitter = interleavedGradientNoise(floor(gl_FragCoord.xy), frameCounter);

  vec3 exitPoint; // where the view ray exits the cloud plane
  rayPlaneIntersection(
    origin,
    worldDir,
    CLOUD_PLANE_ALTITUDE + CLOUD_PLANE_HEIGHT,
    exitPoint
  );
  float totalDensityAlongRay =
    getCloudDensity(point.xz, true) * distance(point, exitPoint);
  vec3 sunExitPoint;
  rayPlaneIntersection(
    point,
    worldLightDir,
    CLOUD_PLANE_ALTITUDE + CLOUD_PLANE_HEIGHT,
    sunExitPoint
  );
  float totalDensityTowardsSun =
    getCloudDensity(mix(point.xz, sunExitPoint.xz, jitter), true) *
    distance(point, sunExitPoint);

  float costh = dot(worldDir, worldLightDir);

  vec3 powder = clamp01(
    1.0 - exp(-totalDensityTowardsSun * 2 * CLOUD_EXTINCTION_COLOR)
  );

  vec3 radiance =
    skylightColor +
    sunlightColor *
      (1.0 + 9.0 * float(lightDir == sunDir)) *
      multipleScattering(
        totalDensityTowardsSun,
        costh,
        0.9,
        -0.4,
        CLOUD_EXTINCTION_COLOR,
        4,
        0.85,
        0.9,
        0.8,
        0.1
      ) *
      mix(2.0 * powder, vec3(1.0), costh * 0.5 + 0.5);

  transmittance = exp(-totalDensityAlongRay * CLOUD_EXTINCTION_COLOR);
  transmittance = mix(
    transmittance,
    vec3(1.0),
    1.0 - smoothstep(0.0, 0.2, worldDir.y)
  ); // fade clouds towards horizon

  vec3 integScatter =
    (radiance - radiance * clamp01(transmittance)) / CLOUD_EXTINCTION_COLOR;
  vec3 scatter = integScatter * transmittance;
  scatter = mix(
    scatter,
    vec3(0.0),
    exp(-distance(point, cameraPosition) * 0.004)
  );

  scatter += pow3(
    clamp01(1.0 - distance(point.xz, lightningBoltPosition.xz) / 10.0) *
      lightningBoltPosition.w *
      1000.0
  );

  #ifdef ANIME_CLOUDS
  scatter = hsv(scatter);
  scatter.b =
    ceil(scatter.b * 32.0 / luminance(sunlightColor)) /
    (32.0 / luminance(sunlightColor));
  scatter = rgb(scatter);

  transmittance = hsv(transmittance);
  transmittance.b = floor(transmittance.b * 32.0) / 32.0;
  transmittance = rgb(transmittance);
  #endif

  scatter *= skyMultiplier;

  // scatter = atmosphericFog(scatter, point);

  return scatter;
}

#endif
