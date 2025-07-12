#include "/lib/common.glsl"

#ifdef csh

layout(local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(25, 25, 1);

#include "/lib/common.glsl"

layout(rgba16f) uniform image2D skyViewLUT;

#include "/lib/atmosphere/sky/hillaireCommon.glsl"

/* 
    'Production Sky Rendering' by Andrew Helmer
    https://www.shadertoy.com/view/slSXRW
*/

const int numScatteringSteps = 32;
vec3 raymarchScattering(
  vec3 pos,
  vec3 rayDir,
  vec3 sunDir,
  float tMax,
  float numSteps
) {
  float cosTheta = dot(rayDir, sunDir);

  float miePhaseValue = getMiePhase(cosTheta);
  float rayleighPhaseValue = getRayleighPhase(-cosTheta);

  vec3 lum = vec3(0.0);
  vec3 transmittance = vec3(1.0);
  float t = 0.0;
  for (float i = 0.0; i < numSteps; i += 1.0) {
    float newT = (i + 0.3) / numSteps * tMax;
    float dt = newT - t;
    t = newT;

    vec3 newPos = pos + t * rayDir;

    vec3 rayleighScattering, extinction;
    float mieScattering;
    getScatteringValues(newPos, rayleighScattering, mieScattering, extinction);

    vec3 sampleTransmittance = exp(-dt * extinction);

    vec3 sunTransmittance = getValFromTLUT(
      sunTransmittanceLUTTex,
      tLUTRes,
      newPos,
      sunDir
    );
    vec3 psiMS = getValFromMultiScattLUT(
      multipleScatteringLUTTex,
      msLUTRes,
      newPos,
      sunDir
    );

    vec3 rayleighInScattering =
      rayleighScattering * (rayleighPhaseValue * sunTransmittance + psiMS);
    vec3 mieInScattering =
      mieScattering * (miePhaseValue * sunTransmittance + psiMS);
    vec3 inScattering =
      (rayleighInScattering + mieInScattering) * sunIrradiance;

    // Integrated scattering within path segment.
    vec3 scatteringIntegral =
      (inScattering - inScattering * sampleTransmittance) / extinction;

    lum += scatteringIntegral * transmittance;

    transmittance *= sampleTransmittance;
  }
  return lum;
}

void main() {
  #ifdef WORLD_THE_END
  sunlightColor = vec3(0.8, 0.7, 1.0) * 0.1;
  skylightColor = vec3(0.5, 0.4, 1.0) * 0.02;
  return;
  #endif

  ivec2 texelCoord = ivec2(gl_GlobalInvocationID.xy);
  float u =
    clamp(float(texelCoord.x), 0.0, skyViewLUTRes.x - 1.0) / skyViewLUTRes.x;
  float v =
    clamp(float(texelCoord.y), 0.0, skyViewLUTRes.y - 1.0) / skyViewLUTRes.y;

  float azimuthAngle = (u - 0.5) * 2.0 * PI;
  // Non-linear mapping of altitude. See Section 5.3 of the paper.
  float adjV;
  if (v < 0.5) {
    float coord = 1.0 - 2.0 * v;
    adjV = -coord * coord;
  } else {
    float coord = v * 2.0 - 1.0;
    adjV = coord * coord;
  }

  float height = length(atmospherePos);
  vec3 up = atmospherePos / height;
  float horizonAngle =
    safeacos(sqrt(height * height - groundRadiusMM * groundRadiusMM) / height) -
    0.5 * PI;
  float altitudeAngle = adjV * 0.5 * PI - horizonAngle;

  float cosAltitude = cos(altitudeAngle);
  vec3 rayDir = vec3(
    cosAltitude * sin(azimuthAngle),
    sin(altitudeAngle),
    -cosAltitude * cos(azimuthAngle)
  );

  float atmoDist = rayIntersectSphere(
    atmospherePos,
    rayDir,
    atmosphereRadiusMM
  );
  float groundDist = rayIntersectSphere(atmospherePos, rayDir, groundRadiusMM);
  float tMax = groundDist < 0.0 ? atmoDist : groundDist;
  vec3 lum = raymarchScattering(
    atmospherePos,
    rayDir,
    worldSunDir,
    tMax,
    float(numScatteringSteps)
  );

  imageStore(skyViewLUT, texelCoord, vec4(lum, 1.0));

  if (texelCoord == ivec2(0.0)) {
    sunlightColor = isDay
      ? getValFromTLUT(
        sunTransmittanceLUTTex,
        tLUTRes,
        atmospherePos,
        worldSunDir
      ) *
      sunIrradiance
      : getValFromTLUT(
        sunTransmittanceLUTTex,
        tLUTRes,
        atmospherePos,
        -worldSunDir
      ) *
      moonIrradiance *
      abs(moonPhase - 4) /
      4.0;

    sunlightColor *= smoothstep(0.0, 0.005, worldLightDir.y); // fade out sunlight to stop hard transition between sun and moon

    skylightColor = vec3(0.0);
  }
}

#endif
