/* settings_store.vala
 *
 * Централизованное хранилище настроек приложения (паттерн Singleton).
 * Настройки сохраняются через GSettings (io.github.ansribas.LongBackgammon).
 * При изменении любого параметра эмитится сигнал `changed`.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class SettingsStore : Object {
    private static SettingsStore? _shared = null;

    public const string SCHEMA_ID = "io.github.ansribas.LongBackgammon";

    public const string KEY_LANGUAGE = "language";
    public const string KEY_OPPONENT = "opponent";
    public const string KEY_AI_DIFFICULTY = "ai-difficulty";
    public const string KEY_GAME_SPEED = "game-speed";
    public const string KEY_BOARD_THEME = "board-theme";
    public const string KEY_MOVEMENT_TYPE = "movement-type";
    public const string KEY_USE_BOARD_DICE_ANIMATION = "use-board-dice-animation";
    public const string KEY_SHOW_PATH_COMPUTER = "show-path-computer";
    public const string KEY_SHOW_PATH_PLAYER = "show-path-player";
    public const string KEY_HIGHLIGHT_LOG_PATHS = "highlight-log-paths";
    public const string KEY_SHOW_CELL_INDICES = "show-cell-indices";
    public const string KEY_ENABLE_DEBUG_EXPORT = "enable-debug-export";
    public const string KEY_SCORE_DISPLAY_MODE = "score-display-mode";
    public const string KEY_GRAPHICS_RENDERER = "graphics-renderer";
    public const string KEY_IS_SOUND_ENABLED = "is-sound-enabled";
    public const string KEY_IS_FIRST_MOVE_ROLLOFF_ENABLED = "is-first-move-rolloff-enabled";
    public const string KEY_BOARD_SIDE = "board-side";
    public const string KEY_IS_DRAG_AND_DROP_ENABLED = "is-drag-and-drop-enabled";
    public const string KEY_WHITE_PLAYER_NAME = "white-player-name";
    public const string KEY_BLACK_PLAYER_NAME = "black-player-name";
    public const string KEY_WINDOW_WIDTH = "window-width";
    public const string KEY_WINDOW_HEIGHT = "window-height";
    public const string KEY_WINDOW_MAXIMIZED = "window-maximized";

    private GLib.Settings? settings = null;

    /** Сигнал об изменении настроек. */
    public signal void changed ();

    public static SettingsStore shared () {
        if (_shared == null) {
            _shared = new SettingsStore ();
        }
        return _shared;
    }

    // MARK: - Публичные свойства
    public Language language;
    public Opponent opponent;
    public AIDifficulty ai_difficulty;
    public GameSpeed game_speed;
    public BoardTheme board_theme;
    public MovementType movement_type;
    public bool use_board_dice_animation;
    public bool show_path_computer;
    public bool show_path_player;
    public bool highlight_log_paths;
    public bool show_cell_indices;
    public bool enable_debug_export;
    public ScoreDisplayMode score_display_mode;
    public GraphicsRenderer graphics_renderer;
    public bool is_sound_enabled;
    public bool is_first_move_rolloff_enabled;
    public BoardSide board_side;
    public bool is_board_side_switching { get; private set; default = false; }
    private bool is_initialized = false;
    private uint board_side_switch_timeout_id = 0;
    public bool is_drag_and_drop_enabled;
    public string white_player_name;
    public string black_player_name;
    public int window_width;
    public int window_height;
    public bool window_maximized;

    private AnimationSpeed? _anim_cache = null;
    private ComputerDelay? _delay_cache = null;

    // MARK: - Вычисляемые свойства
    public bool is_black_computer { get { return opponent == Opponent.COMPUTER; } }
    public bool is_arc_movement_enabled { get { return movement_type == MovementType.ARC; } }

    public AnimationSpeed animation_speed {
        get {
            if (_anim_cache == null) {
                _anim_cache = AnimationSpeed.for_speed (game_speed);
            }
            return _anim_cache;
        }
    }

    public ComputerDelay computer_delay {
        get {
            if (_delay_cache == null) {
                _delay_cache = ComputerDelay.for_speed (game_speed);
            }
            return _delay_cache;
        }
    }

    // MARK: - Setters
    public void set_language (Language value) {
        if (language != value) {
            language = value;
            GLib.Environment.set_variable ("LANGUAGE", language.to_raw (), true);
            GLib.Intl.setlocale (GLib.LocaleCategory.MESSAGES, "");
            settings?.set_string (KEY_LANGUAGE, language.to_raw ());
            changed ();
        }
    }

    public void set_opponent (Opponent value) {
        if (opponent != value) {
            opponent = value;
            settings?.set_string (KEY_OPPONENT, opponent.to_raw ());
            changed ();
        }
    }

    public void set_ai_difficulty (AIDifficulty value) {
        if (ai_difficulty != value) {
            ai_difficulty = value;
            settings?.set_string (KEY_AI_DIFFICULTY, ai_difficulty.to_raw ());
            changed ();
        }
    }

    public void set_game_speed (GameSpeed value) {
        if (game_speed != value) {
            game_speed = value;
            _anim_cache = null;
            _delay_cache = null;
            settings?.set_string (KEY_GAME_SPEED, game_speed.to_raw ());
            changed ();
        }
    }

    public void set_board_theme (BoardTheme value) {
        if (board_theme != value) {
            board_theme = value;
            settings?.set_string (KEY_BOARD_THEME, board_theme.to_raw ());
            changed ();
        }
    }

    public void set_movement_type (MovementType value) {
        if (movement_type != value) {
            movement_type = value;
            settings?.set_string (KEY_MOVEMENT_TYPE, movement_type.to_raw ());
            changed ();
        }
    }

    public void set_use_board_dice_animation (bool value) {
        if (use_board_dice_animation != value) {
            use_board_dice_animation = value;
            settings?.set_boolean (KEY_USE_BOARD_DICE_ANIMATION, use_board_dice_animation);
            changed ();
        }
    }

    public void set_show_path_computer (bool value) {
        if (show_path_computer != value) {
            show_path_computer = value;
            settings?.set_boolean (KEY_SHOW_PATH_COMPUTER, show_path_computer);
            changed ();
        }
    }

    public void set_show_path_player (bool value) {
        if (show_path_player != value) {
            show_path_player = value;
            settings?.set_boolean (KEY_SHOW_PATH_PLAYER, show_path_player);
            changed ();
        }
    }

    public void set_highlight_log_paths (bool value) {
        if (highlight_log_paths != value) {
            highlight_log_paths = value;
            settings?.set_boolean (KEY_HIGHLIGHT_LOG_PATHS, highlight_log_paths);
            changed ();
        }
    }

    public void set_show_cell_indices (bool value) {
        if (show_cell_indices != value) {
            show_cell_indices = value;
            settings?.set_boolean (KEY_SHOW_CELL_INDICES, show_cell_indices);
            changed ();
        }
    }

    public void set_enable_debug_export (bool value) {
        if (enable_debug_export != value) {
            enable_debug_export = value;
            settings?.set_boolean (KEY_ENABLE_DEBUG_EXPORT, enable_debug_export);
            changed ();
        }
    }

    public void set_score_display_mode (ScoreDisplayMode value) {
        if (score_display_mode != value) {
            score_display_mode = value;
            settings?.set_string (KEY_SCORE_DISPLAY_MODE, score_display_mode.to_raw ());
            changed ();
        }
    }

    public void set_graphics_renderer (GraphicsRenderer value) {
        if (graphics_renderer != value) {
            graphics_renderer = value;
            if (settings != null && settings.settings_schema.has_key (KEY_GRAPHICS_RENDERER)) {
                settings.set_string (KEY_GRAPHICS_RENDERER, graphics_renderer.to_raw ());
            }
            changed ();
        }
    }

    public void set_is_sound_enabled (bool value) {
        if (is_sound_enabled != value) {
            is_sound_enabled = value;
            settings?.set_boolean (KEY_IS_SOUND_ENABLED, is_sound_enabled);
            changed ();
        }
    }

    public void set_is_first_move_rolloff_enabled (bool value) {
        if (is_first_move_rolloff_enabled != value) {
            is_first_move_rolloff_enabled = value;
            settings?.set_boolean (KEY_IS_FIRST_MOVE_ROLLOFF_ENABLED, is_first_move_rolloff_enabled);
            changed ();
        }
    }

    public void set_board_side (BoardSide value) {
        if (!is_initialized) {
            board_side = value;
            return;
        }
        if (board_side == value) {
            return;
        }
        board_side = value;
        settings?.set_string (KEY_BOARD_SIDE, board_side.to_raw ());
        is_board_side_switching = true;
        if (board_side_switch_timeout_id != 0) {
            GLib.Source.remove (board_side_switch_timeout_id);
            board_side_switch_timeout_id = 0;
        }
        board_side_switch_timeout_id = GLib.Timeout.add (1900, () => {
            is_board_side_switching = false;
            board_side_switch_timeout_id = 0;
            changed ();
            return GLib.Source.REMOVE;
        });
        changed ();
    }

    public void set_is_drag_and_drop_enabled (bool value) {
        if (is_drag_and_drop_enabled != value) {
            is_drag_and_drop_enabled = value;
            settings?.set_boolean (KEY_IS_DRAG_AND_DROP_ENABLED, is_drag_and_drop_enabled);
            changed ();
        }
    }

    public void set_white_player_name (string value) {
        if (white_player_name != value) {
            white_player_name = value;
            settings?.set_string (KEY_WHITE_PLAYER_NAME, white_player_name);
            changed ();
        }
    }

    public void set_black_player_name (string value) {
        if (black_player_name != value) {
            black_player_name = value;
            settings?.set_string (KEY_BLACK_PLAYER_NAME, black_player_name);
            changed ();
        }
    }

    public void set_window_size (int width, int height) {
        if (window_width != width || window_height != height) {
            window_width = width;
            window_height = height;
            if (settings != null) {
                settings.set_int (KEY_WINDOW_WIDTH, width);
                settings.set_int (KEY_WINDOW_HEIGHT, height);
            }
        }
    }

    public void set_window_maximized (bool maximized) {
        if (window_maximized != maximized) {
            window_maximized = maximized;
            settings?.set_boolean (KEY_WINDOW_MAXIMIZED, maximized);
        }
    }

    public void save () {
        if (settings != null) {
            settings.set_string (KEY_LANGUAGE, language.to_raw ());
            settings.set_string (KEY_OPPONENT, opponent.to_raw ());
            settings.set_string (KEY_AI_DIFFICULTY, ai_difficulty.to_raw ());
            settings.set_string (KEY_GAME_SPEED, game_speed.to_raw ());
            settings.set_string (KEY_BOARD_THEME, board_theme.to_raw ());
            settings.set_string (KEY_MOVEMENT_TYPE, movement_type.to_raw ());
            settings.set_boolean (KEY_USE_BOARD_DICE_ANIMATION, use_board_dice_animation);
            settings.set_boolean (KEY_SHOW_PATH_COMPUTER, show_path_computer);
            settings.set_boolean (KEY_SHOW_PATH_PLAYER, show_path_player);
            settings.set_boolean (KEY_HIGHLIGHT_LOG_PATHS, highlight_log_paths);
            settings.set_boolean (KEY_SHOW_CELL_INDICES, show_cell_indices);
            settings.set_boolean (KEY_ENABLE_DEBUG_EXPORT, enable_debug_export);
            settings.set_string (KEY_SCORE_DISPLAY_MODE, score_display_mode.to_raw ());
            if (settings.settings_schema.has_key (KEY_GRAPHICS_RENDERER)) {
                settings.set_string (KEY_GRAPHICS_RENDERER, graphics_renderer.to_raw ());
            }
            settings.set_boolean (KEY_IS_SOUND_ENABLED, is_sound_enabled);
            settings.set_boolean (KEY_IS_FIRST_MOVE_ROLLOFF_ENABLED, is_first_move_rolloff_enabled);
            settings.set_string (KEY_BOARD_SIDE, board_side.to_raw ());
            settings.set_boolean (KEY_IS_DRAG_AND_DROP_ENABLED, is_drag_and_drop_enabled);
            settings.set_string (KEY_WHITE_PLAYER_NAME, white_player_name);
            settings.set_string (KEY_BLACK_PLAYER_NAME, black_player_name);
            settings.set_int (KEY_WINDOW_WIDTH, window_width);
            settings.set_int (KEY_WINDOW_HEIGHT, window_height);
            settings.set_boolean (KEY_WINDOW_MAXIMIZED, window_maximized);
        }
    }

    private void init_settings () {
        var source = SettingsSchemaSource.get_default ();
        if (source != null && source.lookup (SCHEMA_ID, true) != null) {
            settings = new GLib.Settings (SCHEMA_ID);
        } else {
            string[] search_dirs = {
                GLib.Path.build_filename (Config.SOURCE_DATA_DIR, "..", "build", "data"),
                Config.SOURCE_DATA_DIR,
                GLib.Path.build_filename (Environment.get_current_dir (), "build", "data"),
                GLib.Path.build_filename (Environment.get_current_dir (), "data")
            };
            foreach (var dir in search_dirs) {
                if (FileUtils.test (GLib.Path.build_filename (dir, "gschemas.compiled"), FileTest.EXISTS)) {
                    try {
                        var dir_source = new SettingsSchemaSource.from_directory (dir, source, false);
                        var schema = dir_source.lookup (SCHEMA_ID, true);
                        if (schema != null) {
                            settings = new GLib.Settings.full (schema, null, null);
                            break;
                        }
                    } catch (Error e) {
                    }
                }
            }
        }

        if (settings != null) {
            settings.changed.connect (on_gsettings_changed);
        }
    }

    private void on_gsettings_changed (string key) {
        if (settings == null) {
            return;
        }
        bool was_changed = false;
        switch (key) {
            case KEY_LANGUAGE:
                var raw = settings.get_string (KEY_LANGUAGE);
                var new_lang = (raw != "") ? Language.from_raw (raw) : Language.current ();
                if (language != new_lang) {
                    language = new_lang;
                    GLib.Environment.set_variable ("LANGUAGE", language.to_raw (), true);
                    GLib.Intl.setlocale (GLib.LocaleCategory.MESSAGES, "");
                    was_changed = true;
                }
                break;
            case KEY_OPPONENT:
                var new_opp = Opponent.from_raw (settings.get_string (KEY_OPPONENT));
                if (opponent != new_opp) { opponent = new_opp; was_changed = true; }
                break;
            case KEY_AI_DIFFICULTY:
                var new_ai = AIDifficulty.from_raw (settings.get_string (KEY_AI_DIFFICULTY));
                if (ai_difficulty != new_ai) { ai_difficulty = new_ai; was_changed = true; }
                break;
            case KEY_GAME_SPEED:
                var new_spd = GameSpeed.from_raw (settings.get_string (KEY_GAME_SPEED));
                if (game_speed != new_spd) { game_speed = new_spd; _anim_cache = null; _delay_cache = null; was_changed = true; }
                break;
            case KEY_BOARD_THEME:
                var new_theme = BoardTheme.from_raw (settings.get_string (KEY_BOARD_THEME));
                if (board_theme != new_theme) { board_theme = new_theme; was_changed = true; }
                break;
            case KEY_MOVEMENT_TYPE:
                var new_mov = MovementType.from_raw (settings.get_string (KEY_MOVEMENT_TYPE));
                if (movement_type != new_mov) { movement_type = new_mov; was_changed = true; }
                break;
            case KEY_USE_BOARD_DICE_ANIMATION:
                var new_val = settings.get_boolean (KEY_USE_BOARD_DICE_ANIMATION);
                if (use_board_dice_animation != new_val) { use_board_dice_animation = new_val; was_changed = true; }
                break;
            case KEY_SHOW_PATH_COMPUTER:
                var new_val = settings.get_boolean (KEY_SHOW_PATH_COMPUTER);
                if (show_path_computer != new_val) { show_path_computer = new_val; was_changed = true; }
                break;
            case KEY_SHOW_PATH_PLAYER:
                var new_val = settings.get_boolean (KEY_SHOW_PATH_PLAYER);
                if (show_path_player != new_val) { show_path_player = new_val; was_changed = true; }
                break;
            case KEY_HIGHLIGHT_LOG_PATHS:
                var new_val = settings.get_boolean (KEY_HIGHLIGHT_LOG_PATHS);
                if (highlight_log_paths != new_val) { highlight_log_paths = new_val; was_changed = true; }
                break;
            case KEY_SHOW_CELL_INDICES:
                var new_val = settings.get_boolean (KEY_SHOW_CELL_INDICES);
                if (show_cell_indices != new_val) { show_cell_indices = new_val; was_changed = true; }
                break;
            case KEY_ENABLE_DEBUG_EXPORT:
                var new_val = settings.get_boolean (KEY_ENABLE_DEBUG_EXPORT);
                if (enable_debug_export != new_val) { enable_debug_export = new_val; was_changed = true; }
                break;
            case KEY_SCORE_DISPLAY_MODE:
                var new_sdm = ScoreDisplayMode.from_raw (settings.get_string (KEY_SCORE_DISPLAY_MODE));
                if (score_display_mode != new_sdm) { score_display_mode = new_sdm; was_changed = true; }
                break;
            case KEY_GRAPHICS_RENDERER:
                var new_gr = GraphicsRenderer.from_raw (settings.get_string (KEY_GRAPHICS_RENDERER));
                if (graphics_renderer != new_gr) { graphics_renderer = new_gr; was_changed = true; }
                break;
            case KEY_IS_SOUND_ENABLED:
                var new_val = settings.get_boolean (KEY_IS_SOUND_ENABLED);
                if (is_sound_enabled != new_val) { is_sound_enabled = new_val; was_changed = true; }
                break;
            case KEY_IS_FIRST_MOVE_ROLLOFF_ENABLED:
                var new_val = settings.get_boolean (KEY_IS_FIRST_MOVE_ROLLOFF_ENABLED);
                if (is_first_move_rolloff_enabled != new_val) { is_first_move_rolloff_enabled = new_val; was_changed = true; }
                break;
            case KEY_BOARD_SIDE:
                var new_side = BoardSide.from_raw (settings.get_string (KEY_BOARD_SIDE));
                if (board_side != new_side) { board_side = new_side; was_changed = true; }
                break;
            case KEY_IS_DRAG_AND_DROP_ENABLED:
                var new_val = settings.get_boolean (KEY_IS_DRAG_AND_DROP_ENABLED);
                if (is_drag_and_drop_enabled != new_val) { is_drag_and_drop_enabled = new_val; was_changed = true; }
                break;
            case KEY_WHITE_PLAYER_NAME:
                var new_val = settings.get_string (KEY_WHITE_PLAYER_NAME);
                if (white_player_name != new_val) { white_player_name = new_val; was_changed = true; }
                break;
            case KEY_BLACK_PLAYER_NAME:
                var new_val = settings.get_string (KEY_BLACK_PLAYER_NAME);
                if (black_player_name != new_val) { black_player_name = new_val; was_changed = true; }
                break;
            case KEY_WINDOW_WIDTH:
                window_width = settings.get_int (KEY_WINDOW_WIDTH);
                break;
            case KEY_WINDOW_HEIGHT:
                window_height = settings.get_int (KEY_WINDOW_HEIGHT);
                break;
            case KEY_WINDOW_MAXIMIZED:
                window_maximized = settings.get_boolean (KEY_WINDOW_MAXIMIZED);
                break;
        }
        if (was_changed) {
            changed ();
        }
    }

    private void load () {
        language = Language.current ();
        opponent = Opponent.COMPUTER;
        ai_difficulty = AIDifficulty.MASTER;
        game_speed = GameSpeed.SLOW;
        board_theme = BoardTheme.MARBLE;
        movement_type = MovementType.ARC;
        use_board_dice_animation = true;
        show_path_computer = true;
        show_path_player = true;
        highlight_log_paths = true;
        show_cell_indices = false;
        enable_debug_export = false;
        score_display_mode = ScoreDisplayMode.PROGRESS;
        graphics_renderer = GraphicsRenderer.CAIRO;
        is_sound_enabled = true;
        is_first_move_rolloff_enabled = true;
        board_side = BoardSide.RIGHT;
        is_drag_and_drop_enabled = true;
        white_player_name = "";
        black_player_name = "";
        window_width = 800;
        window_height = 600;
        window_maximized = false;

        init_settings ();

        if (settings != null) {
            var lang_str = settings.get_string (KEY_LANGUAGE);
            language = (lang_str != "") ? Language.from_raw (lang_str) : Language.current ();
            opponent = Opponent.from_raw (settings.get_string (KEY_OPPONENT));
            ai_difficulty = AIDifficulty.from_raw (settings.get_string (KEY_AI_DIFFICULTY));
            game_speed = GameSpeed.from_raw (settings.get_string (KEY_GAME_SPEED));
            board_theme = BoardTheme.from_raw (settings.get_string (KEY_BOARD_THEME));
            movement_type = MovementType.from_raw (settings.get_string (KEY_MOVEMENT_TYPE));
            use_board_dice_animation = settings.get_boolean (KEY_USE_BOARD_DICE_ANIMATION);
            show_path_computer = settings.get_boolean (KEY_SHOW_PATH_COMPUTER);
            show_path_player = settings.get_boolean (KEY_SHOW_PATH_PLAYER);
            highlight_log_paths = settings.get_boolean (KEY_HIGHLIGHT_LOG_PATHS);
            show_cell_indices = settings.get_boolean (KEY_SHOW_CELL_INDICES);
            enable_debug_export = settings.get_boolean (KEY_ENABLE_DEBUG_EXPORT);
            score_display_mode = ScoreDisplayMode.from_raw (settings.get_string (KEY_SCORE_DISPLAY_MODE));
            if (settings.settings_schema.has_key (KEY_GRAPHICS_RENDERER)) {
                graphics_renderer = GraphicsRenderer.from_raw (settings.get_string (KEY_GRAPHICS_RENDERER));
            }
            is_sound_enabled = settings.get_boolean (KEY_IS_SOUND_ENABLED);
            is_first_move_rolloff_enabled = settings.get_boolean (KEY_IS_FIRST_MOVE_ROLLOFF_ENABLED);
            board_side = BoardSide.from_raw (settings.get_string (KEY_BOARD_SIDE));
            is_drag_and_drop_enabled = settings.get_boolean (KEY_IS_DRAG_AND_DROP_ENABLED);
            white_player_name = settings.get_string (KEY_WHITE_PLAYER_NAME);
            black_player_name = settings.get_string (KEY_BLACK_PLAYER_NAME);
            window_width = settings.get_int (KEY_WINDOW_WIDTH);
            window_height = settings.get_int (KEY_WINDOW_HEIGHT);
            window_maximized = settings.get_boolean (KEY_WINDOW_MAXIMIZED);
        }

        GLib.Environment.set_variable ("LANGUAGE", language.to_raw (), true);
        GLib.Intl.setlocale (GLib.LocaleCategory.MESSAGES, "");
        is_initialized = true;
    }

    private SettingsStore () {
        load ();
    }
}

} /* namespace Longbackgammon */
