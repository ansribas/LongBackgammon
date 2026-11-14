namespace Longbackgammon {

/**
 * Управление ходом компьютера (ИИ): задержки, выбор ходов, пошаговое применение комбинированных ходов.
 */
public class ComputerTurnController {

    /** Автобросок компьютера после задержки. */
    public static void auto_play_if_needed (GameSession session) {
        if (!session.is_computer_turn || !session.can_roll) {
            return;
        }
        session.is_auto_playing_black = true;
        var g = session.gen;
        var delay = SettingsStore.shared ().computer_delay.before_roll_delay;
        session.after (delay, () => {
            if (g != session.gen) {
                return;
            }
            if (!session.is_computer_turn || !session.can_roll) {
                session.is_auto_playing_black = false;
                return;
            }
            session.roll_dice ();
        });
    }

    /** Полный цикл хода компьютера. */
    public static async void perform_computer_turn (GameSession session, uint g) {
        session.is_animating = true;
        session.notify_changed ();

        var before_delay = SettingsStore.shared ().computer_delay.before_roll_delay;
        yield session.sleep_async (before_delay);
        if (g != session.gen) {
            return;
        }
        session.status_message = Localization.status_computer_moving ();
        session.notify_changed ();

        var max_iterations = 20;
        while (session.remaining_dice.length > 0 && !session.is_game_over && !session.board.is_winner (session.current_player) && max_iterations > 0) {
            max_iterations--;
            if (g != session.gen) {
                return;
            }
            MoveOption? move = null;
            if (SettingsStore.shared ().ai_difficulty == AIDifficulty.MASTER) {
                move = AdvancedAI.choose_move (session.cached_legal_options, session.board, session.current_player, session.remaining_dice);
            } else {
                move = ComputerAI.choose_move (session.cached_legal_options, session.board, session.current_player, session.remaining_dice);
            }
            if (move == null) {
                break;
            }

            var show_path = SettingsStore.shared ().show_path_computer;
            if (show_path && move.is_combined) {
                if (yield apply_computer_combined_move (session, move, g)) {
                    if (g != session.gen) {
                        return;
                    }
                    continue;
                }
            }

            session.apply (move);
            if (session.board.is_winner (session.current_player)) {
                return;
            }
            session.notify_changed ();
            var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
            var between = SettingsStore.shared ().computer_delay.between_moves_delay;
            yield session.sleep_async (duration + between);
            if (g != session.gen) {
                return;
            }
        }

        session.is_auto_playing_black = false;
        if (!session.is_game_over && !session.board.is_winner (session.current_player)) {
            session.check_and_auto_end_turn ();
        } else {
            session.is_animating = false;
        }
        session.notify_changed ();
    }

    private static async bool apply_computer_combined_move (GameSession session, MoveOption move, uint g) {
        var steps = session.intermediate_steps (move);
        var dice_values = new int[0];
        foreach (var idx in move.die_indices) {
            if (idx < session.remaining_dice.length) {
                dice_values += session.remaining_dice[idx];
            }
        }
        if (steps.length < 2 || steps.length != dice_values.length) {
            return false;
        }
        var is_head_move = MoveValidator.is_head (move.from, session.current_player);
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        var intermediate_delay = SettingsStore.shared ().animation_speed.intermediate_step_delay;
        var between = SettingsStore.shared ().computer_delay.between_moves_delay;

        session.record_move_in_log (move, steps);

        for (var i = 0; i < steps.length - 1; i++) {
            session.board.move_one_checker (steps[i].from, steps[i].to);
            session.remove_die_by_value (dice_values[i]);
            SoundManager.shared ().play_checker_move ();
            session.notify_changed ();
            yield session.sleep_async (duration + intermediate_delay);
            if (g != session.gen) {
                return true;
            }
        }

        var last = steps[steps.length - 1];
        session.board.move_one_checker (last.from, last.to);
        session.remove_die_by_value (dice_values[dice_values.length - 1]);
        SoundManager.shared ().play_checker_move ();
        session.notify_changed ();
        yield session.sleep_async (duration);

        if (g != session.gen) {
            return true;
        }

        if (session.board.is_winner (session.current_player)) {
            session.handle_delayed_victory ();
            return true;
        }
        if (is_head_move) {
            session.checkers_moved_from_head_this_turn += 1;
        }
        session.selected_point = null;
        session.update_available_moves_cache ();
        session.notify_changed ();

        yield session.sleep_async (between);
        return true;
    }
}

} /* namespace Longbackgammon */

