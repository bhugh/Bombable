#version 120

uniform sampler2D texture;
uniform float scattering;

void main()
{
    vec4 texel = texture2D(texture, gl_TexCoord[0].st);
    texel.a = smoothstep(0.0,0.1, texel.a);

    float illumination = length(gl_Color.rgb);
    texel = vec4 (0.1,0.1,0.1,texel.a);
    texel.a *= illumination;
    texel.a *=0.6 * smoothstep(0.5,0.8,scattering);
    texel.a = min(0.8, texel.a);

    vec4 fragColor = texel;
    gl_FragColor = fragColor;
}
