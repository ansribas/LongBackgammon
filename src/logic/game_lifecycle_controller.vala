namespace Longbackgammon {

/**
 * Управление жизненным циклом партии и завершением ходов:
 * переход хода, автозавершение, победа/поражение, сброс и перезапуск игры.
 */
public class GameLifecycleController {

    /** Завершение текущего хода и передача права хода сопернику. */
    public static void end_turn (GameSession session) {
        if (session.is_game_over) {
            return;
        }
        session.move_history = new MoveSnapshot[0];

        if (session.current_turn_record != null) {
            var record = session.current_turn_record;
            if (session.current_turn_dice.length > 0) {
                record.dice = TurnDie.clone_array (session.current_turn_dice);
            }
            session.insert_log_record (session.current_player, record);
        }
        session.current_turn_record = null;
        session.current_turn_dice = new TurnDie[0];

        if (session.current_player == CheckerColor.WHITE) {
            session.is_white_first_turn = false;
        } else {
            session.is_black_first_turn = false;
        }

        session.current_player = session.current_player.opposite ();
        session.dice_roll = null;
        session.rolling_die_index = -1;
        session.remaining_dice = new int[0];
        session.cached_legal_options = new MoveOption[0];
        session.selected_point = null;
        session.checkers_moved_from_head_this_turn = 0;

        session.is_doubling = false;
        session.double_division_progress = 1.0;
        session.is_dice_flash_active = false;
        session.dice_flash_opacity = 0.0;
        session.is_no_moves_flashing = false;
        session.is_rolling = false;
        session.is_animating = false;
        session.is_auto_playing_black = false;

        session.status_message = session.is_computer_turn ? Localization.status_computer_moving () : Localization.status_roll_dice ();
        // Автосохранение партии перед броском следующего игрока
        session.save_to_store ();
        GameSession.trim_heap ();
        session.notify_changed ();
        if (session.is_computer_turn) {
            session.auto_play_if_needed ();
        }
    }

    /** Сброс партии без старта новой (после подтверждения «Новая игра»). */
    public static void force_new_game (
        GameSession session,
        bool record_abandonment = true,
        bool animated = false,
        owned GameSession.PlacementCompletion? completion = null
    ) {
        session.cancel_all_tasks ();
        SoundManager.shared ().stop_placement ();

        if (record_abandonment && session.is_game_started && !session.is_game_over) {
            var loser_color = session.current_player;
            var loser_name = session.player_name (loser_color);
            if (!session.is_computer_player (loser_color)) {
                StatsStore.shared ().record_loss (loser_name);
            }
            var winner_color = loser_color.opposite ();
            if (!session.is_computer_player (winner_color)) {
                StatsStore.shared ().record_victory (session.player_name (winner_color), VictoryType.OIN);
            }
            session.save_game_log ();
        }

        session.white_turn_log = new TurnRecord[0];
        session.black_turn_log = new TurnRecord[0];

        if (animated) {
            session.clearing_logs_animated ();
        }

        session.is_animating = false;
        session.is_rolling = false;
        session.is_auto_playing_black = false;
        session.is_doubling = false;
        session.is_no_moves_flashing = false;
        session.is_dice_flash_active = false;
        session.dice_flash_opacity = 0.0;
        session.is_undoing_move = false;
        session.undo_flight_checker_id = -1;
        session.suppress_dice_cursor = false;
        session.board_dice_state = null;

        session.is_white_first_turn = true;
        session.is_black_first_turn = true;

        session.dice_roll = null;
        session.remaining_dice = new int[0];
        session.rolling_dice_value1 = 6;
        session.rolling_dice_value2 = 6;
        session.selected_point = null;
        session.checkers_moved_from_head_this_turn = 0;

        session.current_turn_record = null;
        session.current_turn_dice = new TurnDie[0];
        session.highlighted_log_id = -1;

        session.is_game_over = false;
        session.showing_game_over_result = false;

        session.white_rolloff_dice = null;
        session.black_rolloff_dice = null;
        session.rolloff_animation_id = 0;
        session.rolling_die_index = -1;
        session.is_first_move_rolloff_in_progress = false;
        session.rolloff_active_player = null;

        session.reset_stats ();
        session.move_history = new MoveSnapshot[0];
        session.cached_legal_options = new MoveOption[0];

        session.init_player_names ();
        session.status_message = Localization.status_new_game ();

        SavedGameStore.shared ().clear ();
        session.is_game_started = false;
        GameSession.trim_heap ();

        session.notify_changed ();

        if (animated) {
            session.animate_checkers_to_tray ((owned) completion);
        } else {
            session.board = GameBoard.in_tray ();
            if (completion != null) {
                var cb = (owned) completion;
                cb ();
            }
            session.notify_changed ();
        }
    }

    /** Новая партия. */
    public static void new_game (GameSession session, bool silent = false, bool animated = true) {
        SavedGameStore.shared ().clear ();
        session.init_player_names ();
        session.is_game_started = true;

        session.cancel_all_tasks ();

        session.is_animating = false;
        session.is_placing_checkers = false;
        session.is_rolling = false;
        session.is_auto_playing_black = false;
        session.is_doubling = false;
        session.is_no_moves_flashing = false;
        session.is_dice_flash_active = false;
        session.dice_flash_opacity = 0.0;
        session.is_undoing_move = false;
        session.undo_flight_checker_id = -1;
        session.suppress_dice_cursor = false;

        session.is_white_first_turn = true;
        session.is_black_first_turn = true;

        session.current_player = CheckerColor.WHITE;
        session.dice_roll = null;
        session.remaining_dice = new int[0];
        session.rolling_dice_value1 = 6;
        session.rolling_dice_value2 = 6;
        session.selected_point = null;
        session.hovered_target_point = null;
        session.is_hovering_bear_off_target = false;
        session.checkers_moved_from_head_this_turn = 0;

        session.white_turn_log = new TurnRecord[0];
        session.black_turn_log = new TurnRecord[0];
        session.current_turn_record = null;
        session.current_turn_dice = new TurnDie[0];
        session.highlighted_log_id = -1;

        session.is_game_over = false;
        session.showing_game_over_result = false;

        session.white_rolloff_dice = null;
        session.black_rolloff_dice = null;
        session.rolloff_animation_id = 0;
        session.rolling_die_index = -1;

        if (SettingsStore.shared ().is_first_move_rolloff_enabled) {
            session.is_first_move_rolloff_in_progress = true;
            session.rolloff_active_player = CheckerColor.WHITE;
            session.status_message = Localization.status_rolloff_prompt ();
        } else {
            session.is_first_move_rolloff_in_progress = false;
            session.rolloff_active_player = null;
            session.status_message = Localization.status_new_game ();
        }

        session.reset_stats ();
        session.move_history = new MoveSnapshot[0];
        session.cached_legal_options = new MoveOption[0];
        GameSession.trim_heap ();

        if (animated) {
            session.is_animating = true;
            session.is_placing_checkers = true;
            session.board = GameBoard.in_tray ();
            session.notify_changed ();
            session.animate_placement (GameBoard.initial_long (), !silent, !silent);
        } else {
            session.board = GameBoard.initial_long ();
            session.is_animating = false;
            session.is_placing_checkers = false;
            if (!silent) {
                SoundManager.shared ().play_new_game_start ();
            }
            session.notify_changed ();
        }
    }

    /** Завершение партии: фиксация победы, запись статистики и отложенный показ итогового окна. */
    public static void handle_delayed_victory (GameSession session) {
        // Немедленно блокируем доску и управление, но сохраняем сессию незавершённой
        // до окончания полёта сгоревших/использованных кубиков в лог
        session.is_animating = true;
        session.selected_point = null;
        session.remaining_dice = new int[0];
        session.move_history = new MoveSnapshot[0];

        SavedGameStore.shared ().clear ();

        session.status_message = (session.current_player == CheckerColor.WHITE)
            ? Localization.victory_white ()
            : Localization.victory_black ();

        // Определяем победителя и проигравшего
        var winner_name = session.player_name (session.current_player);
        var loser_color = session.current_player.opposite ();
        var loser_name = session.player_name (loser_color);

        var victory_type = session.board.victory_type (loser_color);

        if (!session.is_computer_player (session.current_player)) {
            StatsStore.shared ().record_victory (winner_name, victory_type);
        }
        if (!session.is_computer_player (loser_color)) {
            StatsStore.shared ().record_loss (loser_name);
        }

        session.notify_changed ();
        delayed_victory_task.begin (session, session.gen);
    }

    public static async void delayed_victory_task (GameSession session, uint g) {
        var checker_duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        var pause = SettingsStore.shared ().animation_speed.intermediate_step_delay;

        bool has_unused_dice = false;
        foreach (var d in session.current_turn_dice) {
            if (!d.is_used && !d.is_skipped) {
                has_unused_dice = true;
                break;
            }
        }

        if (has_unused_dice) {
            // 1. Ждём завершения движения победной фишки
            yield session.sleep_async (checker_duration);
            if (g != session.gen) {
                return;
            }

            // 2. Пауза перед перечёркиванием: оставшийся кубик (или кубики при дубле) виден неперечёркнутым
            yield session.sleep_async (pause);
            if (g != session.gen) {
                return;
            }

            // Считаем сгоревшие очки и добавляем запись о пропуске в лог
            int burned = 0;
            string[] unused_dice_values = new string[0];
            foreach (var d in session.current_turn_dice) {
                if (!d.is_used && !d.is_skipped) {
                    burned += d.value;
                    unused_dice_values += d.value.to_string ();
                }
            }
            if (session.current_player == CheckerColor.WHITE) {
                session.white_burned_dice_sum += burned;
            } else {
                session.black_burned_dice_sum += burned;
            }

            if (unused_dice_values.length > 0 && session.current_turn_record != null) {
                var skipped_str = string.joinv (", ", unused_dice_values);
                var skip_suffix = Localization.skipped_dice_status (skipped_str).strip ();
                session.current_turn_record.move_strings = ArrUtil.append_str (session.current_turn_record.move_strings, skip_suffix);
            }

            // 3. Перечёркиваем оставшиеся кубики на месте
            foreach (var d in session.current_turn_dice) {
                if (!d.is_used) {
                    d.is_skipped = true;
                }
            }
            if (session.current_turn_record != null) {
                session.current_turn_record.dice = TurnDie.clone_array (session.current_turn_dice);
            }
            session.notify_changed ();

            // 4. Даём время кубикам показаться перечёркнутыми на месте и перенестись в лог
            var flight_duration = checker_duration;
            var staggers = (double) session.current_turn_dice.length * 0.08;
            var total_wait = pause + flight_duration + staggers + 0.25;
            yield session.sleep_async (total_wait);
            if (g != session.gen) {
                return;
            }
        } else {
            // Все кубики были использованы для победы — ждем завершения анимации фишки и обычного перелета кубика в лог
            double die_landing_duration = 0.55;
            double wait_time = double.max (checker_duration, die_landing_duration);
            yield session.sleep_async (wait_time);
            if (g != session.gen) {
                return;
            }
        }

        // 5. Финализируем состояние лога и игры после приземления всех кубиков в слоты лога
        session.is_game_over = true;
        if (session.current_turn_record != null) {
            var record = session.current_turn_record;
            if (session.current_turn_dice.length > 0) {
                record.dice = TurnDie.clone_array (session.current_turn_dice);
            }
            session.insert_log_record (session.current_player, record);
        }
        session.current_turn_record = null;
        session.current_turn_dice = new TurnDie[0];

        // Добавляем в лог обоих игроков строку о победе/поражении (одновременно с экраном победы)
        var winner_color = session.current_player;
        var win_record = new TurnRecord.with_dice (0, new DiceRoll (1, 1));
        win_record.game_result_is_win = true;
        var loss_record = new TurnRecord.with_dice (0, new DiceRoll (1, 1));
        loss_record.game_result_is_win = false;

        if (winner_color == CheckerColor.WHITE) {
            session.insert_log_record (CheckerColor.WHITE, win_record);
            session.insert_log_record (CheckerColor.BLACK, loss_record);
        } else {
            session.insert_log_record (CheckerColor.BLACK, win_record);
            session.insert_log_record (CheckerColor.WHITE, loss_record);
        }

        // Сохраняем полный лог партии после добавления победного хода в историю
        session.save_game_log ();
        session.notify_changed ();

        // 6. Отдельная дополнительная пауза в 0.5 секунды:
        // Игрок видит финальное спокойное состояние доски и завершенный лог
        yield session.sleep_async (0.50);
        if (g != session.gen) {
            return;
        }

        // 7. Торжественное появление экрана победы со звуком
        // Победа человека — фанфары, поражение от ИИ — сдержанный звук поражения
        if (session.is_computer_player (winner_color)) {
            SoundManager.shared ().play_defeat ();
        } else {
            SoundManager.shared ().play_victory ();
        }
        session.showing_game_over_result = true;
        session.is_animating = false;
        session.notify_changed ();
    }

    /** Проверяет после хода, нужно ли автоматически завершить ход. */
    public static void check_and_auto_end_turn (GameSession session) {
        session.update_available_moves_cache ();

        if (session.remaining_dice.length == 0) {
            session.move_history = new MoveSnapshot[0];
            session.is_animating = true;
            var delay = session.is_computer_turn
                ? SettingsStore.shared ().computer_delay.auto_end_turn_delay
                : (double.max (SettingsStore.shared ().animation_speed.checker_move_duration, 0.55) + SettingsStore.shared ().computer_delay.auto_end_turn_delay);
            trigger_auto_end_turn (session, delay, session.dice_roll);
            session.notify_changed ();
            return;
        }

        var has_playable = false;
        foreach (var o in session.cached_legal_options) {
            if (!o.is_illegal_prime) {
                has_playable = true;
                break;
            }
        }

        if (!has_playable) {
            session.move_history = new MoveSnapshot[0];
            session.status_message = Localization.no_available_moves ();
            session.is_animating = true;
            session.notify_changed ();
            no_moves_after_move_task.begin (session, session.gen);
        } else {
            session.status_message = session.is_computer_turn ? Localization.status_computer_moving () : Localization.status_select_checker ();
            // Автосохранение промежуточного состояния хода (после перемещения шашки)
            session.save_to_store ();
            session.notify_changed ();
        }
    }

    public static async void no_moves_after_move_task (GameSession session, uint g) {
        var animation = SettingsStore.shared ().animation_speed;
        var has_used_die = false;
        foreach (var d in session.current_turn_dice) {
            if (d.is_used) {
                has_used_die = true;
                break;
            }
        }
        if (!session.is_computer_turn && has_used_die) {
            yield session.sleep_async (animation.checker_move_duration);
            if (g != session.gen) {
                return;
            }
        }
        var pause = animation.intermediate_step_delay;
        yield session.sleep_async (pause);
        if (g != session.gen) {
            return;
        }
        if (session.remaining_dice.length > 0) {
            var burned = GameSession.sum_ints (session.remaining_dice);
            if (session.current_player == CheckerColor.WHITE) {
                session.white_burned_dice_sum += burned;
            } else {
                session.black_burned_dice_sum += burned;
            }
            if (session.current_turn_record != null) {
                var skip_suffix = Localization.skipped_dice_status (session.current_dice_string ()).strip ();
                session.current_turn_record.move_strings = ArrUtil.append_str (session.current_turn_record.move_strings, skip_suffix);
            }
        }
        foreach (var d in session.current_turn_dice) {
            if (!d.is_used) {
                d.is_skipped = true;
            }
        }
        if (session.current_turn_record != null) {
            session.current_turn_record.dice = TurnDie.clone_array (session.current_turn_dice);
        }
        session.remaining_dice = new int[0];
        session.notify_changed ();

        var transfer_wait = pause + animation.checker_move_duration + session.current_turn_dice.length * 0.08 + 0.25;
        yield session.sleep_async (transfer_wait);
        if (g != session.gen) {
            return;
        }
        trigger_auto_end_turn (session, 0.1, session.dice_roll);
    }

    /** Отложенное завершение хода. Проверяет, что состояние игры не изменилось за время ожидания. */
    public static void trigger_auto_end_turn (GameSession session, double delay, DiceRoll? current_roll) {
        var player_at_trigger = session.current_player;
        var token = ++session.auto_end_token;
        var g = session.gen;
        Timeout.add ((uint) (delay * 1000.0), () => {
            if (token != session.auto_end_token || g != session.gen) {
                return Source.REMOVE;
            }
            if (!session.is_game_over && session.current_player == player_at_trigger
                && (current_roll == null || GameSession.same_roll (session.dice_roll, current_roll))) {
                session.is_animating = false;
                session.end_turn ();
            }
            return Source.REMOVE;
        });
    }
}

} /* namespace Longbackgammon */
