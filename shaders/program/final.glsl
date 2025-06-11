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
    #include "/lib/post/tonemap.glsl"
    #include "/lib/post/processing.glsl"

    in vec2 texcoord;

    uniform sampler2D debugtex;

    layout(location = 0) out vec4 color;

    void main() {
        color = texture(colortex0, texcoord);

        #ifdef BLOOM

        vec3 bloom = texture(colortex2, texcoord).rgb;

        float rain = texture(colortex5, texcoord).r;
        color.rgb = mix(color.rgb, bloom, clamp01(0.01 * BLOOM_STRENGTH + rain * 0.1 + wetness * 0.05 + blindness));
        color.rgb *= (1.0 - 0.8 * blindness);
        #endif

        color.rgb *= (1.0 - 0.95 * blindness);

        color.rgb *= 2.0;
        color.rgb = tonemap(color.rgb);

        color = postProcess(color);

        #ifdef DEBUG_ENABLE
        color = texture(debugtex, texcoord);
        #endif
    }

#endif