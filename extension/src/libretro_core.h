#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "libretro.h"

namespace godot {

// Minimal libretro frontend: loads a core (.dll/.so/.dylib) at runtime,
// runs it one frame at a time and exposes video, audio and input to Godot.
// libretro cores keep global state, so only one instance can be active.
class LibretroCore : public RefCounted {
	GDCLASS(LibretroCore, RefCounted)

public:
	LibretroCore();
	~LibretroCore();

	bool load_core(const String &p_path);
	bool load_game(const String &p_rom_path);
	void unload();
	bool is_running() const { return game_loaded; }

	void run_frame();
	void reset();

	void set_button(int p_port, int p_id, bool p_pressed);
	void clear_input();

	void set_option(const String &p_key, const String &p_value);
	void set_system_directory(const String &p_dir);
	void set_save_directory(const String &p_dir);

	Ref<ImageTexture> get_texture() const { return texture; }
	Vector2i get_frame_size() const { return Vector2i(frame_width, frame_height); }
	double get_aspect_ratio() const;
	double get_fps() const { return av_info.timing.fps; }
	double get_sample_rate() const { return av_info.timing.sample_rate; }
	String get_core_name() const;

	PackedVector2Array take_audio();

	PackedByteArray save_state();
	bool load_state(const PackedByteArray &p_state);

protected:
	static void _bind_methods();

private:
	struct CoreApi {
		void (*retro_init)(void);
		void (*retro_deinit)(void);
		unsigned (*retro_api_version)(void);
		void (*retro_get_system_info)(retro_system_info *);
		void (*retro_get_system_av_info)(retro_system_av_info *);
		void (*retro_set_environment)(retro_environment_t);
		void (*retro_set_video_refresh)(retro_video_refresh_t);
		void (*retro_set_audio_sample)(retro_audio_sample_t);
		void (*retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
		void (*retro_set_input_poll)(retro_input_poll_t);
		void (*retro_set_input_state)(retro_input_state_t);
		void (*retro_reset)(void);
		void (*retro_run)(void);
		size_t (*retro_serialize_size)(void);
		bool (*retro_serialize)(void *, size_t);
		bool (*retro_unserialize)(const void *, size_t);
		bool (*retro_load_game)(const retro_game_info *);
		void (*retro_unload_game)(void);
	};

	static LibretroCore *active;

	static bool cb_environment(unsigned p_cmd, void *p_data);
	static void cb_video_refresh(const void *p_data, unsigned p_width, unsigned p_height, size_t p_pitch);
	static void cb_audio_sample(int16_t p_left, int16_t p_right);
	static size_t cb_audio_sample_batch(const int16_t *p_data, size_t p_frames);
	static void cb_input_poll();
	static int16_t cb_input_state(unsigned p_port, unsigned p_device, unsigned p_index, unsigned p_id);
	static void cb_log(enum retro_log_level p_level, const char *p_fmt, ...);

	void *library = nullptr;
	CoreApi api = {};
	bool core_initialized = false;
	bool game_loaded = false;

	retro_system_info sys_info = {};
	retro_system_av_info av_info = {};
	retro_pixel_format pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;

	std::string system_dir;
	std::string save_dir;
	std::string rom_path_utf8;
	PackedByteArray rom_data;

	std::map<std::string, std::string> options;
	bool options_updated = false;

	static const int MAX_PORTS = 4;
	uint16_t buttons[MAX_PORTS] = {};

	int frame_width = 0;
	int frame_height = 0;
	bool frame_dirty = false;
	PackedByteArray frame_rgba;
	Ref<Image> image;
	Ref<ImageTexture> texture;

	std::vector<int16_t> audio_buffer;

	void close_library();
	void upload_frame();
};

} // namespace godot
