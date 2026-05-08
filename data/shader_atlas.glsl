//example of some shaders compiled
flat basic.vs flat.fs
texture basic.vs texture.fs
plain basic.vs plain.fs
skybox basic.vs skybox.fs
depth quad.vs depth.fs
multi basic.vs multi.fs
phong basic.vs phong.fs
gbuffer basic.vs gbuffer.fs
deferred_ambient quad.vs deferred_ambient.fs
deferred_light_volume basic.vs deferred_light_volume.fs

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

// Shadow map uniforms
uniform sampler2D u_shadowmap0;
uniform sampler2D u_shadowmap1;
uniform sampler2D u_shadowmap2;
uniform sampler2D u_shadowmap3;
uniform int u_shadow_count;
uniform float u_shadow_bias[4];
uniform mat4 u_light_viewprojection[4];

// Perturb normal functions (from cg_stdskybox)
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

	if(albedo.a < u_alpha_cutoff)
		discard;

	// Sample normal map and perturb normal for tangent space
	vec3 normal_pixel = vec3(0.5, 0.5, 1.0); // default normal

	if (textureSize(u_normalmap, 0).x > 1)
		normal_pixel = texture(u_normalmap, v_uv).xyz;

	normal_pixel = normal_pixel * 2.0 - 1.0;
	vec3 N = perturbNormal(normalize(v_normal), v_world_position, v_uv, normal_pixel);
	vec3 V = normalize(u_camera_pos - v_world_position);

	// Ambient (indirect) - simple approximation
	vec3 ambient = 0.1 * albedo.rgb;
	vec3 total_diffuse = vec3(0.0);
	vec3 total_specular = vec3(0.0);

	// Iterate through all lights
	for (int i = 0; i < MAX_LIGHTS; i++)
	{
		if (i >= u_num_lights)
			break;

		vec3 light_dir;
		float attenuation = 1.0;

		if (u_light_type[i] == LIGHT_DIRECTIONAL)
		{
			// Directional light: use direction, no attenuation
			light_dir = normalize(-u_light_dir[i]); // Direction points FROM light TO scene
		}
		else if (u_light_type[i] == LIGHT_SPOT)
		{
			// Spot light: calculate direction from position
			vec3 L = u_light_pos[i] - v_world_position;
			float dist = length(L);
			light_dir = L / dist;

			// Check if light is within range
			if (dist > u_light_max[i] || dist < u_light_near[i])
				continue;

			float cos_inner = cos(u_light_cone[i].x);
			float cos_outer = cos(u_light_cone[i].y);
			float spot_effect = dot(-light_dir, normalize(u_light_dir[i]));

			// El coseno exterior es MENOR que el interior (ej. cos(45º) < cos(10º))
			if (spot_effect < cos_outer)
				continue;

			// Interpolar entre el cono exterior y el interior
			float spot_atten = clamp((spot_effect - cos_outer) / (cos_inner - cos_outer), 0.0, 1.0);

			// Atenuación final (distancia + cono)
			attenuation = spot_atten / (dist * dist);

		}
		else // LIGHT_POINT
		{
			// Point light: calculate direction from position
			vec3 L = u_light_pos[i] - v_world_position;
			float dist = length(L);
			light_dir = L / dist;

			// Check if light is within range
			if (dist > u_light_max[i] || dist < u_light_near[i])
				continue;

			// Quadratic attenuation
			attenuation = 1.0 / (dist * dist);
		}

		// Diffuse - invariant to camera position
		float diff = max(dot(N, light_dir), 0.0);
		total_diffuse += diff * albedo.rgb * u_light_color[i] * u_light_intensity[i] * attenuation;

		// Specular - dependent on view position
		vec3 R = reflect(-light_dir, N);
		float spec = pow(max(dot(V, R), 0.0), u_shininess);
		total_specular += spec * u_light_color[i] * u_light_intensity[i] * attenuation;
	}

	// Apply shadow factor to lighting
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

	// Final color: ambient + diffuse + specular (with shadow)
	vec3 final_color = ambient + (total_diffuse + total_specular) * shadow_factor;

	FragColor = vec4(final_color, albedo.a);
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
uniform float u_alpha_cutoff;
uniform bool u_has_normalmap;

layout(location = 0) out vec4 gbuffer_albedo;
layout(location = 1) out vec4 gbuffer_normal;

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

	vec3 N = normalize(v_normal);
	if(u_has_normalmap)
	{
		vec3 normal_pixel = texture(u_normalmap, v_uv).xyz * 2.0 - 1.0;
		N = perturbNormal(N, v_world_position, v_uv, normal_pixel);
	}

	gbuffer_albedo = color;
	gbuffer_normal = vec4(N * 0.5 + 0.5, 1.0);
}

\deferred_ambient.fs

#version 330 core

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;
uniform vec2 u_res_inv;
uniform mat4 u_inv_vp_mat;
uniform vec3 u_camera_pos;
uniform vec3 u_ambient_light;

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
		float diff = max(dot(N, L), 0.0);
		vec3 R = reflect(-L, N);
		float spec = pow(max(dot(V, R), 0.0), 32.0);
		direct += (diff * albedo.rgb + spec) * u_light_color[i] * u_light_intensity[i];
	}

	FragColor = vec4(albedo.rgb * u_ambient_light + direct * getShadowFactor(world_pos), albedo.a);
}

\deferred_light_volume.fs

#version 330 core

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;
uniform vec2 u_res_inv;
uniform mat4 u_inv_vp_mat;
uniform vec3 u_camera_pos;

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
	vec3 world_pos = reconstructWorldPosition(uv, depth);
	vec3 V = normalize(u_camera_pos - world_pos);

	vec3 light_vec = u_light_pos[i] - world_pos;
	float dist = length(light_vec);
	if(dist > u_light_max[i] || dist < u_light_near[i])
		discard;

	vec3 L = light_vec / dist;
	float attenuation = 1.0 / (1.0 + 0.09 * dist + 0.032 * dist * dist);

	if(u_light_type[i] == LIGHT_SPOT)
	{
		float cos_inner = cos(u_light_cone[i].x);
		float cos_outer = cos(u_light_cone[i].y);
		float spot_effect = dot(L, normalize(u_light_dir[i]));
		if(spot_effect < cos_outer)
			discard;
		attenuation *= clamp((spot_effect - cos_outer) / (cos_inner - cos_outer), 0.0, 1.0);
	}

	float diff = max(dot(N, L), 0.0);
	vec3 R = reflect(-L, N);
	float spec = pow(max(dot(V, R), 0.0), 32.0);
	vec3 color = (diff * albedo.rgb + spec) * u_light_color[i] * u_light_intensity[i] * attenuation;
	FragColor = vec4(color * getShadowFactor(world_pos), 1.0);
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
