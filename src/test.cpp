/*
 * This source file is part of RmlUi, the HTML/CSS Interface Middleware
 *
 * For the latest information, see http://github.com/mikke89/RmlUi
 *
 * Copyright (c) 2008-2010 CodePoint Ltd, Shift Technology Ltd
 * Copyright (c) 2019-2023 The RmlUi Team, and contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#include <RmlUi/Core.h>
#include <RmlUi/Debugger.h>
#include <RmlUi/Lua.h>
#include <RmlUi/Core/RenderInterface.h>
#include <PlatformExtensions.h>
#include <Shell.h>

class NullRenderInterface : public Rml::RenderInterface
{
	Rml::CompiledGeometryHandle geometryHandle = {};
	Rml::TextureHandle textureHandle = {};

public:
	Rml::CompiledGeometryHandle CompileGeometry(Rml::Span<const Rml::Vertex>, Rml::Span<const int>)
	{
		return ++this->geometryHandle;
	}
	void RenderGeometry(Rml::CompiledGeometryHandle, Rml::Vector2f, Rml::TextureHandle) override {}
	void ReleaseGeometry(Rml::CompiledGeometryHandle) override {}

	Rml::TextureHandle LoadTexture(Rml::Vector2i&, const Rml::String&)
	{
		return ++this->textureHandle;
	}
	Rml::TextureHandle GenerateTexture(Rml::Span<const Rml::byte>, Rml::Vector2i)
	{
		return ++this->textureHandle;
	}
	void ReleaseTexture(Rml::TextureHandle) override {}

	void EnableScissorRegion(bool) override {}
	void SetScissorRegion(Rml::Rectanglei) override {}
};

#if defined RMLUI_PLATFORM_WIN32
	#include <RmlUi_Include_Windows.h>
int APIENTRY WinMain(HINSTANCE /*instance_handle*/, HINSTANCE /*previous_instance_handle*/, char* /*command_line*/, int /*command_show*/)
#else
int main(int /*argc*/, char** /*argv*/)
#endif
{
	const int window_width = 1024;
	const int window_height = 768;

	// Initializes the shell which provides common functionality used by the included samples.
	if (!Shell::Initialize())
		return -1;

	// Install the custom interfaces constructed by the backend before initializing RmlUi.
	NullRenderInterface nullRenderInterface;
	Rml::SetRenderInterface(&nullRenderInterface);

	// RmlUi initialisation.
	Rml::Initialise();
	Rml::Lua::Initialise();

	lua_State* L = Rml::Lua::Interpreter::GetLuaState();

	// Add data folder to Lua package.path
	{
		Rml::String dataRoot = PlatformExtensions::FindSamplesRoot() + "RmlLuaDataBinding/scripts/";

		int top = lua_gettop(L);

		lua_getglobal(L, "package");
		lua_getfield(L, -1, "path");

		Rml::String packagePath = lua_tostring(L, -1);
		lua_pop(L, 1);
		packagePath += ";" + dataRoot + "?.lua" + ";" + dataRoot + "?/init.lua";

		lua_pushstring(L, packagePath.c_str());
		lua_setfield(L, -2, "path");

		lua_settop(L, top);
	}

	// Create the main RmlUi context.
	Rml::Context* context = Rml::CreateContext("main", Rml::Vector2i(window_width, window_height));
	if (!context)
	{
		Rml::Shutdown();
		Shell::Shutdown();
		return -1;
	}

	// The RmlUi debugger is optional but very useful. Try it by pressing 'F8' after starting this sample.
	Rml::Debugger::Initialise(context);

	// Fonts should be loaded before any documents are loaded.
	Shell::LoadFonts();

	// Load and show the demo document.
	if (Rml::ElementDocument* document = context->LoadDocument("RmlLuaDataBinding/data/test.rml"))
		document->Show();

	for (int i = 0; i < 100; ++i)
	{
		// This is a good place to update your game or application.

		// Update data binding
		lua_getglobal(L, "update");
		lua_call(L, 0, 0);

		// Always update the context before rendering.
		context->Update();

		// Prepare the backend for taking rendering commands from RmlUi and then render the context.
		context->Render();
	}

	// Shutdown RmlUi.
	Rml::Shutdown();

	Shell::Shutdown();

	return 0;
}
