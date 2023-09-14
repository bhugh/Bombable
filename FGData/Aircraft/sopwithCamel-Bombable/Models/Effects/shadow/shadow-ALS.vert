// -*-C++-*-


#version 120

uniform float hazeLayerAltitude;
uniform float terminator;
uniform float terrain_alt; 
uniform float avisibility;
uniform float visibility;
uniform float overcast;
uniform float ground_scattering;
uniform float eye_alt;
uniform float moonlight;
uniform float alt_agl;
uniform float gear_clearance;

const float EarthRadius = 5800000.0;
const float terminator_width = 200000.0;

float light_func (in float x, in float a, in float b, in float c, in float d, in float e)
{

if (x < -15.0) {return 0.0;}

return e / pow((1.0 + a * exp(-b * (x-c)) ),(1.0/d));
}

void main()
{

   
    gl_TexCoord[0] = gl_TextureMatrix[0] * gl_MultiTexCoord0;

    vec4 ep = gl_ModelViewMatrixInverse * vec4(0.0,0.0,0.0,1.0);
    vec3 relPos = gl_Vertex.xyz - ep.xyz;


    // compute the strength of light
    float vertex_alt = max(gl_Vertex.z,100.0);
    float scattering = ground_scattering + (1.0 - ground_scattering) * smoothstep(hazeLayerAltitude -100.0, hazeLayerAltitude + 100.0, vertex_alt); 
    vec3 lightFull = (gl_ModelViewMatrixInverse * gl_LightSource[0].position).xyz;
    vec3 lightHorizon = normalize(vec3(lightFull.x,lightFull.y, 0.0));
    float yprime = -dot(relPos, lightHorizon);
    float yprime_alt = yprime - sqrt(2.0 * EarthRadius * vertex_alt);
    float earthShade = 0.6 * (1.0 - smoothstep(-terminator_width+ terminator, terminator_width + terminator, yprime_alt)) + 0.4;
    float lightArg = (terminator-yprime_alt)/100000.0;
    vec4 light_diffuse;
    light_diffuse.b = light_func(lightArg, 1.330e-05, 0.264, 3.827, 1.08e-05, 1.0);
    light_diffuse.g = light_func(lightArg, 3.931e-06, 0.264, 3.827, 7.93e-06, 1.0);
    light_diffuse.r = light_func(lightArg, 8.305e-06, 0.161, 3.827, 3.04e-05, 1.0);
    light_diffuse.a = 1.0;
    light_diffuse = light_diffuse * scattering;
    float shade_depth =  1.0 * smoothstep (0.6,0.95,ground_scattering) * (1.0-smoothstep(0.1,0.5,overcast)) * smoothstep(0.4,1.5,earthShade);

    light_diffuse.rgb = light_diffuse.rgb * (1.0 + 1.2 * shade_depth);


    // project the shadow onto the ground
    vec4 pos = gl_Vertex;
    pos.z-=0.95 * alt_agl-0.1;
    pos.xy -= lightFull.xy * 0.95* alt_agl/lightFull.z;

    // enlargen the shadow for low light
    if (dot(pos.xy, lightHorizon.xy)<0.0)
	{
	pos.xy -= lightFull.xy * gear_clearance/lightFull.z;
	}

   
    gl_Position =  gl_ModelViewProjectionMatrix * pos;

    gl_FrontColor = light_diffuse;
    gl_BackColor = gl_FrontColor;
}
