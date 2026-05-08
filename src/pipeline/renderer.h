#pragma once
#include "scene.h"
#include "prefab.h"

#include "light.h"

//forward declarations
class Camera;
class Skeleton;
namespace GFX {
	class Shader;
	class Mesh;
	class FBO;
}

namespace SCN {

	class Prefab;
	class Material;

	// 3.1: Generate a Render Call struct
	struct RenderCall {
		GFX::Mesh* mesh = nullptr;
		Matrix44 model;
		SCN::Material* material = nullptr;
		float distance_to_camera = 0.0f;
	};

	// This class is in charge of rendering anything in our system.
	// Separating the render from anything else makes the code cleaner
	class Renderer
	{
	public:
       // 3.1 + 3.5: Shadow map configuration
		static const int SHADOWMAP_SIZE = 1024;
		static const int MAX_SHADOW_LIGHTS = 4;
		bool render_wireframe;
		bool render_boundaries;
     // 3.4: Global shadow error mitigation controls
		bool shadow_front_face_culling;
		float shadow_bias;
		bool multipass_rendering;

		GFX::Texture* skybox_cubemap;
		GFX::FBO* gbuffer_fbo;
		GFX::FBO* lighting_fbo;
      // 3.1 + 3.5
        std::vector<GFX::FBO*> shadowmap_fbos;
      // 3.5: Data consumed by the shading pass
     std::vector<Matrix44> shadow_viewprojections;
		std::vector<float> shadow_biases;

		SCN::Scene* scene;
		std::vector<RenderCall> render_calls;
		std::vector<LightEntity*> enabled_lights;

		//updated every frame
		Renderer(const char* shaders_atlas_filename );

		//just to be sure we have everything ready for the rendering
		void setupScene();
		//new function to keep the code clean
		void renderShadowMap(SCN::Scene* scene);

		//add here your functions
		//...

		// 3.2: Parse scene entities to generate render calls
		void parseSceneEntities(SCN::Scene* scene, Camera* camera);

		//renders several elements of the scene
		// 3.3 + 3.4: Render scene and order render calls
		void renderScene(SCN::Scene* scene, Camera* camera);

		//render the skybox
		void renderSkybox(GFX::Texture* cubemap);

		//to render one mesh given its material and transformation matrix
		void renderMeshWithMaterial(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material);
		void renderMeshToGBuffer(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material);
		void renderForward();
		void renderDeferred(Camera* camera);
		void renderDeferredAmbient(Camera* camera);
		void renderDeferredLightVolumes(Camera* camera);
		void sendLightUniforms(GFX::Shader* shader);
		void sendShadowUniforms(GFX::Shader* shader);
		void updateDeferredFBOs();

		void showUI();
	};

};
