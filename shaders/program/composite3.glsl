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
    in vec2 texcoord;

    #include "/lib/dh.glsl"

    #include "/lib/util/screenSpaceRayTrace.glsl"
    #include "/lib/atmosphere/sky/sky.glsl"
    #include "/lib/lighting/shading.glsl"
    #include "/lib/water/waveNormals.glsl"
    #include "/lib/util/packing.glsl"
    #include "/lib/water/waterFog.glsl"
    #include "/lib/atmosphere/fog.glsl"
    #include "/lib/atmosphere/clouds.glsl"

    /* RENDERTARGETS: 0 */
    layout(location = 0) out vec4 color;

    void main() {
        color = texture(colortex0, texcoord);

        vec4 data1 = texture(colortex1, texcoord);

        vec3 worldNormal = decodeNormal(data1.xy);
        vec3 normal = mat3(gbufferModelView) * worldNormal;

        bool totalInternalReflection = false;

        float skyLightmap = data1.z;
        int materialID = int(data1.a * 255 + 0.5) + 1000;


        bool isWater = materialIsWater(materialID);
        bool inWater = isEyeInWater == 1;

        float translucentDepth = texture(depthtex0, texcoord).r;
        float opaqueDepth = texture(depthtex1, texcoord).r;

        vec3 translucentViewPos = screenSpaceToViewSpace(vec3(texcoord, translucentDepth));
        vec3 opaqueViewPos = screenSpaceToViewSpace(vec3(texcoord, opaqueDepth));

        dhOverride(opaqueDepth, opaqueViewPos, true);
        dhOverride(translucentDepth, translucentViewPos, false);

        vec3 translucentFeetPlayerPos = (gbufferModelViewInverse * vec4(translucentViewPos, 1.0)).xyz;
        vec3 opaqueFeetPlayerPos = (gbufferModelViewInverse * vec4(opaqueViewPos, 1.0)).xyz;

        bool infiniteOceanMask = false;

        #if defined INFINITE_OCEAN && defined WORLD_OVERWORLD
        if(translucentDepth == 1.0 && !inWater && cameraPosition.y > SEA_LEVEL){
            if(rayPlaneIntersection(vec3(0.0, 0.0, 0.0), normalize(translucentFeetPlayerPos), SEA_LEVEL - cameraPosition.y, translucentFeetPlayerPos)){
                infiniteOceanMask = true;
                translucentViewPos = (gbufferModelView * vec4(translucentFeetPlayerPos, 1.0)).xyz;
                opaqueFeetPlayerPos = translucentFeetPlayerPos * 2.0;
                opaqueViewPos = translucentViewPos * 2.0;
                normal = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
                worldNormal = vec3(0.0, 1.0, 0.0);
                isWater = true;
                color.rgb = vec3(0.0);
            }
        }
        #endif

        vec3 viewDir = normalize(translucentViewPos);

        vec3 scatterFactor = texture(colortex4, texcoord).rgb;

        if(isWater){
            Material material = waterMaterial;

            #ifndef VANILLA_WATER
            vec3 worldWaveNormal = waveNormal(translucentFeetPlayerPos.xz + cameraPosition.xz, worldNormal, sin(PI * 0.5 * clamp01(abs(dot(normal, viewDir)))));
            vec3 waveNormal = mat3(gbufferModelView) * worldWaveNormal;
            #else
            vec3 worldWaveNormal = worldNormal;
            vec3 waveNormal = normal;
            // material.f0 += 
            #endif



            // if(dot(waveNormal, viewDir) > 0.0){
            //     waveNormal = normal;
            // }

            // refraction
            #ifdef REFRACTION
                vec3 refractionNormal = inWater ? waveNormal : normal - waveNormal;

                vec3 refractedDir = normalize(refract(viewDir, refractionNormal, !inWater ? rcp(1.33) : 1.33)); // when in water it should be rcp(1.33) but unless I use the actual normal (which results in snell's window) this results in no refraction

                vec3 worldRefractedDir = mat3(gbufferModelViewInverse) * refractedDir;
                vec3 refractedViewPos = translucentViewPos + refractedDir * distance(translucentViewPos, opaqueViewPos);
                vec3 refractedPos = viewSpaceToScreenSpace(refractedViewPos);

                float refractedDepth = texture(depthtex2, refractedPos.xy).r;
                refractedViewPos = screenSpaceToViewSpace(vec3(refractedPos.xy, refractedDepth));

                if(texture(depthtex0, refractedPos.xy).r == 1.0){
                    dhOverride(refractedDepth, refractedViewPos, true);
                } else {
                    dhMask = false;
                }
                
                if(clamp01(refractedPos.xy) == refractedPos.xy && refractedDepth > translucentDepth){
                    color = texture(colortex0, refractedPos.xy);
                    opaqueDepth = texture(depthtex2, refractedPos.xy).r;
                    opaqueViewPos = refractedViewPos;
                } else if (inWater && refract(viewDir, refractionNormal, 1.33) != vec3(0.0)){
                    color.rgb = getSky(worldRefractedDir, true) * clamp01(smoothstep(13.5 / 15.0, 14.5 / 15.0, skyLightmap));
                    vec3 cloudTransmittance;
                    vec3 cloudScatter = getClouds(vec3(0.0), worldRefractedDir, cloudTransmittance) * clamp01(smoothstep(13.5 / 15.0, 14.5 / 15.0, skyLightmap));
                    color.rgb = color.rgb * cloudTransmittance + cloudScatter;
                } else if(inWater) {
                    totalInternalReflection = true;
                }

                if(refractedDir == vec3(0.0)){
                    totalInternalReflection = true;
                }
            #endif

            #ifdef PIXEL_LOCKED_LIGHTING
            if(isWater){
                translucentFeetPlayerPos = floor((translucentFeetPlayerPos + cameraPosition) * PIXEL_SIZE) / PIXEL_SIZE - cameraPosition;
                translucentViewPos = (gbufferModelView * vec4(translucentFeetPlayerPos, 1.0)).xyz;
            }   
            #endif



            // water fog when we're not in water
            if (!inWater){
                // so basically dh terrain doesn't get the shadow cast on it by water
                // since we have already shaded it, we can't really account for this properly
                // so we just add fog based on the distance between the terrain and the water's surface going towards the sun
                // it looks plausible
                // also I am lazy so this maths only works for water facing upward
                // which is like 90% of water anyway
                // and it still looks terrible because I can't tell terrain that's underwater not to use the lightmap
                // as a fallback for shadows (which is bad because it makes it really dark underwater)
                float dhFactor = 0.0;
                if(dhMask && worldNormal.y > 0.5){
                    float cost = dot(worldLightDir, vec3(0.0, 1.0, 0.0));
                    dhFactor = (translucentFeetPlayerPos.y - opaqueFeetPlayerPos.y) / cost;
                }


                color.rgb = waterFog(color.rgb, translucentViewPos, opaqueViewPos, dhFactor, vec3(sunVisibilitySmooth));
                
            }

            // SSR
            #ifdef SSR_JITTER
            float jitter = interleavedGradientNoise(floor(gl_FragCoord.xy), frameCounter);
            #else
            float jitter = 1.0;
            #endif
            vec3 reflectedDir = reflect(viewDir, waveNormal);
            vec3 reflectedPos = vec3(0.0);
            vec3 reflectedColor = vec3(0.0);

            vec3 scatter = vec3(0.0);

            #if REFLECTION_MODE > 0
                bool doReflections = true;
                #if defined INFINITE_OCEAN && !defined DISTANT_HORIZONS
                doReflections = doReflections && !infiniteOceanMask;
                #endif
            #else
                bool doReflections = false;
            #endif

            float fadeFactor = 0.0; // full sky reflection

            // note that we are incorrectly applying fog to reflections here
            // we do fog from the camera when we should really do fog from the reflection position
            // but it looks passable and is much easier

            // the following code is truly horrible
            // I am required to do it because newer AMD cards don't let you do ternary operations on samplers
            // making there NO WAY to conditionally select a sampler before passing it to a function
            // fuck you, AMD

            bool reflectionHit = doReflections;

            
            #ifdef DISTANT_HORIZONS
                if(dhMask){
                    reflectionHit = reflectionHit && rayIntersects(translucentViewPos, reflectedDir, SSR_STEPS, jitter, true, reflectedPos, dhDepthTex0, dhProjection);
                } else{
                    reflectionHit = reflectionHit && rayIntersects(translucentViewPos, reflectedDir, SSR_STEPS, jitter, true, reflectedPos, colortex6, combinedProjection);
                }

            #else
                reflectionHit = reflectionHit && rayIntersects(translucentViewPos, reflectedDir, SSR_STEPS, jitter, true, reflectedPos, depthtex0, gbufferProjection);
            #endif

            if(reflectionHit){

                reflectedColor = texture(colortex0, reflectedPos.xy).rgb;
                #ifdef DISTANT_HORIZONS
                    vec3 viewReflectedPos = screenSpaceToViewSpace(reflectedPos, dhMask ? dhProjectionInverse : combinedProjectionInverse);
                #else
                    vec3 viewReflectedPos = screenSpaceToViewSpace(reflectedPos);
                #endif

                vec3 playerReflectedPos = mat3(gbufferModelViewInverse) * viewReflectedPos;

                #ifdef ATMOSPHERIC_FOG
                    reflectedColor = atmosphericFog(reflectedColor, viewReflectedPos);
                #endif

                #ifdef CLOUDY_FOG
                    reflectedColor = cloudyFog(reflectedColor, playerReflectedPos, reflectedPos.z, vec3(sunVisibilitySmooth));
                #endif

                #ifdef FADE_REFLECTIONS
                    fadeFactor = 1.0 - smoothstep(0.9, 1.0, maxVec2(abs(reflectedPos.xy - 0.5)) * 2);
                #else
                    fadeFactor = 1.0;
                #endif
            }

            if(fadeFactor < 1.0){
                vec3 worldReflectedDir = mat3(gbufferModelViewInverse) * reflectedDir;
                vec3 skyReflection = getSky(worldReflectedDir, false);

                vec3 transmittance;
                vec3 cloudScatter = getClouds(translucentFeetPlayerPos, worldReflectedDir, transmittance);
                skyReflection = skyReflection * transmittance + cloudScatter;
                skyReflection *= skyLightmap;

                vec3 shadow = getShadowing(translucentFeetPlayerPos, waveNormal, vec2(skyLightmap), material, scatter);

                if(minVec3(shadow) > 0.0 && dot(waveNormal, lightDir) > 0.0){
                    skyReflection += max0(brdf(material, waveNormal, waveNormal, translucentViewPos, shadow, scatter) * weatherSunlightColor);
                }
                #ifdef CLOUDY_FOG
                vec3 playerReflectedPos = translucentFeetPlayerPos + worldReflectedDir * far;
                skyReflection = cloudyFog(skyReflection, playerReflectedPos, reflectedPos.z, vec3(1.0));
                #endif

                reflectedColor = mix(skyReflection, reflectedColor, fadeFactor);
            }

            

            vec3 fresnel = fresnel(material, dot(waveNormal, normalize(-translucentViewPos)));
            if(totalInternalReflection){
                fresnel = vec3(1.0);
            }

            color.rgb = mix(color.rgb, reflectedColor, fresnel);
        }

        // water fog when we're in water
        if (inWater){
            float distanceThroughWater;
            if(isWater){
                color.rgb = waterFog(color.rgb, vec3(0.0), translucentViewPos, vec3(sunVisibilitySmooth));
            } else {
               color.rgb = waterFog(color.rgb, vec3(0.0), opaqueViewPos, vec3(sunVisibilitySmooth));
            }
        }
    }

#endif