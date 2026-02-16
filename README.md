# RmlUi data binding alternative made in Lua

## Dependencies

- https://github.com/mikke89/RmlUi
- https://www.lua.org

## Example

The example is made to run as a RmlUi sample.

- Make sure Lua and samples are enabled in RmlUi build.
- Copy the RmlLuaDataBinding directory to `[RmlUi root]/Samples/`.
- Add `add_subdirectory("RmlLuaDataBinding")` to `[RmlUi root]/Samples/CMakeLists.txt`.
- The example will be built as `rmlui_sample_lua_data_binding`.

If you want to load the example document in a different program:

- Make sure Lua is enabled in RmlUi.
- Make sure the `scripts` directory is added to Lua's `package.path` variable.
- Call Lua method `update` each frame.

