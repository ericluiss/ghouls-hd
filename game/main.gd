extends Control

## Roda o Ghouls 'n Ghosts original através de um core libretro (Genesis Plus GX Wide)
## e preenche a tela de 1920x1080 com o cenário, desenhando colunas extras nas laterais.

enum DisplayMode { FILL, SQUARE_PIXELS, INTEGER }
enum GameVersion { AMERICAN, JAPANESE }

const DISPLAY_MODE_NAMES := {
	DisplayMode.FILL: "Preencher a tela (1920x1080)",
	DisplayMode.SQUARE_PIXELS: "Pixels quadrados (altura 1080)",
	DisplayMode.INTEGER: "Escala inteira 4x (pixel perfect)",
}

const VERSION_REGIONS := {
	GameVersion.AMERICAN: "ntsc-u",
	GameVersion.JAPANESE: "ntsc-j",
}

# O core Wide vem primeiro; o comum é só um plano B (mostra o jogo em 4:3, com bordas pretas).
const CORE_BASENAMES := ["genesis_plus_gx_wide_libretro", "genesis_plus_gx_libretro"]
# 320 + 10 x 8 = 400 pixels de largura: 400x224 é praticamente 16:9.
const WIDE_EXTRA_COLUMNS := "10"
const FILL_ASPECT_TOLERANCE := 0.05
const ROM_EXTENSIONS := ["md", "bin", "gen", "smd"]
const SETTINGS_PATH := "user://settings.cfg"
const STATES_DIR := "user://states"
const AUDIO_BUFFER_SECONDS := 0.1
const AUDIO_TARGET_FILL := 0.5
const FAST_FORWARD_SPEED := 4.0

# Alterações na ROM: [endereço, bytes originais, bytes novos]. A ROM confere o checksum do
# cabeçalho e mostra uma tela vermelha se ele não bater, por isso ele é ajustado junto.
const ROM_PATCHES := [
	# Ao ligar, a ROM grava PRACTICE em $FE94 só em consoles ocidentais (move.w d0,$FE94).
	# Sem essa escrita a variável fica em 0, que é PROFESSIONAL.
	[0x290, [0x31, 0xC0, 0xFE, 0x94], [0x4E, 0x71, 0x4E, 0x71]],
	# O jogo só carrega cenário para uma tela de 320 pixels, e as colunas extras mostrariam
	# restos antigos. Estes valores cobrem os 400 pixels dentro do mapa de 512 pixels:
	# colunas novas em câmera+368 e câmera-56, linhas de 28 blocos a partir de câmera-56.
	[0x376E, [0x7A, 0x00], [0x7A, 0xC8]], # Linha ao subir
	[0x3776, [0x7A, 0x00], [0x7A, 0xC8]],
	[0x377E, [0x7A, 0x00], [0x7A, 0xC8]], # Linha ao descer
	[0x3788, [0x7A, 0x00], [0x7A, 0xC8]],
	[0x3790, [0x7A, 0x00], [0x7A, 0xC8]], # Coluna ao ir para a esquerda
	[0x3798, [0x7A, 0x00], [0x7A, 0xC8]],
	[0x37A0, [0x3A, 0x3C, 0x01, 0x40], [0x3A, 0x3C, 0x01, 0x70]], # Coluna ao ir para a direita
	[0x37AA, [0x3A, 0x3C, 0x01, 0x40], [0x3A, 0x3C, 0x01, 0x70]],
	[0x37B8, [0x7C, 0x15], [0x7C, 0x1B]], # Blocos por linha
	[0x38F0, [0x7A, 0x00], [0x7A, 0xC8]], # Desenho completo ao carregar a fase
	[0x38FE, [0x7A, 0x00], [0x7A, 0xC8]],
	# À esquerda da posição 0 da câmera o mapa acabou, e 40 pixels extras mostrariam uma faixa
	# preta. A câmera passa a parar em 8 (imagem começa em 0) e só anda quando Arthur passa do centro.
	[0x6C44, [0xFF, 0xE0], [0x00, 0x08]], # Limite esquerdo de cada trecho da tabela em $6C42
	[0x6C5C, [0x00, 0x00], [0x00, 0x08]],
	[0x6C74, [0x00, 0x00], [0x00, 0x08]],
	[0x6C8C, [0x00, 0x00], [0x00, 0x08]],
	[0x6C98, [0x00, 0x00], [0x00, 0x08]],
	[0x6CA4, [0x00, 0x00], [0x00, 0x08]],
	[0x6CBC, [0x00, 0x00], [0x00, 0x08]],
	[0x6CC8, [0x00, 0x00], [0x00, 0x08]],
	[0x6C06, [0x02, 0x80, 0x00, 0x00, 0xFF, 0xFF], [0x02, 0x80, 0x00, 0x08, 0xFF, 0xFF]], # Ao voltar a um trecho
	[0x60D06, [0x00, 0x00], [0x00, 0x08]], # Posição inicial da câmera em cada fase
	[0x60D16, [0x00, 0x00], [0x00, 0x08]],
	[0x60D26, [0x00, 0x00], [0x00, 0x08]],
	[0x60D36, [0x00, 0x00], [0x00, 0x08]],
	[0x60D46, [0x00, 0x00], [0x00, 0x08]],
	[0x60D56, [0x00, 0x00], [0x00, 0x08]],
	[0x60D66, [0x00, 0x00], [0x00, 0x08]], # Posição inicial do fundo em cada fase
	[0x60D76, [0x00, 0x00], [0x00, 0x08]],
	[0x60D86, [0x00, 0x00], [0x00, 0x08]],
	[0x60D96, [0x00, 0x00], [0x00, 0x08]],
	[0x60DA6, [0x00, 0x00], [0x00, 0x08]],
	[0x60DB6, [0x00, 0x00], [0x00, 0x08]],
]
const CHECKSUM_OFFSET := 0x18E

