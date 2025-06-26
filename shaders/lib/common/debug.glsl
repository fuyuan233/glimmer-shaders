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

#ifndef DEBUG_GLSL
#define DEBUG_GLSL

#ifdef DEBUG_ENABLE
#endif

#if defined DEBUG_ENABLE && defined fsh
layout(rgba8) uniform image2D debug;

void show(vec4 x) {
  imageStore(debug, ivec2(gl_FragCoord.xy), x);
}

void show(vec3 x) {
  show(vec4(x, 1.0));
}

void show(vec2 x) {
  show(vec3(x, 0.0));
}

void show(float x) {
  show(vec3(x));
}

void show(bool x) {
  show(float(x));
}

#else
void show(vec4 x) {}

void show(vec3 x) {}

void show(vec2 x) {}

void show(float x) {}

void show(bool x) {}
#endif

#endif // DEBUG_GLSL
