#include "libretro_core.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdarg>
#include <cstdio>
#include <cstring>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

using namespace godot;

LibretroCore *LibretroCore::active = nullptr;

static void *open_library(const String &p_path) {
#ifdef _WIN32
	Char16String wide = p_path.replace("/", "\\").utf16();
	return (void *)LoadLibraryW((LPCWSTR)wide.get_data());
#else
	return dlopen(p_path.utf8().get_data(), RTLD_NOW | RTLD_LOCAL);
#endif
}

static void *library_symbol(void *p_lib, const char *p_name) {
#ifdef _WIN32
	return (void *)GetProcAddress((HMODULE)p_lib, p_name);
#else
	return dlsym(p_lib, p_name);
#endif
}

static void free_library(void *p_lib) {
#ifdef _WIN32
	FreeLibrary((HMODULE)p_lib);
#else
	dlclose(p_lib);
#endif
}

static String library_error() {
#ifdef _WIN32
	return String("Windows error ") + String::num_int64((int64_t)GetLastError());
#else
	const char *err = dlerror();
	return err ? String::utf8(err) : String("unknown error");
#endif
}

LibretroCore::LibretroCore() {
	texture.instantiate();
}

LibretroCore::~LibretroCore() {
	unload();
}

bool LibretroCore::load_core(const String &p_path) {
	if (active && active != this) {
		UtilityFunctions::push_error("LibretroCore: another core is already active.");
		return false;
	}
	unload();

	library = open_library(p_path);
	if (!library) {
		UtilityFunctions::push_error("LibretroCore: could not open core '", p_path, "': ", library_error());
		return false;
	}

#define LOAD_SYM(name)                                                                        \
	api.name = reinterpret_cast<decltype(api.name)>(library_symbol(library, #name));          \
	if (!api.name) {                                                                          \
		UtilityFunctions::push_error("LibretroCore: symbol '" #name "' missing in ", p_path); \
		close_library();                                                                      \
		return false;                                                                         \
	}

	LOAD_SYM(retro_init)
	LOAD_SYM(retro_deinit)
	LOAD_SYM(retro_api_version)
	LOAD_SYM(retro_get_system_info)
	LOAD_SYM(retro_get_system_av_info)
	LOAD_SYM(retro_set_environment)
	LOAD_SYM(retro_set_video_refresh)
	LOAD_SYM(retro_set_audio_sample)
	LOAD_SYM(retro_set_audio_sample_batch)
	LOAD_SYM(retro_set_input_poll)
	LOAD_SYM(retro_set_input_state)
	LOAD_SYM(retro_reset)
	LOAD_SYM(retro_run)
	LOAD_SYM(retro_serialize_size)
	LOAD_SYM(retro_serialize)
	LOAD_SYM(retro_unserialize)
	LOAD_SYM(retro_load_game)
	LOAD_SYM(retro_unload_game)
#undef LOAD_SYM

	if (api.retro_api_version() != RETRO_API_VERSION) {
		UtilityFunctions::push_error("LibretroCore: incompatible libretro API version.");
		close_library();
		return false;
	}

	active = this;
	api.retro_set_environment(&LibretroCore::cb_environment);
	api.retro_set_video_refresh(&LibretroCore::cb_video_refresh);
	api.retro_set_audio_sample(&LibretroCore::cb_audio_sample);
	api.retro_set_audio_sample_batch(&LibretroCore::cb_audio_sample_batch);
	api.retro_set_input_poll(&LibretroCore::cb_input_poll);
	api.retro_set_input_state(&LibretroCore::cb_input_state);
	api.retro_init();
	core_initialized = true;

	api.retro_get_system_info(&sys_info);
	UtilityFunctions::print("LibretroCore: loaded ", get_core_name());
	return true;
}

bool LibretroCore::load_game(const String &p_rom_path) {
	if (!core_initialized) {
		UtilityFunctions::push_error("LibretroCore: load a core before loading a game.");
		return false;
	}
	if (game_loaded) {
		api.retro_unload_game();
		game_loaded = false;
	}

	rom_data = FileAccess::get_file_as_bytes(p_rom_path);
	if (rom_data.is_empty()) {
		UtilityFunctions::push_error("LibretroCore: could not read ROM '", p_rom_path, "'.");
		return false;
	}
	rom_path_utf8 = std::string(p_rom_path.utf8().get_data());

	retro_game_info info = {};
	info.path = rom_path_utf8.c_str();
	info.data = rom_data.ptr();
	info.size = (size_t)rom_data.size();

	if (!api.retro_load_game(&info)) {
		UtilityFunctions::push_error("LibretroCore: the core rejected the ROM.");
		return false;
	}

	api.retro_get_system_av_info(&av_info);
	game_loaded = true;
	return true;
}

void LibretroCore::unload() {
	if (game_loaded) {
		api.retro_unload_game();
		game_loaded = false;
	}
	close_library();
}

void LibretroCore::close_library() {
	if (core_initialized) {
		api.retro_deinit();
		core_initialized = false;
	}
	if (library) {
		free_library(library);
		library = nullptr;
	}
	api = {};
	if (active == this) {
		active = nullptr;
	}
}

void LibretroCore::run_frame() {
	if (!game_loaded) {
		return;
	}
	active = this;
	api.retro_run();
	if (frame_dirty) {
		upload_frame();
	}
}

void LibretroCore::reset() {
	if (game_loaded) {
		api.retro_reset();
	}
}

void LibretroCore::set_button(int p_port, int p_id, bool p_pressed) {
	if (p_port < 0 || p_port >= MAX_PORTS || p_id < 0 || p_id > 15) {
		return;
	}
	if (p_pressed) {
		buttons[p_port] |= (uint16_t)(1u << p_id);
	} else {
		buttons[p_port] &= (uint16_t)~(1u << p_id);
	}
}

void LibretroCore::clear_input() {
	for (int i = 0; i < MAX_PORTS; i++) {
		buttons[i] = 0;
	}
}

void LibretroCore::set_option(const String &p_key, const String &p_value) {
	options[std::string(p_key.utf8().get_data())] = std::string(p_value.utf8().get_data());
	options_updated = true;
}

void LibretroCore::set_system_directory(const String &p_dir) {
	system_dir = std::string(p_dir.utf8().get_data());
}

void LibretroCore::set_save_directory(const String &p_dir) {
	save_dir = std::string(p_dir.utf8().get_data());
}

double LibretroCore::get_aspect_ratio() const {
	if (av_info.geometry.aspect_ratio > 0.0f) {
		return av_info.geometry.aspect_ratio;
	}
	if (frame_height > 0) {
		return (double)frame_width / (double)frame_height;
	}
	return 4.0 / 3.0;
}

String LibretroCore::get_core_name() const {
	if (!sys_info.library_name) {
		return String();
	}
	return String::utf8(sys_info.library_name) + " " + String::utf8(sys_info.library_version ? sys_info.library_version : "");
}

PackedVector2Array LibretroCore::take_audio() {
	PackedVector2Array out;
	const size_t frames = audio_buffer.size() / 2;
	out.resize((int64_t)frames);
	Vector2 *dst = out.ptrw();
	const float scale = 1.0f / 32768.0f;
	for (size_t i = 0; i < frames; i++) {
		dst[i] = Vector2(audio_buffer[i * 2] * scale, audio_buffer[i * 2 + 1] * scale);
	}
	audio_buffer.clear();
	return out;
}

PackedByteArray LibretroCore::save_state() {
	PackedByteArray state;
	if (!game_loaded) {
		return state;
	}
	const size_t size = api.retro_serialize_size();
	state.resize((int64_t)size);
	if (size == 0 || !api.retro_serialize(state.ptrw(), size)) {
		state.clear();
	}
	return state;
}

bool LibretroCore::load_state(const PackedByteArray &p_state) {
	if (!game_loaded || p_state.is_empty()) {
		return false;
	}
	return api.retro_unserialize(p_state.ptr(), (size_t)p_state.size());
}

void LibretroCore::upload_frame() {
	frame_dirty = false;
	const bool same_size = image.is_valid() && image->get_width() == frame_width && image->get_height() == frame_height;
	if (same_size) {
		image->set_data(frame_width, frame_height, false, Image::FORMAT_RGBA8, frame_rgba);
		texture->update(image);
	} else {
		image = Image::create_from_data(frame_width, frame_height, false, Image::FORMAT_RGBA8, frame_rgba);
		texture->set_image(image);
	}
}

// ---------------------------------------------------------------------------
// libretro callbacks

void LibretroCore::cb_log(enum retro_log_level p_level, const char *p_fmt, ...) {
	char buffer[1024];
	va_list args;
	va_start(args, p_fmt);
	vsnprintf(buffer, sizeof(buffer), p_fmt, args);
	va_end(args);

	String msg = String::utf8(buffer).strip_edges();
	if (p_level >= RETRO_LOG_ERROR) {
		UtilityFunctions::push_error("[core] ", msg);
	} else if (p_level == RETRO_LOG_WARN) {
		UtilityFunctions::push_warning("[core] ", msg);
	} else if (p_level == RETRO_LOG_INFO) {
		UtilityFunctions::print("[core] ", msg);
	}
}

bool LibretroCore::cb_environment(unsigned p_cmd, void *p_data) {
	LibretroCore *self = active;
	if (!self) {
		return false;
	}

	switch (p_cmd) {
		case RETRO_ENVIRONMENT_GET_CAN_DUPE:
			*(bool *)p_data = true;
			return true;

		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
			const retro_pixel_format fmt = *(const retro_pixel_format *)p_data;
			if (fmt == RETRO_PIXEL_FORMAT_0RGB1555 || fmt == RETRO_PIXEL_FORMAT_XRGB8888 || fmt == RETRO_PIXEL_FORMAT_RGB565) {
				self->pixel_format = fmt;
				return true;
			}
			return false;
		}

		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
			*(const char **)p_data = self->system_dir.empty() ? nullptr : self->system_dir.c_str();
			return !self->system_dir.empty();

		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
			*(const char **)p_data = self->save_dir.empty() ? nullptr : self->save_dir.c_str();
			return !self->save_dir.empty();

		case RETRO_ENVIRONMENT_GET_VARIABLE: {
			retro_variable *var = (retro_variable *)p_data;
			auto it = self->options.find(var->key ? var->key : "");
			if (it == self->options.end()) {
				var->value = nullptr;
				return false;
			}
			var->value = it->second.c_str();
			return true;
		}

		case RETRO_ENVIRONMENT_SET_VARIABLES:
			return true;

		case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
			*(bool *)p_data = self->options_updated;
			self->options_updated = false;
			return true;

		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
			((retro_log_callback *)p_data)->log = &LibretroCore::cb_log;
			return true;

		case RETRO_ENVIRONMENT_SET_GEOMETRY:
			self->av_info.geometry = *(const retro_game_geometry *)p_data;
			return true;

		case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
			self->av_info = *(const retro_system_av_info *)p_data;
			return true;

		case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
			return true;

		default:
			return false;
	}
}

void LibretroCore::cb_video_refresh(const void *p_data, unsigned p_width, unsigned p_height, size_t p_pitch) {
	LibretroCore *self = active;
	if (!self || !p_data || p_width == 0 || p_height == 0) {
		return; // NULL data means "duplicate the previous frame".
	}

	self->frame_width = (int)p_width;
	self->frame_height = (int)p_height;
	const int64_t needed = (int64_t)p_width * p_height * 4;
	if (self->frame_rgba.size() != needed) {
		self->frame_rgba.resize(needed);
	}
	uint8_t *dst = self->frame_rgba.ptrw();
	const uint8_t *src = (const uint8_t *)p_data;

	for (unsigned y = 0; y < p_height; y++) {
		const uint8_t *row = src + y * p_pitch;
		uint8_t *out = dst + (size_t)y * p_width * 4;
		switch (self->pixel_format) {
			case RETRO_PIXEL_FORMAT_XRGB8888: {
				const uint32_t *px = (const uint32_t *)row;
				for (unsigned x = 0; x < p_width; x++) {
					const uint32_t c = px[x];
					out[x * 4 + 0] = (c >> 16) & 0xff;
					out[x * 4 + 1] = (c >> 8) & 0xff;
					out[x * 4 + 2] = c & 0xff;
					out[x * 4 + 3] = 0xff;
				}
			} break;
			case RETRO_PIXEL_FORMAT_RGB565: {
				const uint16_t *px = (const uint16_t *)row;
				for (unsigned x = 0; x < p_width; x++) {
					const uint16_t c = px[x];
					const uint8_t r = (c >> 11) & 0x1f, g = (c >> 5) & 0x3f, b = c & 0x1f;
					out[x * 4 + 0] = (uint8_t)((r << 3) | (r >> 2));
					out[x * 4 + 1] = (uint8_t)((g << 2) | (g >> 4));
					out[x * 4 + 2] = (uint8_t)((b << 3) | (b >> 2));
					out[x * 4 + 3] = 0xff;
				}
			} break;
			default: { // 0RGB1555
				const uint16_t *px = (const uint16_t *)row;
				for (unsigned x = 0; x < p_width; x++) {
					const uint16_t c = px[x];
					const uint8_t r = (c >> 10) & 0x1f, g = (c >> 5) & 0x1f, b = c & 0x1f;
					out[x * 4 + 0] = (uint8_t)((r << 3) | (r >> 2));
					out[x * 4 + 1] = (uint8_t)((g << 3) | (g >> 2));
					out[x * 4 + 2] = (uint8_t)((b << 3) | (b >> 2));
					out[x * 4 + 3] = 0xff;
				}
			} break;
		}
	}
	self->frame_dirty = true;
}

void LibretroCore::cb_audio_sample(int16_t p_left, int16_t p_right) {
	if (active) {
		active->audio_buffer.push_back(p_left);
		active->audio_buffer.push_back(p_right);
	}
}

size_t LibretroCore::cb_audio_sample_batch(const int16_t *p_data, size_t p_frames) {
	if (active) {
		active->audio_buffer.insert(active->audio_buffer.end(), p_data, p_data + p_frames * 2);
	}
	return p_frames;
}

void LibretroCore::cb_input_poll() {
	// Input is pushed from Godot through set_button() before each frame.
}

int16_t LibretroCore::cb_input_state(unsigned p_port, unsigned p_device, unsigned p_index, unsigned p_id) {
	LibretroCore *self = active;
	if (!self || p_port >= (unsigned)MAX_PORTS || p_device != RETRO_DEVICE_JOYPAD || p_index != 0) {
		return 0;
	}
	if (p_id == RETRO_DEVICE_ID_JOYPAD_MASK) {
		return (int16_t)self->buttons[p_port];
	}
	return (self->buttons[p_port] >> p_id) & 1;
}

// ---------------------------------------------------------------------------

void LibretroCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_core", "path"), &LibretroCore::load_core);
	ClassDB::bind_method(D_METHOD("load_game", "rom_path"), &LibretroCore::load_game);
	ClassDB::bind_method(D_METHOD("unload"), &LibretroCore::unload);
	ClassDB::bind_method(D_METHOD("is_running"), &LibretroCore::is_running);
	ClassDB::bind_method(D_METHOD("run_frame"), &LibretroCore::run_frame);
	ClassDB::bind_method(D_METHOD("reset"), &LibretroCore::reset);
	ClassDB::bind_method(D_METHOD("set_button", "port", "id", "pressed"), &LibretroCore::set_button);
	ClassDB::bind_method(D_METHOD("clear_input"), &LibretroCore::clear_input);
	ClassDB::bind_method(D_METHOD("set_option", "key", "value"), &LibretroCore::set_option);
	ClassDB::bind_method(D_METHOD("set_system_directory", "dir"), &LibretroCore::set_system_directory);
	ClassDB::bind_method(D_METHOD("set_save_directory", "dir"), &LibretroCore::set_save_directory);
	ClassDB::bind_method(D_METHOD("get_texture"), &LibretroCore::get_texture);
	ClassDB::bind_method(D_METHOD("get_frame_size"), &LibretroCore::get_frame_size);
	ClassDB::bind_method(D_METHOD("get_aspect_ratio"), &LibretroCore::get_aspect_ratio);
	ClassDB::bind_method(D_METHOD("get_fps"), &LibretroCore::get_fps);
	ClassDB::bind_method(D_METHOD("get_sample_rate"), &LibretroCore::get_sample_rate);
	ClassDB::bind_method(D_METHOD("get_core_name"), &LibretroCore::get_core_name);
	ClassDB::bind_method(D_METHOD("take_audio"), &LibretroCore::take_audio);
	ClassDB::bind_method(D_METHOD("save_state"), &LibretroCore::save_state);
	ClassDB::bind_method(D_METHOD("load_state", "state"), &LibretroCore::load_state);

	// RetroPad button ids, as used by set_button().
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_B", RETRO_DEVICE_ID_JOYPAD_B);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_Y", RETRO_DEVICE_ID_JOYPAD_Y);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_SELECT", RETRO_DEVICE_ID_JOYPAD_SELECT);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_START", RETRO_DEVICE_ID_JOYPAD_START);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_UP", RETRO_DEVICE_ID_JOYPAD_UP);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_DOWN", RETRO_DEVICE_ID_JOYPAD_DOWN);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_LEFT", RETRO_DEVICE_ID_JOYPAD_LEFT);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_RIGHT", RETRO_DEVICE_ID_JOYPAD_RIGHT);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_A", RETRO_DEVICE_ID_JOYPAD_A);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_X", RETRO_DEVICE_ID_JOYPAD_X);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_L", RETRO_DEVICE_ID_JOYPAD_L);
	ClassDB::bind_integer_constant(get_class_static(), "", "JOYPAD_R", RETRO_DEVICE_ID_JOYPAD_R);
}
