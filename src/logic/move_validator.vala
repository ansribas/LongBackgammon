/* move_validator.vala
 *
 * Движок валидации ходов для Длинных нард:
 * - предикаты блокировки и «головы»
 * - проверка запрещённых блоков (prime)
 * - генерация всех легальных опций хода
 * - правила выноса за борт
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class MoveValidator {

    /** Занята ли ячейка хотя бы одной фишкой соперника. */
    public static bool is_blocked (BoardPoint point, GameBoard board, CheckerColor color) {
        var stack = board.stack_at (point);
        return stack != null && stack.color != color;
    }

    /** Является ли точка «головой» игрока. */
    public static bool is_head (BoardPoint point, CheckerColor color) {
        return point == PlayerPath.start_point (color);
    }

    /** Можно ли пройти на точку на расстоянии `steps` (промежуточная остановка). */
    public static bool can_pass_through (BoardPoint from, int steps, GameBoard board, CheckerColor color) {
        var intermediate = PlayerPath.point_from (from, steps, color);
        if (intermediate == null) {
            return false;
        }
        return !is_blocked (intermediate, board, color)
               && !creates_illegal_prime (from, intermediate, board, color);
    }

    /** Запрещённое запирание (prime): непрерывный блок из 6 фишек, за которым нет фишек соперника. */
    public static bool creates_illegal_prime (BoardPoint from, BoardPoint? to, GameBoard board, CheckerColor color) {
        if (to == null) {
            return false;
        }
        var temp_board = board.clone ();
        temp_board.move_one_checker (from, to);

        var opponent_color = color.opposite ();
        var opponent_route = PlayerPath.path (opponent_color);

        // Если соперник уже вывел хотя бы одну фишку, блокировка разрешена
        if (temp_board.borne_off_count (opponent_color) > 0) {
            return false;
        }

        var block_start = -1;
        var current_block_length = 0;

        for (var index = 0; index < opponent_route.length; index++) {
            var stack = temp_board.stack_at (opponent_route[index]);
            if (stack != null && stack.color == color) {
                if (block_start < 0) {
                    block_start = index;
                }
                current_block_length++;
            } else {
                if (block_start >= 0 && current_block_length >= 6) {
                    if (!has_opponent_checkers_ahead (index - 1, opponent_route, temp_board, opponent_color)) {
                        return true;
                    }
                }
                block_start = -1;
                current_block_length = 0;
            }
        }

        if (block_start >= 0 && current_block_length >= 6) {
            if (!has_opponent_checkers_ahead (opponent_route.length - 1, opponent_route, temp_board, opponent_color)) {
                return true;
            }
        }

        return false;
    }
