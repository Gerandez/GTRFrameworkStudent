//example of some shaders compiled
flat basic.vs flat.fs
texture basic.vs texture.fs
plain basic.vs plain.fs
skybox basic.vs skybox.fs
depth quad.vs depth.fs
multi basic.vs multi.fs
phong basic.vs phong.fs
gbuffer basic.vs gbuffer.fs
ssao quad.vs ssao.fs
tonemap quad.vs tonemap.fs
deferred_ambient quad.vs deferred_ambient.fs
deferred_light_volume basic.vs deferred_light_volume.fs

\color_space

vec3 degamma(vec3 color)
{
	return pow(max(color, vec3(0.0)), vec3(2.2));
}

vec3 gamma(vec3 color)
{
	return pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 tonemapACES(vec3 color)
{
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

\perturbNormal

// From https://github.com/glslify/glsl-perturb-normal/blob/master/cotangent-frame.glsl
mat3 cotangent_frame(vec3 N, vec3 p, vec2 uv)
{
	// get edge vectors of the pixel triangle
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	// solve the linear system
	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame 
	float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
	return mat3(T * invmax, B * invmax, N);
}

// assume N, the interpolated vertex normal and 
// WP the world position
vec3 perturbNormal(vec3 N, vec3 WP, vec2 uv, vec3 normal_pixel)
{
	mat3 TBN = cotangent_frame(N, WP, uv);
	return normalize(TBN * normal_pixel);
}

\brdf

const float PBR_PI = 3.14159265359;
const float PBR_EPSILON = 1e-4;

float saturate(float value)
{
	return clamp(value, 0.0, 1.0);
}

float DistributionGGX(vec3 N, vec3 H, float roughness)
{
	float a = roughness * roughness;
	float a2 = a * a;
	float NdotH = max(dot(N, H), 0.0);
	float NdotH2 = NdotH * NdotH;
	float denom = (NdotH2 * (a2 - 1.0) + 1.0);
	return a2 / max(PBR_PI * denom * denom, PBR_EPSILON);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
	float r = roughness + 1.0;
	float k = (r * r) / 8.0;
	return NdotV / max(NdotV * (1.0 - k) + k, PBR_EPSILON);
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
	float NdotV = max(dot(N, V), 0.0);
	float NdotL = max(dot(N, L), 0.0);
	float ggx1 = GeometrySchlickGGX(NdotV, roughness);
	float ggx2 = GeometrySchlickGGX(NdotL, roughness);
	return ggx1 * ggx2;
}

vec3 FresnelSchlick(float cosTheta, vec3 F0)
{
	return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

vec3 BRDF_PBR(vec3 N, vec3 V, vec3 L, vec3 albedo, float metallic, float roughness)
{
	float NdotL = max(dot(N, L), 0.0);
	float NdotV = max(dot(N, V), 0.0);
	if (NdotL <= 0.0 || NdotV <= 0.0)
		return vec3(0.0);

	vec3 H = normalize(V + L);
	float NdotH = max(dot(N, H), 0.0);
	float VdotH = max(dot(V, H), 0.0);

	vec3 F0 = mix(vec3(0.04), albedo, metallic);
	vec3 F = FresnelSchlick(VdotH, F0);
	float D = DistributionGGX(N, H, roughness);
	float G = GeometrySmith(N, V, L, roughness);

	vec3 numerator = D * G * F;
	float denominator = max(4.0 * NdotV * NdotL, PBR_EPSILON);
	vec3 specular = numerator / denominator;

	vec3 kS = F;
	vec3 kD = (1.0 - kS) * (1.0 - metallic);
	kD *= 1.0 / PBR_PI;

	return (kD * albedo + specular) * NdotL;
}

\basic.vs

#version 330 core

in vec3 a_vertex;
in vec3 a_normal;
in vec2 a_coord;
in vec4 a_color;

uniform vec3 u_camera_pos;

uniform mat4 u_model;
uniform mat4 u_viewprojection;

//this will store the color for the pixel shader
out vec3 v_position;
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_color;

uniform float u_time;

void main()
{	
	//calcule the normal in camera space (the NormalMatrix is like ViewMatrix but without traslation)
	v_normal = (u_model * vec4( a_normal, 0.0) ).xyz;
	
	//calcule the vertex in object space
	v_position = a_vertex;
	v_world_position = (u_model * vec4( v_position, 1.0) ).xyz;
	
	//store the color in the varying var to use it from the pixel shader
	v_color = a_color;

	//store the texture coordinates
	v_uv = a_coord;

	//calcule the position of the vertex using the matrices
	gl_Position = u_viewprojection * vec4( v_world_position, 1.0 );
}

\phong.vs

#version 330 core

in vec3 a_vertex;
in vec3 a_normal;
in vec2 a_coord;
in vec4 a_color;

uniform vec3 u_camera_pos;

uniform mat4 u_model;
uniform mat4 u_viewprojection;

out vec3 v_position;
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_color;

void main()
{	
	v_normal = mat3(transpose(inverse(u_model))) * a_normal;
	v_position = a_vertex;
	v_world_position = (u_model * vec4(v_position, 1.0)).xyz;
	v_color = a_color;
	v_uv = a_coord;
	gl_Position = u_viewprojection * vec4(v_world_position, 1.0);
}

\quad.vs

#version 330 core

in vec3 a_vertex;
in vec2 a_coord;
out vec2 v_uv;

void main()
{	
	v_uv = a_coord;
	gl_Position = vec4( a_vertex, 1.0 );
}


\flat.fs

#version 330 core

uniform vec4 u_color;

out vec4 FragColor;

void main()
{
	FragColor = u_color;
}


\plain.fs

#version 330 core

in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_alpha_cutoff;

out vec4 FragColor;

void main()
{
	vec4 color = texture(u_texture, v_uv);
	if(color.a < u_alpha_cutoff)
		discard;
	FragColor = vec4(0.0, 0.0, 0.0, 1.0);
}


\texture.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;

uniform vec4 u_color;
uniform sampler2D u_texture;
// 3.5: Multiple shadow maps
uniform sampler2D u_shadowmap0;
uniform sampler2D u_shadowmap1;
uniform sampler2D u_shadowmap2;
uniform sampler2D u_shadowmap3;
uniform float u_time;
uniform float u_alpha_cutoff;
// 3.5: Per-light shadow data
uniform int u_shadow_count;
uniform float u_shadow_bias[4];
uniform mat4 u_light_viewprojection[4];

out vec4 FragColor;

float readShadowDepth(int idx, vec2 uv)
{
	if(idx == 0)
		return texture(u_shadowmap0, uv).x;
	if(idx == 1)
		return texture(u_shadowmap1, uv).x;
	if(idx == 2)
		return texture(u_shadowmap2, uv).x;
	return texture(u_shadowmap3, uv).x;
}

void main()
{
	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	if(color.a < u_alpha_cutoff)
		discard;

   // 3.3 + 3.4.1: Shadow test
  float lit_lights = 0.0;
	if(u_shadow_count > 0)
	{
      for(int i = 0; i < u_shadow_count; ++i)
		{
         float light_visibility = 1.0;
			vec4 proj_pos = u_light_viewprojection[i] * vec4(v_world_position, 1.0);
			vec3 light_ndc = proj_pos.xyz / proj_pos.w;

			if(light_ndc.x >= -1.0 && light_ndc.x <= 1.0 && light_ndc.y >= -1.0 && light_ndc.y <= 1.0 && light_ndc.z >= -1.0 && light_ndc.z <= 1.0)
			{
              float real_depth = (proj_pos.z - u_shadow_bias[i]) / proj_pos.w;
				vec2 shadow_uv = light_ndc.xy * 0.5 + 0.5;
				float shadow_depth = readShadowDepth(i, shadow_uv);
				float current_depth = real_depth * 0.5 + 0.5;
				if(current_depth > shadow_depth)
					light_visibility = 0.0;
			}

			lit_lights += light_visibility;
		}
	}
	float shadow_factor = u_shadow_count > 0 ? (lit_lights / float(u_shadow_count)) : 1.0;

  FragColor = vec4(color.rgb * mix(0.35, 1.0, shadow_factor), color.a);
}


\phong.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_alpha_cutoff;
uniform float u_shininess;
uniform sampler2D u_normalmap;
uniform sampler2D u_metallic_roughness;
uniform bool u_has_metallic_roughness;
uniform float u_metallic_factor;
uniform float u_roughness_factor;

// Shadow map uniforms
uniform sampler2D u_shadowmap0;
uniform sampler2D u_shadowmap1;
uniform sampler2D u_shadowmap2;
uniform sampler2D u_shadowmap3;
uniform int u_shadow_count;
uniform float u_shadow_bias[4];
uniform mat4 u_light_viewprojection[4];

#include "perturbNormal"
#include "brdf"
#include "color_space"

// Shadow map functions
float readShadowDepth(int idx, vec2 uv)
{
	if(idx == 0)
		return texture(u_shadowmap0, uv).x;
	if(idx == 1)
		return texture(u_shadowmap1, uv).x;
	if(idx == 2)
		return texture(u_shadowmap2, uv).x;
	return texture(u_shadowmap3, uv).x;
}

float calculateShadow(int idx, vec3 world_pos)
{
	vec4 proj_pos = u_light_viewprojection[idx] * vec4(world_pos, 1.0);
	vec3 light_ndc = proj_pos.xyz / proj_pos.w;

	// Check if fragment is within light frustum
	if(light_ndc.x < -1.0 || light_ndc.x > 1.0 || light_ndc.y < -1.0 || light_ndc.y > 1.0 || light_ndc.z < -1.0 || light_ndc.z > 1.0)
		return 1.0; // Outside frustum, not in shadow

	vec2 shadow_uv = light_ndc.xy * 0.5 + 0.5;
	float shadow_depth = readShadowDepth(idx, shadow_uv);
	
	// Compare depth with bias
	float real_depth = (proj_pos.z - u_shadow_bias[idx]) / proj_pos.w;
	float current_depth = real_depth * 0.5 + 0.5;
	if(current_depth > shadow_depth)
		return 0.0; // In shadow

	return 1.0; // Not in shadow
}

uniform vec3 u_camera_pos;

// Light arrays
#define MAX_LIGHTS 8
#define LIGHT_POINT 1
#define LIGHT_SPOT 2
#define LIGHT_DIRECTIONAL 3

uniform int u_num_lights;
uniform int u_light_type[MAX_LIGHTS];
uniform vec3 u_light_pos[MAX_LIGHTS];
uniform vec3 u_light_dir[MAX_LIGHTS];
uniform vec3 u_light_color[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];
uniform float u_light_near[MAX_LIGHTS];
uniform float u_light_max[MAX_LIGHTS];
uniform vec2 u_light_cone[MAX_LIGHTS]; // x: inner angle (radians), y: outer angle (radians)

out vec4 FragColor;

void main()
{
	vec2 uv = v_uv;
	vec4 albedo = u_color;
	albedo *= texture(u_texture, v_uv);
	albedo.rgb = degamma(albedo.rgb);

	if(albedo.a < u_alpha_cutoff)
		discard;

	vec3 normal_pixel = vec3(0.5, 0.5, 1.0);
	if (textureSize(u_normalmap, 0).x > 1)
		normal_pixel = texture(u_normalmap, v_uv).xyz;

	normal_pixel = normal_pixel * 2.0 - 1.0;
	vec3 N = perturbNormal(normalize(v_normal), v_world_position, v_uv, normal_pixel);
	vec3 V = normalize(u_camera_pos - v_world_position);

	float ao = 1.0;
	float roughness = u_roughness_factor;
	float metallic = u_metallic_factor;
	if (u_has_metallic_roughness)
	{
		vec3 mr = texture(u_metallic_roughness, v_uv).rgb;
		ao = mr.r;
		roughness = max(mr.g * u_roughness_factor, 0.05);
		metallic = mr.b * u_metallic_factor;
	}
	else
	{
		roughness = max(u_roughness_factor, 0.05);
		metallic = clamp(u_metallic_factor, 0.0, 1.0);
	}

	vec3 ambient = vec3(0.03) * albedo.rgb * ao;
	vec3 direct = vec3(0.0);

	for (int i = 0; i < MAX_LIGHTS; i++)
	{
		if (i >= u_num_lights)
			break;

		vec3 light_dir;
		float attenuation = 1.0;

		if (u_light_type[i] == LIGHT_DIRECTIONAL)
		{
			light_dir = normalize(-u_light_dir[i]);
		}
		else if (u_light_type[i] == LIGHT_SPOT)
		{
			vec3 L = u_light_pos[i] - v_world_position;
			float dist = length(L);
			light_dir = L / max(dist, PBR_EPSILON);

			if (dist > u_light_max[i] || dist < u_light_near[i])
				continue;

			float cos_inner = cos(u_light_cone[i].x);
			float cos_outer = cos(u_light_cone[i].y);
			float spot_effect = dot(-light_dir, normalize(u_light_dir[i]));
			if (spot_effect < cos_outer)
				continue;

			float spot_atten = clamp((spot_effect - cos_outer) / max(cos_inner - cos_outer, PBR_EPSILON), 0.0, 1.0);
			attenuation = spot_atten / max(dist * dist, PBR_EPSILON);
		}
		else
		{
			vec3 L = u_light_pos[i] - v_world_position;
			float dist = length(L);
			light_dir = L / max(dist, PBR_EPSILON);

			if (dist > u_light_max[i] || dist < u_light_near[i])
				continue;

			attenuation = 1.0 / max(dist * dist, PBR_EPSILON);
		}

		vec3 radiance = degamma(u_light_color[i]) * u_light_intensity[i] * attenuation;
		direct += BRDF_PBR(N, V, light_dir, albedo.rgb, metallic, roughness) * radiance;
	}

	float shadow_factor = 1.0;
	if (u_shadow_count > 0)
	{
		float total_visibility = 0.0;
		for (int i = 0; i < u_shadow_count; i++)
		{
			total_visibility += calculateShadow(i, v_world_position);
		}
		shadow_factor = total_visibility / float(u_shadow_count);
	}

	vec3 final_color = ambient + direct * shadow_factor;
	FragColor = vec4(gamma(final_color), albedo.a);
}


\skybox.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;

uniform samplerCube u_texture;
uniform vec3 u_camera_position;
out vec4 FragColor;

void main()
{
	vec3 E = v_world_position - u_camera_position;
	vec4 color = texture( u_texture, E );
	FragColor = color;
}


\multi.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

layout(location = 0) out vec4 FragColor;
layout(location = 1) out vec4 NormalColor;

void main()
{
	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, uv );

	if(color.a < u_alpha_cutoff)
		discard;

	vec3 N = normalize(v_normal);

	FragColor = color;
	NormalColor = vec4(N,1.0);
}

\gbuffer.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform sampler2D u_normalmap;
uniform sampler2D u_metallic_roughness;
uniform bool u_has_normalmap;
uniform bool u_has_metallic_roughness;
uniform float u_metallic_factor;
uniform float u_roughness_factor;
uniform float u_alpha_cutoff;

layout(location = 0) out vec4 gbuffer_albedo;
layout(location = 1) out vec4 gbuffer_normal;
layout(location = 2) out vec4 gbuffer_metallic_roughness;

#include "color_space"

mat3 cotangent_frame(vec3 N, vec3 p, vec2 uv)
{
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);
	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
	return mat3(T * invmax, B * invmax, N);
}

vec3 perturbNormal(vec3 N, vec3 WP, vec2 uv, vec3 normal_pixel)
{
	mat3 TBN = cotangent_frame(N, WP, uv);
	return normalize(TBN * normal_pixel);
}

void main()
{
	vec4 color = u_color * texture(u_texture, v_uv);
	if(color.a < u_alpha_cutoff)
		discard;
	color.rgb = degamma(color.rgb);

	vec3 N = normalize(v_normal);
	if(u_has_normalmap)
	{
		vec3 normal_pixel = texture(u_normalmap, v_uv).xyz * 2.0 - 1.0;
		N = perturbNormal(N, v_world_position, v_uv, normal_pixel);
	}

	float ao = 1.0;
	float roughness = u_roughness_factor;
	float metallic = u_metallic_factor;
	if (u_has_metallic_roughness)
	{
		vec3 mr = texture(u_metallic_roughness, v_uv).rgb;
		ao = mr.r;
		roughness = mr.g;
		metallic = mr.b;
	}

	gbuffer_albedo = color;
	gbuffer_normal = vec4(N * 0.5 + 0.5, 1.0);
	gbuffer_metallic_roughness = vec4(ao, roughness, metallic, 1.0);
}

\deferred_ambient.fs

#version 330 core

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_metallic_roughness;
uniform sampler2D u_gbuffer_depth;
uniform sampler2D u_ssao_texture;
uniform bool u_ssao_enabled;
uniform vec2 u_res_inv;
uniform mat4 u_inv_vp_mat;
uniform vec3 u_camera_pos;
uniform vec3 u_ambient_light;
#include "brdf"
#include "color_space"

uniform sampler2D u_shadowmap0;
uniform sampler2D u_shadowmap1;
uniform sampler2D u_shadowmap2;
uniform sampler2D u_shadowmap3;
uniform int u_shadow_count;
uniform float u_shadow_bias[4];
uniform mat4 u_light_viewprojection[4];

#define MAX_LIGHTS 8
#define LIGHT_DIRECTIONAL 3

uniform int u_num_lights;
uniform int u_light_type[MAX_LIGHTS];
uniform vec3 u_light_pos[MAX_LIGHTS];
uniform vec3 u_light_dir[MAX_LIGHTS];
uniform vec3 u_light_color[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];

out vec4 FragColor;

vec3 reconstructWorldPosition(vec2 uv, float depth)
{
	vec4 clip_coords = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 world_pos = u_inv_vp_mat * clip_coords;
	return world_pos.xyz / world_pos.w;
}

float readShadowDepth(int idx, vec2 uv)
{
	if(idx == 0) return texture(u_shadowmap0, uv).x;
	if(idx == 1) return texture(u_shadowmap1, uv).x;
	if(idx == 2) return texture(u_shadowmap2, uv).x;
	return texture(u_shadowmap3, uv).x;
}

float calculateShadow(int idx, vec3 world_pos)
{
	vec4 proj_pos = u_light_viewprojection[idx] * vec4(world_pos, 1.0);
	vec3 light_ndc = proj_pos.xyz / proj_pos.w;
	if(light_ndc.x < -1.0 || light_ndc.x > 1.0 || light_ndc.y < -1.0 || light_ndc.y > 1.0 || light_ndc.z < -1.0 || light_ndc.z > 1.0)
		return 1.0;

	vec2 shadow_uv = light_ndc.xy * 0.5 + 0.5;
	float shadow_depth = readShadowDepth(idx, shadow_uv);
	float current_depth = light_ndc.z * 0.5 + 0.5;
	return current_depth > shadow_depth + u_shadow_bias[idx] ? 0.0 : 1.0;
}

float getShadowFactor(vec3 world_pos)
{
	if(u_shadow_count == 0)
		return 1.0;

	float total_visibility = 0.0;
	for(int i = 0; i < u_shadow_count; ++i)
		total_visibility += calculateShadow(i, world_pos);
	return total_visibility / float(u_shadow_count);
}

void main()
{
	vec2 uv = gl_FragCoord.xy * u_res_inv;
	float depth = texture(u_gbuffer_depth, uv).r;
	if(depth >= 0.999999)
		discard;

	vec4 albedo = texture(u_gbuffer_color, uv);
	vec3 N = normalize(texture(u_gbuffer_normal, uv).xyz * 2.0 - 1.0);
	vec3 mr = texture(u_gbuffer_metallic_roughness, uv).rgb;
	float ao = mr.r;
	if(u_ssao_enabled)
		ao *= texture(u_ssao_texture, uv).r;
	float roughness = max(mr.g, 0.05);
	float metallic = mr.b;
	vec3 world_pos = reconstructWorldPosition(uv, depth);
	vec3 V = normalize(u_camera_pos - world_pos);
	vec3 direct = vec3(0.0);

	for(int i = 0; i < MAX_LIGHTS; ++i)
	{
		if(i >= u_num_lights)
			break;
		if(u_light_type[i] != LIGHT_DIRECTIONAL)
			continue;

		vec3 L = normalize(-u_light_dir[i]);
		vec3 radiance = degamma(u_light_color[i]) * u_light_intensity[i];
		direct += BRDF_PBR(N, V, L, albedo.rgb, metallic, roughness) * radiance;
	}

	vec3 ambient = albedo.rgb * degamma(u_ambient_light) * ao;
	FragColor = vec4(ambient + direct * getShadowFactor(world_pos), albedo.a);
}

\ssao.fs

#version 330 core

uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;
uniform vec2 u_res_inv;
uniform vec2 u_ssao_res_inv;
uniform mat4 u_inv_vp_mat;
uniform mat4 u_viewprojection;
uniform vec3 u_samples[64];
uniform int u_num_samples;
uniform float u_sample_radius;
uniform bool u_hemisphere;

out vec4 FragColor;

vec3 reconstructWorldPosition(vec2 uv, float depth)
{
	vec4 clip_coords = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 world_pos = u_inv_vp_mat * clip_coords;
	return world_pos.xyz / world_pos.w;
}

mat3 buildNormalBasis(vec3 N)
{
	vec3 v = vec3(0.0, 1.0, 0.0);
	if(abs(dot(v, N)) > 0.99)
		v = vec3(1.0, 0.0, 0.0);

	vec3 T = normalize(v - N * dot(v, N));
	vec3 B = cross(N, T);
	return mat3(T, B, N);
}

void main()
{
	vec2 uv = gl_FragCoord.xy * u_ssao_res_inv;
	float depth = texture(u_gbuffer_depth, uv).r;
	if(depth >= 0.999999)
	{
		FragColor = vec4(1.0);
		return;
	}

	vec3 world_pos = reconstructWorldPosition(uv, depth);
	vec3 normal = normalize(texture(u_gbuffer_normal, uv).xyz * 2.0 - 1.0);
	mat3 rotmat = buildNormalBasis(normal);

	float occlusion = 0.0;
	for(int i = 0; i < 64; ++i)
	{
		if(i >= u_num_samples)
			break;

		vec3 sample_dir = u_samples[i];
		if(u_hemisphere)
			sample_dir = rotmat * sample_dir;

		vec3 sample_pos = world_pos + sample_dir * u_sample_radius;
		vec4 projected_sample = u_viewprojection * vec4(sample_pos, 1.0);
		vec3 sample_ndc = projected_sample.xyz / projected_sample.w;

		if(sample_ndc.x < -1.0 || sample_ndc.x > 1.0 || sample_ndc.y < -1.0 || sample_ndc.y > 1.0 || sample_ndc.z < -1.0 || sample_ndc.z > 1.0)
			continue;

		vec2 sample_uv = sample_ndc.xy * 0.5 + 0.5;
		float sample_depth = texture(u_gbuffer_depth, sample_uv).r;
		float sample_depth_projected = sample_ndc.z * 0.5 + 0.5;

		if(sample_depth < sample_depth_projected - 0.001)
			occlusion += 1.0;
	}

	float ao = 1.0 - occlusion / max(float(u_num_samples), 1.0);
	FragColor = vec4(vec3(ao), 1.0);
}

\deferred_light_volume.fs

#version 330 core

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_metallic_roughness;
uniform sampler2D u_gbuffer_depth;
uniform vec2 u_res_inv;
uniform mat4 u_inv_vp_mat;
uniform vec3 u_camera_pos;
#include "brdf"

uniform sampler2D u_shadowmap0;
uniform sampler2D u_shadowmap1;
uniform sampler2D u_shadowmap2;
uniform sampler2D u_shadowmap3;
uniform int u_shadow_count;
uniform float u_shadow_bias[4];
uniform mat4 u_light_viewprojection[4];

#define MAX_LIGHTS 8
#define LIGHT_POINT 1
#define LIGHT_SPOT 2

uniform int u_num_lights;
uniform int u_light_index;
uniform int u_light_type[MAX_LIGHTS];
uniform vec3 u_light_pos[MAX_LIGHTS];
uniform vec3 u_light_dir[MAX_LIGHTS];
uniform vec3 u_light_color[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];
uniform float u_light_near[MAX_LIGHTS];
uniform float u_light_max[MAX_LIGHTS];
uniform vec2 u_light_cone[MAX_LIGHTS];

out vec4 FragColor;

#include "color_space"

vec3 reconstructWorldPosition(vec2 uv, float depth)
{
	vec4 clip_coords = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 world_pos = u_inv_vp_mat * clip_coords;
	return world_pos.xyz / world_pos.w;
}

float readShadowDepth(int idx, vec2 uv)
{
	if(idx == 0) return texture(u_shadowmap0, uv).x;
	if(idx == 1) return texture(u_shadowmap1, uv).x;
	if(idx == 2) return texture(u_shadowmap2, uv).x;
	return texture(u_shadowmap3, uv).x;
}

float calculateShadow(int idx, vec3 world_pos)
{
	vec4 proj_pos = u_light_viewprojection[idx] * vec4(world_pos, 1.0);
	vec3 light_ndc = proj_pos.xyz / proj_pos.w;
	if(light_ndc.x < -1.0 || light_ndc.x > 1.0 || light_ndc.y < -1.0 || light_ndc.y > 1.0 || light_ndc.z < -1.0 || light_ndc.z > 1.0)
		return 1.0;

	vec2 shadow_uv = light_ndc.xy * 0.5 + 0.5;
	float shadow_depth = readShadowDepth(idx, shadow_uv);
	float current_depth = light_ndc.z * 0.5 + 0.5;
	return current_depth > shadow_depth + u_shadow_bias[idx] ? 0.0 : 1.0;
}

float getShadowFactor(vec3 world_pos)
{
	if(u_shadow_count == 0)
		return 1.0;

	float total_visibility = 0.0;
	for(int i = 0; i < u_shadow_count; ++i)
		total_visibility += calculateShadow(i, world_pos);
	return total_visibility / float(u_shadow_count);
}

void main()
{
	vec2 uv = gl_FragCoord.xy * u_res_inv;
	float depth = texture(u_gbuffer_depth, uv).r;
	if(depth >= 0.999999)
		discard;

	int i = u_light_index;
	if(i >= u_num_lights || (u_light_type[i] != LIGHT_POINT && u_light_type[i] != LIGHT_SPOT))
		discard;

	vec4 albedo = texture(u_gbuffer_color, uv);
	vec3 N = normalize(texture(u_gbuffer_normal, uv).xyz * 2.0 - 1.0);
	vec3 mr = texture(u_gbuffer_metallic_roughness, uv).rgb;
	float roughness = max(mr.g, 0.05);
	float metallic = mr.b;
	vec3 world_pos = reconstructWorldPosition(uv, depth);
	vec3 V = normalize(u_camera_pos - world_pos);

	vec3 light_vec = u_light_pos[i] - world_pos;
	float dist = length(light_vec);
	if(dist > u_light_max[i] || dist < u_light_near[i])
		discard;

	vec3 L = light_vec / max(dist, PBR_EPSILON);
	float attenuation = 1.0 / (1.0 + 0.09 * dist + 0.032 * dist * dist);

	if(u_light_type[i] == LIGHT_SPOT)
	{
		float cos_inner = cos(u_light_cone[i].x);
		float cos_outer = cos(u_light_cone[i].y);
		float spot_effect = dot(L, normalize(u_light_dir[i]));
		if(spot_effect < cos_outer)
			discard;
		attenuation *= clamp((spot_effect - cos_outer) / max(cos_inner - cos_outer, PBR_EPSILON), 0.0, 1.0);
	}

	vec3 radiance = degamma(u_light_color[i]) * u_light_intensity[i] * attenuation;
	vec3 color = BRDF_PBR(N, V, L, albedo.rgb, metallic, roughness) * radiance;
	FragColor = vec4(color * getShadowFactor(world_pos), 1.0);
}


\tonemap.fs

#version 330 core

uniform sampler2D u_texture;
uniform float u_exposure;
uniform bool u_enabled;

in vec2 v_uv;
out vec4 FragColor;

#include "color_space"

void main()
{
	vec4 hdr_color = texture(u_texture, v_uv);
	vec3 color = hdr_color.rgb * u_exposure;
	if(u_enabled)
		color = tonemapACES(color);
	FragColor = vec4(gamma(color), hdr_color.a);
}

\depth.fs

#version 330 core

uniform vec2 u_camera_nearfar;
uniform sampler2D u_texture; //depth map
in vec2 v_uv;
out vec4 FragColor;

void main()
{
	float n = u_camera_nearfar.x;
	float f = u_camera_nearfar.y;
	float z = texture(u_texture,v_uv).x;
	if( n == 0.0 && f == 1.0 )
		FragColor = vec4(z);
	else
		FragColor = vec4( n * (z + 1.0) / (f + n - z * (f - n)) );
}


\instanced.vs

#version 330 core

in vec3 a_vertex;
in vec3 a_normal;
in vec2 a_coord;

in mat4 u_model;

uniform vec3 u_camera_pos;

uniform mat4 u_viewprojection;

//this will store the color for the pixel shader
out vec3 v_position;
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_uv;

void main()
{	
	//calcule the normal in camera space (the NormalMatrix is like ViewMatrix but without traslation)
	v_normal = (u_model * vec4( a_normal, 0.0) ).xyz;
	
	//calcule the vertex in object space
	v_position = a_vertex;
	v_world_position = (u_model * vec4( a_vertex, 1.0) ).xyz;
	
	//store the texture coordinates
	v_uv = a_coord;

	//calcule the position of the vertex using the matrices
	gl_Position = u_viewprojection * vec4( v_world_position, 1.0 );
}
