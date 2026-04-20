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
		bool render_wireframe;
		bool render_boundaries;

		GFX::Texture* skybox_cubemap;

		SCN::Scene* scene;
		std::vector<RenderCall> render_calls;

		//updated every frame
		Renderer(const char* shaders_atlas_filename );

		//just to be sure we have everything ready for the rendering
		void setupScene();

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

		void showUI();
	};

};