namespace Longbackgammon {

/**
 * Логика сохранения, восстановления партии и форфейта (сдачи).
 */
public class GameSessionStorage {

    public static void save_on_close (GameSession session) {
        if (session.is_game_over) {
            SavedGameStore.shared ().clear ();
            return;
        }
        if (session.is_game_in_progress) {
            save_to_store (session);
        } else if (!SavedGameStore.shared ().has_saved_game) {
            SavedGameStore.shared ().clear ();
        }
    }

    /** Завершает текущую игру форфейтом: текущий игрок проигрывает. */
    public static void forfeit_current_game (GameSession session) {
        if (session.is_game_started && !session.is_game_over) {
            var loser_color = session.current_player;
            var loser_name = session.player_name (loser_color);
            if (!session.is_computer_player (loser_color)) {
                StatsStore.shared ().record_loss (loser_name);
            }
            var winner_color = loser_color.opposite ();
            if (!session.is_computer_player (winner_color)) {
                StatsStore.shared ().record_victory (session.player_name (winner_color), VictoryType.OIN);
            }
            SavedGameStore.shared ().clear ();
            session.force_new_game ();
        } else {
            var saved_data = SavedGameStore.shared ().load ();
            if (saved_data != null) {
                var loser_color = saved_data.current_player;
                var loser_name = loser_color == CheckerColor.WHITE ? saved_data.white_player_name : saved_data.black_player_name;
                if (!saved_data.is_black_computer || loser_color == CheckerColor.WHITE) {
                    StatsStore.shared ().record_loss (loser_name);
                }
                var winner_color = loser_color.opposite ();
                var winner_name = winner_color == CheckerColor.WHITE ? saved_data.white_player_name : saved_data.black_player_name;
                if (!saved_data.is_black_computer || winner_color == CheckerColor.WHITE) {
                    StatsStore.shared ().record_victory (winner_name, VictoryType.OIN);
                }
                SavedGameStore.shared ().clear ();
                session.force_new_game ();
            } else {
                SavedGameStore.shared ().clear ();
                session.force_new_game ();
            }
        }
    }

    /** Сохраняет текущее состояние игры в SavedGameStore. */
    public static void save_to_store (GameSession session) {
        if (!session.is_game_in_progress) {
            return;
        }
        // Никогда не перезаписываем сохранение пустой доской (inTray)
        if (!session.board.has_any_checkers_on_board ()) {
            return;
        }
        var data = new SavedGameData ();
        data.stacks = SavedGameStore.stacks_from_board (session.board);
        data.white_borne_off_ids = copy_uint8 (session.board.white_borne_off_ids);
        data.black_borne_off_ids = copy_uint8 (session.board.black_borne_off_ids);

        data.current_player = session.current_player;
        data.is_game_started = session.is_game_started;
        data.is_game_over = session.is_game_over;
        data.showing_game_over_result = session.showing_game_over_result;
        data.is_white_first_turn = session.is_white_first_turn;
        data.is_black_first_turn = session.is_black_first_turn;
        data.is_first_move_rolloff_in_progress = session.is_first_move_rolloff_in_progress;
        data.white_rolloff_die1 = session.white_rolloff_dice == null ? 0 : session.white_rolloff_dice.die1;
        data.white_rolloff_die2 = session.white_rolloff_dice == null ? 0 : session.white_rolloff_dice.die2;
        data.black_rolloff_die1 = session.black_rolloff_dice == null ? 0 : session.black_rolloff_dice.die1;
        data.black_rolloff_die2 = session.black_rolloff_dice == null ? 0 : session.black_rolloff_dice.die2;
        data.dice_roll_die1 = session.dice_roll == null ? 0 : session.dice_roll.die1;
        data.dice_roll_die2 = session.dice_roll == null ? 0 : session.dice_roll.die2;
        data.remaining_dice = GameSession.copy_int_array (session.remaining_dice);

        data.white_moves_count = session.white_moves_count;
        data.black_moves_count = session.black_moves_count;
        data.white_doubles_count = session.white_doubles_count;
        data.black_doubles_count = session.black_doubles_count;
        data.white_total_dice_sum = session.white_total_dice_sum;
        data.black_total_dice_sum = session.black_total_dice_sum;
        data.white_burned_dice_sum = session.white_burned_dice_sum;
        data.black_burned_dice_sum = session.black_burned_dice_sum;

        data.white_turn_log = session.white_turn_log;
        data.black_turn_log = session.black_turn_log;
        data.white_player_name = session.white_player_name;
        data.black_player_name = session.black_player_name;
        data.is_black_computer = session.is_black_computer;
        data.is_auto_playing_black = session.is_auto_playing_black;
        data.board_side = SettingsStore.shared ().board_side.to_raw ();
        data.checkers_moved_from_head_this_turn = session.checkers_moved_from_head_this_turn;
        data.current_turn_record = session.current_turn_record;
        data.move_history = session.move_history;

        SavedGameStore.shared ().save (data);
    }

