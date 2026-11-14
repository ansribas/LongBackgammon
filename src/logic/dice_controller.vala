namespace Longbackgammon {

/**
 * Управление кубиками: броски, розыгрыш первого хода (roll-off), анимации выпадения и дублей,
 * обработка ситуаций отсутствия ходов.
 */
public class DiceController {

    /** Основной метод броска кубиков. */
    public static void roll_dice (GameSession session) {
        if (!session.can_roll) {
            return;
        }
        if (!session.is_first_move_rolloff_in_progress) {
            session.dice_roll = null;
        }
        int target_index;
        if (session.is_first_move_rolloff_in_progress) {
            target_index = (session.rolloff_active_player == CheckerColor.BLACK) ? 1 : 0;
        } else {
            target_index = -1;
        }

        session.is_rolling = true;
        session.rolling_die_index = target_index;
        session.is_animating = true;
        if (session.is_first_move_rolloff_in_progress) {
            session.status_message = session.is_computer_turn ? Localization.status_rolloff_ai () : Localization.status_rolloff_prompt ();
        } else if (session.is_computer_turn) {
            session.status_message = Localization.status_computer_moving ();
        } else {
            session.status_message = "";
        }
        session.notify_changed ();

        roll_task.begin (session, session.gen);
    }

    private static async void roll_task (GameSession session, uint g) {
        var anim = SettingsStore.shared ().animation_speed;
        var use_board_animation = SettingsStore.shared ().use_board_dice_animation;
        if (session.is_first_move_rolloff_in_progress) {
            if (use_board_animation) {
                yield handle_board_rolloff_phase (session, g);
            } else {
                SoundManager.shared ().play_dice_roll ();
                yield handle_rolloff_phase (session, anim, g);
            }
            return;
        }
        if (use_board_animation) {
            yield handle_board_normal_roll (session, g);
        } else {
            SoundManager.shared ().play_dice_roll ();
            yield handle_normal_roll (session, anim, g);
        }
    }

    private static async bool animate_rolling (GameSession session, AnimationSpeed anim, uint g) {
        for (var i = 0; i < anim.dice_rolling_steps; i++) {
            session.rolling_dice_value1 = GLib.Random.int_range (1, 7);
            session.rolling_dice_value2 = GLib.Random.int_range (1, 7);
            session.notify_changed ();
            var progress = (double) i / (double) anim.dice_rolling_steps;
            yield session.sleep_async (anim.dice_rolling_step_delay * (0.5 + progress));
            if (g != session.gen) {
                return false;
            }
        }
        return true;
    }

    private static async void resolve_rolloff (GameSession session, uint g) {
        var w_roll = session.white_rolloff_dice;
        var b_roll = session.black_rolloff_dice;
        if (w_roll == null || b_roll == null) {
            session.is_animating = false;
            session.notify_changed ();
            return;
        }
        var w_sum = w_roll.die1 + w_roll.die2;
        var b_sum = b_roll.die1 + b_roll.die2;
        if (w_sum == b_sum) {
            yield handle_rolloff_tie (session, w_roll, b_roll, g);
        } else {
            var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
            yield handle_rolloff_win (session, winner, w_roll, b_roll, g);
        }
        if (g != session.gen) {
            return;
        }
        session.is_animating = false;
        session.notify_changed ();
        if (session.is_computer_turn) {
            session.auto_play_if_needed ();
        }
    }

    private static async void handle_rolloff_phase (GameSession session, AnimationSpeed anim, uint g) {
        if (session.white_rolloff_dice == null) {
            yield rolloff_white (session, anim, g);
        } else if (session.black_rolloff_dice == null) {
            yield rolloff_black (session, anim, g);
        } else {
            yield resolve_rolloff (session, g);
        }
    }

    private static async void rolloff_white (GameSession session, AnimationSpeed anim, uint g) {
        if (!(yield animate_rolling (session, anim, g))) {
            return;
        }
        var roll = DiceRoll.random ();
        session.white_rolloff_dice = roll;
        session.rolling_dice_value1 = roll.die1;
        session.rolling_dice_value2 = roll.die2;
        session.white_total_dice_sum += roll.die1 + roll.die2;
        session.is_rolling = false;
        session.rolling_die_index = 0;
        session.suppress_dice_cursor = true;
        session.is_animating = false;
        session.status_message = "";
        session.notify_changed ();

        yield session.sleep_async (0.75);
        if (g != session.gen) {
            return;
        }

        session.rolloff_active_player = CheckerColor.BLACK;

        if (session.is_black_computer) {
            session.status_message = Localization.status_rolloff_ai ();
            session.notify_changed ();
            yield session.sleep_async (0.60);
            if (g != session.gen) {
                return;
            }
            session.suppress_dice_cursor = false;
            roll_dice (session);
        } else {
            session.status_message = Localization.status_rolloff_prompt ();
            session.suppress_dice_cursor = false;
            session.notify_changed ();
        }
    }

    private static async void rolloff_black (GameSession session, AnimationSpeed anim, uint g) {
        if (!(yield animate_rolling (session, anim, g))) {
            return;
        }
        var roll = DiceRoll.random ();
        session.black_rolloff_dice = roll;
        session.rolling_dice_value1 = roll.die1;
        session.rolling_dice_value2 = roll.die2;
        session.black_total_dice_sum += roll.die1 + roll.die2;
        session.is_rolling = false;
        session.rolling_die_index = 1;
        session.notify_changed ();

        yield session.sleep_async (0.75);
        if (g != session.gen) {
            return;
        }

        yield resolve_rolloff (session, g);
    }

    private static TurnRecord make_rolloff_record (DiceRoll roll, string text, bool winner, CheckerColor? winner_color) {
        var r = new TurnRecord.with_dice (0, new DiceRoll (roll.die1, roll.die2));
        r.is_rolloff = true;
        r.is_rolloff_winner = winner;
        r.rolloff_winner = winner_color;
        r.move_strings = new string[] { text };
        return r;
    }

    public static async void handle_rolloff_tie (GameSession session, DiceRoll w_roll, DiceRoll b_roll, uint g) {
        session.rolloff_active_player = null;
        session.status_message = Localization.status_rolloff_tie ();
        var tie_label = Localization.status_rolloff_tie_label ();
        var is_already_logged = session.white_turn_log.length > 0 && session.black_turn_log.length > 0
            && session.white_turn_log[0].is_rolloff_tie ()
            && GameSession.same_roll (session.white_turn_log[0].dice_roll, w_roll)
            && GameSession.same_roll (session.black_turn_log[0].dice_roll, b_roll);
        if (!is_already_logged) {
            session.insert_log_record (CheckerColor.WHITE, make_rolloff_record (w_roll, tie_label, false, null));
            session.insert_log_record (CheckerColor.BLACK, make_rolloff_record (b_roll, tie_label, false, null));
        }

        session.rolloff_animation_id = ++session.rolloff_anim_counter;
        session.notify_changed ();

        yield session.sleep_async (1.2);
        if (g != session.gen) {
            return;
        }
        session.rolloff_active_player = CheckerColor.WHITE;
        session.suppress_dice_cursor = false;
        session.white_rolloff_dice = null;
        session.black_rolloff_dice = null;
        session.board_dice_state = null;
        session.rolloff_animation_id = 0;
        session.rolling_dice_value1 = 6;
        session.rolling_dice_value2 = 6;
        session.rolling_die_index = -1;
        session.status_message = Localization.status_rolloff_prompt ();
        session.notify_changed ();
    }

    public static async void handle_rolloff_win (GameSession session, CheckerColor winner, DiceRoll w_roll, DiceRoll b_roll, uint g) {
        session.rolloff_active_player = winner;
        var result_msg = Localization.status_rolloff_result (session.player_name (winner));
        session.status_message = result_msg;
        var is_already_logged = session.white_turn_log.length > 0 && session.black_turn_log.length > 0
            && session.white_turn_log[0].is_rolloff && session.white_turn_log[0].rolloff_winner == winner
            && GameSession.same_roll (session.white_turn_log[0].dice_roll, w_roll)
            && GameSession.same_roll (session.black_turn_log[0].dice_roll, b_roll);
        if (!is_already_logged) {
            session.insert_log_record (CheckerColor.WHITE, make_rolloff_record (w_roll, result_msg, winner == CheckerColor.WHITE, winner));
            session.insert_log_record (CheckerColor.BLACK, make_rolloff_record (b_roll, result_msg, winner == CheckerColor.BLACK, winner));
        }

        session.rolloff_animation_id = ++session.rolloff_anim_counter;
        session.notify_changed ();

        yield session.sleep_async (1.2);
        if (g != session.gen) {
            return;
        }

        session.is_first_move_rolloff_in_progress = false;
        session.rolloff_active_player = null;
        session.suppress_dice_cursor = false;
        session.current_player = winner;
        session.white_rolloff_dice = null;
        session.black_rolloff_dice = null;
        session.board_dice_state = null;
        session.rolloff_animation_id = 0;
        session.dice_roll = null;
        session.remaining_dice = new int[0];
        session.rolling_die_index = -1;
        session.status_message = session.is_computer_turn ? Localization.status_computer_moving () : Localization.status_roll_dice ();
        // Автосохранение после определения победителя жеребьёвки первого хода
        session.save_to_store ();
        session.notify_changed ();
    }

    public static void apply_dice_roll (GameSession session, DiceRoll roll) {
        session.dice_roll = roll;
        session.is_rolling = false;
        session.rolling_dice_value1 = roll.die1;
        session.rolling_dice_value2 = roll.die2;

        var t_num = (session.current_player == CheckerColor.WHITE
            ? GameSession.non_rolloff_count (session.white_turn_log)
            : GameSession.non_rolloff_count (session.black_turn_log)) + 1;
        session.current_turn_record = new TurnRecord.with_dice (t_num, roll);

        var values = GameSession.move_values (roll);
        if (session.current_player == CheckerColor.WHITE) {
            session.white_moves_count += 1;
            session.white_total_dice_sum += GameSession.sum_ints (values);
            if (roll.is_double) {
                session.white_doubles_count += 1;
            }
        } else {
            session.black_moves_count += 1;
            session.black_total_dice_sum += GameSession.sum_ints (values);
            if (roll.is_double) {
                session.black_doubles_count += 1;
            }
        }

        session.move_history = new MoveSnapshot[0];
        session.remaining_dice = values;
        var dice = new TurnDie[0];
        for (var i = 0; i < values.length; i++) {
            dice += new TurnDie (i, values[i]);
        }
        session.current_turn_dice = dice;
        session.double_division_progress = roll.is_double ? 0.0 : 1.0;
        session.current_turn_record.dice = TurnDie.clone_array (session.current_turn_dice);
        session.selected_point = null;
        session.checkers_moved_from_head_this_turn = 0;
        // Автосохранение партии после броска кубиков
        session.save_to_store ();
    }

    private static async bool await_board_dice_animation (GameSession session, double duration, string state_id, uint g) {
        yield session.sleep_async (duration);
        if (g != session.gen) {
            cleanup_board_dice (session, state_id);
            return false;
        }
        yield session.sleep_async (0.70);
        if (g != session.gen) {
            cleanup_board_dice (session, state_id);
            return false;
        }
        if (session.board_dice_state != null && session.board_dice_state.id == state_id) {
            session.board_dice_state.is_transferring = true;
            session.board_dice_state.transfer_start_time_us = GLib.get_monotonic_time ();
            session.notify_changed ();
        }
        yield session.sleep_async (0.38);
        cleanup_board_dice (session, state_id);
        return g == session.gen;
    }

    private static void cleanup_board_dice (GameSession session, string state_id) {
        if (session.board_dice_state != null && session.board_dice_state.id == state_id) {
            session.board_dice_state = null;
        }
    }

    private static async void handle_board_rolloff_phase (GameSession session, uint g) {
        var duration = (SettingsStore.shared ().game_speed == GameSpeed.SLOW) ? 2.10 : 1.75;
        if (session.white_rolloff_dice == null) {
            yield rolloff_white_board (session, duration, g);
        } else if (session.black_rolloff_dice == null) {
            yield rolloff_black_board (session, duration, g);
        } else {
            yield resolve_rolloff (session, g);
        }
    }

    private static async void rolloff_white_board (GameSession session, double duration, uint g) {
        var roll = DiceRoll.random ();
        var state = new BoardDiceState (CheckerColor.WHITE, roll, duration);
        session.board_dice_state = state;
        session.rolling_die_index = -1;
        session.notify_changed ();

        if (!(yield await_board_dice_animation (session, duration, state.id, g))) {
            return;
        }

        session.white_rolloff_dice = roll;
        session.rolling_dice_value1 = roll.die1;
        session.rolling_dice_value2 = roll.die2;
        session.white_total_dice_sum += roll.die1 + roll.die2;
        session.is_rolling = false;
        session.rolling_die_index = 0;
        session.suppress_dice_cursor = true;
        session.is_animating = false;
        session.status_message = "";
        session.notify_changed ();

        yield session.sleep_async (0.75);
        if (g != session.gen) {
            return;
        }

        session.rolloff_active_player = CheckerColor.BLACK;

        if (session.is_black_computer) {
            session.status_message = Localization.status_rolloff_ai ();
            session.notify_changed ();
            yield session.sleep_async (0.60);
            if (g != session.gen) {
                return;
            }
            session.suppress_dice_cursor = false;
            roll_dice (session);
        } else {
            session.status_message = Localization.status_rolloff_prompt ();
            session.suppress_dice_cursor = false;
            session.notify_changed ();
        }
    }

    private static async void rolloff_black_board (GameSession session, double duration, uint g) {
        var roll = DiceRoll.random ();
        var state = new BoardDiceState (CheckerColor.BLACK, roll, duration);
        session.board_dice_state = state;
        session.rolling_die_index = -1;
        session.notify_changed ();

        if (!(yield await_board_dice_animation (session, duration, state.id, g))) {
            return;
        }

        session.black_rolloff_dice = roll;
        session.rolling_dice_value1 = roll.die1;
        session.rolling_dice_value2 = roll.die2;
        session.black_total_dice_sum += roll.die1 + roll.die2;
        session.is_rolling = false;
        session.rolling_die_index = 1;
        session.notify_changed ();

        yield session.sleep_async (0.75);
        if (g != session.gen) {
            return;
        }

        yield resolve_rolloff (session, g);
    }

    private static async void handle_board_normal_roll (GameSession session, uint g) {
        var is_comp = session.is_computer_turn;
        session.rolling_die_index = -1;
        if (is_comp) {
            session.status_message = Localization.status_computer_moving ();
        }
        var duration = (SettingsStore.shared ().game_speed == GameSpeed.SLOW) ? 2.10 : 1.75;
        var roll = DiceRoll.random ();
        var state = new BoardDiceState (session.current_player, roll, duration);
        session.board_dice_state = state;
        session.notify_changed ();

        if (!(yield await_board_dice_animation (session, duration, state.id, g))) {
            return;
        }

        var rolling_player = session.current_player;
        apply_dice_roll (session, roll);
        session.update_available_moves_cache ();
        session.notify_changed ();

        yield finish_normal_roll (session, roll, rolling_player, is_comp, g);
    }

    private static async void handle_normal_roll (GameSession session, AnimationSpeed anim, uint g) {
        session.rolling_die_index = -1;
        var is_comp = session.is_computer_turn;
        if (is_comp) {
            session.status_message = Localization.status_computer_moving ();
        }
        if (!(yield animate_rolling (session, anim, g))) {
            return;
        }

        var roll = DiceRoll.random ();
        var rolling_player = session.current_player;
        apply_dice_roll (session, roll);
        session.update_available_moves_cache ();
        session.notify_changed ();

        yield finish_normal_roll (session, roll, rolling_player, is_comp, g);
    }

    private static async void finish_normal_roll (GameSession session, DiceRoll roll, CheckerColor rolling_player, bool is_comp, uint g) {
        if (session.current_player == rolling_player && session.is_game_started && !session.is_game_over) {
            if (roll.is_double) {
                yield handle_double_animation (session, g);
                if (g != session.gen) {
                    return;
                }
            }
        }

        if (session.current_player != rolling_player || !session.is_game_started || session.is_game_over) {
            return;
        }

        if (!is_comp) {
            session.status_message = Localization.status_select_checker ();
            session.is_animating = false;
            session.notify_changed ();
        }

        var has_playable = false;
        foreach (var o in session.cached_legal_options) {
            if (!o.is_illegal_prime) {
                has_playable = true;
                break;
            }
        }
        var initial_dice_count = GameSession.move_values (roll).length;
        if (!has_playable && session.remaining_dice.length == initial_dice_count) {
            session.notify_changed ();
            yield handle_no_moves (session, roll, g);
            return;
        }

        session.is_animating = false;
        session.notify_changed ();
        if (is_comp && session.is_computer_turn) {
            session.status_message = Localization.status_computer_moving ();
            session.notify_changed ();
            yield session.perform_computer_turn (g);
        }
    }

    private static async void handle_double_animation (GameSession session, uint g) {
        var rolling_player = session.current_player;
        session.is_doubling = true;
        session.notify_changed ();

        // Задержка 350 мс перед началом раскрытия костей на доске
        yield session.sleep_async (0.35);
        if (g != session.gen || !session.is_game_in_progress || session.current_player != rolling_player) {
            session.is_doubling = false;
            session.is_dice_flash_active = false;
            session.dice_flash_opacity = 0.0;
            session.double_division_progress = 1.0;
            session.notify_changed ();
            return;
        }

        // Spring(response: 0.50, dampingFraction: 0.65) раскладывает их в сетку 2x2.
        session.is_dice_flash_active = true;
        session.dice_flash_opacity = 0.0;
        var started_us = GLib.get_monotonic_time ();
        const double response = 0.50;
        const double damping = 0.65;
        var omega = 2.0 * Math.PI / response;
        var damped_omega = omega * Math.sqrt (1.0 - damping * damping);
        while (true) {
            var elapsed = (GLib.get_monotonic_time () - started_us) / 1000000.0;
            var spring_t = double.min (response, elapsed);
            var progress = 1.0 - Math.exp (-damping * omega * spring_t) *
                (Math.cos (damped_omega * spring_t) + damping * omega / damped_omega * Math.sin (damped_omega * spring_t));
            session.double_division_progress = double.min (1.08, double.max (0.0, progress));
            if (elapsed < 0.12) {
                var flash_t = elapsed / 0.12;
                session.dice_flash_opacity = flash_t * flash_t * flash_t;
            } else if (elapsed < 0.53) {
                var flash_t = (elapsed - 0.18) / 0.35;
                flash_t = double.max (0.0, double.min (1.0, flash_t));
                session.dice_flash_opacity = 1.0 - (1.0 - flash_t) * (1.0 - flash_t) * (1.0 - flash_t);
            } else {
                session.dice_flash_opacity = 0.0;
            }
            session.is_dice_flash_active = session.dice_flash_opacity > 0.0;
            if (elapsed >= response) {
                session.double_division_progress = 1.0;
            }
            session.notify_changed ();
            if (elapsed >= 0.53) {
                break;
            }
            yield session.sleep_async (0.016);
            if (g != session.gen || !session.is_game_in_progress || session.current_player != rolling_player) {
                session.is_doubling = false;
                session.is_dice_flash_active = false;
                session.dice_flash_opacity = 0.0;
                session.double_division_progress = 1.0;
                session.notify_changed ();
                return;
            }
        }
        session.is_dice_flash_active = false;
        session.dice_flash_opacity = 0.0;
        session.double_division_progress = 1.0;
        session.notify_changed ();

        // Фиксация раскрытых костей на экране перед передачей управления ходом
        yield session.sleep_async (0.22);
        session.is_doubling = false;
        if (g != session.gen || !session.is_game_in_progress || session.current_player != rolling_player) {
            session.notify_changed ();
            return;
        }
        if (session.is_computer_turn) {
            session.status_message = Localization.status_computer_moving ();
        }
        session.notify_changed ();
    }

    private static async void handle_no_moves (GameSession session, DiceRoll roll, uint g) {
        session.board_dice_state = null;
        session.is_animating = true;
        session.status_message = Localization.no_available_moves ();
        session.notify_changed ();

        var pause = SettingsStore.shared ().animation_speed.intermediate_step_delay;
        yield session.sleep_async (pause);
        if (g != session.gen) {
            return;
        }

        var burned = GameSession.sum_ints (session.remaining_dice);
        if (session.current_player == CheckerColor.WHITE) {
            session.white_burned_dice_sum += burned;
        } else {
            session.black_burned_dice_sum += burned;
        }

        var skipped_str = session.current_dice_string ();

        foreach (var d in session.current_turn_dice) {
            if (!d.is_used) {
                d.is_skipped = true;
            }
        }
        if (session.current_turn_record != null) {
            session.current_turn_record.dice = TurnDie.clone_array (session.current_turn_dice);
        }
        session.remaining_dice = new int[0];
        if (session.current_turn_record != null) {
            session.current_turn_record.move_strings = ArrUtil.append_str (
                session.current_turn_record.move_strings, Localization.skipped_dice_status (skipped_str));
        }
        session.notify_changed ();

        var animation = SettingsStore.shared ().animation_speed;
        var transfer_wait = pause + animation.checker_move_duration + session.current_turn_dice.length * 0.08 + 0.25;
        yield session.sleep_async (transfer_wait);
        if (g != session.gen) {
            return;
        }
        session.trigger_auto_end_turn (0.1, roll);
    }
}

} /* namespace Longbackgammon */

