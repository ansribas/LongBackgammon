namespace Longbackgammon {

/**
 * Обработка ходов игрока: выбор точек, перемещение фишек, составные шаги, сброс за борт и отмена ходов (undo).
 */
public class MoveController {

    /** Применяет одиночный ход: перемещает фишку, записывает в лог, обновляет кэш. */
    public static void apply (GameSession session, MoveOption move, bool is_dragged = false) {
        session.board.move_one_checker (move.from, move.to);
        session.record_move_in_log (move, new IntermediateStep[0]);

        if (MoveValidator.is_head (move.from, session.current_player)) {
            session.checkers_moved_from_head_this_turn += 1;
        }
        session.remove_used_dice (move.die_indices);
        SoundManager.shared ().play_checker_move ();

        if (session.board.is_winner (session.current_player)) {
            session.handle_delayed_victory ();
            return;
        }
        session.update_available_moves_cache ();
    }

    /** Разбивает составной ход на промежуточные шаги (по одному кубику). */
    public static IntermediateStep[] intermediate_steps (GameSession session, MoveOption move) {
        if (!move.is_combined || move.die_indices.length < 2) {
            return new IntermediateStep[0];
        }
        var dice_values = new int[0];
        foreach (var idx in move.die_indices) {
            if (idx < session.remaining_dice.length) {
                dice_values += session.remaining_dice[idx];
            }
        }
        if (dice_values.length < 2) {
            return new IntermediateStep[0];
        }

        var steps = new IntermediateStep[0];
        BoardPoint current = move.from;
        for (var i = 0; i < dice_values.length; i++) {
            var next = PlayerPath.point_from (current, dice_values[i], session.current_player);
            if (next != null) {
                if (MoveValidator.is_blocked (next, session.board, session.current_player)) {
                    return new IntermediateStep[0];
                }
                steps += new IntermediateStep (current, next);
                current = next;
            } else {
                if (i == dice_values.length - 1) {
                    steps += new IntermediateStep (current, null);
                }
                break;
            }
        }
        return steps;
    }

    /** Завершится ли ход игрока после указанного перемещения. */
    public static bool will_turn_end_after (GameSession session, MoveOption move) {
        var temp_board = session.board.clone ();
        var steps = move.is_combined ? intermediate_steps (session, move) : new IntermediateStep[0];
        if (move.is_combined && steps.length > 0) {
            foreach (var s in steps) {
                temp_board.move_one_checker (s.from, s.to);
            }
        } else {
            temp_board.move_one_checker (move.from, move.to);
        }

        var temp_dice = GameSession.copy_int_array (session.remaining_dice);
        foreach (var index in GameSession.sorted_desc (move.die_indices)) {
            if (index < temp_dice.length) {
                temp_dice = GameSession.remove_at (temp_dice, index);
            }
        }
        if (temp_dice.length == 0) {
            return true;
        }

        var next_head = session.checkers_moved_from_head_this_turn + (MoveValidator.is_head (move.from, session.current_player) ? 1 : 0);
        var is_first_turn = (session.current_player == CheckerColor.WHITE) ? session.is_white_first_turn : session.is_black_first_turn;
        var all = MoveValidator.all_moves (temp_board, session.current_player, temp_dice, next_head,
                                           session.dice_roll != null && session.dice_roll.is_double, is_first_turn);
        foreach (var o in MoveValidator.filter_legal_moves (
            all, temp_board, session.current_player, temp_dice, next_head,
            session.dice_roll != null && session.dice_roll.is_double, is_first_turn)) {
            if (!o.is_illegal_prime) {
                return false;
            }
        }
        return true;
    }

    /**
     * Обрабатывает клик игрока по ячейке доски:
     * - Повторный клик по выбранной фишке — быстрый ход.
     * - Клик по цели выбранной фишки — перемещение (в т.ч. на свои фишки).
     * - Своя фишка — выбор; чужая/пустая — сброс выбора.
     */
    public static void select (GameSession session, BoardPoint point) {
        if (session.remaining_dice.length == 0 || session.is_animating) {
            return;
        }
        if (session.selected_point != null && session.selected_point == point) {
            quick_move (session, point);
            return;
        }
        if (session.selected_point != null && GameSession.contains_point (session.target_points (), point)) {
            apply_move (session, point, session.selected_point);
            return;
        }

        var stack = session.board.stack_at (point);
        if (stack == null || stack.color != session.current_player) {
            session.set_selected_point (null);
            session.status_message = Localization.status_select_checker ();
            session.notify_changed ();
            return;
        }

        session.selected_point = point;
        if (session.options_from (point).length == 0) {
            var is_head = MoveValidator.is_head (point, session.current_player);
            var is_first_turn = (session.current_player == CheckerColor.WHITE) ? session.is_white_first_turn : session.is_black_first_turn;
            var is_double = session.dice_roll != null && session.dice_roll.is_double;
            var first_die = session.remaining_dice.length > 0 ? session.remaining_dice[0] : 0;
            var max_head = 1;
            if (is_double && is_first_turn && (first_die == 3 || first_die == 4 || first_die == 6)) {
                max_head = 2;
            }
            if (is_head && session.checkers_moved_from_head_this_turn >= max_head) {
                session.status_message = Localization.status_head_limit_reached ();
            } else {
                var is_blocked_by_opponent = false;
                foreach (var die in session.remaining_dice) {
                    var target = PlayerPath.point_from (point, die, session.current_player);
                    if (target != null && MoveValidator.is_blocked (target, session.board, session.current_player)) {
                        is_blocked_by_opponent = true;
                        break;
                    }
                }
                session.status_message = is_blocked_by_opponent
                    ? Localization.status_move_blocked_by_opponent ()
                    : Localization.no_available_moves ();
            }
        } else {
            session.status_message = Localization.status_select_target ();
        }
        session.notify_changed ();
    }

    /** Быстрый ход (двойной клик): вынос за борт или ближайшая точка. */
    public static void quick_move (GameSession session, BoardPoint point) {
        if (session.remaining_dice.length == 0 || session.is_animating || session.is_game_over) {
            return;
        }
        var available = new MoveOption[0];
        foreach (var o in session.options_from (point)) {
            if (!o.is_illegal_prime) {
                available += o;
            }
        }
        if (available.length == 0) {
            return;
        }
        foreach (var o in available) {
            if (o.to == null) {
                session.selected_point = point;
                bear_off_selected (session);
                return;
            }
        }
        MoveOption? nearest = null;
        foreach (var o in available) {
            if (nearest == null || o.die < nearest.die) {
                nearest = o;
            }
        }
        if (nearest != null && nearest.to != null) {
            apply_move (session, nearest.to, point);
        }
    }

    /** Основной метод перемещения фишки from → to. */
    public static void apply_move (GameSession session, BoardPoint to, BoardPoint from, bool is_dragged = false) {
        if (session.is_computer_turn || session.is_animating) {
            return;
        }

        MoveOption? move = null;
        foreach (var o in session.options_from (from)) {
            if (o.to != null && o.to == to && !o.is_illegal_prime) {
                move = o;
                break;
            }
        }
        if (move == null) {
            return;
        }

        var is_turn_ending = will_turn_end_after (session, move);
        save_snapshot (session);

        session.is_animating = true;
        session.selected_point = null;

        if (!session.is_computer_turn) {
            session.status_message = is_turn_ending ? "" : Localization.status_select_checker ();
        }

        var show_path = SettingsStore.shared ().show_path_player;
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;

        var dice_values = new int[0];
        foreach (var idx in move.die_indices) {
            if (idx < session.remaining_dice.length) {
                dice_values += session.remaining_dice[idx];
            }
        }

        if (show_path && move.is_combined && !is_dragged) {
            animate_combined_move.begin (session, move, (owned) dice_values, true, session.gen);
            return;
        }

        session.record_move_in_log (move, new IntermediateStep[0]);

        session.board.move_one_checker (from, to);
        if (MoveValidator.is_head (from, session.current_player)) {
            session.checkers_moved_from_head_this_turn += 1;
        }
        session.remove_used_dice (move.die_indices);
        SoundManager.shared ().play_checker_move ();

        if (session.board.is_winner (session.current_player)) {
            session.handle_delayed_victory ();
            return;
        }

        session.update_available_moves_cache ();
        session.check_and_auto_end_turn ();
        session.notify_changed ();

        if (!is_turn_ending) {
            session.after (duration, () => {
                session.is_animating = false;
                session.notify_changed ();
            });
        }
    }

    /**
     * Поэтапная анимация составного хода (и составного выноса за борт).
     * record_steps = true — запись в лог с промежуточными шагами.
     */
    public static async void animate_combined_move (GameSession session, MoveOption move, owned int[] dice_values, bool record_steps, uint g) {
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        var intermediate_delay = SettingsStore.shared ().animation_speed.intermediate_step_delay;
        var steps = intermediate_steps (session, move);

        if (steps.length < 2 || steps.length != dice_values.length) {
            apply (session, move);
            if (session.board.is_winner (session.current_player)) {
                return;
            }
            session.check_and_auto_end_turn ();
            session.is_animating = false;
            session.notify_changed ();
            return;
        }

        var is_head_move = MoveValidator.is_head (move.from, session.current_player);
        if (record_steps) {
            session.record_move_in_log (move, steps);
        }

        for (var i = 0; i < steps.length - 1; i++) {
            session.board.move_one_checker (steps[i].from, steps[i].to);
            session.remove_die_by_value (dice_values[i]);
            SoundManager.shared ().play_checker_move ();
            session.notify_changed ();
            yield session.sleep_async (duration + intermediate_delay);
            if (g != session.gen) {
                return;
            }
        }

        var last = steps[steps.length - 1];
        session.board.move_one_checker (last.from, last.to);
        session.remove_die_by_value (dice_values[dice_values.length - 1]);
        SoundManager.shared ().play_checker_move ();
        session.notify_changed ();
        yield session.sleep_async (duration);

        if (g != session.gen) {
            return;
        }

        if (session.board.is_winner (session.current_player)) {
            session.handle_delayed_victory ();
            return;
        }
        if (is_head_move) {
            session.checkers_moved_from_head_this_turn += 1;
        }
        session.selected_point = null;
        session.update_available_moves_cache ();
        session.check_and_auto_end_turn ();
        session.is_animating = false;
        session.notify_changed ();
    }

    /** Вынос выбранной фишки за борт. */
    public static void bear_off_selected (GameSession session, bool is_dragged = false) {
        if (session.is_animating || session.selected_point == null || !session.can_bear_off_selected) {
            return;
        }
        var from = session.selected_point;
        MoveOption? move = null;
        foreach (var o in session.options_from (from)) {
            if (o.to == null && !o.is_illegal_prime) {
                move = o;
                break;
            }
        }
        if (move == null) {
            return;
        }

        var is_turn_ending = will_turn_end_after (session, move);
        save_snapshot (session);

        session.is_animating = true;
        session.selected_point = null;

        if (!session.is_computer_turn) {
            session.status_message = is_turn_ending ? "" : Localization.status_select_checker ();
        }

        var show_path = SettingsStore.shared ().show_path_player;
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;

        if (show_path && move.is_combined && !is_dragged) {
            var dice_values = new int[0];
            foreach (var idx in move.die_indices) {
                if (idx < session.remaining_dice.length) {
                    dice_values += session.remaining_dice[idx];
                }
            }
            animate_combined_move.begin (session, move, (owned) dice_values, true, session.gen);
            return;
        }

        apply (session, move, is_dragged);
        if (session.board.is_winner (session.current_player)) {
            return;
        }
        session.check_and_auto_end_turn ();
        session.notify_changed ();

        if (!is_turn_ending) {
            session.after (duration, () => {
                session.is_animating = false;
                session.notify_changed ();
            });
        }
    }

    /** Сохраняет снимок состояния для отмены хода (только для игрока). */
    public static void save_snapshot (GameSession session) {
        if (session.is_computer_turn) {
            return;
        }
        session.move_history += new MoveSnapshot (
            session.board.clone (),
            GameSession.copy_int_array (session.remaining_dice),
            session.checkers_moved_from_head_this_turn,
            session.status_message,
            session.current_turn_record,
            session.current_turn_dice);
    }

    /** Отмена последнего хода. */
    public static void undo_move (GameSession session) {
        if (session.is_animating || session.move_history.length == 0 || session.is_game_over) {
            return;
        }
        SoundManager.shared ().play_undo ();

        var last = session.move_history[session.move_history.length - 1];
        var new_history = new MoveSnapshot[0];
        for (var i = 0; i < session.move_history.length - 1; i++) {
            new_history += session.move_history[i];
        }
        session.move_history = new_history;

        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        session.is_animating = true;

        // Находим одиночную фишку, совершающую обратный полёт при отмене шага;
        // остальные перемещения восстанавливаются мгновенно из снимка.
        session.undo_flight_checker_id = find_reverse_undo_checker (session.board, last.board, session.current_player);
        session.is_undoing_move = session.undo_flight_checker_id >= 0;

        session.board = last.board.clone ();
        session.remaining_dice = GameSession.copy_int_array (last.remaining_dice);
        session.current_turn_dice = TurnDie.clone_array (last.current_turn_dice);
        session.checkers_moved_from_head_this_turn = last.head_count;
        session.status_message = last.status;
        session.current_turn_record = last.current_turn_record == null ? null : last.current_turn_record.clone ();
        session.selected_point = null;
        session.update_available_moves_cache ();
        // Автосохранение партии после отмены хода
        session.save_to_store ();
        session.notify_changed ();

        var undo_generation = session.gen;
        session.after (duration, () => {
            if (undo_generation != session.gen) {
                return;
            }
            session.is_undoing_move = false;
            session.undo_flight_checker_id = -1;
            session.is_animating = false;
            session.notify_changed ();
        });
    }

    private static int undo_stack_count (GameBoard board, BoardPoint point) {
        var stack = board.stack_at (point);
        return stack != null ? stack.checker_ids.length : 0;
    }

    private static int find_reverse_undo_checker (GameBoard current, GameBoard target, CheckerColor preferred) {
        CheckerColor[] colors = { preferred, preferred == CheckerColor.WHITE ? CheckerColor.BLACK : CheckerColor.WHITE };
        foreach (var color in colors) {
            var current_off = color == CheckerColor.WHITE ? current.white_borne_off_ids : current.black_borne_off_ids;
            var target_off = color == CheckerColor.WHITE ? target.white_borne_off_ids : target.black_borne_off_ids;
            if (current_off.length > target_off.length && current_off.length > 0) {
                for (var raw = 1; raw <= 24; raw++) {
                    var point = (BoardPoint) raw;
                    if (undo_stack_count (target, point) > undo_stack_count (current, point)) {
                        return (int) current_off[current_off.length - 1];
                    }
                }
            }
        }

        for (var raw = 1; raw <= 24; raw++) {
            var point = (BoardPoint) raw;
            if (undo_stack_count (current, point) <= undo_stack_count (target, point)) {
                continue;
            }
            var stack = current.stack_at (point);
            if (stack != null && stack.checker_ids.length > 0) {
                return (int) stack.checker_ids[stack.checker_ids.length - 1];
            }
        }
        return -1;
    }
}

} /* namespace Longbackgammon */

