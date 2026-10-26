/* game_config.vala
 *
 * Глобальная конфигурация игры «Длинные нарды»:
 * размеры окна, цвета подсветки, скорости анимации,
 * задержки ИИ и полная система локализации.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class Language : Object {
    private static HashTable<string, Language> registry;

    public string raw_value { get; private set; }

    public static Language RUSSIAN;
    public static Language ENGLISH;

    private static void ensure_registry () {
        if (registry == null) {
            registry = new HashTable<string, Language> (str_hash, str_equal);
            RUSSIAN = new Language ("ru");
            ENGLISH = new Language ("en");
            registry.insert ("ru", RUSSIAN);
            registry.insert ("en", ENGLISH);
        }
    }

    private Language (string code) {
        this.raw_value = code;
    }

    public new static Language get (string code) {
        ensure_registry ();
        var key = code.strip ().down ();
        if (key == "") {
            key = "ru";
        }
        var existing = registry.lookup (key);
        if (existing != null) {
            return existing;
        }
        var created = new Language (key);
        registry.insert (key, created);
        return created;
    }

    public string to_raw () {
        return raw_value;
    }

    public static Language from_raw (string raw) {
        return Language.get (raw);
    }

    public string display_name () {
        return LocalizationManager.shared ().display_name_for_language (this);
    }

    public static Language[] all_cases () {
        return LocalizationManager.shared ().available_languages ();
    }

    /** Текущий язык системы среди доступных, по умолчанию русский. */
    public static Language current () {
        string[] env_vars = { "LANGUAGE", "LC_ALL", "LANG" };
        var all = all_cases ();
        foreach (var env in env_vars) {
            var val = Environment.get_variable (env);
            if (val != null && val.length >= 2) {
                var prefix = val.substring (0, 2).down ();
                foreach (var l in all) {
                    if (l.raw_value == prefix) {
                        return l;
                    }
                }
            }
        }
        return RUSSIAN;
    }
}

public enum Opponent {
    COMPUTER,
    HUMAN;

    public string to_raw () {
        return (this == Opponent.COMPUTER) ? "computer" : "human";
    }

    public static Opponent from_raw (string raw) {
        return (raw == "human") ? Opponent.HUMAN : Opponent.COMPUTER;
    }
}

public enum GameSpeed {
    FAST,
    SLOW;

    public string to_raw () {
        return (this == GameSpeed.FAST) ? "fast" : "slow";
    }

    public static GameSpeed from_raw (string raw) {
        return (raw == "slow") ? GameSpeed.SLOW : GameSpeed.FAST;
    }
}

public enum ScoreDisplayMode {
    SCORE,
    PROGRESS;

    public string to_raw () {
        return (this == ScoreDisplayMode.SCORE) ? "score" : "progress";
    }

    public static ScoreDisplayMode from_raw (string raw) {
        return (raw == "score") ? ScoreDisplayMode.SCORE : ScoreDisplayMode.PROGRESS;
    }
}

public enum BoardTheme {
    WOOD,
    MARBLE;

    public string to_raw () {
        return (this == BoardTheme.MARBLE) ? "marble" : "wood";
    }

    public static BoardTheme from_raw (string raw) {
        return (raw == "wood") ? BoardTheme.WOOD : BoardTheme.MARBLE;
    }

    public string board_asset_name () {
        return (this == BoardTheme.MARBLE) ? "marble_board.png" : "wood_board.png";
    }

    public string dice_cursor_asset_name () {
        return (this == BoardTheme.MARBLE) ? "marble_dicecursor.png" : "wood_dicecursor.png";
    }

    public string checker_asset_name (CheckerColor color) {
        if (this == BoardTheme.MARBLE) {
            return (color == CheckerColor.WHITE) ? "marble_white.png" : "marble_black.png";
        } else {
            return (color == CheckerColor.WHITE) ? "wood_white.png" : "wood_black.png";
        }
    }

    public void get_move_color (bool is_emphasized, out double r, out double g, out double b, out double a) {
        if (this == BoardTheme.MARBLE) {
            if (is_emphasized) {
                r = 1.0 / 255.0;
                g = 104.0 / 255.0;
                b = 46.0 / 255.0;
                a = 0.81;
            } else {
                r = 0.0;
                g = 1.0;
                b = 0.0;
                a = 0.61;
            }
        } else {
            // Wood
            r = 0.0;
            g = 1.0;
            b = 0.0;
            a = is_emphasized ? 0.92 : 0.70;
        }
    }

