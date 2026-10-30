/* settings_store.vala
 *
 * Централизованное хранилище настроек приложения (паттерн Singleton).
 * Настройки сохраняются в файл settings.conf в каталоге данных.
 * При изменении любого параметра эмитится сигнал `changed`.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class SettingsStore : Object {
    private static SettingsStore? _shared = null;

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
    public bool is_sound_enabled;
    public bool is_first_move_rolloff_enabled;
    public BoardSide board_side;
    public bool is_board_side_switching { get; private set; default = false; }
    private bool is_initialized = false;
    private uint board_side_switch_timeout_id = 0;
    public bool is_drag_and_drop_enabled;
    public string white_player_name;
    public string black_player_name;

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

    // MARK: - Setters (с автосохранением)
    public void set_language (Language value) {
        if (language != value) {
            language = value;
            GLib.Environment.set_variable ("LANGUAGE", language.to_raw (), true);
            GLib.Intl.setlocale (GLib.LocaleCategory.MESSAGES, "");
            save ();
            changed ();
        }
    }
    public void set_opponent (Opponent value) {
        if (opponent != value) { opponent = value; save (); changed (); }
    }
    public void set_ai_difficulty (AIDifficulty value) {
        if (ai_difficulty != value) { ai_difficulty = value; save (); changed (); }
    }
    public void set_game_speed (GameSpeed value) {
        if (game_speed != value) { game_speed = value; _anim_cache = null; _delay_cache = null; save (); changed (); }
    }
    public void set_board_theme (BoardTheme value) {
        if (board_theme != value) { board_theme = value; save (); changed (); }
    }
    public void set_movement_type (MovementType value) {
        if (movement_type != value) { movement_type = value; save (); changed (); }
    }
    public void set_use_board_dice_animation (bool value) {
        if (use_board_dice_animation != value) { use_board_dice_animation = value; save (); changed (); }
    }
    public void set_show_path_computer (bool value) {
        if (show_path_computer != value) { show_path_computer = value; save (); changed (); }
    }
    public void set_show_path_player (bool value) {
        if (show_path_player != value) { show_path_player = value; save (); changed (); }
    }
    public void set_highlight_log_paths (bool value) {
        if (highlight_log_paths != value) { highlight_log_paths = value; save (); changed (); }
    }
    public void set_show_cell_indices (bool value) {
        if (show_cell_indices != value) { show_cell_indices = value; save (); changed (); }
    }
    public void set_enable_debug_export (bool value) {
        if (enable_debug_export != value) { enable_debug_export = value; save (); changed (); }
    }
    public void set_score_display_mode (ScoreDisplayMode value) {
        if (score_display_mode != value) { score_display_mode = value; save (); changed (); }
    }
    public void set_is_sound_enabled (bool value) {
        if (is_sound_enabled != value) { is_sound_enabled = value; save (); changed (); }
    }
    public void set_is_first_move_rolloff_enabled (bool value) {
        if (is_first_move_rolloff_enabled != value) { is_first_move_rolloff_enabled = value; save (); changed (); }
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
        save ();
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
        if (is_drag_and_drop_enabled != value) { is_drag_and_drop_enabled = value; save (); changed (); }
    }
    public void set_white_player_name (string value) {
        if (white_player_name != value) { white_player_name = value; save (); changed (); }
    }
    public void set_black_player_name (string value) {
        if (black_player_name != value) { black_player_name = value; save (); changed (); }
    }

    // MARK: - Сохранение/загрузка (INI-файл)
    private void save () {
        var path = StoragePaths.file_path (GameConfig.SETTINGS_FILE_NAME);
        var keyfile = new KeyFile ();
        keyfile.set_string ("settings", "language", language.to_raw ());
        keyfile.set_string ("settings", "opponent", opponent.to_raw ());
        keyfile.set_string ("settings", "ai_difficulty", ai_difficulty.to_raw ());
        keyfile.set_string ("settings", "game_speed", game_speed.to_raw ());
        keyfile.set_string ("settings", "board_theme", board_theme.to_raw ());
        keyfile.set_string ("settings", "movement_type", movement_type.to_raw ());
        keyfile.set_boolean ("settings", "use_board_dice_animation", use_board_dice_animation);
        keyfile.set_boolean ("settings", "show_path_computer", show_path_computer);
        keyfile.set_boolean ("settings", "show_path_player", show_path_player);
        keyfile.set_boolean ("settings", "highlight_log_paths", highlight_log_paths);
        keyfile.set_boolean ("settings", "show_cell_indices", show_cell_indices);
        keyfile.set_boolean ("settings", "enable_debug_export", enable_debug_export);
        keyfile.set_string ("settings", "score_display_mode", score_display_mode.to_raw ());
        keyfile.set_boolean ("settings", "is_sound_enabled", is_sound_enabled);
        keyfile.set_boolean ("settings", "is_first_move_rolloff_enabled", is_first_move_rolloff_enabled);
        keyfile.set_string ("settings", "board_side", board_side.to_raw ());
        keyfile.set_boolean ("settings", "is_drag_and_drop_enabled", is_drag_and_drop_enabled);
        keyfile.set_string ("settings", "white_player_name", white_player_name);
        keyfile.set_string ("settings", "black_player_name", black_player_name);
        StoragePaths.write_text_file (path, keyfile.to_data ());
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
        is_sound_enabled = true;
        is_first_move_rolloff_enabled = true;
        board_side = BoardSide.RIGHT;
        is_drag_and_drop_enabled = true;
        white_player_name = "";
        black_player_name = "";

        var path = StoragePaths.file_path (GameConfig.SETTINGS_FILE_NAME);
        var text = StoragePaths.read_text_file (path);
        if (text != null) {
            var keyfile = new KeyFile ();
            try {
                if (keyfile.load_from_data (text, text.length, GLib.KeyFileFlags.NONE)) {
                    if (keyfile.has_key ("settings", "language")) language = Language.from_raw (keyfile.get_string ("settings", "language"));
                    if (keyfile.has_key ("settings", "opponent")) opponent = Opponent.from_raw (keyfile.get_string ("settings", "opponent"));
                    if (keyfile.has_key ("settings", "ai_difficulty")) ai_difficulty = AIDifficulty.from_raw (keyfile.get_string ("settings", "ai_difficulty"));
                    if (keyfile.has_key ("settings", "game_speed")) game_speed = GameSpeed.from_raw (keyfile.get_string ("settings", "game_speed"));
                    if (keyfile.has_key ("settings", "board_theme")) board_theme = BoardTheme.from_raw (keyfile.get_string ("settings", "board_theme"));
                    if (keyfile.has_key ("settings", "movement_type")) movement_type = MovementType.from_raw (keyfile.get_string ("settings", "movement_type"));
                    if (keyfile.has_key ("settings", "use_board_dice_animation")) use_board_dice_animation = keyfile.get_boolean ("settings", "use_board_dice_animation");
                    if (keyfile.has_key ("settings", "show_path_computer")) show_path_computer = keyfile.get_boolean ("settings", "show_path_computer");
                    if (keyfile.has_key ("settings", "show_path_player")) show_path_player = keyfile.get_boolean ("settings", "show_path_player");
                    if (keyfile.has_key ("settings", "highlight_log_paths")) highlight_log_paths = keyfile.get_boolean ("settings", "highlight_log_paths");
                    if (keyfile.has_key ("settings", "show_cell_indices")) show_cell_indices = keyfile.get_boolean ("settings", "show_cell_indices");
                    if (keyfile.has_key ("settings", "enable_debug_export")) enable_debug_export = keyfile.get_boolean ("settings", "enable_debug_export");
                    if (keyfile.has_key ("settings", "score_display_mode")) score_display_mode = ScoreDisplayMode.from_raw (keyfile.get_string ("settings", "score_display_mode"));
                    if (keyfile.has_key ("settings", "is_sound_enabled")) is_sound_enabled = keyfile.get_boolean ("settings", "is_sound_enabled");
                    if (keyfile.has_key ("settings", "is_first_move_rolloff_enabled")) is_first_move_rolloff_enabled = keyfile.get_boolean ("settings", "is_first_move_rolloff_enabled");
                    if (keyfile.has_key ("settings", "board_side")) board_side = BoardSide.from_raw (keyfile.get_string ("settings", "board_side"));
                    if (keyfile.has_key ("settings", "is_drag_and_drop_enabled")) is_drag_and_drop_enabled = keyfile.get_boolean ("settings", "is_drag_and_drop_enabled");
                    if (keyfile.has_key ("settings", "white_player_name")) white_player_name = keyfile.get_string ("settings", "white_player_name");
                    if (keyfile.has_key ("settings", "black_player_name")) black_player_name = keyfile.get_string ("settings", "black_player_name");
                }
            } catch (Error e) {
                warning ("Settings load error: %s", e.message);
            }
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