# Ids do RetroPad (libretro.h). No Genesis Plus GX: Y = A, B = B, A = C, SELECT = MODE.
const BUTTON_ACTIONS := {
	"md_up": 4,
	"md_down": 5,
	"md_left": 6,
	"md_right": 7,
	"md_a": 1,
	"md_b": 0,
	"md_c": 8,
	"md_start": 3,
	"md_mode": 2,
}

@onready var screen: TextureRect = $Screen
@onready var osd: Label = $Osd
@onready var audio_player: AudioStreamPlayer = $Audio
@onready var menu: Control = $Menu
@onready var continue_button: Button = $Menu/Center/Items/Continue
@onready var american_button: Button = $Menu/Center/Items/American
@onready var japanese_button: Button = $Menu/Center/Items/Japanese

var core # LibretroCore, criado via ClassDB para dar um erro claro se a extensão faltar.
var playback: AudioStreamGeneratorPlayback
var audio_capacity := 1
var frame_accumulator := 0.0
var display_mode: int = DisplayMode.FILL
var game_version: int = GameVersion.AMERICAN
var core_options_prefix := ""
var scanlines := false
var rom_path := ""
var settings := ConfigFile.new()
var last_frame_size := Vector2i.ZERO
var last_aspect := 0.0
var osd_tween: Tween


func _ready() -> void:
	set_process(false)
	settings.load(SETTINGS_PATH)
	display_mode = settings.get_value("video", "display_mode", DisplayMode.FILL)
	game_version = settings.get_value("game", "version", GameVersion.AMERICAN)
	scanlines = settings.get_value("video", "scanlines", false)
	_setup_input()
	get_window().files_dropped.connect(_on_files_dropped)
	continue_button.pressed.connect(_close_menu)
	american_button.pressed.connect(_choose_version.bind(GameVersion.AMERICAN))
	japanese_button.pressed.connect(_choose_version.bind(GameVersion.JAPANESE))

	if not ClassDB.class_exists("LibretroCore"):
		_show_message("A extensão libretro_host não foi carregada. Rode scripts/setup e abra o projeto de novo.", 0.0)
		return

	var core_path := _find_core()
	if core_path.is_empty():
		_show_message("Core não encontrado: coloque %s em game/cores/." % _core_filename(CORE_BASENAMES[0]), 0.0)
		return

	core_options_prefix = core_path.get_file().get_basename().trim_suffix("_libretro")
	core = ClassDB.instantiate("LibretroCore")
	core.set_system_directory(_ensure_dir("user://system"))
	core.set_save_directory(_ensure_dir("user://saves"))
	if not core.load_core(core_path):
		_show_message("Falha ao carregar o core: %s" % core_path, 0.0)
		return
	screen.texture = core.get_texture()

	var rom := _find_rom()
	if rom.is_empty():
		_ask_for_rom()
	else:
		rom_path = rom
		_open_menu()