    public void get_illegal_move_color (bool is_emphasized, out double r, out double g, out double b, out double a) {
        r = 1.0;
        g = 0.0;
        b = 0.0;
        if (this == BoardTheme.MARBLE) {
            a = is_emphasized ? 0.97 : 0.65;
        } else {
            // Wood
            a = is_emphasized ? 0.95 : 0.70;
        }
    }
}

public enum MovementType {
    STRAIGHT,
    ARC;

    public string to_raw () {
        return (this == MovementType.STRAIGHT) ? "straight" : "arc";
    }

    public static MovementType from_raw (string raw) {
        return (raw == "straight") ? MovementType.STRAIGHT : MovementType.ARC;
    }
}

public enum AIDifficulty {
    MASTER,
    STANDARD;

    public string to_raw () {
        return (this == AIDifficulty.STANDARD) ? "standard" : "master";
    }

    public static AIDifficulty from_raw (string raw) {
        return (raw == "standard") ? AIDifficulty.STANDARD : AIDifficulty.MASTER;
    }
}

public class PlacementAnimation {
    public const double STEP_INTERVAL = 0.051;
    public const double SPRING_RESPONSE = 0.68;
    public const double SPRING_DAMPING = 0.85;
    public const double AUDIO_FLIGHT_DELAY = 0.430;
    public const double COMPLETION_DELAY = 0.510;
}

/** Настройки скорости движения фишек и анимаций. */
public class AnimationSpeed {
    public double checker_move_duration;
    public double intermediate_step_delay;
    public int dice_rolling_steps;
    public double dice_rolling_step_delay;

    public AnimationSpeed (
        double checker_move_duration,
        double intermediate_step_delay,
        int dice_rolling_steps,
        double dice_rolling_step_delay) {
        this.checker_move_duration = checker_move_duration;
        this.intermediate_step_delay = intermediate_step_delay;
        this.dice_rolling_steps = dice_rolling_steps;
        this.dice_rolling_step_delay = dice_rolling_step_delay;
    }

    public static AnimationSpeed fast () {
        return new AnimationSpeed (0.32, 0.5, 15, 0.1);
    }

    public static AnimationSpeed slow () {
        return new AnimationSpeed (0.5, 1.1, 25, 0.1);
    }

    public static AnimationSpeed for_speed (GameSpeed speed) {
        return (speed == GameSpeed.FAST) ? fast () : slow ();
    }
}

/** Задержки для хода компьютерного противника. */
public class ComputerDelay {
    public double before_roll_delay;
    public double between_moves_delay;
    public double auto_end_turn_delay;

    public ComputerDelay (
        double before_roll_delay,
        double between_moves_delay,
        double auto_end_turn_delay) {
        this.before_roll_delay = before_roll_delay;
        this.between_moves_delay = between_moves_delay;
        this.auto_end_turn_delay = auto_end_turn_delay;
    }

    public static ComputerDelay fast () {
        return new ComputerDelay (0.3, 0.5, 0.3);
    }

    public static ComputerDelay slow () {
        return new ComputerDelay (1.0, 1.1, 0.8);
    }

    public static ComputerDelay for_speed (GameSpeed speed) {
        return (speed == GameSpeed.FAST) ? fast () : slow ();
    }
}

/** Глобальные константы игры. */
public abstract class GameConfig {
    // MARK: - Размеры окна и панелей
    public const int CONTROL_PANEL_WIDTH = 300;   // фикс. ширина боковых панелей (по 150pt на сторону)
    public const int WINDOW_PADDING = 10;         // стандартный отступ доски (10px)
    public const int MIN_WINDOW_WIDTH = 900;
    public const int MIN_WINDOW_HEIGHT = 620;

    // MARK: - Цвета подсветки (RGBA 0…1)
    public const double SIMPLE_MOVE_R = 0.204;
    public const double SIMPLE_MOVE_G = 0.780;
    public const double SIMPLE_MOVE_B = 0.349;
    public const double SIMPLE_MOVE_A = 0.70;

    public const double ILLEGAL_MOVE_R = 1.0;
    public const double ILLEGAL_MOVE_G = 0.231;
    public const double ILLEGAL_MOVE_B = 0.188;
    public const double ILLEGAL_MOVE_A = 0.70;

    public const double SELECTED_CHECKER_R = 1.0;
    public const double SELECTED_CHECKER_G = 1.0;
    public const double SELECTED_CHECKER_B = 0.0;
    public const double SELECTED_CHECKER_A = 1.0;

    public const double LOG_MOVES_R = 0.20;
    public const double LOG_MOVES_G = 0.40;
    public const double LOG_MOVES_B = 1.0;
    public const double LOG_MOVES_A = 0.70;

    // MARK: - Аудио
    public const int DICE_ROLL_SOUNDS_COUNT = 3;