    /** Восстанавливает игру из структуры сохранённых данных партии. */
    public static void restore_from_store (GameSession session, SavedGameData data) {
        session.cancel_all_tasks ();

        var target_board = SavedGameStore.board_from_data (data.stacks, data.white_borne_off_ids, data.black_borne_off_ids);
        session.board = GameBoard.in_tray ();
        session.current_player = data.current_player;
        session.is_game_started = data.is_game_started;
        session.is_game_over = data.is_game_over;
        session.showing_game_over_result = data.showing_game_over_result;
        session.is_white_first_turn = data.is_white_first_turn;
        session.is_black_first_turn = data.is_black_first_turn;
        session.is_first_move_rolloff_in_progress = data.is_first_move_rolloff_in_progress;
        session.white_rolloff_dice = (data.white_rolloff_die1 > 0 && data.white_rolloff_die2 > 0)
            ? new DiceRoll (data.white_rolloff_die1, data.white_rolloff_die2) : null;
        session.black_rolloff_dice = (data.black_rolloff_die1 > 0 && data.black_rolloff_die2 > 0)
            ? new DiceRoll (data.black_rolloff_die1, data.black_rolloff_die2) : null;
        if (data.is_first_move_rolloff_in_progress) {
            if (session.white_rolloff_dice != null && session.black_rolloff_dice != null) {
                var w_sum = session.white_rolloff_dice.die1 + session.white_rolloff_dice.die2;
                var b_sum = session.black_rolloff_dice.die1 + session.black_rolloff_dice.die2;
                if (w_sum == b_sum) {
                    session.rolloff_active_player = null;
                } else {
                    session.rolloff_active_player = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
                }
            } else {
                session.rolloff_active_player = (session.white_rolloff_dice == null) ? CheckerColor.WHITE : CheckerColor.BLACK;
            }
        } else {
            session.rolloff_active_player = null;
        }
        session.rolloff_animation_id = 0;
        session.rolling_die_index = -1;
        session.is_rolling = false;
        session.is_doubling = false;
        session.is_no_moves_flashing = false;
        session.is_dice_flash_active = false;
        session.dice_flash_opacity = 0.0;
        session.suppress_dice_cursor = false;

        session.dice_roll = (data.dice_roll_die1 > 0 && data.dice_roll_die2 > 0)
            ? new DiceRoll (data.dice_roll_die1, data.dice_roll_die2) : null;
        session.remaining_dice = GameSession.copy_int_array (data.remaining_dice);

        session.white_moves_count = data.white_moves_count;
        session.black_moves_count = data.black_moves_count;
        session.white_doubles_count = data.white_doubles_count;
        session.black_doubles_count = data.black_doubles_count;
        session.white_total_dice_sum = data.white_total_dice_sum;
        session.black_total_dice_sum = data.black_total_dice_sum;
        session.white_burned_dice_sum = data.white_burned_dice_sum;
        session.black_burned_dice_sum = data.black_burned_dice_sum;

        SettingsStore.shared ().set_opponent (data.is_black_computer ? Opponent.COMPUTER : Opponent.HUMAN);
        if (data.board_side != null && data.board_side != "") {
            SettingsStore.shared ().set_board_side (BoardSide.from_raw (data.board_side));
        }

        session.white_player_name = data.white_player_name;
        session.black_player_name = data.black_player_name;
        session.checkers_moved_from_head_this_turn = data.checkers_moved_from_head_this_turn;
        session.is_auto_playing_black = data.is_auto_playing_black;

        session.white_turn_log = data.white_turn_log;
        session.black_turn_log = data.black_turn_log;

        if (data.current_turn_record != null) {
            session.current_turn_record = data.current_turn_record;
        } else if (session.dice_roll != null) {
            var t_num = (session.current_player == CheckerColor.WHITE
                ? GameSession.non_rolloff_count (session.white_turn_log) : GameSession.non_rolloff_count (session.black_turn_log)) + 1;
            session.current_turn_record = new TurnRecord.with_dice (t_num, new DiceRoll (session.dice_roll.die1, session.dice_roll.die2));
        } else {
            session.current_turn_record = null;
        }

        if (session.dice_roll != null) {
            var all_vals = GameSession.move_values (session.dice_roll);
            var rem = GameSession.copy_int_array (session.remaining_dice);
            var dice = new TurnDie[0];
            for (var i = 0; i < all_vals.length; i++) {
                var r_idx = GameSession.index_of (rem, all_vals[i]);
                if (r_idx >= 0) {
                    rem = GameSession.remove_at (rem, r_idx);
                    dice += new TurnDie (i, all_vals[i], false);
                } else {
                    dice += new TurnDie (i, all_vals[i], true);
                }
            }
            session.current_turn_dice = dice;
        } else {
            session.current_turn_dice = new TurnDie[0];
        }

        session.highlighted_log_id = -1;
        session.selected_point = null;
        session.move_history = data.move_history;

        session.notify_changed ();
        session.restoring_logs_animated ();

        session.animate_placement (target_board, true, false, () => {
            update_status_on_restore (session);
            session.update_available_moves_cache ();

            var g = session.gen;
            if (session.is_first_move_rolloff_in_progress) {
                if (session.white_rolloff_dice != null && session.black_rolloff_dice != null) {
                    // A saved game may have been closed after both players rolled
                    // but before the tie/winner presentation completed.
                    var white_result = new DiceRoll (session.white_rolloff_dice.die1, session.white_rolloff_dice.die2);
                    var black_result = new DiceRoll (session.black_rolloff_dice.die1, session.black_rolloff_dice.die2);
                    session.after (0.6, () => {
                        var white_sum = white_result.die1 + white_result.die2;
                        var black_sum = black_result.die1 + black_result.die2;
                        if (white_sum == black_sum) {
                            session.handle_rolloff_tie.begin (white_result, black_result, g);
                        } else {
                            var winner = white_sum > black_sum
                                ? CheckerColor.WHITE : CheckerColor.BLACK;
                            session.handle_rolloff_win.begin (winner, white_result, black_result, g);
                        }
                    });
                } else if (session.is_computer_turn) {
                    session.after (0.6, () => {
                        session.roll_dice ();
                    });
                }
            } else if (session.is_computer_turn) {
                if (session.dice_roll != null) {
                    if (session.remaining_dice.length > 0) {
                        session.status_message = Localization.status_computer_moving ();
                        session.after (0.5, () => {
                            session.perform_computer_turn.begin (g);
                        });
                    } else {
                        session.status_message = Localization.status_roll_dice ();
                        session.after (0.0, () => {
                            session.end_turn ();
                        });
                    }
                } else {
                    session.auto_play_if_needed ();
                }
            } else {
                if (session.dice_roll != null) {
                    session.check_and_auto_end_turn ();
                }
            }
            session.notify_changed ();
        });
    }

