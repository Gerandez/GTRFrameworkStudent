#include "renderer.h"

#include <algorithm> //sort

#include "camera.h"
#include "../gfx/gfx.h"
#include "../gfx/shader.h"
#include "../gfx/mesh.h"
#include "../gfx/texture.h"
#include "../gfx/fbo.h"
#include "../pipeline/prefab.h"
#include "../pipeline/material.h"
#include "../pipeline/animation.h"
#include "../utils/utils.h"
#include "../extra/hdre.h"
#include "../core/ui.h"

#include "scene.h"

using namespace SCN;

//some globals
GFX::Mesh sphere;

namespace {
	// 3.5 EXTRA: Frustum culling + recursive node traversal
	void collectRenderCallsFromNode(
		SCN::Node* node,
		const Matrix44& parent_model,
		Camera* camera,
		std::vector<SCN::RenderCall>& render_calls)
	{
		if (!node)
			return;

		Matrix44 global_model = node->model * parent_model;

		if (node->visible && node->mesh && node->material)
		{
			BoundingBox world_box = transformBoundingBox(global_model, node->mesh->box);
			bool inside_frustum = !camera || camera->testBoxInFrustum(world_box.center, world_box.halfsize) != CLIP_OUTSIDE;

			if (inside_frustum)
			{
				SCN::RenderCall call;
				call.mesh = node->mesh;
				call.model = global_model;
				call.material = node->material;
				call.distance_to_camera = camera ? camera->eye.distance(global_model.getTranslation()) : 0.0f;
				render_calls.push_back(call);
			}
		}

		for (size_t i = 0; i < node->children.size(); ++i)
			collectRenderCallsFromNode(node->children[i], global_model, camera, render_calls);
	}
}

Renderer::Renderer(const char* shader_atlas_filename)
{
	render_wireframe = false;
	render_boundaries = false;
<<<<<<< Updated upstream

	// 3.4: Shadow error mitigation controls
	shadow_front_face_culling = true;
	shadow_bias = 0.001f;

=======
	multipass_rendering = false;
>>>>>>> Stashed changes
	scene = nullptr;
	skybox_cubemap = nullptr;

   // 3.5: Reset per-frame shadow containers
	shadow_viewprojections.clear();
	shadow_biases.clear();

	if (!GFX::Shader::LoadAtlas(shader_atlas_filename))
		exit(1);
	GFX::checkGLErrors();

	// 3.1: Create depth shadow map FBOs
	shadowmap_fbos.resize(MAX_SHADOW_LIGHTS);
	for (int i = 0; i < MAX_SHADOW_LIGHTS; ++i)
	{
		shadowmap_fbos[i] = new GFX::FBO();
		shadowmap_fbos[i]->setDepthOnly(SHADOWMAP_SIZE, SHADOWMAP_SIZE);
	}

	sphere.createSphere(1.0f);
	sphere.uploadToVRAM();
}

void Renderer::setupScene()
{
	if (scene->skybox_filename.size())
		skybox_cubemap = GFX::Texture::Get(std::string(scene->base_folder + "/" + scene->skybox_filename).c_str());
	else
		skybox_cubemap = nullptr;
}

void Renderer::parseSceneEntities(SCN::Scene* scene, Camera* cam)
{
	// HERE =====================
	// TODO: GENERATE RENDERABLES
	// ==========================

	// 3.2: Parsing the scene to generate render calls
	render_calls.clear();
	enabled_lights.clear();

	if (!scene)
		return;

	for (size_t i = 0; i < scene->entities.size(); ++i)
	{
		BaseEntity* entity = scene->entities[i];
		if (!entity || !entity->visible)
			continue;

		if (entity->getType() == SCN::eEntityType::PREFAB)
		{
			PrefabEntity* prefab_entity = (PrefabEntity*)entity;
			collectRenderCallsFromNode(&prefab_entity->root, Matrix44::IDENTITY, cam, render_calls);
		}
		else if (entity->getType() == SCN::eEntityType::LIGHT)
		{
			LightEntity* light_entity = (LightEntity*)entity;
			enabled_lights.push_back(light_entity);
		}
	}
}