    // MARK: - Логи партий
    public const int LOG_MAX_ENTRIES = 100;
    public const string LOG_SUBDIRECTORY_NAME = "longbackgammon";
    public const string LOG_FILE_NAME = "game_logs.json";
    public const string STATS_FILE_NAME = "player_stats.json";
    public const string SAVED_GAME_FILE_NAME = "saved_game.json";
    public const string SETTINGS_FILE_NAME = "settings.conf";
}

/** Словарь приложения. Динамически загружает строки из JSON-файлов переводов через LocalizationManager. */
public class Localization {
    private static Language lang () {
        return SettingsStore.shared ().language;
    }

    public static string tr (string key, Language? custom_lang = null) {
        var l = (custom_lang != null) ? custom_lang : lang ();
        return LocalizationManager.shared ().string_for_key (key, l);
    }

    public static string format (string key, string[] replacements, Language? custom_lang = null) {
        var l = (custom_lang != null) ? custom_lang : lang ();
        return LocalizationManager.shared ().format_string (key, l, replacements);
    }

    // MARK: - Меню и заголовки
    public static string app_menu_about ()        { return tr ("appMenuAbout"); }
    public static string window_title ()          { return tr ("windowTitle"); }
    public static string settings_menu ()         { return tr ("settingsMenu"); }
    public static string menu_edit ()             { return tr ("menuEdit"); }
    public static string menu_view ()             { return tr ("menuView"); }
    public static string menu_help ()             { return tr ("menuHelp") + "\u00A0"; }
    public static string menu_file ()             { return tr ("menuFile"); }
    public static string menu_quit ()             { return tr ("menuQuit"); }
    public static string menu_fullscreen ()       { return tr ("menuFullScreen"); }
    public static string menu_undo ()             { return tr ("menuUndo"); }
    public static string rules_menu_item ()       { return tr ("rulesMenuItem"); }
    public static string stats_menu ()            { return tr ("statsMenu"); }
    public static string new_game_header ()       { return tr ("newGameHeader"); }
    public static string button_new_game ()       { return tr ("buttonNewGame"); }
    public static string button_start_game ()     { return tr ("buttonStartGame"); }

    // MARK: - Статистика
    public static string stats_title ()           { return tr ("statsTitle"); }
    public static string stats_games_played ()    { return tr ("gameOverMovesStat"); }
    public static string stats_losses ()          { return tr ("statsLosses"); }
    public static string stats_oin_victories ()   { return tr ("statsOinVictories"); }
    public static string stats_mars_victories ()  { return tr ("statsMarsVictories"); }
    public static string stats_home_mars_victories () { return tr ("statsHomeMarsVictories"); }
    public static string stats_total_points ()    { return tr ("statsTotalPoints"); }
    public static string stats_win_rate ()        { return tr ("statsWinRate"); }
    public static string stats_header_count ()    { return tr ("statsHeaderCount"); }
    public static string stats_header_points ()   { return tr ("statsHeaderPoints"); }
    public static string stats_no_data ()         { return tr ("statsNoData"); }
    public static string stats_reset_button ()    { return tr ("statsResetButton"); }
    public static string stats_reset_confirmation_title () { return tr ("statsResetConfirmationTitle"); }
    public static string stats_reset_confirmation_message () { return tr ("statsResetConfirmationMessage"); }
    public static string stats_reset_confirm_button () { return tr ("statsResetConfirmButton"); }
    public static string stats_reset_cancel_button ()  { return tr ("statsResetCancelButton"); }