    private static void update_status_on_restore (GameSession session) {
        if (session.is_game_over) {
            session.status_message = (session.current_player == CheckerColor.WHITE)
                ? Localization.victory_white () : Localization.victory_black ();
        } else if (session.is_first_move_rolloff_in_progress) {
            if (session.white_rolloff_dice != null && session.black_rolloff_dice != null) {
                var w_sum = session.white_rolloff_dice.die1 + session.white_rolloff_dice.die2;
                var b_sum = session.black_rolloff_dice.die1 + session.black_rolloff_dice.die2;
                if (w_sum == b_sum) {
                    session.status_message = Localization.status_rolloff_tie ();
                } else {
                    var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
                    session.status_message = Localization.status_rolloff_result (session.player_name (winner));
                }
            } else {
                session.status_message = session.is_computer_turn
                    ? Localization.status_rolloff_ai () : Localization.status_rolloff_prompt ();
            }
        } else if (session.dice_roll == null) {
            session.status_message = session.is_computer_turn
                ? Localization.status_computer_moving () : Localization.status_roll_dice ();
        } else if (session.remaining_dice.length == 0) {
            session.status_message = Localization.status_roll_dice ();
        } else {
            session.status_message = (session.selected_point == null)
                ? Localization.status_select_checker () : Localization.status_select_target ();
        }
    }