func _process(delta: float) -> void:
	if not core.is_running() or menu.visible:
		return

	for action in BUTTON_ACTIONS:
		core.set_button(0, BUTTON_ACTIONS[action], Input.is_action_pressed(action))

	# O áudio dita o ritmo: se o buffer esvazia, roda um pouco mais rápido; se enche, mais devagar.
	var fill := 1.0 - float(playback.get_frames_available()) / audio_capacity
	var correction := clampf(AUDIO_TARGET_FILL - fill, -0.5, 0.5) * 0.1
	var fast_forward := Input.is_action_pressed("emu_fast_forward")
	var speed := FAST_FORWARD_SPEED if fast_forward else 1.0
	frame_accumulator += delta * core.get_fps() * (1.0 + correction) * speed

	var frames_run := 0
	while frame_accumulator >= 1.0 and frames_run < int(speed) * 2:
		core.run_frame()
		frame_accumulator -= 1.0
		frames_run += 1
	if frame_accumulator > 2.0:
		frame_accumulator = 0.0

	var samples: PackedVector2Array = core.take_audio()
	if not fast_forward:
		var free := playback.get_frames_available()
		if samples.size() > free:
			samples = samples.slice(0, free)
		playback.push_buffer(samples)

	if core.get_frame_size() != last_frame_size or not is_equal_approx(core.get_aspect_ratio(), last_aspect):
		_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("emu_fullscreen"):
		_toggle_fullscreen()
	elif event.is_action_pressed("emu_open_rom"):
		_ask_for_rom()
	elif core == null or not core.is_running():
		return
	elif event.is_action_pressed("emu_menu"):
		if menu.visible:
			_close_menu()
		else:
			_open_menu()
	elif menu.visible:
		return
	elif event.is_action_pressed("emu_display_mode"):
		display_mode = (display_mode + 1) % DisplayMode.size()
		_save_settings()
		_layout()
		_show_message(DISPLAY_MODE_NAMES[display_mode])
	elif event.is_action_pressed("emu_scanlines"):
		scanlines = not scanlines
		_save_settings()
		_layout()
		_show_message("Scanlines: %s" % ("ligadas" if scanlines else "desligadas"))
	elif event.is_action_pressed("emu_reset"):
		core.reset()
		_show_message("Reset")
	elif event.is_action_pressed("emu_save_state"):
		_save_state()
	elif event.is_action_pressed("emu_load_state"):
		_load_state()


func _open_menu() -> void:
	var running: bool = core.is_running()
	continue_button.visible = running
	menu.visible = true
	if running:
		continue_button.grab_focus()
	elif game_version == GameVersion.JAPANESE:
		japanese_button.grab_focus()
	else:
		american_button.grab_focus()


func _close_menu() -> void:
	menu.visible = false
	core.clear_input()
	frame_accumulator = 0.0


func _choose_version(version: int) -> void:
	game_version = version
	_start_game(rom_path)


func _start_game(path: String) -> void:
	var load_path := path
	if path.get_extension().to_lower() == "zip":
		load_path = _extract_rom_from_zip(path)
		if load_path.is_empty():
			_show_message("Nenhuma ROM de Mega Drive dentro de %s" % path.get_file(), 0.0)
			return

	# A região do console decide a versão: a ROM é a mesma nas duas.
	core.set_option(core_options_prefix + "_region_detect", VERSION_REGIONS[game_version])
	core.set_option(core_options_prefix + "_h40_extra_columns", WIDE_EXTRA_COLUMNS)
	core.set_option(core_options_prefix + "_h40_extra_columns_alpha", "100")
	load_path = _apply_rom_patches(load_path)
	if not core.load_game(ProjectSettings.globalize_path(load_path)):
		_show_message("O core não conseguiu abrir %s" % path.get_file(), 0.0)
		return

	rom_path = path
	_save_settings()
	_setup_audio()
	_close_menu()
	_layout()
	set_process(true)
	if core_options_prefix.ends_with("_wide"):
		_show_message("%s  |  Esc menu  F1 modo de tela  F2 scanlines  F5/F8 salvar/carregar  F11 tela cheia" % path.get_file().get_basename())
	else:
		_show_message("Core Wide não encontrado: rode scripts/setup para o cenário preencher a tela.", 8.0)


