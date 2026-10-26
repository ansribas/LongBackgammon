/* computer_ai.vala
 *
 * Движок принятия решений базового уровня сложности искусственного интеллекта.
 * Реализует эвристическую оценку ходов, снятия фишек с головы и построения блоков.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class ComputerAI {
    /** Суммарное количество очков (дистанции) до финиша. */
    public static int calculate_pip_count (GameBoard board, CheckerColor color) {
        var route = PlayerPath.path (color);
        var total = 0;
        for (var idx = route.length - 1; idx >= 0; idx--) {
            var stack = board.stack_at (route[idx]);
            if (stack != null && stack.color == color) {
                total += stack.checker_ids.length * (route.length - idx);
            }
        }
        return total;
    }

    private static bool[] home_points (CheckerColor color) {
        var home = new bool[25];
        if (color == CheckerColor.WHITE) {
            for (var raw = 1; raw <= 6; raw++) {
                home[raw] = true;
            }
        } else {
            for (var raw = 13; raw <= 18; raw++) {
                home[raw] = true;
            }
        }
        return home;
    }

    private static int count_checkers_outside_home (GameBoard board, CheckerColor color) {
        var hp = home_points (color);
        var count = 0;
        for (var raw = 1; raw <= 24; raw++) {
            if (!hp[raw]) {
                var stack = board.stack_at ((BoardPoint) raw);
                if (stack != null && stack.color == color) {
                    count += stack.checker_ids.length;
                }
            }
        }
        return count;
    }

    private static int count_checkers_on_opponent_half (GameBoard board, CheckerColor color) {
        var route = PlayerPath.path (color.opposite ());
        var count = 0;
        for (var i = 0; i < route.length; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == color) {
                count += stack.checker_ids.length;
            }
        }
        return count;
    }

    private static int calculate_max_our_prime (GameBoard board, CheckerColor color) {
        var route = PlayerPath.path (color);
        var max_len = 0;
        var current_len = 0;
        for (var i = 0; i < route.length; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == color) {
                current_len++;
                if (current_len > max_len) {
                    max_len = current_len;
                }
            } else {
                current_len = 0;
            }
        }
        return max_len;
    }

    private static double calculate_connectivity_score (GameBoard board, CheckerColor color) {
        var route = PlayerPath.path (color);
        var score = 0.0;
        for (var i = 0; i < route.length - 1; i++) {
            var s1 = board.stack_at (route[i]);
            var s2 = board.stack_at (route[i + 1]);
            if (s1 != null && s1.color == color && s2 != null && s2.color == color) {
                score += 1.0;
                if (s1.checker_ids.length >= 2 && s2.checker_ids.length >= 2) {
                    score += 0.5;
                }
            }
        }
        return score;
    }

    private static int count_trapped_opponent_checkers (GameBoard board, CheckerColor color) {
        var opponent_color = color.opposite ();
        var route = PlayerPath.path (opponent_color);
        var block_len = 0;
        var best_len = 0;
        var block_start = -1;
        var best_start = -1;
        for (var i = 0; i < route.length; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == color) {
                if (block_len == 0) {
                    block_start = i;
                }
                block_len++;
                if (block_len > best_len) {
                    best_len = block_len;
                    best_start = block_start;
                }
            } else {
                block_len = 0;
            }
        }
        if (best_len < 3 || best_start <= 0) {
            return 0;
        }
        var trapped = 0;
        for (var i = 0; i < best_start; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == opponent_color) {
                trapped += stack.checker_ids.length;
            }
        }
        return trapped;
    }

    private static void count_occupied_info (GameBoard board, CheckerColor color, out int occupied, out int blots) {
        occupied = 0;
        blots = 0;
        for (var raw = 1; raw <= 24; raw++) {
            var stack = board.stack_at ((BoardPoint) raw);
            if (stack == null || stack.color != color) {
                continue;
            }
            occupied++;
            if (stack.checker_ids.length == 1) {
                blots++;
            }
        }
    }

    private static double future_flexibility_score (GameBoard board, CheckerColor color) {
        var w = AIWeights.default_weights ();
        var total_moves = 0;
        var blocked_rolls = 0;
        for (var die1 = 1; die1 <= 6; die1++) {
            for (var die2 = die1; die2 <= 6; die2++) {
                int[] dice;
                if (die1 == die2) {
                    dice = new int[] { die1, die1, die1, die1 };
                } else {
                    dice = new int[] { die1, die2 };
                }
                var moves = MoveValidator.all_moves (board, color, dice, 0, die1 == die2, false);
                var playable = 0;
                for (var i = 0; i < moves.length; i++) {
                    if (!moves[i].is_illegal_prime) {
                        playable++;
                    }
                }
                if (playable == 0) {
                    blocked_rolls++;
                } else {
                    total_moves += int.min (playable, 8);
                }
            }
        }
        return (double) total_moves * w.flex_moves_count_mult
               - (double) blocked_rolls * w.flex_blocked_rolls_penalty;
    }

    private static double evaluate_score (MoveOption move, GameBoard board, CheckerColor color, int[] remaining_dice) {
        var w = AIWeights.default_weights ();
        var route = PlayerPath.path (color);
        var opponent_color = color.opposite ();
        var opponent_route = PlayerPath.path (opponent_color);
        var hp = home_points (color);
        var home_start_idx = route.length - 6;
        var from_index = PlayerPath.find_index (route, move.from);
        if (from_index < 0) {
            from_index = 0;
        }
        var target_index = move.to == null ? route.length : PlayerPath.find_index (route, move.to);
        if (target_index < 0) {
            target_index = from_index;
        }
        var progress = (move.to == null) ? (route.length - from_index) : (target_index - from_index);
        var simulated = board.clone ();
        simulated.move_one_checker (move.from, move.to);
        var all_in_home = MoveValidator.are_all_checkers_in_home (board, color);
        var all_in_home_after = MoveValidator.are_all_checkers_in_home (simulated, color);
        var outside_before = count_checkers_outside_home (board, color);
        var is_endgame = outside_before <= 6;
        var score = 0.0;
        var is_from_home = hp[move.from.raw_value ()];
        var is_to_home = move.to != null && hp[move.to.raw_value ()];
        var is_from_head = MoveValidator.is_head (move.from, color);
        var pip_progress = calculate_pip_count (board, color) - calculate_pip_count (simulated, color);
        var any_behind = false;
        var tail_idx = route.length;
        for (var i = 0; i < route.length; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == color) {
                tail_idx = i;
                break;
            }
        }
        var head_count = 0;
        var head_stack = board.stack_at (PlayerPath.start_point (color));
        if (head_stack != null && head_stack.color == color) {
            head_count = head_stack.checker_ids.length;
        }
        var opp_head_idx = PlayerPath.find_index (opponent_route, PlayerPath.start_point (opponent_color));
        if (opp_head_idx < 0) {
            opp_head_idx = 0;
        }

        // 1. Вынос за борт
        if (move.to == null) {
            score += w.bear_off_all_in_home_bonus;
            score += (double) (route.length - from_index) * w.bear_off_dist_to_finish_mult;
            if (move.from.raw_value () <= 3 || (move.from.raw_value () >= 13 && move.from.raw_value () <= 15)) {
                score -= w.bear_off_point123_penalty_mult;
            }
            if (move.is_combined) {
                score -= w.bear_off_combined_penalty;
            }
        }

        // 2. Эндшпиль
        if (is_endgame) {
            var entered = (is_to_home && !is_from_home) ? 1 : 0;
            if (entered > 0) {
                score += w.endgame_total_entries_mult;
            } else {
                score -= w.endgame_no_entries_penalty;
            }
            if (is_from_home && is_to_home) {
                score -= w.endgame_move_inside_home_penalty;
            }
            if (is_to_home && !is_from_home) {
                score += w.endgame_move_to_home_bonus;
                var deepness = target_index - home_start_idx + 1;
                score += (double) deepness * w.endgame_deep_home_bonus_mult;
                var target_stack = simulated.stack_at (move.to);
                if (target_stack != null && target_stack.checker_ids.length > 2) {
                    score -= 3000000.0 * (double) (target_stack.checker_ids.length - 2);
                }
            }
            if (is_from_home && !is_to_home) {
                score -= w.endgame_move_from_home_to_outside_penalty;
            }
        }

        // 3. Голова
        if (is_from_head) {
            var urgency = head_count >= 12 ? 3.0 : (head_count >= 8 ? 2.0 : 1.0);
            score += w.head_move_bonus * urgency + (double) head_count * w.head_stack_count_mult * urgency;
            if (move.to != null) {
                var target_stack = simulated.stack_at (move.to);
                if (target_stack != null) {
                    if (target_stack.checker_ids.length == 1) {
                        score += w.head_target_stack1_bonus;
                    } else if (target_stack.checker_ids.length == 2) {
                        score += w.head_target_stack2_bonus;
                    } else {
                        score -= w.head_target_stack3_plus_penalty_mult * (double) (target_stack.checker_ids.length - 2);
                    }
                } else {
                    score += w.head_target_empty_bonus;
                }
                var opp_dist = PlayerPath.find_index (opponent_route, move.to) - opp_head_idx;
                if (opp_dist >= 0) {
                    score += w.head_move_to_opponent_half_bonus;
                    if (opp_dist >= 1 && opp_dist <= 6) {
                        score += w.head_move_to_opp_half_near_head_bonus;
                    }
                } else {
                    score += w.head_move_to_our_half_bonus;
                }
            }
        } else if (head_count > 0) {
            var scale = head_count >= 10 ? 3.0 : (head_count >= 7 ? 2.0 : 1.0);
            score -= (double) head_count * w.not_moving_from_head_penalty_mult * scale;
        }

        // 4. Продвижение и баланс половин
        if (!all_in_home) {
            if (from_index == tail_idx) {
                score += 8000000.0;
                score += (double) progress * 800000.0;
            } else if (tail_idx < route.length / 2 && from_index > tail_idx) {
                var gap = from_index - tail_idx;
                score -= (double) gap * 1000000.0;
                var midpoint = route.length / 2;
                if (from_index < midpoint && target_index >= midpoint) {
                    score -= 12000000.0;
                }
            }
            var on_opp_side = move.to != null && PlayerPath.find_index (opponent_route, move.to) >= 0;
            var was_opp_side = PlayerPath.find_index (opponent_route, move.from) >= 0;
            var mult = any_behind ? 1.0 : 0.2;
            if (on_opp_side && !was_opp_side) {
                score += w.move_to_opp_half_first_time_bonus * mult;
            }
            var checkers_on_opp = count_checkers_on_opponent_half (simulated, color);
            score += (double) checkers_on_opp * w.checkers_on_opp_half_mult * mult;
            if (on_opp_side) {
                var opp_dist = PlayerPath.find_index (opponent_route, move.to) - opp_head_idx;
                if (opp_dist > 6) {
                    score += (double) opp_dist * w.move_to_opp_half_far_from_head_mult * mult;
                }
            }
            if (pip_progress > 0) {
                score += (double) pip_progress * w.midgame_progress_mult * 0.4;
                if (!any_behind) {
                    score += (double) pip_progress * w.midgame_progress_mult;
                }
            }
        }

        // 5. Занятие пунктов и праймы
        if (!all_in_home) {
            int occ_before, blots_before;
            count_occupied_info (board, color, out occ_before, out blots_before);
            int occ_after, blots_after;
            count_occupied_info (simulated, color, out occ_after, out blots_after);
            if (occ_after > occ_before) {
                score += w.occupy_new_point_bonus_target;
            }
            for (var raw = 1; raw <= 24; raw++) {
                var stack = simulated.stack_at ((BoardPoint) raw);
                if (stack != null && stack.color == color && stack.checker_ids.length >= 3) {
                    if (all_in_home_after) {
                        score -= w.tower_penalty_finishing;
                    } else {
                        score -= w.tower_penalty_normal;
                    }
                    if (stack.checker_ids.length >= 4) {
                        score -= w.tower4_plus_penalty_mult * (double) (stack.checker_ids.length - 3);
                    }
                }
            }
            score += calculate_connectivity_score (simulated, color) * w.connectivity_midgame_mult;
            var prime = calculate_max_our_prime (simulated, color);
            if (prime == 6) {
                score += w.prime_block6_bonus;
            } else if (prime == 5) {
                score += w.prime_block5_bonus;
            } else if (prime == 4) {
                score += w.prime_block4_bonus;
            } else if (prime == 3) {
                score += w.prime_block3_bonus;
            } else if (prime == 2) {
                score += w.prime_block2_bonus;
            }
            score += (double) count_trapped_opponent_checkers (simulated, color) * w.trapped_opponents_mult;
        }

        // 6. Защита хвоста
        var opponent_block = 0;
        if (tail_idx < route.length) {
            var current = 0;
            for (var idx = tail_idx; idx < route.length; idx++) {
                var stack = simulated.stack_at (route[idx]);
                if (stack != null && stack.color == opponent_color) {
                    current++;
                    if (current > opponent_block) {
                        opponent_block = current;
                    }
                } else {
                    current = 0;
                }
            }
        }
        if (opponent_block >= 3 && tail_idx < from_index) {
            if (from_index != tail_idx) {
                score -= w.not_saving_tail_penalty;
            } else {
                score += w.saving_tail_bonus;
                score += (double) progress * w.saving_tail_progress_mult;
            }
        }

        // 7. Штрафы за комбо и ходы в доме
        if (move.is_combined && move.to == null) {
            score -= w.combined_move_penalty;
        }
        if (is_from_home && is_to_home && all_in_home) {
            score -= w.all_in_home_move_inside_home_penalty;
        }
        if (is_from_home && is_to_home && !all_in_home) {
            score -= w.midgame_move_inside_home_penalty;
        }

        // 8. Пипы, гибкость, небольшая случайность
        var pips_diff = calculate_pip_count (simulated, opponent_color) - calculate_pip_count (simulated, color);
        score += (double) pips_diff * 20000.0;
        var future_flex = future_flexibility_score (simulated, color);
        score += future_flex * (is_endgame ? 0.2 : 0.65);
        score += GLib.Random.double_range (0, 300000.0);

        return score;
    }

    /** Выбирает наилучший ход из доступных опций (без запрещённых праймов). */
    public static MoveOption? choose_move (MoveOption[] options, GameBoard board, CheckerColor color, int[] remaining_dice) {
        var playable = new MoveOption[0];
        for (var i = 0; i < options.length; i++) {
            if (!options[i].is_illegal_prime) {
                playable += options[i];
            }
        }
        if (playable.length == 0) {
            return null;
        }
        MoveOption? best = null;
        var best_score = -1e300;
        for (var i = 0; i < playable.length; i++) {
            var score = evaluate_score (playable[i], board, color, remaining_dice);
            if (best == null || score > best_score) {
                best = playable[i];
                best_score = score;
            }
        }
        return best;
    }
}

} /* namespace Longbackgammon */