    // MARK: - Настройки
    public static string settings_header ()       { return tr ("settingsHeader"); }
    public static string settings_language_label () { return tr ("settingsLanguageLabel"); }
    public static string settings_sound_label ()  { return tr ("settingsSoundLabel"); }
    public static string sound_mute_tooltip ()    { return tr ("soundMuteTooltip"); }
    public static string sound_unmute_tooltip ()  { return tr ("soundUnmuteTooltip"); }
    public static string settings_section_general ()    { return tr ("settingsSectionGeneral"); }
    public static string settings_section_appearance () { return tr ("settingsSectionAppearance"); }
    public static string settings_section_controls ()   { return tr ("settingsSectionControls"); }
    public static string settings_section_debug ()      { return tr ("settingsSectionDebug"); }
    public static string settings_first_move_rolloff_label () { return tr ("settingsFirstMoveRollOffLabel"); }
    public static string settings_opponent_label () { return tr ("settingsOpponentLabel"); }
    public static string settings_opponent_computer () { return tr ("settingsOpponentComputer"); }
    public static string settings_opponent_human () { return tr ("settingsOpponentHuman"); }
    public static string settings_player_name_label () { return tr ("settingsPlayerNameLabel"); }
    public static string settings_player1_label () { return tr ("settingsPlayer1Label"); }
    public static string settings_player2_label () { return tr ("settingsPlayer2Label"); }
    public static string default_player_name ()   { return tr ("defaultPlayerName"); }
    public static string default_player1_name ()  { return tr ("defaultPlayer1Name"); }
    public static string default_player2_name ()  { return tr ("defaultPlayer2Name"); }
    public static string settings_close_button () { return tr ("settingsCloseButton"); }
    public static string settings_speed_label ()  { return tr ("settingsSpeedLabel"); }
    public static string settings_speed_fast ()   { return tr ("settingsSpeedFast"); }
    public static string settings_speed_slow ()   { return tr ("settingsSpeedSlow"); }
    public static string settings_show_path_label () { return tr ("settingsShowPathLabel"); }
    public static string settings_show_path_computer () { return tr ("settingsShowPathComputer"); }
    public static string settings_show_path_player ()   { return tr ("settingsShowPathPlayer"); }
    public static string settings_drag_and_drop_label () { return tr ("settingsDragAndDropLabel"); }
    public static string settings_section_movement_footer () { return tr ("settingsSectionMovementFooter"); }
    public static string settings_section_score_footer () { return tr ("settingsSectionScoreFooter"); }
    public static string settings_score_display_label () { return tr ("settingsScoreDisplayLabel"); }
    public static string settings_score_display_score () { return tr ("settingsScoreDisplayScore"); }
    public static string settings_score_display_progress () { return tr ("settingsScoreDisplayProgress"); }
    public static string settings_debug_export_label () { return tr ("settingsDebugExportLabel"); }
    public static string settings_language_russian () { return tr ("settingsLanguageRussian"); }
    public static string settings_language_english () { return tr ("settingsLanguageEnglish"); }
    public static string info_section_title () { return tr ("infoSectionTitle"); }

    // MARK: - Статусные сообщения
    public static string status_select_target ()  { return tr ("statusSelectTarget"); }
    public static string status_select_checker () { return tr ("statusSelectChecker"); }
    public static string status_roll_dice ()      { return tr ("statusRollDice"); }
    public static string status_rolloff_prompt () { return tr ("statusRollOffPrompt"); }
    public static string status_new_game ()       { return tr ("statusNewGame"); }
    public static string no_available_moves ()    { return tr ("statusNoAvailableMoves"); }
    public static string status_rolloff_tie ()    { return tr ("statusRollOffTie"); }
    public static string status_rolloff_tie_label () { return tr ("statusRollOffTieLabel"); }
    public static string status_rolloff_result (string player) {
        return format ("statusRollOffResult", new string[] { "player", player });
    }
    public static string skipped_dice_status (string dice) {
        return format ("statusSkippedDice", new string[] { "dice", dice });
    }
    public static string settings_theme_label () { return tr ("settingsThemeLabel"); }
    public static string settings_theme_wood ()  { return tr ("settingsThemeWood"); }
    public static string settings_theme_marble () { return tr ("settingsThemeMarble"); }
    public static string settings_movement_type_label () { return tr ("settingsMovementTypeLabel"); }
    public static string settings_movement_type_straight () { return tr ("settingsMovementTypeStraight"); }
    public static string settings_movement_type_arc () { return tr ("settingsMovementTypeArc"); }
    public static string settings_ai_difficulty_label () { return tr ("settingsAIDifficultyLabel"); }
    public static string settings_ai_master () { return tr ("settingsAIMaster"); }
    public static string settings_ai_standard () { return tr ("settingsAIStandard"); }
    public static string settings_dice_animation_label () { return tr ("settingsDiceAnimationLabel"); }
    public static string settings_dice_animation_board () { return tr ("settingsDiceAnimationBoard"); }
    public static string settings_dice_animation_panel () { return tr ("settingsDiceAnimationPanel"); }
    public static string settings_section_log () { return tr ("settingsSectionLog"); }
    public static string settings_highlight_log_paths_label () { return tr ("settingsHighlightLogPathsLabel"); }
    public static string settings_show_cell_indices_label () { return tr ("settingsShowCellIndicesLabel"); }

    public static string status_rolloff_ai () { return tr ("statusRollOffAI"); }
    public static string status_move_blocked_by_opponent () { return tr ("statusMoveBlockedByOpponent"); }
    public static string status_head_limit_reached () { return tr ("statusHeadLimitReached"); }
    public static string status_computer_rolled () { return tr ("statusRollDice"); }
    public static string status_double_doubled () { return tr ("statusDoubleDoubled"); }
    public static string status_computer_moving () { return tr ("statusComputerMoving"); }
    public static string pip_count_label ()       { return tr ("pipCountTitle") + ":"; }

