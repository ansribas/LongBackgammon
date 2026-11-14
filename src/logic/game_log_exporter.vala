namespace Longbackgammon {

/**
 * Утилиты для форматирования и экспорта логов партии.
 */
public class GameLogExporter {

    /** Имя игрока на английском для логов (GameLogStore). */
    public static string english_player_name (CheckerColor color) {
        var store = SettingsStore.shared ();
        if (color == CheckerColor.WHITE) {
            var trimmed = store.white_player_name.strip ();
            if (trimmed != "") {
                return trimmed;
            }
            return store.opponent == Opponent.COMPUTER ? "Player" : "Player 1";
        }
        if (store.opponent == Opponent.COMPUTER) {
            return "Computer";
        }
        var trimmed = store.black_player_name.strip ();
        return trimmed == "" ? "Player 2" : trimmed;
    }

    /** Текстовый дамп состояния на английском (для GameLogStore). */
    public static string generate_log_text (GameSession session) {
        var b = new StringBuilder ();
        b.append ("--- LONG BACKGAMMON DEBUG ---\n");
        b.append ("Turn: %s\n".printf (english_player_name (session.current_player)));
        b.append ("Pips: W:%d B:%d\n".printf (session.white_pip_count, session.black_pip_count));
        b.append ("\n--- BOARD STACKS ---\n");
        append_board (b, session.board);
        b.append ("\n--- WHITE LOG ---\n");
        append_log_english (b, session, session.white_turn_log, CheckerColor.WHITE);
        b.append ("\n--- BLACK LOG ---\n");
        append_log_english (b, session, session.black_turn_log, CheckerColor.BLACK);
        b.append ("\n--- SETTINGS ---\n");
        b.append ("Game Speed: %s\n".printf (SettingsStore.shared ().game_speed == GameSpeed.FAST ? "Fast" : "Slow"));
        return b.str;
    }

    private static void append_board (StringBuilder b, GameBoard board) {
        for (var raw = 1; raw <= 24; raw++) {
            var stack = board.stack_at ((BoardPoint) raw);
            if (stack != null) {
                b.append ("%d:%s%d ".printf (raw, stack.color == CheckerColor.WHITE ? "W" : "B", stack.checker_ids.length));
            }
        }
    }

    /** Записывает выполненный ход в текущую запись лога сессии. */
    public static void record_move_in_log (GameSession session, MoveOption move, IntermediateStep[] steps) {
        if (session.current_turn_record == null) {
            return;
        }
        var log_steps = new LogStep[0];
        string move_str;

        if (steps.length > 0) {
            foreach (var s in steps) {
                log_steps += new LogStep (s.from, s.to);
            }
            var b = new StringBuilder (move.from.raw_value ().to_string ());
            foreach (var s in steps) {
                b.append_c ('-');
                b.append (s.to == null ? "^" : s.to.raw_value ().to_string ());
            }
            move_str = b.str;
        } else {
            log_steps += new LogStep (move.from, move.to);
            move_str = "%d-%s".printf (move.from.raw_value (), move.to == null ? "^" : move.to.raw_value ().to_string ());
        }

        session.current_turn_record.move_strings = ArrUtil.append_str (session.current_turn_record.move_strings, move_str);
        session.current_turn_record.moves = ArrUtil.append_move (session.current_turn_record.moves, new LogMove (log_steps));
    }

    private static void append_log_english (StringBuilder b, GameSession session, TurnRecord[] log, CheckerColor color = CheckerColor.WHITE) {
        foreach (var record in log) {
            b.append ("%d. [%d:%d] ".printf (record.turn_number, record.dice_roll.die1, record.dice_roll.die2));
            var moves = record.export_moves_string (color, session, true);
            b.append (moves == "" ? "NONE" : moves).append_c ('\n');
        }
    }

    /** Сохраняет лог завершённой партии в GameLogStore. */
    public static void save_game_log (GameSession session) {
        var text = generate_log_text (session);
        if (SettingsStore.shared ().opponent == Opponent.COMPUTER) {
            GameLogStore.shared ().add_entry (session.white_player_name, "Computer", text);
        } else {
            GameLogStore.shared ().add_entry (session.white_player_name, session.black_player_name, text);
        }
    }

    /** Локализованный дамп состояния (для копирования в буфер обмена). */
    public static string debug_export_text (GameSession session) {
        var b = new StringBuilder ();
        b.append (Localization.debug_export_title ()).append_c ('\n');
        b.append (Localization.debug_export_turn ()).append (" ").append (session.player_name (session.current_player)).append_c ('\n');
        b.append (Localization.debug_export_pips ()).append (" W:%d B:%d\n".printf (session.white_pip_count, session.black_pip_count));
        b.append ("\n").append (Localization.debug_export_board ()).append_c ('\n');
        append_board (b, session.board);
        b.append ("\n\n").append (Localization.debug_export_white_log ()).append_c ('\n');
        append_log_localized (b, session, session.white_turn_log, CheckerColor.WHITE);
        b.append ("\n").append (Localization.debug_export_black_log ()).append_c ('\n');
        append_log_localized (b, session, session.black_turn_log, CheckerColor.BLACK);
        b.append ("\n").append (Localization.debug_export_settings ()).append_c ('\n');
        b.append (Localization.settings_speed_label ()).append (": ")
         .append (SettingsStore.shared ().game_speed == GameSpeed.FAST
                  ? Localization.settings_speed_fast () : Localization.settings_speed_slow ())
         .append_c ('\n');
        return b.str;
    }

    private static void append_log_localized (StringBuilder b, GameSession session, TurnRecord[] log, CheckerColor color = CheckerColor.WHITE) {
        foreach (var record in log) {
            b.append ("%d. [%d:%d] ".printf (record.turn_number, record.dice_roll.die1, record.dice_roll.die2));
            var moves = record.export_moves_string (color, session, false);
            b.append (moves == "" ? Localization.debug_export_none () : moves);
            b.append_c ('\n');
        }
    }
}

} /* namespace Longbackgammon */