    private static uint8[] copy_uint8 (uint8[] src) {
        var copy = new uint8[src.length];
        for (var i = 0; i < src.length; i++) {
            copy[i] = src[i];
        }
        return copy;
    }

    /** Настройка тестовой расстановки перед победным ходом дублем 2-2. */
    public static void setup_test_last_move (GameSession session) {
        session.board = new GameBoard ();
        // У белых осталась 1 фишка на лунке 1 (P1)
        session.board.stacks[1] = new PointStack.with_ids (CheckerColor.WHITE, new uint8[] { 0 });
        var w_off = new uint8[14];
        for (var i = 0; i < 14; i++) {
            w_off[i] = (uint8) (i + 1);
        }
        session.board.white_borne_off_ids = w_off;

        // У чёрных 15 фишек: 2:B1 3:B1 4:B1 5:B1 6:B2 13:B6 14:B2 24:B1
        session.board.stacks[2] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 15 });
        session.board.stacks[3] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 16 });
        session.board.stacks[4] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 17 });
        session.board.stacks[5] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 18 });
        session.board.stacks[6] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 19, 20 });
        session.board.stacks[13] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 21, 22, 23, 24, 25, 26 });
        session.board.stacks[14] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 27, 28 });
        session.board.stacks[24] = new PointStack.with_ids (CheckerColor.BLACK, new uint8[] { 29 });
        session.board.black_borne_off_ids = new uint8[0];

        session.is_game_started = true;
        session.is_game_over = false;
        session.showing_game_over_result = false;
        session.current_player = CheckerColor.WHITE;
        SettingsStore.shared ().set_opponent (Opponent.COMPUTER);
        session.is_auto_playing_black = false;
        session.white_player_name = "Алексей";
        session.black_player_name = "Computer";
        session.is_first_move_rolloff_in_progress = false;
        session.rolloff_active_player = null;
        session.is_rolling = false;
        session.is_animating = false;
        session.selected_point = null;
        session.move_history = new MoveSnapshot[0];
        session.checkers_moved_from_head_this_turn = 0;

        session.white_moves_count = 41;
        session.black_moves_count = 41;
        session.white_doubles_count = 5;
        session.black_doubles_count = 6;
        session.white_total_dice_sum = 300;
        session.black_total_dice_sum = 240;
        session.white_burned_dice_sum = 0;
        session.black_burned_dice_sum = 38;

        session.dice_roll = new DiceRoll (2, 2);
        session.remaining_dice = new int[] { 2, 2, 2, 2 };
        session.current_turn_dice = new TurnDie[] {
            new TurnDie (0, 2, false, false),
            new TurnDie (1, 2, false, false),
            new TurnDie (2, 2, false, false),
            new TurnDie (3, 2, false, false)
        };
        session.current_turn_record = new TurnRecord.with_dice (42, new DiceRoll (2, 2));
        session.current_turn_record.dice = TurnDie.clone_array (session.current_turn_dice);
        session.double_division_progress = 1.0;
        session.status_message = Localization.status_select_checker ();

        // Предыдущие ходы в логах для полноты картины
        var prev_w = new TurnRecord.with_dice (41, new DiceRoll (6, 1));
        prev_w.move_strings = new string[] { "1-^", "1-^" };
        prev_w.dice = new TurnDie[] { new TurnDie (0, 6, true, false), new TurnDie (1, 1, true, false) };
        session.white_turn_log = new TurnRecord[] { prev_w };

        var prev_b = new TurnRecord.with_dice (41, new DiceRoll (1, 1));
        prev_b.move_strings = new string[] { "6-5-4-3-2" };
        prev_b.dice = new TurnDie[] {
            new TurnDie (0, 1, true, false), new TurnDie (1, 1, true, false),
            new TurnDie (2, 1, true, false), new TurnDie (3, 1, true, false)
        };
        session.black_turn_log = new TurnRecord[] { prev_b };

        session.update_available_moves_cache ();
        session.notify_changed ();
    }
}

} /* namespace Longbackgammon */