    // MARK: - Бейджи
    public static string badge_turn_number (int turn) {
        return format ("badgeTurnNumber", new string[] { "turn", "%d".printf (turn) });
    }
    public static string badge_double ()          { return tr ("badgeDouble"); }
    public static string badge_first_move ()      { return tr ("badgeFirstMove"); }
    public static string badge_tie ()             { return tr ("badgeTie"); }
    public static string badge_rolloff ()         { return tr ("badgeRollOff"); }

    // MARK: - Экран завершения игры
    public static string game_over_moves_stat ()  { return tr ("gameOverMovesStat"); }
    public static string game_over_doubles_stat (){ return tr ("gameOverDoublesStat"); }
    public static string game_over_fellout_dice_stat () { return tr ("gameOverFelloutDiceStat"); }
    public static string game_over_burned_dice_stat ()  { return tr ("gameOverBurnedDiceStat"); }
    public static string game_over_score_stat ()  { return tr ("gameOverScoreStat"); }
    public static string game_over_button_new_game () { return tr ("gameOverButtonNewGame"); }
    public static string victory_mars ()          { return tr ("victoryMars"); }
    public static string victory_home_mars ()     { return tr ("victoryHomeMars"); }
    public static string victory_oin ()           { return tr ("victoryOin"); }
    public static string victory_white ()         { return tr ("victoryWhite"); }
    public static string victory_black ()         { return tr ("victoryBlack"); }

    // MARK: - Подтверждение новой игры
    public static string confirm_new_game_title () { return tr ("confirmNewGameTitle"); }
    public static string confirm_new_game_message (string loser) {
        return format ("confirmNewGameMessage", new string[] { "loser", loser });
    }
    public static string confirm_new_game_start () { return tr ("confirmNewGameStart"); }
    public static string confirm_new_game_cancel () { return tr ("confirmNewGameCancel"); }

    // MARK: - Восстановление сохранённой игры
    public static string restore_game_title ()    { return tr ("restoreGameTitle"); }
    public static string restore_game_message (string player) {
        return format ("restoreGameMessage", new string[] { "player", player });
    }
    public static string restore_game_continue () { return tr ("restoreGameContinue"); }
    public static string restore_game_forfeit ()  { return tr ("restoreGameForfeit"); }

    // MARK: - Правила игры
    public static string rules_title () { return tr ("rulesTitle"); }
    public static string rules_goal_title () { return tr ("rulesGoalTitle"); }
    public static string rules_goal_text () { return tr ("rulesGoalText"); }
    public static string rules_movement_title () { return tr ("rulesMovementTitle"); }
    public static string rules_movement_text () { return tr ("rulesMovementText"); }
    public static string rules_dice_title () { return tr ("rulesDiceTitle"); }
    public static string rules_dice_text () { return tr ("rulesDiceText"); }
    public static string rules_head_title () { return tr ("rulesHeadTitle"); }
    public static string rules_head_text () { return tr ("rulesHeadText"); }
    public static string rules_block_title () { return tr ("rulesBlockTitle"); }
    public static string rules_block_text () { return tr ("rulesBlockText"); }
    public static string rules_home_title () { return tr ("rulesHomeTitle"); }
    public static string rules_home_text () { return tr ("rulesHomeText"); }
    public static string rules_victory_title () { return tr ("rulesVictoryTitle"); }
    public static string rules_victory_text () { return tr ("rulesVictoryText"); }
    public static string rules_tip_title () { return tr ("rulesTipTitle"); }
    public static string rules_tip_text () { return tr ("rulesTipText"); }

    // MARK: - Отладка
    public static string debug_export_success () { return tr ("debugExportSuccess"); }
    public static string debug_export_success_prefix () { return tr ("debugExportSuccessPrefix"); }
    public static string debug_export_title () { return tr ("debugExportTitle"); }
    public static string debug_export_turn () { return tr ("debugExportTurn"); }
    public static string debug_export_pips () { return tr ("debugExportPips"); }
    public static string debug_export_board () { return tr ("debugExportBoard"); }
    public static string debug_export_white_log () { return tr ("debugExportWhiteLog"); }
    public static string debug_export_black_log () { return tr ("debugExportBlackLog"); }
    public static string debug_export_settings () { return tr ("debugExportSettings"); }
    public static string debug_export_none () { return tr ("debugExportNone"); }
}

} /* namespace Longbackgammon */