/* advanced_ai.vala
 *
 * Продвинутый движок искусственного интеллекта (Advanced AI).
 * В отличие от жадного пошагового алгоритма:
 * 1. Просчитывает полный ход целиком (все 2 или 4 кубика) до финальной позиции на доске.
 * 2. Ищет все легальные последовательности ходов и гарантированно выбирает те, что используют максимум кубиков.
 * 3. Оценивает итоговую доску по стратегическим принципам гроссмейстеров длинных нард:
 *    - Запирание головы противника (choke zone)
 *    - Построение непрерывных заборов (primes 3..6)
 *    - Быстрая разгрузка своей головы
 *    - Защита отстающих фишек (хвоста) от блокады
 *    - Равномерное распределение фишек (бонус за пары, штраф за башни 5+)
 *    - Оптимальная подготовка к выбросу и быстрый сброс
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class AdvancedAI {

    private class TurnResult {
        public MoveOption first_move;
        public GameBoard final_board;
        public int dice_used;
        public int head_checkers_moved;
        public double score;

        public TurnResult (MoveOption first_move, GameBoard final_board, int dice_used, int head_checkers_moved, double score) {
            this.first_move = first_move;
            this.final_board = final_board;
            this.dice_used = dice_used;
            this.head_checkers_moved = head_checkers_moved;
            this.score = score;
        }
    }

    private class SubResult {
        public GameBoard final_board;
        public int total_dice_used;
        public int head_checkers_moved;
        public double score;

        public SubResult (GameBoard final_board, int total_dice_used, int head_checkers_moved, double score) {
            this.final_board = final_board;
            this.total_dice_used = total_dice_used;
            this.head_checkers_moved = head_checkers_moved;
            this.score = score;
        }
    }

    public class PrimeInfo {
        public int length;
        public int start_idx;
        public int trapped_checkers;
        public bool[] points; // 25 elements bool lookup

        public PrimeInfo (int length, int start_idx, int trapped_checkers, bool[] points) {
            this.length = length;
            this.start_idx = start_idx;
            this.trapped_checkers = trapped_checkers;
            this.points = points;
        }
    }

    /** Основной метод выбора хода для уровня Master. */
    public static MoveOption? choose_move (
        MoveOption[] options,
        GameBoard board,
        CheckerColor color,
        int[] remaining_dice
    ) {
        var playable_options = new MoveOption[0];
        for (var i = 0; i < options.length; i++) {
            if (!options[i].is_illegal_prime) {
                playable_options += options[i];
            }
        }
        if (playable_options.length == 0) {
            return null;
        }

        // Если остался только 1 доступный ход, возвращаем его сразу
        if (playable_options.length == 1) {
            return playable_options[0];
        }

        var is_first_turn = is_game_first_turn (board, color);
        var is_double = remaining_dice.length >= 2;
        if (is_double) {
            var first_d = remaining_dice[0];
            for (var i = 1; i < remaining_dice.length; i++) {
                if (remaining_dice[i] != first_d) {
                    is_double = false;
                    break;
                }
            }
        }

        var checkers_moved_from_head = 0;

        var best_first = find_best_turn_first_move (
            board,
            color,
            remaining_dice,
            checkers_moved_from_head,
            is_double,
            is_first_turn,
            playable_options
        );

        if (best_first != null) {
            return best_first;
        }

        return evaluate_single_step (playable_options, board, color);
    }

    private static bool can_sacrifice_head_condition (GameBoard root_board, CheckerColor color) {
        var our_head = PlayerPath.start_point (color);
        var our_stack = root_board.stack_at (our_head);
        var our_head_count = (our_stack != null && our_stack.color == color) ? our_stack.checker_ids.length : 0;

        var opponent_color = color.opposite ();
        var opp_head = PlayerPath.start_point (opponent_color);
        var opp_stack = root_board.stack_at (opp_head);
        var opp_head_count = (opp_stack != null && opp_stack.color == opponent_color) ? opp_stack.checker_ids.length : 0;

        if (!(our_head_count <= 6 && our_head_count < opp_head_count && opp_head_count >= 3)) {
            return false;
        }

        var our_route = PlayerPath.path (color);
        var our_starter_control = 0;
        for (var idx = 0; idx <= 6; idx++) {
            var s = root_board.stack_at (our_route[idx]);
            if (s != null && s.color == color) {
                our_starter_control++;
            }
        }
        if (our_starter_control < 4) {
            return false;
        }

        var opp_consecutive = 0;
        var opp_max_consecutive = 0;
        for (var idx = 1; idx <= 6; idx++) {
            var s = root_board.stack_at (our_route[idx]);
            if (s != null && s.color == opponent_color) {
                opp_consecutive++;
                if (opp_consecutive > opp_max_consecutive) {
                    opp_max_consecutive = opp_consecutive;
                }
            } else {
                opp_consecutive = 0;
            }
        }
        if (opp_max_consecutive >= 3) {
            return false;
        }

        return true;
    }

    private static bool captures_new_choke_point (
        GameBoard root_board,
        GameBoard candidate_final_board,
        CheckerColor color
    ) {
        var opponent_color = color.opposite ();
        var opp_route = PlayerPath.path (opponent_color);
        var initial_choke_points = 0;
        for (var idx = 1; idx <= 3; idx++) {
            var s = root_board.stack_at (opp_route[idx]);
            if (s != null && s.color == color) {
                initial_choke_points++;
            }
        }

        var final_choke_points = 0;
        for (var idx = 1; idx <= 3; idx++) {
            var s = candidate_final_board.stack_at (opp_route[idx]);
            if (s != null && s.color == color) {
                final_choke_points++;
            }
        }

        return final_choke_points > initial_choke_points;
    }

    private static MoveOption? find_best_turn_first_move (
        GameBoard board,
        CheckerColor color,
        int[] remaining_dice,
        int checkers_moved_from_head,
        bool is_double,
        bool is_first_turn,
        MoveOption[] root_options
    ) {
        var all_results = new GenericArray<TurnResult> ();
        var our_head = PlayerPath.start_point (color);

        for (var i = 0; i < root_options.length; i++) {
            var option = root_options[i];
            var next_board = board.clone ();
            next_board.move_one_checker (option.from, option.to);

            var next_dice = remaining_dice_after (option, remaining_dice);
            var is_head_move = MoveValidator.is_head (option.from, color);
            var next_head_count = checkers_moved_from_head + (is_head_move ? 1 : 0);

            if (next_dice.length == 0 || next_board.is_winner (color)) {
                var score = evaluate_board (next_board, color);
                all_results.add (new TurnResult (
                    option,
                    next_board,
                    option.die_indices.length,
                    next_head_count,
                    score
                ));
            } else {
                var sub_result = explore_turn_continuation (
                    board,
                    next_board,
                    color,
                    next_dice,
                    next_head_count,
                    is_double,
                    is_first_turn,
                    option.die_indices.length
                );

                all_results.add (new TurnResult (
                    option,
                    sub_result.final_board,
                    sub_result.total_dice_used,
                    sub_result.head_checkers_moved,
                    sub_result.score
                ));
            }
        }

        if (all_results.length == 0) {
            return null;
        }

        var max_dice_used = 0;
        for (var i = 0; i < all_results.length; i++) {
            if (all_results[i].dice_used > max_dice_used) {
                max_dice_used = all_results[i].dice_used;
            }
        }

        var candidates_with_max_dice = new GenericArray<TurnResult> ();
        for (var i = 0; i < all_results.length; i++) {
            if (all_results[i].dice_used == max_dice_used) {
                candidates_with_max_dice.add (all_results[i]);
            }
        }

        var our_head_stack = board.stack_at (our_head);
        var head_count_before_turn = (our_head_stack != null && our_head_stack.color == color) ? our_head_stack.checker_ids.length : 0;

        var can_sacrifice = can_sacrifice_head_condition (board, color);
        var candidates_after_head_rule = new GenericArray<TurnResult> ();

        if (head_count_before_turn > 0) {
            var candidates_with_head_move = new GenericArray<TurnResult> ();
            for (var i = 0; i < candidates_with_max_dice.length; i++) {
                if (candidates_with_max_dice[i].head_checkers_moved > 0) {
                    candidates_with_head_move.add (candidates_with_max_dice[i]);
                }
            }

            if (can_sacrifice) {
                var choke_sacrifice_candidates = new GenericArray<TurnResult> ();
                for (var i = 0; i < candidates_with_max_dice.length; i++) {
                    var cand = candidates_with_max_dice[i];
                    if (cand.head_checkers_moved == 0 && captures_new_choke_point (board, cand.final_board, color)) {
                        choke_sacrifice_candidates.add (cand);
                    }
                }

                if (choke_sacrifice_candidates.length > 0) {
                    for (var i = 0; i < candidates_with_max_dice.length; i++) {
                        var cand = candidates_with_max_dice[i];
                        if (cand.head_checkers_moved > 0 || captures_new_choke_point (board, cand.final_board, color)) {
                            candidates_after_head_rule.add (cand);
                        }
                    }
                    if (candidates_after_head_rule.length == 0) {
                        candidates_after_head_rule = candidates_with_max_dice;
                    }
                } else {
                    candidates_after_head_rule = (candidates_with_head_move.length > 0) ? candidates_with_head_move : candidates_with_max_dice;
                }
            } else {
                candidates_after_head_rule = (candidates_with_head_move.length > 0) ? candidates_with_head_move : candidates_with_max_dice;
            }
        } else {
            candidates_after_head_rule = candidates_with_max_dice;
        }

        // Правило 1.1: Если можно сыграть только 1 кубик (при наличии 2+ кубиков), играем старший кубик
        var candidates = new GenericArray<TurnResult> ();
        if (max_dice_used == 1 && remaining_dice.length >= 2) {
            var max_played_die = 0;
            for (var i = 0; i < candidates_after_head_rule.length; i++) {
                if (candidates_after_head_rule[i].first_move.die > max_played_die) {
                    max_played_die = candidates_after_head_rule[i].first_move.die;
                }
            }
            for (var i = 0; i < candidates_after_head_rule.length; i++) {
                if (candidates_after_head_rule[i].first_move.die == max_played_die) {
                    candidates.add (candidates_after_head_rule[i]);
                }
            }
        } else {
            candidates = candidates_after_head_rule;
        }

        if (candidates.length == 0) {
            return null;
        }

        // Правило 2: Из вариантов с максимальным числом кубиков выбираем лучший по оценке финальной доски.
        // При равенстве score (разница <= 0.001) начинаем со старшего кубика.
        TurnResult? best = null;
        for (var i = 0; i < candidates.length; i++) {
            var cand = candidates[i];
            if (best == null) {
                best = cand;
            } else {
                if (Math.fabs (cand.score - best.score) > 0.001) {
                    if (cand.score > best.score) {
                        best = cand;
                    }
                } else {
                    if (cand.first_move.die > best.first_move.die) {
                        best = cand;
                    }
                }
            }
        }

        return (best != null) ? best.first_move : null;
    }

    private static SubResult explore_turn_continuation (
        GameBoard root_board,
        GameBoard board,
        CheckerColor color,
        int[] remaining_dice,
        int checkers_moved_from_head,
        bool is_double,
        bool is_first_turn,
        int dice_used_so_far
    ) {
        var visited_boards = new HashTable<string, bool> (str_hash, str_equal);
        return explore_turn_continuation_internal (
            root_board,
            board,
            color,
            remaining_dice,
            checkers_moved_from_head,
            is_double,
            is_first_turn,
            dice_used_so_far,
            visited_boards
        );
    }

    private static SubResult explore_turn_continuation_internal (
        GameBoard root_board,
        GameBoard board,
        CheckerColor color,
        int[] remaining_dice,
        int checkers_moved_from_head,
        bool is_double,
        bool is_first_turn,
        int dice_used_so_far,
        HashTable<string, bool> visited_boards
    ) {
        var raw_options = MoveValidator.all_moves (
            board,
            color,
            remaining_dice,
            checkers_moved_from_head,
            is_double,
            is_first_turn
        );

        var legal_options = new MoveOption[0];
        for (var i = 0; i < raw_options.length; i++) {
            if (!raw_options[i].is_illegal_prime) {
                legal_options += raw_options[i];
            }
        }

        var filtered_options = MoveValidator.filter_forced_single_die (legal_options);

        if (filtered_options.length == 0 || board.is_winner (color)) {
            return new SubResult (board, dice_used_so_far, checkers_moved_from_head, evaluate_board (board, color));
        }

        var best_board = board;
        var max_total_dice = dice_used_so_far;
        var best_head_checkers_moved = checkers_moved_from_head;
        var best_score = -1e12;

        for (var i = 0; i < filtered_options.length; i++) {
            var option = filtered_options[i];
            var next_board = board.clone ();
            next_board.move_one_checker (option.from, option.to);

            var sig = next_board.position_signature ();
            if (visited_boards.contains (sig)) {
                continue;
            }
            visited_boards.insert (sig, true);

            var next_dice = remaining_dice_after (option, remaining_dice);
            var is_head_move = MoveValidator.is_head (option.from, color);
            var next_head_count = checkers_moved_from_head + (is_head_move ? 1 : 0);
            var current_dice_used = dice_used_so_far + option.die_indices.length;

            SubResult result;
            if (next_dice.length == 0 || next_board.is_winner (color)) {
                result = new SubResult (next_board, current_dice_used, next_head_count, evaluate_board (next_board, color));
            } else {
                result = explore_turn_continuation_internal (
                    root_board,
                    next_board,
                    color,
                    next_dice,
                    next_head_count,
                    is_double,
                    is_first_turn,
                    current_dice_used,
                    visited_boards
                );
            }

            var can_sacrifice_condition = can_sacrifice_head_condition (root_board, color);
            var is_current_choke_sacrifice = can_sacrifice_condition && captures_new_choke_point (root_board, result.final_board, color);
            var is_best_choke_sacrifice = can_sacrifice_condition && captures_new_choke_point (root_board, best_board, color);

            if (result.total_dice_used > max_total_dice) {
                max_total_dice = result.total_dice_used;
                best_head_checkers_moved = result.head_checkers_moved;
                best_score = result.score;
                best_board = result.final_board;
            } else if (result.total_dice_used == max_total_dice) {
                if (is_current_choke_sacrifice || is_best_choke_sacrifice) {
                    if (result.score > best_score) {
                        best_score = result.score;
                        best_board = result.final_board;
                        best_head_checkers_moved = result.head_checkers_moved;
                    }
                } else {
                    if (result.head_checkers_moved > best_head_checkers_moved) {
                        best_head_checkers_moved = result.head_checkers_moved;
                        best_score = result.score;
                        best_board = result.final_board;
                    } else if (result.head_checkers_moved == best_head_checkers_moved && result.score > best_score) {
                        best_score = result.score;
                        best_board = result.final_board;
                    }
                }
            }
        }

        return new SubResult (best_board, max_total_dice, best_head_checkers_moved, best_score);
    }

    private static MoveOption? evaluate_single_step (
        MoveOption[] options,
        GameBoard board,
        CheckerColor color
    ) {
        var single_moves = new GenericArray<MoveOption> ();
        var max_die = 0;
        for (var i = 0; i < options.length; i++) {
            if (!options[i].is_combined) {
                single_moves.add (options[i]);
                if (options[i].die > max_die) {
                    max_die = options[i].die;
                }
            }
        }

        var eligible = new GenericArray<MoveOption> ();
        for (var i = 0; i < options.length; i++) {
            if (options[i].is_combined || options[i].die == max_die) {
                eligible.add (options[i]);
            }
        }

        var our_head = PlayerPath.start_point (color);
        var head_st = board.stack_at (our_head);
        var head_count = (head_st != null && head_st.color == color) ? head_st.checker_ids.length : 0;

        var head_moves = new GenericArray<MoveOption> ();
        for (var i = 0; i < eligible.length; i++) {
            if (MoveValidator.is_head (eligible[i].from, color)) {
                head_moves.add (eligible[i]);
            }
        }

        var candidates = (head_count > 0 && head_moves.length > 0) ? head_moves : eligible;

        MoveOption? best_move = null;
        var best_score = -1e12;

        for (var i = 0; i < candidates.length; i++) {
            var opt = candidates[i];
            var next_board = board.clone ();
            next_board.move_one_checker (opt.from, opt.to);
            var score = evaluate_board (next_board, color);
            if (score > best_score) {
                best_score = score;
                best_move = opt;
            }
        }

        return (best_move != null) ? best_move : ((candidates.length > 0) ? candidates[0] : ((options.length > 0) ? options[0] : null));
    }

    /** Комплексная оценка состояния доски (Board Evaluation) */
    public static double evaluate_board (GameBoard board, CheckerColor color) {
        var opponent_color = color.opposite ();

        // 1. Проверка победы / поражения
        if (board.is_winner (color)) return 100000000.0;
        if (board.is_winner (opponent_color)) return -100000000.0;

        var score = 0.0;

        var our_route = PlayerPath.path (color);
        var opp_route = PlayerPath.path (opponent_color);
        var our_head = PlayerPath.start_point (color);
        var opp_head = PlayerPath.start_point (opponent_color);

        int tail_idx = -1;
        for (var i = 0; i < our_route.length; i++) {
            var s = board.stack_at (our_route[i]);
            if (s != null && s.color == color) {
                tail_idx = i;
                break;
            }
        }

        var our_borne_off = board.borne_off_count (color);
        var opp_borne_off = board.borne_off_count (opponent_color);

        // 2. Сброс фишек (Bear-off)
        score += ((double) our_borne_off) * 600000.0;
        if (our_borne_off >= 1) {
            score += 400000.0;
        }
        score -= ((double) opp_borne_off) * 70000.0;

        // 3. Подсчет дистанции (Pip Count)
        var our_pip = calculate_pip_count (board, color);
        var opp_pip = calculate_pip_count (board, opponent_color);
        var pip_advantage = opp_pip - our_pip;
        score += ((double) pip_advantage) * 1200.0;

        // 4. Разгрузка головы (Head Evacuation)
        var head_st = board.stack_at (our_head);
        var head_count = (head_st != null && head_st.color == color) ? head_st.checker_ids.length : 0;
        score -= ((double) head_count) * 220000.0;
        if (head_count >= 5) {
            score -= ((double) (head_count - 4)) * 60000.0;
        }
        if (head_count >= 8) {
            score -= ((double) (head_count - 7)) * 50000.0;
        }
        if (head_count >= 11) {
            score -= ((double) (head_count - 10)) * 50000.0;
        }
        if (head_count == 0) {
            score += 5500000.0;
        }
        if (opp_borne_off > 0 && head_count > 0) {
            score -= ((double) head_count) * 400000.0;
        }

        // Head Bottleneck
        var checkers_in_home_early = 0;
        for (var idx = 18; idx < 24; idx++) {
            var pt = our_route[idx];
            var s = board.stack_at (pt);
            if (s != null && s.color == color) {
                checkers_in_home_early += s.checker_ids.length;
            }
        }
        if (head_count > 0) {
            if (checkers_in_home_early >= 8) {
                score -= ((double) head_count) * ((double) (checkers_in_home_early - 7)) * 80000.0;
            }
            if (checkers_in_home_early >= 11) {
                score -= ((double) head_count) * 300000.0;
            }
            if (checkers_in_home_early >= 13) {
                score -= ((double) head_count) * 800000.0;
            }
        }

        var opp_head_st = board.stack_at (opp_head);
        var opp_head_count = (opp_head_st != null && opp_head_st.color == opponent_color) ? opp_head_st.checker_ids.length : 0;

        if (head_count > opp_head_count && head_count > 0) {
            var head_deficit = head_count - opp_head_count;
            var deficit_multiplier = (opp_head_count == 0) ? 1000000.0 : 450000.0;
            score -= ((double) head_deficit) * deficit_multiplier;
        }

        var opp_outside_home_checkers = 0;
        for (var idx = 0; idx < 18; idx++) {
            var pt = opp_route[idx];
            var s = board.stack_at (pt);
            if (s != null && s.color == opponent_color) {
                opp_outside_home_checkers += s.checker_ids.length;
            }
        }

        // 5. Запирание выхода с головы противника (Choke Zone Control)
        double[] choke_weights = { 0.0, 50000.0, 50000.0, 40000.0, 45000.0, 45000.0, 55000.0 };
        var choke_score = 0.0;
        var choke_count = 0;
        double opp_head_urgency;
        if (opp_head_count >= 10) {
            opp_head_urgency = 2.5;
        } else if (opp_head_count >= 6) {
            opp_head_urgency = 2.0;
        } else if (opp_head_count >= 3) {
            opp_head_urgency = 1.7;
        } else if (opp_head_count >= 1) {
            opp_head_urgency = 1.4;
        } else {
            opp_head_urgency = 0.0;
        }

        if (opp_head_urgency > 0.0) {
            for (var idx = 1; idx <= int.min (6, opp_route.length - 1); idx++) {
                var point = opp_route[idx];
                var stack = board.stack_at (point);
                if (stack != null && stack.color == color) {
                    choke_count++;
                    var base_weight = (idx <= 6) ? choke_weights[idx] : 10000.0;
                    choke_score += base_weight * opp_head_urgency;

                    if ((idx == 1 || idx == 2) && stack.checker_ids.length >= 2) {
                        choke_score += 35000.0 * opp_head_urgency;
                    } else if (idx == 3 && stack.checker_ids.length >= 2 && opp_head_count >= 2 && head_count >= 3) {
                        choke_score += 80000.0 * opp_head_urgency;
                    }
                }
            }

            if (choke_count >= 2) {
                choke_score += ((double) (choke_count * choke_count)) * 10000.0 * opp_head_urgency;
            }

            if (opp_head_count >= 1) {
                var choke_point1 = opp_route[1];
                var s1 = board.stack_at (choke_point1);
                if (s1 != null && s1.color == color) {
                    var p1_bonus = (opp_head_count >= 4) ? 110000.0 : 70000.0;
                    choke_score += p1_bonus * opp_head_urgency;
                }
            }

            if (opp_head_count >= 2) {
                var current_choke_streak = 0;
                var max_choke_streak = 0;
                for (var idx = 1; idx <= 5; idx++) {
                    var pt = opp_route[idx];
                    var s = board.stack_at (pt);
                    if (s != null && s.color == color) {
                        current_choke_streak++;
                        if (current_choke_streak > max_choke_streak) {
                            max_choke_streak = current_choke_streak;
                        }
                    } else {
                        current_choke_streak = 0;
                    }
                }
                if (max_choke_streak >= 5) {
                    choke_score += 1500000.0 * opp_head_urgency;
                } else if (max_choke_streak >= 4) {
                    choke_score += 900000.0 * opp_head_urgency;
                } else if (max_choke_streak >= 3) {
                    choke_score += 450000.0 * opp_head_urgency;
                } else if (max_choke_streak >= 2) {
                    choke_score += 150000.0 * opp_head_urgency;
                }
            }

            // Choke Anchor Synergy
            if (opp_head_count >= 2) {
                for (var choke_idx = 2; choke_idx <= 5; choke_idx++) {
                    var choke_point = opp_route[choke_idx];
                    var our_idx = index_of_point (our_route, choke_point);
                    if (our_idx < 0) continue;
                    var s = board.stack_at (choke_point);
                    if (s != null && s.color == color && s.checker_ids.length == 1) {
                        var distinct_step_count = 0;
                        for (var step = 1; step <= 6; step++) {
                            var support_idx = our_idx - step;
                            if (support_idx < 6) break;
                            var sup_stack = board.stack_at (our_route[support_idx]);
                            if (sup_stack != null && sup_stack.color == color) {
                                distinct_step_count++;
                                choke_score += 25000.0 * opp_head_urgency;
                            }
                        }
                        if (distinct_step_count >= 2) {
                            choke_score += 30000.0 * opp_head_urgency;
                        }
                    }
                }
            }

            score += choke_score;
        }

        // 5b. Стратегическая оценка первой четверти соперника
        var checkers_past_opp_quadrant = 0;
        var checkers_behind_opp_quadrant = 0;
        var checkers_in_opp_quadrant = 0;
        for (var idx = 0; idx < our_route.length; idx++) {
            var pt = our_route[idx];
            var s = board.stack_at (pt);
            if (s == null || s.color != color) continue;
            var cnt = s.checker_ids.length;
            if (idx >= 18) {
                checkers_past_opp_quadrant += cnt;
            } else if (idx >= 12) {
                checkers_in_opp_quadrant += cnt;
            } else {
                checkers_behind_opp_quadrant += cnt;
            }
        }
        checkers_past_opp_quadrant += our_borne_off;

        if (checkers_past_opp_quadrant >= 1 && checkers_behind_opp_quadrant >= 6 && head_count >= 6 && checkers_in_opp_quadrant < 2) {
            if (checkers_in_opp_quadrant == 0) {
                score -= 700000.0;
            }

            var opp_blocks_in_quadrant = 0;
            var current_consecutive = 0;
            var opp_max_consecutive = 0;
            for (var idx = 12; idx <= 17; idx++) {
                var pt = our_route[idx];
                var s = board.stack_at (pt);
                if (s != null && s.color == opponent_color) {
                    opp_blocks_in_quadrant++;
                    current_consecutive++;
                    if (current_consecutive > opp_max_consecutive) {
                        opp_max_consecutive = current_consecutive;
                    }
                } else {
                    current_consecutive = 0;
                }
            }
            if (opp_max_consecutive >= 4 || opp_blocks_in_quadrant >= 5) {
                score -= ((double) opp_blocks_in_quadrant) * 300000.0;
            }
        }

        // Блокада максимального выхода соперника с головы кубиком 6 (opp_route[6])
        if (opp_head_count > 0) {
            var choke_point6 = opp_route[6];
            var s6 = board.stack_at (choke_point6);
            if (s6 != null && s6.color == color) {
                score += 65000.0 * opp_head_urgency;
                if (checkers_in_opp_quadrant >= 1) {
                    score += 60000.0 * opp_head_urgency;
                }
            }
        }

        // 5c. Защита собственного выхода из головы (Exit Corridor Defense)
        if (head_count > 0) {
            var our_exit_anchors = 0;
            var our_exit_controlled_points = 0;
            var our_consecutive_exit = 0;
            var our_max_consecutive_exit = 0;
            var opp_max_consecutive_in_exit = 0;
            var opp_current_consecutive = 0;
            var opp_controlled_in_exit = 0;

            for (var idx = 1; idx <= int.min (6, our_route.length - 1); idx++) {
                var point = our_route[idx];
                var s = board.stack_at (point);
                if (s != null) {
                    if (s.color == color) {
                        our_exit_controlled_points++;
                        our_consecutive_exit++;
                        if (our_consecutive_exit > our_max_consecutive_exit) {
                            our_max_consecutive_exit = our_consecutive_exit;
                        }
                        if (s.checker_ids.length >= 2 && (idx <= 2 || head_count < 8)) {
                            our_exit_anchors++;
                        }
                        opp_current_consecutive = 0;
                    } else {
                        our_consecutive_exit = 0;
                        opp_controlled_in_exit++;
                        opp_current_consecutive++;
                        if (opp_current_consecutive > opp_max_consecutive_in_exit) {
                            opp_max_consecutive_in_exit = opp_current_consecutive;
                        }
                    }
                } else {
                    our_consecutive_exit = 0;
                    opp_current_consecutive = 0;
                }
            }

            var head_urgency = (head_count >= 8) ? 2.0 : ((head_count >= 4) ? 1.4 : 1.0);
            score += ((double) our_exit_controlled_points) * 20000.0 * head_urgency;
            score += ((double) our_exit_anchors) * 20000.0 * head_urgency;

            if (our_max_consecutive_exit >= 2) {
                if (our_max_consecutive_exit == 2) score += 40000.0 * head_urgency;
                else if (our_max_consecutive_exit == 3) score += 100000.0 * head_urgency;
                else if (our_max_consecutive_exit == 4) score += 250000.0 * head_urgency;
                else if (our_max_consecutive_exit >= 5) score += 450000.0 * head_urgency;
            }

            if (head_count >= 8) {
                for (var idx = 3; idx <= int.min (6, our_route.length - 1); idx++) {
                    var exit_pt = our_route[idx];
                    var s = board.stack_at (exit_pt);
                    if (s != null && s.color == color && s.checker_ids.length >= 2) {
                        score -= 35000.0 * ((double) (s.checker_ids.length - 1));
                    }
                }
            }

            if (head_count > 0) {
                var golden_exit_multiplier = (head_count >= 8) ? 1.4 : ((head_count >= 4) ? 1.2 : 1.0);
                var our_controlled_in_exit = 0;
                for (var idx = 1; idx <= int.min (6, our_route.length - 1); idx++) {
                    var exit_pt = our_route[idx];
                    var s = board.stack_at (exit_pt);
                    if (s != null && s.color == color) {
                        our_controlled_in_exit++;
                    }
                }

                if (opp_controlled_in_exit >= 2) {
                    if (our_controlled_in_exit == 0) {
                        score -= 3500000.0 * ((double) head_count);
                    } else if (head_count >= 3 && our_controlled_in_exit <= 1 && opp_max_consecutive_in_exit >= 2) {
                        score -= ((double) head_count) * 350000.0;
                    }
                }

                for (var idx = 1; idx <= int.min (6, our_route.length - 1); idx++) {
                    var exit_pt = our_route[idx];
                    var is_golden = (idx <= 2);

                    var has_opp_adjacent = false;
                    if (idx > 1) {
                        var ps = board.stack_at (our_route[idx - 1]);
                        if (ps != null && ps.color == opponent_color) has_opp_adjacent = true;
                    }
                    if (idx < int.min (6, our_route.length - 1)) {
                        var ns = board.stack_at (our_route[idx + 1]);
                        if (ns != null && ns.color == opponent_color) has_opp_adjacent = true;
                    }

                    var is_critical_exit = (head_count > 0) && (is_golden || idx <= 3 || has_opp_adjacent);
                    var base_gate_bonus = (is_golden ? 55000.0 : (is_critical_exit ? 35000.0 : 15000.0));

                    var s = board.stack_at (exit_pt);
                    if (s != null && s.color == color) {
                        score += base_gate_bonus * golden_exit_multiplier;
                        if (is_golden && s.checker_ids.length >= 2) {
                            score += 20000.0 * golden_exit_multiplier;
                        }
                        if (opp_controlled_in_exit >= 2) {
                            score += (is_critical_exit ? 120000.0 : 65000.0) * golden_exit_multiplier;
                            if (is_golden) {
                                score += 50000.0 * golden_exit_multiplier;
                            }
                        }
                        if (idx == 6) {
                            var s_1 = board.stack_at (our_route[1]);
                            var s_2 = board.stack_at (our_route[2]);
                            var small_exits_blocked = (s_1 != null && s_1.color == opponent_color) || (s_2 != null && s_2.color == opponent_color);
                            if (small_exits_blocked) {
                                score += 80000.0 * golden_exit_multiplier;
                            }
                        }
                    } else if (s == null) {
                        if (is_golden && head_count >= 8) {
                            score -= 55000.0 * golden_exit_multiplier;
                        }

                        if (is_golden || opp_controlled_in_exit >= 2) {
                            var opp_pt_idx = index_of_point (opp_route, exit_pt);
                            if (opp_pt_idx >= 0) {
                                var opp_can_reach = false;
                                for (var step = 1; step <= 6; step++) {
                                    var src_idx = opp_pt_idx - step;
                                    if (src_idx < 0) break;
                                    var os = board.stack_at (opp_route[src_idx]);
                                    if (os != null && os.color == opponent_color) {
                                        opp_can_reach = true;
                                        break;
                                    }
                                }
                                if (opp_can_reach) {
                                    double threat_penalty;
                                    if (opp_controlled_in_exit >= 2 && is_critical_exit) {
                                        threat_penalty = 450000.0 * (head_count >= 3 ? ((double) head_count) / 2.0 : 1.0);
                                    } else {
                                        threat_penalty = (is_golden ? 60000.0 : 20000.0) * golden_exit_multiplier;
                                    }
                                    score -= threat_penalty;
                                }
                            }
                        }
                    }
                }
            }

            if (opp_max_consecutive_in_exit >= 2) {
                if (opp_max_consecutive_in_exit == 2) score -= 15000.0 * head_urgency;
                else if (opp_max_consecutive_in_exit == 3) score -= 45000.0 * head_urgency;
                else if (opp_max_consecutive_in_exit == 4) score -= 120000.0 * head_urgency;
                else if (opp_max_consecutive_in_exit == 5) score -= 350000.0 * head_urgency;
                else if (opp_max_consecutive_in_exit >= 6) score -= 2500000.0;
            }

            if (opp_max_consecutive_in_exit >= 3 && head_count > 0) {
                score -= ((double) head_count) * ((double) opp_max_consecutive_in_exit) * 120000.0;
            }
        }

        // 5d. Дебютная экспансия в дом соперника
        if (head_count >= 4) {
            for (var idx = 6; idx <= 17; idx++) {
                var point = our_route[idx];
                var s = board.stack_at (point);
                if (s != null && s.color == color) {
                    var depth_bonus = ((double) (idx - 5)) * 18000.0;
                    score += depth_bonus * ((double) s.checker_ids.length);
                    if (idx >= 12 && s.checker_ids.length >= 4) {
                        score -= ((double) (s.checker_ids.length - 3)) * 80000.0;
                    }
                }
            }

            var springboard_point = our_route[11];
            var sp_stack = board.stack_at (springboard_point);
            if (sp_stack != null && sp_stack.color == color) {
                score += 85000.0 * ((double) sp_stack.checker_ids.length);

                var has_target_gap = false;
                for (var gap_step = 1; gap_step <= 6; gap_step++) {
                    var gap_idx = 11 + gap_step;
                    if (gap_idx >= our_route.length) break;
                    var target_pt = our_route[gap_idx];
                    var t_stack = board.stack_at (target_pt);
                    if (t_stack == null || t_stack.color == color) {
                        has_target_gap = true;
                        break;
                    }
                }
                if (has_target_gap) {
                    score += 40000.0;
                }
            }

            if (checkers_in_opp_quadrant >= 1) {
                for (var idx = 18; idx <= 23; idx++) {
                    var point = our_route[idx];
                    var s = board.stack_at (point);
                    if (s != null && s.color == color) {
                        score += 60000.0 * ((double) s.checker_ids.length);
                    }
                }
            }

            var point6 = our_route[6];
            var s_p6 = board.stack_at (point6);
            if (head_count >= 8 && s_p6 != null && s_p6.color == color) {
                if (s_p6.checker_ids.length >= 3) {
                    score -= 35000.0 * ((double) (s_p6.checker_ids.length - 2));
                }
                if (s_p6.checker_ids.length >= 2 && opp_head_count >= 4) {
                    var sp_s = board.stack_at (our_route[11]);
                    if (sp_s == null || sp_s.color != color) {
                        score -= 50000.0 * ((double) (s_p6.checker_ids.length - 1));
                    }
                }
            }
        }

        // 5e. Защита передовых клин-пунктов и ключевых рубежей
        var checkers_in_first_half = 0;
        for (var i = 0; i < 12; i++) {
            var s = board.stack_at (our_route[i]);
            if (s != null && s.color == color) {
                checkers_in_first_half += s.checker_ids.length;
            }
        }

        for (var idx = 1; idx <= 17; idx++) {
            var point = our_route[idx];
            if (point == opp_head) continue;

            var opp_consecutive_before = 0;
            for (var step = 1; step <= 5; step++) {
                var check_idx = idx - step;
                if (check_idx < 0) break;
                if ((idx >= 12 && check_idx <= 11) || (idx <= 11 && check_idx >= 12)) break;
                var s = board.stack_at (our_route[check_idx]);
                if (s != null && s.color == opponent_color) {
                    opp_consecutive_before++;
                } else {
                    break;
                }
            }

            var opp_consecutive_after = 0;
            for (var step = 1; step <= 5; step++) {
                var check_idx = idx + step;
                if (check_idx >= our_route.length) break;
                if ((idx <= 11 && check_idx >= 12) || (idx >= 12 && check_idx <= 11)) break;
                var s = board.stack_at (our_route[check_idx]);
                if (s != null && s.color == opponent_color) {
                    opp_consecutive_after++;
                } else {
                    break;
                }
            }

            var friendly_behind_count = 0;
            for (var check_idx = 0; check_idx < idx; check_idx++) {
                var s = board.stack_at (our_route[check_idx]);
                if (s != null && s.color == color) {
                    friendly_behind_count += s.checker_ids.length;
                }
            }

            var is_internal_wedge = (opp_consecutive_before >= 1 && opp_consecutive_after >= 1);
            var potential_wall = is_internal_wedge
                ? (opp_consecutive_before + opp_consecutive_after + 1)
                : (int.max (opp_consecutive_before, opp_consecutive_after) + 1);

            var s_pt = board.stack_at (point);
            if (s_pt != null && s_pt.color == color) {
                var is_lone_straggler = (s_pt.checker_ids.length == 1 && friendly_behind_count == 0 && head_count == 0 && idx < 12 && checkers_in_first_half <= 2);
                if (!is_lone_straggler && (is_internal_wedge || friendly_behind_count >= 1)) {
                    if (potential_wall >= 6) {
                        score += 1500000.0;
                    } else if (potential_wall == 5) {
                        score += 390000.0;
                    } else if (potential_wall == 4) {
                        score += 150000.0;
                    }
                }
            } else if (friendly_behind_count >= 1) {
                if (potential_wall >= 6) {
                    score -= 1500000.0 + ((double) friendly_behind_count) * 100000.0;
                } else if (potential_wall == 5) {
                    score -= 390000.0 + ((double) friendly_behind_count) * 25000.0;
                } else if (potential_wall == 4) {
                    score -= 150000.0 + ((double) friendly_behind_count) * 15000.0;
                }
            }
        }

        // 5f. Контроль калитки дома соперника (Gate 6 Control / our_route[6])
        if (head_count <= 6) {
            var gate_point = our_route[6];
            var s = board.stack_at (gate_point);
            if (s != null && s.color == color) {
                var gate_urgency = (head_count == 0 && tail_idx < 12) ? 2.5 : 1.2;
                score += 120000.0 * gate_urgency;
            } else if (s == null && head_count == 0 && tail_idx < 12) {
                score -= 150000.0;
            }
        }

        // 6. Построение заборов (Primes)
        var our_primes = analyze_primes_info (board, color, opponent_color);
        var active_prime_points = new bool[25];
        var has_active_primes = false;

        for (var i = 0; i < our_primes.length; i++) {
            var prime = our_primes[i];
            var trapped = prime.trapped_checkers;
            if (prime.length >= 6 && trapped >= 1) {
                has_active_primes = true;
                for (var r = 1; r <= 24; r++) {
                    if (prime.points[r]) active_prime_points[r] = true;
                }
            }

            if (prime.length == 2) score += 3000.0;
            else if (prime.length == 3) score += 10000.0;
            else if (prime.length == 4) score += 35000.0;
            else if (prime.length == 5) score += 95000.0;
            else if (prime.length >= 6) score += 300000.0;

            if (prime.length >= 6 && trapped >= 1) {
                score += 1500000.0 + ((double) trapped) * 100000.0 + ((double) (prime.length - 6)) * 75000.0;

                var rear_point = opp_route[prime.start_idx];
                var s = board.stack_at (rear_point);
                if (s != null && s.color == color) {
                    score += 800000.0 + ((double) trapped) * 50000.0;
                } else {
                    var opp_can_enter_rear = false;
                    for (var step = 1; step <= 6; step++) {
                        var chk = prime.start_idx - step;
                        if (chk < 0) break;
                        var os = board.stack_at (opp_route[chk]);
                        if (os != null && os.color == opponent_color) {
                            opp_can_enter_rear = true;
                            break;
                        }
                    }
                    if (opp_can_enter_rear) {
                        score -= 1200000.0 + ((double) trapped) * 50000.0;
                    }
                }

                if (prime.start_idx + 1 < opp_route.length) {
                    var second_rear = opp_route[prime.start_idx + 1];
                    var s2 = board.stack_at (second_rear);
                    if (s2 != null && s2.color == color) {
                        score += 400000.0 + ((double) trapped) * 30000.0;
                    }
                }
            } else if (prime.length == 5 && trapped >= 1) {
                score += ((double) trapped) * 15000.0;
            }
        }

        // Заборы соперника
        var opp_primes = analyze_primes_info (board, opponent_color, color);
        for (var i = 0; i < opp_primes.length; i++) {
            var prime = opp_primes[i];
            var trapped = prime.trapped_checkers;
            if (prime.length == 3) score -= 8000.0;
            else if (prime.length == 4) score -= 30000.0;
            else if (prime.length == 5) score -= 90000.0;
            else if (prime.length >= 6) score -= 280000.0;

            if (prime.length >= 6 && trapped >= 1) {
                score -= 1200000.0 + ((double) trapped) * 80000.0;
            } else if (prime.length == 5 && trapped >= 1) {
                score -= ((double) trapped) * 15000.0;
            }
        }

        // 6b. Блокада отстающих фишек соперника
        int opp_trailing_idx = -1;
        for (var i = 0; i < opp_route.length; i++) {
            var s = board.stack_at (opp_route[i]);
            if (s != null && s.color == opponent_color) {
                opp_trailing_idx = i;
                break;
            }
        }

        for (var opp_idx = 1; opp_idx < 18; opp_idx++) {
            var opp_point = opp_route[opp_idx];
            var opp_stack = board.stack_at (opp_point);
            if (opp_stack == null || opp_stack.color != opponent_color) continue;

            for (var step = 1; step <= 3; step++) {
                var block_idx = opp_idx + step;
                if (block_idx >= opp_route.length) break;
                var block_point = opp_route[block_idx];
                var s = board.stack_at (block_point);
                if (s != null && s.color == color) {
                    var our_block_idx = index_of_point (our_route, block_point);
                    if (head_count == 0 && our_block_idx <= 6) {
                        continue;
                    }

                    var block_bonus = 40000.0 * ((double) opp_stack.checker_ids.length);
                    if (opp_idx == opp_trailing_idx) {
                        block_bonus += 250000.0 * ((double) opp_stack.checker_ids.length);
                    }
                    if (opp_outside_home_checkers <= 3) {
                        block_bonus += 250000.0 * ((double) opp_stack.checker_ids.length);
                    }

                    if (block_idx > 0) {
                        var prev_s = board.stack_at (opp_route[block_idx - 1]);
                        if (prev_s != null && prev_s.color == color) {
                            block_bonus += 45000.0;
                        }
                    }
                    if (block_idx + 1 < opp_route.length) {
                        var next_s = board.stack_at (opp_route[block_idx + 1]);
                        if (next_s != null && next_s.color == color) {
                            block_bonus += 45000.0;
                        }
                    }

                    score += block_bonus;
                }
            }
        }

        // 7. Контроль хвоста и предотвращение глухой блокады
        var has_endangered_checkers = false;
        var tail_danger_penalty = 0.0;

        for (var idx = 0; idx < 18; idx++) {
            var point = our_route[idx];
            var stack = board.stack_at (point);
            if (stack == null || stack.color != color) continue;

            var count_multiplier = (double) stack.checker_ids.length;
            var max_steps = int.min (6, our_route.length - 1 - idx);
            if (max_steps <= 0) continue;

            var max_consecutive_blocked = 0;
            var current_consecutive = 0;
            for (var step = 1; step <= max_steps; step++) {
                var target_point = our_route[idx + step];
                var s = board.stack_at (target_point);
                if (s != null && s.color == opponent_color) {
                    current_consecutive++;
                    if (current_consecutive > max_consecutive_blocked) {
                        max_consecutive_blocked = current_consecutive;
                    }
                } else {
                    current_consecutive = 0;
                }
            }

            var can_leap_over_with_six = false;
            if (max_steps == 6) {
                var leap_point = our_route[idx + 6];
                var s = board.stack_at (leap_point);
                can_leap_over_with_six = (s == null || s.color == color);
            }

            if (max_consecutive_blocked >= 3) {
                has_endangered_checkers = true;
                var danger = 0.0;
                if (max_consecutive_blocked == 6) {
                    danger = 2000000.0 * count_multiplier;
                } else if (max_consecutive_blocked == 5) {
                    danger = (!can_leap_over_with_six ? 800000.0 : 250000.0) * count_multiplier;
                } else if (max_consecutive_blocked == 4) {
                    danger = (!can_leap_over_with_six ? 180000.0 : 45000.0) * count_multiplier;
                } else if (max_consecutive_blocked == 3) {
                    danger = 120000.0 * count_multiplier;
                }

                var danger_scale = 1.0;
                if (opp_borne_off > 0) {
                    danger_scale = 0.0;
                } else if (opp_outside_home_checkers <= 3) {
                    danger_scale = 0.05;
                } else if (idx <= 2) {
                    danger_scale = 0.15;
                } else if (idx >= 12 && can_leap_over_with_six) {
                    danger_scale = 0.15;
                }

                if (max_steps >= 1) {
                    var next_point = our_route[idx + 1];
                    var s = board.stack_at (next_point);
                    if (s != null && s.color == color && s.checker_ids.length >= 2) {
                        danger_scale *= 0.1;
                    }
                }

                tail_danger_penalty += danger * danger_scale;
            }
        }

        if (head_count == 0 && tail_idx >= 0) {
            var tail_point = our_route[tail_idx];
            var tail_is_jailer = active_prime_points[tail_point.raw_value ()];

            if (tail_idx < 12 && !tail_is_jailer) {
                var lag_dist = 12 - tail_idx;
                tail_danger_penalty += ((double) lag_dist) * 160000.0;

                for (var idx = tail_idx; idx < 12; idx++) {
                    var pt = our_route[idx];
                    if (active_prime_points[pt.raw_value ()]) continue;
                    var stack = board.stack_at (pt);
                    if (stack != null && stack.color == color) {
                        var extra_count = (idx == tail_idx) ? (stack.checker_ids.length - 1) : stack.checker_ids.length;
                        if (extra_count > 0) {
                            tail_danger_penalty += ((double) (12 - idx)) * 80000.0 * ((double) extra_count);
                        }
                    }
                }

                var next_checker_idx = 24;
                for (var idx = tail_idx + 1; idx < our_route.length; idx++) {
                    var s = board.stack_at (our_route[idx]);
                    if (s != null && s.color == color) {
                        next_checker_idx = idx;
                        break;
                    }
                }
                var gap = next_checker_idx - tail_idx;
                if (gap >= 4) {
                    tail_danger_penalty += ((double) (gap - 3)) * 60000.0;
                }
            } else if (tail_idx < 12 && tail_is_jailer) {
                for (var idx = tail_idx; idx < 12; idx++) {
                    var pt = our_route[idx];
                    if (active_prime_points[pt.raw_value ()]) continue;
                    var stack = board.stack_at (pt);
                    if (stack != null && stack.color == color) {
                        tail_danger_penalty += ((double) (12 - idx)) * 80000.0 * ((double) stack.checker_ids.length);
                    }
                }
            }
            if (tail_idx < 6 && !tail_is_jailer) {
                tail_danger_penalty += ((double) (6 - tail_idx)) * 120000.0;
            }
        }

        score -= tail_danger_penalty;

        // 8. Подсчет параметров дома
        var checkers_in_home = 0;
        var occupied_home_points = 0;
        for (var raw = 1; raw <= 24; raw++) {
            var pt = (BoardPoint) raw;
            if (is_home_point_for (pt, color)) {
                var stack = board.stack_at (pt);
                if (stack != null && stack.color == color) {
                    checkers_in_home += stack.checker_ids.length;
                    occupied_home_points++;
                }
            }
        }

        var outside_home_checkers = 15 - our_borne_off - checkers_in_home;
        var is_home_rush = (opp_borne_off > 0 || opp_outside_home_checkers <= 6 || checkers_in_home >= 8);

        // Качество структуры армии (анкоры vs башни)
        var occupied_points_count = 0;
        var anchors_count = 0;
        for (var raw = 1; raw <= 24; raw++) {
            var pt = (BoardPoint) raw;
            var stack = board.stack_at (pt);
            if (stack == null || stack.color != color) continue;
            occupied_points_count++;
            var is_in_home = is_home_point_for (pt, color);
            var tower_scale = (is_in_home && outside_home_checkers > 0) ? 0.05 : 1.0;
            var cnt = stack.checker_ids.length;
            if (cnt == 2) {
                anchors_count++;
                score += 25000.0;
            } else if (cnt == 3) {
                score += 15000.0;
            } else if (cnt == 4) {
                score -= 8000.0 * tower_scale;
            } else if (cnt == 5) {
                score -= 25000.0 * tower_scale;
            } else if (cnt == 6) {
                score -= 70000.0 * tower_scale;
            } else if (cnt == 7) {
                score -= 350000.0 * tower_scale;
            } else if (cnt >= 8) {
                score -= (800000.0 + ((double) (cnt - 8)) * 300000.0) * tower_scale;
            }
        }

        if (!is_home_rush || outside_home_checkers == 0) {
            score += ((double) (occupied_points_count * occupied_points_count)) * 800.0;
        }

        // 9. Фаза дома
        if (outside_home_checkers == 0) {
            score += 1500000.0;
            if (our_borne_off == 0) {
                score += ((double) occupied_home_points) * 15000.0;
            }
        } else {
            if (is_home_rush) {
                score -= ((double) outside_home_checkers) * 80000.0;
                score += ((double) checkers_in_home) * 35000.0;
            } else if (has_endangered_checkers || tail_idx < 12) {
                score += ((double) checkers_in_home) * 20000.0;
            } else {
                var home_urgency = (head_count <= 4) ? 1.2 : ((head_count <= 8) ? 0.7 : 0.1);
                score += ((double) checkers_in_home) * 8000.0 * home_urgency;
            }
        }

        // 9b. Подтягивание внешних фишек в дом
        var outside_checkers_distance_penalty = 0.0;
        if (outside_home_checkers > 0) {
            var c_near = is_home_rush ? 140000.0 : 45000.0;
            var c_far = is_home_rush ? 140000.0 : 70000.0;

            for (var idx = 0; idx < 18; idx++) {
                var point = our_route[idx];
                var stack = board.stack_at (point);
                if (stack != null && stack.color == color) {
                    var dist_to_home = 18 - idx;
                    double dist_penalty;
                    if (dist_to_home <= 6) {
                        dist_penalty = ((double) dist_to_home) * c_near;
                    } else {
                        dist_penalty = 6.0 * c_near + ((double) (dist_to_home - 6)) * c_far;
                    }
                    outside_checkers_distance_penalty += ((double) stack.checker_ids.length) * dist_penalty;
                }
            }
            score -= outside_checkers_distance_penalty;
        }

        // 9c. Штраф за преждевременную глубокую упаковку
        if (head_count == 0) {
            var checkers_lagging_in_first_half = 0;
            for (var idx = 0; idx < 12; idx++) {
                var point = our_route[idx];
                if (active_prime_points[point.raw_value ()]) continue;
                var stack = board.stack_at (point);
                if (stack != null && stack.color == color) {
                    checkers_lagging_in_first_half += stack.checker_ids.length;
                }
            }
            if (checkers_lagging_in_first_half > 0) {
                var deep_home_checkers = 0;
                for (var idx = 21; idx < 24; idx++) {
                    var point = our_route[idx];
                    var stack = board.stack_at (point);
                    if (stack != null && stack.color == color) {
                        deep_home_checkers += stack.checker_ids.length;
                    }
                }
                if (deep_home_checkers > 0) {
                    score -= ((double) deep_home_checkers) * 35000.0;
                }
            }
        }

        // 9d. Стратегия при активном глухом запирании соперника
        if (has_active_primes) {
            score += ((double) checkers_in_home) * 350000.0;

            for (var idx = 12; idx <= 17; idx++) {
                var point = our_route[idx];
                var stack = board.stack_at (point);
                if (stack != null && stack.color == color) {
                    score += ((double) (idx - 11)) * 30000.0 * ((double) stack.checker_ids.length);
                }
            }

            for (var idx = 11; idx <= 12; idx++) {
                var point = our_route[idx];
                var stack = board.stack_at (point);
                if (stack != null && stack.color == color) {
                    score += 90000.0 * ((double) stack.checker_ids.length);
                }
            }
        }

        return score;
    }

    // MARK: - Вспомогательные функции

    public static int calculate_pip_count (GameBoard board, CheckerColor color) {
        var route = PlayerPath.path (color);
        var total = 0;
        for (var index = 0; index < route.length; index++) {
            var stack = board.stack_at (route[index]);
            if (stack != null && stack.color == color) {
                total += stack.checker_ids.length * (route.length - index);
            }
        }
        return total;
    }

    private static int count_checkers_before (int index, BoardPoint[] route, GameBoard board, CheckerColor color) {
        var count = 0;
        for (var i = 0; i < index; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == color) {
                count += stack.checker_ids.length;
            }
        }
        return count;
    }

    public static PrimeInfo[] analyze_primes_info (GameBoard board, CheckerColor friendly_color, CheckerColor target_route_color) {
        var route = PlayerPath.path (target_route_color);
        var primes = new GenericArray<PrimeInfo> ();
        var current_len = 0;
        var prime_start_idx = 0;
        var current_points = new bool[25];

        for (var idx = 0; idx < route.length; idx++) {
            var pt = route[idx];
            var stack = board.stack_at (pt);
            if (stack != null && stack.color == friendly_color) {
                if (current_len == 0) prime_start_idx = idx;
                current_len++;
                current_points[pt.raw_value ()] = true;
            } else {
                if (current_len >= 2) {
                    var trapped = count_checkers_before (prime_start_idx, route, board, target_route_color);
                    if (trapped > 0) {
                        primes.add (new PrimeInfo (current_len, prime_start_idx, trapped, copy_bool_arr (current_points)));
                    }
                }
                current_len = 0;
                current_points = new bool[25];
            }
        }

        if (current_len >= 2) {
            var trapped = count_checkers_before (prime_start_idx, route, board, target_route_color);
            if (trapped > 0) {
                primes.add (new PrimeInfo (current_len, prime_start_idx, trapped, copy_bool_arr (current_points)));
            }
        }

        var result = new PrimeInfo[primes.length];
        for (var i = 0; i < primes.length; i++) {
            result[i] = primes[i];
        }
        return result;
    }

    private static bool[] copy_bool_arr (bool[] src) {
        var r = new bool[src.length];
        for (var i = 0; i < src.length; i++) {
            r[i] = src[i];
        }
        return r;
    }

    private static int index_of_point (BoardPoint[] route, BoardPoint point) {
        for (var i = 0; i < route.length; i++) {
            if (route[i] == point) return i;
        }
        return -1;
    }

    public static int[] remaining_dice_after (MoveOption move, int[] dice) {
        var sorted = new int[move.die_indices.length];
        for (var i = 0; i < move.die_indices.length; i++) {
            sorted[i] = move.die_indices[i];
        }
        for (var i = 0; i < sorted.length - 1; i++) {
            for (var j = i + 1; j < sorted.length; j++) {
                if (sorted[i] < sorted[j]) {
                    var tmp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = tmp;
                }
            }
        }
        var list = new GenericArray<int> ();
        for (var i = 0; i < dice.length; i++) {
            list.add (dice[i]);
        }
        for (var i = 0; i < sorted.length; i++) {
            var idx = sorted[i];
            if (idx >= 0 && idx < list.length) {
                list.remove_index (idx);
            }
        }
        var result = new int[list.length];
        for (var i = 0; i < list.length; i++) {
            result[i] = list[i];
        }
        return result;
    }

    private static bool is_game_first_turn (GameBoard board, CheckerColor color) {
        var head_point = PlayerPath.start_point (color);
        var stack = board.stack_at (head_point);
        var head_count = (stack != null && stack.color == color) ? stack.checker_ids.length : 0;
        return head_count == 15;
    }

    private static bool is_home_point_for (BoardPoint point, CheckerColor color) {
        var raw = point.raw_value ();
        if (color == CheckerColor.WHITE) {
            return raw >= 1 && raw <= 6;
        } else {
            return raw >= 13 && raw <= 18;
        }
    }
}

} /* namespace Longbackgammon */