func _setup_audio() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = core.get_sample_rate()
	generator.buffer_length = AUDIO_BUFFER_SECONDS
	audio_player.stream = generator
	audio_player.play()
	playback = audio_player.get_stream_playback()
	audio_capacity = maxi(playback.get_frames_available(), 1)


func _layout() -> void:
	var frame_size: Vector2i = core.get_frame_size()
	if frame_size.x <= 0 or frame_size.y <= 0:
		return
	last_frame_size = frame_size
	last_aspect = core.get_aspect_ratio()

	var view := get_viewport_rect().size
	var source := Vector2(frame_size)
	var source_aspect := source.x / source.y
	var target: Vector2
	if display_mode == DisplayMode.INTEGER:
		var factor := maxf(1.0, floorf(minf(view.x / source.x, view.y / source.y)))
		target = source * factor
	elif display_mode == DisplayMode.FILL and absf(source_aspect / (view.x / view.y) - 1.0) < FILL_ASPECT_TOLERANCE:
		target = view
	else:
		var aspect := last_aspect if display_mode == DisplayMode.FILL else source_aspect
		target = Vector2(view.y * aspect, view.y)
		if target.x > view.x:
			target = Vector2(view.x, view.x / aspect)

	screen.size = target.round()
	screen.position = ((view - screen.size) / 2.0).floor()
	(screen.material as ShaderMaterial).set_shader_parameter("scanline_strength", 0.45 if scanlines else 0.0)


func _find_core() -> String:
	for basename: String in CORE_BASENAMES:
		var candidates := [
			OS.get_executable_path().get_base_dir().path_join("cores").path_join(_core_filename(basename)),
			ProjectSettings.globalize_path("res://cores").path_join(_core_filename(basename)),
		]
		for candidate: String in candidates:
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


func _core_filename(basename: String) -> String:
	match OS.get_name():
		"Windows":
			return basename + ".dll"
		"macOS":
			return basename + ".dylib"
		_:
			return basename + ".so"


func _find_rom() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			return arg.trim_prefix("--rom=")

	var saved: String = settings.get_value("game", "rom_path", "")
	if not saved.is_empty() and FileAccess.file_exists(saved):
		return saved

	for dir: String in [OS.get_executable_path().get_base_dir().path_join("roms"), ProjectSettings.globalize_path("res://roms")]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file: String in DirAccess.get_files_at(dir):
			var ext := file.get_extension().to_lower()
			if ext in ROM_EXTENSIONS or ext == "zip":
				return dir.path_join(file)
	return ""