void Renderer::renderScene(SCN::Scene* scene, Camera* camera)
{
	this->scene = scene;
	setupScene();

	// 3.2.2: Generate all theshadow maps
	renderShadowMap(scene);
	if (camera)
		camera->enable();

	parseSceneEntities(scene, camera);

	//set the clear color (the background color)
	glClearColor(scene->background_color.x, scene->background_color.y, scene->background_color.z, 1.0);

	// Clear the color and the depth buffer
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	GFX::checkGLErrors();

	//render skybox
	if(skybox_cubemap)
		renderSkybox(skybox_cubemap);

	// HERE =====================
	// TODO: RENDER RENDERABLES
	// ==========================

	// 3.4: Order render calls by transparency mode and distance
	std::sort(render_calls.begin(), render_calls.end(), [](const SCN::RenderCall& a, const SCN::RenderCall& b) {
		bool a_blend = a.material->alpha_mode == SCN::eAlphaMode::BLEND;
		bool b_blend = b.material->alpha_mode == SCN::eAlphaMode::BLEND;

		if (a_blend != b_blend)
			return !a_blend; // Opaque first

		if (a_blend)
			return a.distance_to_camera > b.distance_to_camera; // Transparent far to near

		return a.distance_to_camera < b.distance_to_camera; // Opaque near to far
	});

	// 3.3: Render all generated render calls
	for (size_t i = 0; i < render_calls.size(); ++i)
		renderMeshWithMaterial(render_calls[i].model, render_calls[i].mesh, render_calls[i].material);
}

void Renderer::renderShadowMap(SCN::Scene* scene)
{
    // 3.5: Reset shadow data each frame
	shadow_viewprojections.clear();
	shadow_biases.clear();

	if (!scene)
		return;

   // 3.5: Gather shadow-casting spot/directional lights
	std::vector<SCN::LightEntity*> shadow_lights;
	for (size_t i = 0; i < scene->entities.size() && shadow_lights.size() < MAX_SHADOW_LIGHTS; ++i)
	{
		BaseEntity* entity = scene->entities[i];
		if (!entity || !entity->visible || entity->getType() != SCN::eEntityType::LIGHT)
			continue;

		LightEntity* light = (LightEntity*)entity;
		if (!light->cast_shadows)
			continue;
		if (light->light_type != SCN::eLightType::SPOT && light->light_type != SCN::eLightType::DIRECTIONAL)
			continue;

		shadow_lights.push_back(light);
	}

	if (shadow_lights.empty())
		return;

   // 3.2.2: Use simple shader for shadow-map generation
	GFX::Shader* shadow_shader = GFX::Shader::Get("plain");
	if (!shadow_shader)
		return;

   Camera shadow_camera;
	for (size_t light_index = 0; light_index < shadow_lights.size(); ++light_index)
	{
		LightEntity* light = shadow_lights[light_index];
		GFX::FBO* shadow_fbo = shadowmap_fbos[light_index];
		if (!light || !shadow_fbo)
			continue;

       // 3.2.1: Light camera (view)
		Matrix44 light_model = light->root.getGlobalMatrix();
		vec3 light_pos = light_model.getTranslation();
		vec3 light_dir = light_model.rotateVector(vec3(0.0f, 0.0f, -1.0f));
		if (light_dir.length() < 0.0001f)
			light_dir = vec3(0, -1, 0);
		light_dir.normalize();
		shadow_camera.lookAt(light_pos, light_pos + light_dir, vec3(0, 1, 0));

		// 3.2.1: Light camera (projection)
		if (light->light_type == SCN::eLightType::SPOT)
		{
			float fov = light->cone_info.y * 2.0f; // half-cone -> full FOV
			shadow_camera.setPerspective(fov, 1.0f, light->near_distance, light->max_distance);
		}
		else
		{
			float area = light->area > 0.001f ? light->area : 10.0f;
			shadow_camera.setOrthographic(-area, area, -area, area, light->near_distance, light->max_distance);
		}

		shadow_viewprojections.push_back(shadow_camera.viewprojection_matrix);
		shadow_biases.push_back(shadow_bias);

		parseSceneEntities(scene, &shadow_camera);

		// 3.2.2: Z-Prepass style render to depth-only shadow map
		shadow_fbo->bind();
		glClear(GL_DEPTH_BUFFER_BIT);
		glColorMask(false, false, false, false);
		glEnable(GL_DEPTH_TEST);
		glDisable(GL_BLEND);

		// 3.4.2: Front-face culling control in shadow pass
		glEnable(GL_CULL_FACE);
		glCullFace(shadow_front_face_culling ? GL_FRONT : GL_BACK);

		shadow_shader->enable();
		shadow_shader->setUniform("u_viewprojection", shadow_camera.viewprojection_matrix);

		for (size_t i = 0; i < render_calls.size(); ++i)
		{
			const SCN::RenderCall& call = render_calls[i];
			if (!call.mesh || !call.material)
				continue;
			if (call.material->alpha_mode == SCN::eAlphaMode::BLEND)
				continue;

         GFX::Texture* shadow_texture = call.material->textures[SCN::eTextureChannel::ALBEDO].texture;
			if (!shadow_texture)
				shadow_texture = GFX::Texture::getWhiteTexture();

			shadow_shader->setUniform("u_model", call.model);
            shadow_shader->setUniform("u_texture", shadow_texture, 0);
			shadow_shader->setUniform("u_alpha_cutoff", call.material->alpha_mode == SCN::eAlphaMode::MASK ? call.material->alpha_cutoff : 0.001f);
			call.mesh->render(GL_TRIANGLES);
		}

		shadow_shader->disable();
		glCullFace(GL_BACK);
		glColorMask(true, true, true, true);
		shadow_fbo->unbind();
	}
}