/** Все ли фишки цвета находятся в «доме» (последние 6 пунктов маршрута). */
    public static bool are_all_checkers_in_home (GameBoard board, CheckerColor color) {
        var home = home_points (color);
        for (var raw = 1; raw <= 24; raw++) {
            if (!home[raw]) {
                var stack = board.stack_at ((BoardPoint) raw);
                if (stack != null && stack.color == color && stack.checker_ids.length > 0) {
                    return false;
                }
            }
        }
        return true;
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

    /**
     * Правило выноса за борт: все фишки в доме, а с пункта, соответствующего
     * кубику, можно выносить; если там пусто — выносим с ближайшего старшего.
     */
    private static bool communities_allow_bear_off (BoardPoint from, int die, GameBoard board, CheckerColor color) {
        if (!are_all_checkers_in_home (board, color)) {
            return false;
        }

        int point_home_number;
        if (color == CheckerColor.WHITE) {
            if (from.raw_value () > 6) {
                return false;
            }
            point_home_number = from.raw_value ();
        } else {
            if (from.raw_value () < 13 || from.raw_value () > 18) {
                return false;
            }
            point_home_number = from.raw_value () - 12;
        }

        if (point_home_number == die) {
            return true;
        }

        if (die > point_home_number) {
            for (var check = point_home_number + 1; check <= 6; check++) {
                var check_point = (color == CheckerColor.WHITE)
                    ? (BoardPoint) check
                    : (BoardPoint) (check + 12);
                var stack = board.stack_at (check_point);
                if (stack != null && stack.color == color && stack.checker_ids.length > 0) {
                    return false;
                }
            }
            return true;
        }

        return false;
    }

    private static bool has_opponent_checkers_ahead (int after_index, BoardPoint[] route, GameBoard board, CheckerColor opponent_color) {
        for (var i = after_index + 1; i < route.length; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == opponent_color) {
                return true;
            }
        }
        return false;
    }
    /** Рассчитывает целевую точку назначения фишки при ходе на значение одного кубика с проверкой правила головы. */
    public static BoardPoint? destination (
        BoardPoint from, int die, GameBoard board, CheckerColor color,
        int checkers_moved_from_head_this_turn, bool is_double, bool is_first_turn_of_game) {
        if (die <= 0) {
            return null;
        }
        var stack = board.stack_at (from);
        if (stack == null || stack.color != color || stack.checker_ids.length == 0) {
            return null;
        }
        if (is_head (from, color)) {
            var max_allowed = 1;
            if (is_double && is_first_turn_of_game && (die == 3 || die == 4 || die == 6)) {
                max_allowed = 2;
            }
            if (checkers_moved_from_head_this_turn >= max_allowed) {
                return null;
            }
        }
        var to = PlayerPath.point_from (from, die, color);
        if (to == null || is_blocked (to, board, color)) {
            return null;
        }
        return to;
    }

    private static bool has_option (MoveOption[] options, BoardPoint from, BoardPoint? to, int die, bool check_die) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].from == from && options[i].to == to && (!check_die || options[i].die == die)) {
                return true;
            }
        }
        return false;
    }

    /** Формирует список всех доступных вариантов ходов фишки из указанной точки с учётом оставшихся кубиков. */
    public static MoveOption[] moves (
        BoardPoint from,
        GameBoard board,
        CheckerColor color,
        int[] remaining_dice,
        int checkers_moved_from_head_this_turn,
        bool is_double,
        bool is_first_turn_of_game) {

        var options = new MoveOption[0];
        var stack = board.stack_at (from);
        if (stack == null || stack.color != color || stack.checker_ids.length == 0 || remaining_dice.length == 0) {
            return options;
        }

        var head_die_value = remaining_dice[0];
        var max_allowed_from_head = 1;
        if (is_double && is_first_turn_of_game && (head_die_value == 3 || head_die_value == 4 || head_die_value == 6)) {
            max_allowed_from_head = 2;
        }
        var can_move_from_head = checkers_moved_from_head_this_turn < max_allowed_from_head;

        // 1. Одиночные ходы
        for (var i = 0; i < remaining_dice.length; i++) {
            var die = remaining_dice[i];
            var to = destination (from, die, board, color, checkers_moved_from_head_this_turn, is_double, is_first_turn_of_game);
            if (to != null) {
                var option = new MoveOption (from, to, die, new int[] { i }, false);
                if (creates_illegal_prime (from, to, board, color)) {
                    option.is_illegal_prime = true;
                }
                options += option;
            }
            if (communities_allow_bear_off (from, die, board, color)) {
                options += new MoveOption (from, null, die, new int[] { i }, false);
            }
        }

        // 2. Составные ходы (за 2 и более кубиков)
        if (remaining_dice.length < 2) {
            return options;
        }

        if (is_double) {
            var die_value = remaining_dice[0];
            var current_steps = die_value;
            var used = new int[] { 0 };
            var all_clear = true;
            for (var k = 2; k <= remaining_dice.length; k++) {
                if (all_clear && can_pass_through (from, current_steps, board, color)) {
                    var mid = PlayerPath.point_from (from, current_steps, color);
                    if (mid != null) {
                        var head_move_used = is_head (from, color);
                        if (!head_move_used || can_move_from_head) {
                            var to_point = PlayerPath.point_from (mid, die_value, color);
                            if (to_point != null && !is_blocked (to_point, board, color)) {
                                used += (k - 1);
                                var option = new MoveOption (from, to_point, die_value * k, copy_ints (used), true);
                                if (creates_illegal_prime (from, to_point, board, color)) {
                                    option.is_illegal_prime = true;
                                }
                                options += option;
                            } else {
                                var temp_board = board.clone ();
                                temp_board.move_one_checker (from, mid);
                                if (communities_allow_bear_off (mid, die_value, temp_board, color)) {
                                    used += (k - 1);
                                    options += new MoveOption (from, null, die_value * k, copy_ints (used), true);
                                }
                            }
                        }
                    }
                } else {
                    all_clear = false;
                }
                current_steps += die_value;
            }
        } else {
            var die1 = remaining_dice[0];
            var die2 = remaining_dice[1];
            var allow_combined_from_head = !is_head (from, color) || can_move_from_head;

            if (allow_combined_from_head && can_pass_through (from, die1, board, color)) {
                var mid = PlayerPath.point_from (from, die1, color);
                if (mid != null) {
                    var to_a = PlayerPath.point_from (mid, die2, color);
                    if (to_a != null && !is_blocked (to_a, board, color)) {
                        var option = new MoveOption (from, to_a, die1 + die2, new int[] { 0, 1 }, true);
                        if (creates_illegal_prime (from, to_a, board, color)) {
                            option.is_illegal_prime = true;
                        }
                        options += option;
                    } else {
                        var temp_board = board.clone ();
                        temp_board.move_one_checker (from, mid);
                        if (communities_allow_bear_off (mid, die2, temp_board, color)) {
                            options += new MoveOption (from, null, die1 + die2, new int[] { 0, 1 }, true);
                        }
                    }
                }
            }

            if (allow_combined_from_head && can_pass_through (from, die2, board, color)) {
                var mid = PlayerPath.point_from (from, die2, color);
                if (mid != null) {
                    var to_b = PlayerPath.point_from (mid, die1, color);
                    if (to_b != null && !is_blocked (to_b, board, color)) {
                        if (!has_option (options, from, to_b, 0, false)) {
                            var option = new MoveOption (from, to_b, die1 + die2, new int[] { 1, 0 }, true);
                            if (creates_illegal_prime (from, to_b, board, color)) {
                                option.is_illegal_prime = true;
                            }
                            options += option;
                        }
                    } else {
                        var temp_board = board.clone ();
                        temp_board.move_one_checker (from, mid);
                        if (communities_allow_bear_off (mid, die1, temp_board, color)) {
                            if (!has_option (options, from, null, die1 + die2, true)) {
                                options += new MoveOption (from, null, die1 + die2, new int[] { 1, 0 }, true);
                            }
                        }
                    }
                }
            }
        }

        return options;
    }

    private static int[] copy_ints (int[] src) {
        var r = new int[src.length];
        for (var i = 0; i < src.length; i++) {
            r[i] = src[i];
        }
        return r;
    }

    /** Все опции хода со всех занятых точек. */
    public static MoveOption[] all_moves (
        GameBoard board,
        CheckerColor color,
        int[] remaining_dice,
        int checkers_moved_from_head_this_turn,
        bool is_double,
        bool is_first_turn_of_game) {

        var result = new MoveOption[0];
        var points = board.occupied_points ();
        for (var p = 0; p < points.length; p++) {
            var point = points[p];
            var stack = board.stack_at (point);
            if (stack == null || stack.color != color) {
                continue;
            }
            var opts = moves (
                point, board, color, remaining_dice,
                checkers_moved_from_head_this_turn, is_double, is_first_turn_of_game);
            for (var o = 0; o < opts.length; o++) {
                result += opts[o];
            }
        }
        return result;
    }

    /**
     * Правило принудительного одиночного кубика:
     * если можно использовать только один из двух кубиков,
     * его и нужно использовать (больший).
     */
    public static MoveOption[] filter_forced_single_die (MoveOption[] options) {
        var single_moves = new MoveOption[0];
        for (var i = 0; i < options.length; i++) {
            if (!options[i].is_combined) {
                single_moves += options[i];
            }
        }
        if (single_moves.length == 0) {
            return options;
        }

        // Собираем индексы использованных кубиков в одиночных ходах
        var playable_indices = new bool[6];
        for (var i = 0; i < single_moves.length; i++) {
            for (var k = 0; k < single_moves[i].die_indices.length; k++) {
                var idx = single_moves[i].die_indices[k];
                if (idx < playable_indices.length) {
                    playable_indices[idx] = true;
                }
            }
        }
        var used_count = 0;
        for (var k = 0; k < playable_indices.length; k++) {
            if (playable_indices[k]) {
                used_count++;
            }
        }
        if (used_count != 1) {
            return options;
        }

        // Индекс единственного играемого кубика
        var playable_index = -1;
        for (var k = 0; k < playable_indices.length; k++) {
            if (playable_indices[k]) {
                playable_index = k;
                break;
            }
        }
        if (playable_index < 0) {
            return options;
        }

        var max_die = 0;
        for (var i = 0; i < single_moves.length; i++) {
            bool uses_playable = false;
            for (var k = 0; k < single_moves[i].die_indices.length; k++) {
                if (single_moves[i].die_indices[k] == playable_index) {
                    uses_playable = true;
                    break;
                }
            }
            if (uses_playable && single_moves[i].die > max_die) {
                max_die = single_moves[i].die;
            }
        }

        var result = new MoveOption[0];
        for (var i = 0; i < options.length; i++) {
            if (options[i].die == max_die || options[i].is_combined) {
                result += options[i];
            }
        }
        return result;
    }

    /**
     * Фильтрует варианты по полным правилам использования кубиков.
     * При двух разных кубиках сначала оставляет ходы, после которых можно
     * использовать второй кубик; если это невозможно, требует старший.
     */
    public static MoveOption[] filter_legal_moves (
        MoveOption[] options,
        GameBoard board,
        CheckerColor color,
        int[] remaining_dice,
        int checkers_moved_from_head_this_turn,
        bool is_double,
        bool is_first_turn_of_game
    ) {
        var playable = new MoveOption[0];
        foreach (var option in options) {
            if (!option.is_illegal_prime) playable += option;
        }

        if (remaining_dice.length != 2 || is_double) {
            return filter_forced_single_die (playable);
        }
        if (playable.length == 0) return playable;

        // A combined move consumes both dice in a single checker movement.
        foreach (var option in playable) {
            if (option.is_combined) return playable;
        }

        var can_play_both = new MoveOption[0];
        var can_play_one = new MoveOption[0];
        foreach (var option in playable) {
            if (option.die_indices.length == 0 || option.die_indices[0] >= remaining_dice.length) {
                continue;
            }
            var temp_board = board.clone ();
            temp_board.move_one_checker (option.from, option.to);

            var next_dice = new int[remaining_dice.length - 1];
            var removed = false;
            var next_count = 0;
            for (var i = 0; i < remaining_dice.length; i++) {
                if (!removed && i == option.die_indices[0]) {
                    removed = true;
                    continue;
                }
                next_dice[next_count++] = remaining_dice[i];
            }

            var next_head_count = checkers_moved_from_head_this_turn
                + (is_head (option.from, color) ? 1 : 0);
            var follow_up = all_moves (temp_board, color, next_dice, next_head_count, false, is_first_turn_of_game);
            var has_follow_up = false;
            foreach (var next in follow_up) {
                if (!next.is_illegal_prime) {
                    has_follow_up = true;
                    break;
                }
            }
            if (has_follow_up) can_play_both += option;
            else can_play_one += option;
        }

        if (can_play_both.length > 0) return can_play_both;

        var max_die = 0;
        foreach (var option in can_play_one) max_die = int.max (max_die, option.die);
        var result = new MoveOption[0];
        foreach (var option in can_play_one) {
            if (option.die == max_die) result += option;
        }
        return result;
    }
}

} /* namespace Longbackgammon */
