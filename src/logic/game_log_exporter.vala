/* game_log_exporter.vala
 *
 * Утилиты для форматирования ходов и экспорта структурированного лога партии.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Утилиты для форматирования и сборки структурированных логов партии.
 */
public class GameLogExporter {

    /** Имя игрока на английском. */
    public static string english_player_name (GameSession session, CheckerColor color) {
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

    /** Сохраняет структурированный лог завершённой партии в GameLogStore. */
    public static void save_game_log (GameSession session, CheckerColor? winner_color = null, bool is_forfeit = false) {
        var resolved_winner = winner_color != null ? winner_color : session.current_player;
        var entry = build_game_log_entry (session, resolved_winner, is_forfeit);
        GameLogStore.shared ().add_entry (entry);
    }

    /** Создаёт структурированную запись партии (GameLogEntry) для архива game_logs.json. */
    public static GameLogEntry build_game_log_entry (GameSession session, CheckerColor winner_color, bool is_forfeit = false) {
        var loser_color = winner_color.opposite ();
        var victory_type = is_forfeit ? VictoryType.OIN : session.board.victory_type (loser_color);
        var points = is_forfeit ? 1 : victory_type.points ();
        string victory_type_str = is_forfeit ? "forfeit" : (
            victory_type == VictoryType.HOME_MARS ? "homeMars" : (
                victory_type == VictoryType.MARS ? "mars" : "oin"
            )
        );

        var settings = SettingsStore.shared ();
        bool white_is_comp = session.is_computer_player (CheckerColor.WHITE);
        bool black_is_comp = session.is_computer_player (CheckerColor.BLACK);
        string? ai_diff = (settings.opponent == Opponent.COMPUTER)
            ? (settings.ai_difficulty == AIDifficulty.MASTER ? "master" : "standard")
            : null;

        var players = new GameLogPlayers (
            new GameLogPlayer (session.white_player_name, white_is_comp, white_is_comp ? ai_diff : null),
            new GameLogPlayer (session.black_player_name, black_is_comp, black_is_comp ? ai_diff : null)
        );

        var log_settings = new GameLogSettings (
            settings.game_speed == GameSpeed.FAST ? "fast" : "slow",
            settings.board_theme == BoardTheme.WOOD ? "wood" : "marble",
            settings.board_side == BoardSide.RIGHT ? "right" : "left",
            settings.is_first_move_rolloff_enabled
        );

        // Финальное состояние доски
        var final_board = new GameLogPointStack[0];
        for (var raw = 1; raw <= 24; raw++) {
            var pt = (BoardPoint) raw;
            var stack = session.board.stack_at (pt);
            if (stack != null && stack.checker_ids.length > 0) {
                final_board += new GameLogPointStack (
                    raw,
                    stack.color == CheckerColor.WHITE ? "white" : "black",
                    stack.checker_ids.length
                );
            }
        }

        // Розыгрыш первого хода
        var roll_off_rounds = build_rolloff_rounds (session);
        var roll_off_winner_color = extract_rolloff_winner (session);
        GameLogRollOff? roll_off = (roll_off_rounds.length == 0) ? null : new GameLogRollOff (
            roll_off_rounds,
            roll_off_winner_color == CheckerColor.WHITE ? "white" : "black",
            session.player_name (roll_off_winner_color ?? CheckerColor.WHITE)
        );

        // Хронологический список ходов
        var turns = build_chronological_turns (session, roll_off_winner_color);

        var result = new GameLogResult (
            winner_color == CheckerColor.WHITE ? "white" : "black",
            session.player_name (winner_color),
            loser_color == CheckerColor.WHITE ? "white" : "black",
            session.player_name (loser_color),
            victory_type_str,
            points,
            is_forfeit,
            turns.length,
            new GameLogPipCount (session.white_pip_count, session.black_pip_count)
        );

        var now = new DateTime.now_utc ();
        var date_str = now.format ("%Y-%m-%dT%H:%M:%SZ");

        return new GameLogEntry (
            Uuid.string_random (),
            date_str,
            players,
            log_settings,
            result,
            roll_off,
            turns,
            final_board
        );
    }

    private static GameLogRollOffRound[] build_rolloff_rounds (GameSession session) {
        var white_rolloffs = new TurnRecord[0];
        for (var i = session.white_turn_log.length - 1; i >= 0; i--) {
            if (session.white_turn_log[i].is_rolloff) {
                white_rolloffs += session.white_turn_log[i];
            }
        }
        var black_rolloffs = new TurnRecord[0];
        for (var i = session.black_turn_log.length - 1; i >= 0; i--) {
            if (session.black_turn_log[i].is_rolloff) {
                black_rolloffs += session.black_turn_log[i];
            }
        }
        var count = int.min (white_rolloffs.length, black_rolloffs.length);
        var rounds = new GameLogRollOffRound[count];
        for (var i = 0; i < count; i++) {
            var w = white_rolloffs[i];
            var b = black_rolloffs[i];
            rounds[i] = new GameLogRollOffRound (
                i + 1,
                w.dice_roll.die1,
                b.dice_roll.die1,
                w.is_rolloff_tie ()
            );
        }
        return rounds;
    }

    private static CheckerColor? extract_rolloff_winner (GameSession session) {
        foreach (var rec in session.white_turn_log) {
            if (rec.is_rolloff && !rec.is_rolloff_tie ()) {
                if (rec.rolloff_winner != null) return rec.rolloff_winner;
                return rec.is_rolloff_winner ? CheckerColor.WHITE : CheckerColor.BLACK;
            }
        }
        return null;
    }

    private static GameLogTurn[] build_chronological_turns (GameSession session, CheckerColor? roll_off_winner) {
        CheckerColor first_player = roll_off_winner != null ? roll_off_winner : CheckerColor.WHITE;
        var white_turns = new TurnRecord[0];
        for (var i = session.white_turn_log.length - 1; i >= 0; i--) {
            var r = session.white_turn_log[i];
            if (!r.is_rolloff && r.game_result_is_win == null) {
                white_turns += r;
            }
        }
        var black_turns = new TurnRecord[0];
        for (var i = session.black_turn_log.length - 1; i >= 0; i--) {
            var r = session.black_turn_log[i];
            if (!r.is_rolloff && r.game_result_is_win == null) {
                black_turns += r;
            }
        }

        var turns = new GameLogTurn[0];
        int max_count = int.max (white_turns.length, black_turns.length);

        for (var i = 0; i < max_count; i++) {
            if (first_player == CheckerColor.WHITE) {
                if (i < white_turns.length) {
                    turns += convert_turn_record (session, white_turns[i], CheckerColor.WHITE);
                }
                if (i < black_turns.length) {
                    turns += convert_turn_record (session, black_turns[i], CheckerColor.BLACK);
                }
            } else {
                if (i < black_turns.length) {
                    turns += convert_turn_record (session, black_turns[i], CheckerColor.BLACK);
                }
                if (i < white_turns.length) {
                    turns += convert_turn_record (session, white_turns[i], CheckerColor.WHITE);
                }
            }
        }
        return turns;
    }

    private static GameLogTurn convert_turn_record (GameSession session, TurnRecord record, CheckerColor player) {
        bool is_double = record.dice_roll.is_double;
        int[] dice_values;
        if (is_double) {
            dice_values = new int[] { record.dice_roll.die1, record.dice_roll.die1, record.dice_roll.die1, record.dice_roll.die1 };
        } else {
            dice_values = new int[] { record.dice_roll.die1, record.dice_roll.die2 };
        }

        var moves = new GameLogMove[0];
        foreach (var move in record.moves) {
            if (move.steps.length > 0) {
                var first_step = move.steps[0];
                var last_step = move.steps[move.steps.length - 1];
                int from = first_step.from.raw_value ();
                int? to = null;
                if (last_step.to != null) {
                    to = last_step.to.raw_value ();
                }
                bool is_bear_off = (last_step.to == null);
                int[]? path = null;
                if (move.steps.length > 1) {
                    path = new int[move.steps.length + 1];
                    path[0] = from;
                    for (var s = 0; s < move.steps.length; s++) {
                        var step_to = move.steps[s].to;
                        path[s + 1] = (step_to != null) ? step_to.raw_value () : 0;
                    }
                }
                moves += new GameLogMove (from, to, is_bear_off, path);
            }
        }

        var skipped = record.skipped_dice_values ();
        int[]? skipped_dice = (skipped.length > 0) ? skipped : null;
        var notation = string.joinv (", ", record.move_strings);
        if (notation == "") notation = "None";

        return new GameLogTurn (
            record.turn_number,
            player == CheckerColor.WHITE ? "white" : "black",
            session.player_name (player),
            dice_values,
            is_double,
            moves,
            notation,
            skipped_dice
        );
    }
}

} /* namespace Longbackgammon */