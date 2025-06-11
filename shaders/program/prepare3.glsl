#include "/lib/common.glsl"

#ifdef csh

layout (local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
const ivec3 workGroups = ivec3(8, 8, 8);

#include "/lib/common.glsl"

layout(rgba16f) uniform image3D aerialPerspectiveLUT;

#include "/lib/atmosphere/sky/hillaireCommon.glsl"

/* 
    Extended from 'Production Sky Rendering' by Andrew Helmer
    https://www.shadertoy.com/view/slSXRW
*/


const int numScatteringSteps = 32;
vec3 raymarchScattering(vec3 pos, 
                              vec3 rayDir, 
                              vec3 sunDir,
                              float tMax,
                              float numSteps, out vec3 transmittance) {
    float cosTheta = dot(rayDir, sunDir);
    
	float miePhaseValue = getMiePhase(cosTheta);
	float rayleighPhaseValue = getRayleighPhase(-cosTheta);
    
    vec3 lum = vec3(0.0);
    transmittance = vec3(1.0);
    float t = 0.0;

    for (float i = 0.0; i < numSteps; i += 1.0) {
        float newT = ((i + 0.3)/numSteps)*tMax;
        float dt = newT - t;
        t = newT;
        
        vec3 newPos = pos + t*rayDir;
        
        vec3 rayleighScattering, extinction;
        float mieScattering;
        getScatteringValues(newPos, rayleighScattering, mieScattering, extinction);
        
        vec3 sampleTransmittance = exp(-dt*extinction);

        vec3 sunTransmittance = getValFromTLUT(sunTransmittanceLUTTex, tLUTRes, newPos, sunDir);
        vec3 psiMS = getValFromMultiScattLUT(multipleScatteringLUTTex, msLUTRes, newPos, sunDir);
        
        vec3 rayleighInScattering = rayleighScattering*(rayleighPhaseValue*sunTransmittance + psiMS);
        vec3 mieInScattering = mieScattering*(miePhaseValue*sunTransmittance + psiMS);

        rayleighScattering *= 20.0;
        mieScattering *= 20.0;
        rayleighInScattering *= 20.0;
        mieInScattering *= 20.0;
        // extinction *= 20.0;

        vec3 inScattering = (rayleighInScattering + mieInScattering);

        // Integrated scattering within path segment.
        vec3 scatteringIntegral = (inScattering - inScattering * sampleTransmittance) / extinction;

        lum += scatteringIntegral*transmittance*sunIrradiance;
        
        transmittance *= sampleTransmittance;
    }
    return lum;
}

void main()
{


    ivec3 texelCoord = ivec3(gl_GlobalInvocationID.xyz);
    vec3 coord = vec3(texelCoord) / 32.0;
    
    vec3 viewPos = unmapAerialPerspectivePos(coord);

    vec3 rayDir = normalize(mat3(gbufferModelViewInverse) * viewPos);
    float tMax = length(viewPos) * 1e-6;
    float groundDist = rayIntersectSphere(atmospherePos, rayDir, groundRadiusMM);
    if(groundDist > 0.0 && groundDist < tMax) tMax = groundDist;

    float atmoDist = rayIntersectSphere(atmospherePos, rayDir, atmosphereRadiusMM);
    if(atmoDist > 0.0 && atmoDist < tMax) tMax = atmoDist;


    vec3 transmittance;
    vec3 lum = raymarchScattering(atmospherePos, rayDir, worldSunDir, tMax, float(numScatteringSteps), transmittance);
    
    imageStore(aerialPerspectiveLUT, texelCoord, vec4(lum, (transmittance.r + transmittance.g + transmittance.b) / 3.0));
}

#endif