void Renderer::renderSkybox(GFX::Texture* cubemap)
{
	Camera* camera = Camera::current;

	// Apply skybox necesarry config:
	// No blending, no dpeth test, we are always rendering the skybox
	// Set the culling aproppiately, since we just want the back faces
	glDisable(GL_BLEND);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);

	if (render_wireframe)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

	GFX::Shader* shader = GFX::Shader::Get("skybox");
	if (!shader)
		return;
	shader->enable();

	// Center the skybox at the camera, with a big sphere
	Matrix44 m;
	m.setTranslation(camera->eye.x, camera->eye.y, camera->eye.z);
	m.scale(10, 10, 10);
	shader->setUniform("u_model", m);

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_position", camera->eye);

	shader->setUniform("u_texture", cubemap, 0);

	sphere.render(GL_TRIANGLES);

	shader->disable();

	// Return opengl state to default
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
	glEnable(GL_DEPTH_TEST);
}

// Renders a mesh given its transform and material
void Renderer::renderMeshWithMaterial(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material)
{
	//in case there is nothing to do
	if (!mesh || !mesh->getNumVertices() || !material)
		return;
	assert(glGetError() == GL_NO_ERROR);

	//define locals to simplify coding
	GFX::Shader* shader = NULL;
	Camera* camera = Camera::current;

	glEnable(GL_DEPTH_TEST);

	//chose a shader - use phong for lighting
	shader = GFX::Shader::Get("phong");

	assert(glGetError() == GL_NO_ERROR);

	//no shader? then nothing to render
	if (!shader)
		return;
	shader->enable();

	material->bind(shader);

	//upload uniforms
	shader->setUniform("u_model", model);

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_pos", camera->eye);

	// 3.3 + 3.5: Send shadow info to shading pass
	shader->setUniform("u_shadow_count", (int)shadow_viewprojections.size());
	if (!shadow_viewprojections.empty())
	{
		shader->setUniform("u_light_viewprojection", shadow_viewprojections);
		shader->setUniform1Array("u_shadow_bias", &shadow_biases[0], (int)shadow_biases.size());

		if (shadow_viewprojections.size() > 0) shader->setUniform("u_shadowmap0", shadowmap_fbos[0]->depth_texture, 2);
		if (shadow_viewprojections.size() > 1) shader->setUniform("u_shadowmap1", shadowmap_fbos[1]->depth_texture, 3);
		if (shadow_viewprojections.size() > 2) shader->setUniform("u_shadowmap2", shadowmap_fbos[2]->depth_texture, 4);
		if (shadow_viewprojections.size() > 3) shader->setUniform("u_shadowmap3", shadowmap_fbos[3]->depth_texture, 5);
	}

	// Upload time, for cool shader effects
	float t = getTime();
	shader->setUniform("u_time", t);

	// Upload light arrays
	int num_lights = (int)enabled_lights.size();
	if (num_lights > 8) num_lights = 8; // MAX_LIGHTS in shader

	shader->setUniform("u_num_lights", num_lights);

	if (num_lights > 0)
	{
		// Prepare arrays for uniforms
		std::vector<int> light_type_array(num_lights);
		std::vector<float> light_pos_array(num_lights * 3);
		std::vector<float> light_dir_array(num_lights * 3);
		std::vector<float> light_color_array(num_lights * 3);
		std::vector<float> light_intensity_array(num_lights);
		std::vector<float> light_near_array(num_lights);
		std::vector<float> light_max_array(num_lights);
		std::vector<float> light_cone_array(num_lights * 2); // vec2 usa 2 floats

		for (int i = 0; i < num_lights; i++)
		{
			LightEntity* light = enabled_lights[i];
			Matrix44 light_model = light->root.getGlobalMatrix();

			light_type_array[i] = (int)light->light_type;

			vec3 light_world_pos = light_model.getTranslation();
			light_pos_array[i * 3 + 0] = light_world_pos.x;
			light_pos_array[i * 3 + 1] = light_world_pos.y;
			light_pos_array[i * 3 + 2] = light_world_pos.z;

			// Get light direction from the model's front vector
			vec3 light_front = light_model.frontVector();
			light_dir_array[i * 3 + 0] = light_front.x;
			light_dir_array[i * 3 + 1] = light_front.y;
			light_dir_array[i * 3 + 2] = light_front.z;

			light_color_array[i * 3 + 0] = light->color.x;
			light_color_array[i * 3 + 1] = light->color.y;
			light_color_array[i * 3 + 2] = light->color.z;

			light_intensity_array[i] = light->intensity;
			light_near_array[i] = light->near_distance;
			light_max_array[i] = light->max_distance;

			light_cone_array[i * 2 + 0] = light->cone_info.x * DEG2RAD;
			light_cone_array[i * 2 + 1] = light->cone_info.y * DEG2RAD;
		}

		shader->setUniform1Array("u_light_type", light_type_array.data(), num_lights);
		shader->setUniform3Array("u_light_pos", light_pos_array.data(), num_lights);
		shader->setUniform3Array("u_light_dir", light_dir_array.data(), num_lights);
		shader->setUniform3Array("u_light_color", light_color_array.data(), num_lights);
		shader->setUniform1Array("u_light_intensity", light_intensity_array.data(), num_lights);
		shader->setUniform1Array("u_light_near", light_near_array.data(), num_lights);
		shader->setUniform1Array("u_light_max", light_max_array.data(), num_lights);
		shader->setUniform2Array("u_light_cone", light_cone_array.data(), num_lights);
	}

	// Render just the verticies as a wireframe
	if (render_wireframe)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

	//do the draw call that renders the mesh into the screen
	mesh->render(GL_TRIANGLES);

	//disable shader
	shader->disable();

	//set the render state as it was before to avoid problems with future renders
	glDisable(GL_BLEND);
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}

#ifndef SKIP_IMGUI

void Renderer::showUI()
{
	ImGui::Checkbox("Wireframe", &render_wireframe);
	ImGui::Checkbox("Boundaries", &render_boundaries);
<<<<<<< Updated upstream

	// 3.4 + 3.5: Global shadow controls
	ImGui::DragFloat("Shadow Bias", &shadow_bias, 0.0001f, 0.0f, 0.1f);
	ImGui::Checkbox("Front Face Culling (Shadow Pass)", &shadow_front_face_culling);

	//add here your stuff
	//...
=======
	ImGui::Checkbox("Multipass Rendering", &multipass_rendering);
>>>>>>> Stashed changes
}

#else
void Renderer::showUI() {}
#endif