func _extract_rom_from_zip(zip_path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return ""
	var result := ""
	for entry: String in zip.get_files():
		if entry.get_extension().to_lower() in ROM_EXTENSIONS:
			var out_path := _ensure_dir("user://cache").path_join(entry.get_file())
			var file := FileAccess.open(out_path, FileAccess.WRITE)
			if file:
				file.store_buffer(zip.read_file(entry))
				file.close()
				result = out_path
			break
	zip.close()
	return result


# Grava no cache uma cópia da ROM com as alterações de ROM_PATCHES. A ROM original não é alterada,
# e uma ROM diferente desta (sem os códigos esperados) é carregada como está.
func _apply_rom_patches(path: String) -> String:
	var rom := FileAccess.get_file_as_bytes(path)
	for patch: Array in ROM_PATCHES:
		var offset: int = patch[0]
		if rom.slice(offset, offset + patch[1].size()) != PackedByteArray(patch[1]):
			return path

	var checksum: int = rom[CHECKSUM_OFFSET] << 8 | rom[CHECKSUM_OFFSET + 1]
	for patch: Array in ROM_PATCHES:
		var offset: int = patch[0]
		for i in range(0, patch[2].size(), 2):
			checksum += (patch[2][i] << 8 | patch[2][i + 1]) - (patch[1][i] << 8 | patch[1][i + 1])
			rom[offset + i] = patch[2][i]
			rom[offset + i + 1] = patch[2][i + 1]
	rom[CHECKSUM_OFFSET] = (checksum >> 8) & 0xFF
	rom[CHECKSUM_OFFSET + 1] = checksum & 0xFF

	var out_path := _ensure_dir("user://cache").path_join(path.get_file())
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		return path
	file.store_buffer(rom)
	file.close()
	return out_path


func _ask_for_rom() -> void:
	_show_message("Escolha a ROM do Ghouls 'n Ghosts (ou arraste o arquivo para a janela).", 0.0)
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.md, *.bin, *.gen, *.smd, *.zip ; ROM de Mega Drive"])
	dialog.file_selected.connect(_start_game)
	dialog.file_selected.connect(func(_path: String) -> void: dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(1200, 800))


func _on_files_dropped(files: PackedStringArray) -> void:
	if core != null and not files.is_empty():
		_start_game(files[0])


func _state_path() -> String:
	var file_name := "%s.%s.state" % [rom_path.get_file().get_basename(), VERSION_REGIONS[game_version]]
	return _ensure_dir(STATES_DIR).path_join(file_name)


func _save_state() -> void:
	var state: PackedByteArray = core.save_state()
	var file := FileAccess.open(_state_path(), FileAccess.WRITE)
	if state.is_empty() or file == null:
		_show_message("Não foi possível salvar o estado")
		return
	file.store_buffer(state)
	file.close()
	_show_message("Estado salvo")


func _load_state() -> void:
	if not FileAccess.file_exists(_state_path()):
		_show_message("Nenhum estado salvo ainda (F5 salva)")
		return
	if core.load_state(FileAccess.get_file_as_bytes(_state_path())):
		_show_message("Estado carregado")
	else:
		_show_message("Estado salvo inválido")


func _toggle_fullscreen() -> void:
	var window := get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
		window.size = Vector2i(1600, 900)
		window.move_to_center()
	else:
		window.mode = Window.MODE_FULLSCREEN


func _save_settings() -> void:
	settings.set_value("video", "display_mode", display_mode)
	settings.set_value("video", "scanlines", scanlines)
	settings.set_value("game", "rom_path", rom_path)
	settings.set_value("game", "version", game_version)
	settings.save(SETTINGS_PATH)


func _ensure_dir(path: String) -> String:
	DirAccess.make_dir_recursive_absolute(path)
	return ProjectSettings.globalize_path(path)


func _show_message(text: String, duration := 3.0) -> void:
	if osd_tween:
		osd_tween.kill()
	osd.text = text
	osd.modulate.a = 1.0
	if duration > 0.0:
		osd_tween = create_tween()
		osd_tween.tween_interval(duration)
		osd_tween.tween_property(osd, "modulate:a", 0.0, 0.5)


func _setup_input() -> void:
	# Controles padrão (teclado + controle). Ações já definidas no Input Map do projeto têm prioridade.
	_add_action("md_up", [KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add_action("md_down", [KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add_action("md_left", [KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_action("md_right", [KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_action("md_a", [KEY_A, KEY_Z], [JOY_BUTTON_X])
	_add_action("md_b", [KEY_S, KEY_X], [JOY_BUTTON_A])
	_add_action("md_c", [KEY_D, KEY_C], [JOY_BUTTON_B])
	_add_action("md_start", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START])
	_add_action("md_mode", [KEY_SHIFT], [JOY_BUTTON_BACK])
	_add_action("emu_fast_forward", [KEY_TAB], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("emu_menu", [KEY_ESCAPE], [JOY_BUTTON_GUIDE])
	_add_action("emu_display_mode", [KEY_F1])
	_add_action("emu_scanlines", [KEY_F2])
	_add_action("emu_reset", [KEY_F3])
	_add_action("emu_open_rom", [KEY_F4])
	_add_action("emu_save_state", [KEY_F5])
	_add_action("emu_load_state", [KEY_F8])
	_add_action("emu_fullscreen", [KEY_F11])
	var start_confirms := InputEventJoypadButton.new()
	start_confirms.button_index = JOY_BUTTON_START
	InputMap.action_add_event("ui_accept", start_confirms)


func _add_action(action: String, keys: Array, joy_buttons: Array = [], joy_axes: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.5)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	for button in joy_buttons:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		InputMap.action_add_event(action, event)
	for axis in joy_axes:
		var event := InputEventJoypadMotion.new()
		event.axis = axis[0]
		event.axis_value = axis[1]
		InputMap.action_add_event(action, event)
