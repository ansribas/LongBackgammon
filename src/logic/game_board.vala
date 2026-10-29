/* game_board.vala
 *
 * Структура, управляющая текущим состоянием игральной доски.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Управляет состоянием доски: стопки фишек и вынесенные за борт. */
public class GameBoard : Object {
    /** Стопки: индекс 0 не используется, индекс 1…24 соответствует ячейке P1…P24. */
    public PointStack?[] stacks;
    public uint8[] white_borne_off_ids;
    public uint8[] black_borne_off_ids;

    public GameBoard () {
        stacks = new PointStack?[25];
        white_borne_off_ids = new uint8[0];
        black_borne_off_ids = new uint8[0];
    }

    /** Доска в стартовом состоянии для Длинных нард: по 15 фишек на «головах». */
    public static GameBoard initial_long () {
        var board = new GameBoard ();
        board.stacks[PlayerPath.start_point (CheckerColor.WHITE).raw_value ()] =
            new PointStack.with_count (CheckerColor.WHITE, 15);
        board.stacks[PlayerPath.start_point (CheckerColor.BLACK).raw_value ()] =
            new PointStack.with_count (CheckerColor.BLACK, 15);
        return board;
    }

    /** Состояние inTray (все фишки в накопителях перед анимацией расстановки). */
    public static GameBoard in_tray () {
        var board = new GameBoard ();
        var w = new uint8[15];
        for (var i = 0; i < 15; i++) {
            w[i] = (uint8) (14 - i);
        }
        board.white_borne_off_ids = w;

        var blk = new uint8[15];
        for (var i = 0; i < 15; i++) {
            blk[i] = (uint8) (29 - i);
        }
        board.black_borne_off_ids = blk;
        return board;
    }

    /** Проверяет, находятся ли все фишки в накопителях (состояние inTray перед анимацией). */
    public bool is_in_tray () {
        if (white_borne_off_ids.length != 15 || black_borne_off_ids.length != 15) {
            return false;
        }
        for (var raw = 1; raw <= 24; raw++) {
            if (stacks[raw] != null && stacks[raw].checker_ids.length > 0) {
                return false;
            }
        }
        return true;
    }

    private class BoardSlot : Object {
        public BoardPoint point;
        public int stack_index;
        public uint8 old_id;
        public CheckerColor color;
        public BoardSlot (BoardPoint point, int stack_index, uint8 old_id, CheckerColor color) {
            this.point = point;
            this.stack_index = stack_index;
            this.old_id = old_id;
            this.color = color;
        }
    }

    private static int path_index_of (BoardPoint[] p, BoardPoint pt) {
        for (var i = 0; i < p.length; i++) {
            if (p[i] == pt) return i;
        }
        return pt.raw_value ();
    }

    /**
     * Возвращает доску с канонически упорядоченными ID фишек (0..<15 для белых, 15..<30 для чёрных),
     * согласованными с порядком извлечения из накопителя сверху вниз.
     */
    public GameBoard normalized_for_placement_from_tray () {
        BoardSlot[] white_slots = new BoardSlot[0];
        BoardSlot[] black_slots = new BoardSlot[0];

        for (var raw = 1; raw <= 24; raw++) {
            var st = stacks[raw];
            if (st != null) {
                var pt = BoardPoint.from_raw (raw);
                for (var idx = 0; idx < st.checker_ids.length; idx++) {
                    var slot = new BoardSlot (pt, idx, st.checker_ids[idx], st.color);
                    if (st.color == CheckerColor.WHITE) {
                        white_slots += slot;
                    } else {
                        black_slots += slot;
                    }
                }
            }
        }

        var w_path = PlayerPath.white ();
        var b_path = PlayerPath.black ();

        for (var i = 0; i < white_slots.length - 1; i++) {
            for (var j = i + 1; j < white_slots.length; j++) {
                var a = white_slots[i];
                var b = white_slots[j];
                bool swap = false;
                if (a.stack_index != b.stack_index) {
                    swap = (a.stack_index > b.stack_index);
                } else {
                    var a_idx = path_index_of (w_path, a.point);
                    var b_idx = path_index_of (w_path, b.point);
                    swap = (a_idx > b_idx);
                }
                if (swap) {
                    white_slots[i] = b;
                    white_slots[j] = a;
                }
            }
        }

        for (var i = 0; i < black_slots.length - 1; i++) {
            for (var j = i + 1; j < black_slots.length; j++) {
                var a = black_slots[i];
                var b = black_slots[j];
                bool swap = false;
                if (a.stack_index != b.stack_index) {
                    swap = (a.stack_index > b.stack_index);
                } else {
                    var a_idx = path_index_of (b_path, a.point);
                    var b_idx = path_index_of (b_path, b.point);
                    swap = (a_idx > b_idx);
                }
                if (swap) {
                    black_slots[i] = b;
                    black_slots[j] = a;
                }
            }
        }

        var new_board = new GameBoard ();

        for (var i = 0; i < white_slots.length; i++) {
            var slot = white_slots[i];
            var new_id = (uint8) i;
            new_board.place_checker (new_id, CheckerColor.WHITE, slot.point, slot.stack_index);
        }

        for (var i = 0; i < black_slots.length; i++) {
            var slot = black_slots[i];
            var new_id = (uint8) (15 + i);
            new_board.place_checker (new_id, CheckerColor.BLACK, slot.point, slot.stack_index);
        }

        var w_count = white_slots.length;
        var b_count = black_slots.length;

        var rem_w = new uint8[15 - w_count];
        for (var i = 0; i < 15 - w_count; i++) {
            rem_w[i] = (uint8) (14 - i);
        }
        new_board.white_borne_off_ids = rem_w;

        var rem_b = new uint8[15 - b_count];
        for (var i = 0; i < 15 - b_count; i++) {
            rem_b[i] = (uint8) (29 - i);
        }
        new_board.black_borne_off_ids = rem_b;

        return new_board;
    }

    /** Количество выброшенных за борт фишек для цвета. */
    public int borne_off_count (CheckerColor color) {
        return (color == CheckerColor.WHITE) ? white_borne_off_ids.length : black_borne_off_ids.length;
    }

    /** Победитель — игрок, вынесший все 15 фишек (не в состоянии inTray). */
    public bool is_winner (CheckerColor color) {
        if (white_borne_off_ids.length >= 15 && black_borne_off_ids.length >= 15) {
            return false;
        }
        return borne_off_count (color) >= 15;
    }

    /** Классифицирует победу против проигравшего игрока (Оин, Марс, Домашний марс). */
    public VictoryType victory_type (CheckerColor loser_color) {
        var is_home_mars = borne_off_count (loser_color) == 0 && MoveValidator.are_all_checkers_in_home (this, loser_color);
        var is_mars = borne_off_count (loser_color) == 0 && !is_home_mars;
        return is_home_mars ? VictoryType.HOME_MARS : (is_mars ? VictoryType.MARS : VictoryType.OIN);
    }

    /** Перемещает фишку с конкретным ID в целевую позицию (для последовательной расстановки). */
    public void place_checker (uint8 id, CheckerColor color, BoardPoint? point, int index) {
        var w_list = new GenericArray<uint8> ();
        for (var i = 0; i < white_borne_off_ids.length; i++) {
            if (white_borne_off_ids[i] != id) w_list.add (white_borne_off_ids[i]);
        }
        white_borne_off_ids = new uint8[w_list.length];
        for (var i = 0; i < w_list.length; i++) white_borne_off_ids[i] = w_list[i];

        var b_list = new GenericArray<uint8> ();
        for (var i = 0; i < black_borne_off_ids.length; i++) {
            if (black_borne_off_ids[i] != id) b_list.add (black_borne_off_ids[i]);
        }
        black_borne_off_ids = new uint8[b_list.length];
        for (var i = 0; i < b_list.length; i++) black_borne_off_ids[i] = b_list[i];

        for (var raw = 1; raw <= 24; raw++) {
            var st = stacks[raw];
            if (st != null) {
                var found_idx = -1;
                for (var i = 0; i < st.checker_ids.length; i++) {
                    if (st.checker_ids[i] == id) {
                        found_idx = i;
                        break;
                    }
                }
                if (found_idx >= 0) {
                    var remaining = new uint8[st.checker_ids.length - 1];
                    var k = 0;
                    for (var i = 0; i < st.checker_ids.length; i++) {
                        if (i != found_idx) remaining[k++] = st.checker_ids[i];
                    }
                    if (remaining.length == 0) {
                        stacks[raw] = null;
                    } else {
                        stacks[raw] = new PointStack.with_ids (st.color, remaining);
                    }
                    break;
                }
            }
        }

        if (point != null) {
            var raw = point.raw_value ();
            var existing = stacks[raw];
            if (existing != null) {
                var already = false;
                for (var i = 0; i < existing.checker_ids.length; i++) {
                    if (existing.checker_ids[i] == id) { already = true; break; }
                }
                if (!already) {
                    var new_ids = new uint8[existing.checker_ids.length + 1];
                    for (var i = 0; i < existing.checker_ids.length; i++) new_ids[i] = existing.checker_ids[i];
                    new_ids[existing.checker_ids.length] = id;
                    stacks[raw] = new PointStack.with_ids (color, new_ids);
                }
            } else {
                stacks[raw] = new PointStack.with_ids (color, new uint8[] { id });
            }
        } else {
            if (color == CheckerColor.WHITE) {
                white_borne_off_ids = ArrUtil.append_u8 (white_borne_off_ids, id);
            } else {
                black_borne_off_ids = ArrUtil.append_u8 (black_borne_off_ids, id);
            }
        }
    }

    /** Безопасное получение стопки на ячейке (или null). */
    public PointStack? stack_at (BoardPoint point) {
        return stacks[point.raw_value ()];
    }

    /** ID верхней фишки в стопке (или null). */
    public uint8? top_checker_id_at (BoardPoint point) {
        var stack = stacks[point.raw_value ()];
        if (stack == null || stack.checker_ids.length == 0) {
            return null;
        }
        return stack.checker_ids[stack.checker_ids.length - 1];
    }

    /** Устанавливает стопку (для восстановления игры). */
    public void set_stack (BoardPoint point, CheckerColor color, uint8[] checker_ids) {
        stacks[point.raw_value ()] = new PointStack.with_ids (color, checker_ids);
    }

    /** Устанавливает массивы вынесенных фишек. */
    public void set_borne_off (uint8[] white, uint8[] black) {
        white_borne_off_ids = white;
        black_borne_off_ids = black;
    }

    /** Очищает все стопки. */
    public void clear_all_stacks () {
        stacks = new PointStack?[25];
        white_borne_off_ids = new uint8[0];
        black_borne_off_ids = new uint8[0];
    }

    /** Ячейки, на которых стоит хотя бы одна фишка. */
    public BoardPoint[] occupied_points () {
        var result = new BoardPoint[0];
        for (var raw = 1; raw <= 24; raw++) {
            if (stacks[raw] != null) {
                result += (BoardPoint) raw;
            }
        }
        return result;
    }

    /** Перемещает ровно одну (верхнюю) фишку; при to == null — выносит за борт. */
    public void move_one_checker (BoardPoint from, BoardPoint? to) {
        var source = stacks[from.raw_value ()];
        if (source == null || source.checker_ids.length == 0) {
            return;
        }
        var moving_id = source.checker_ids[source.checker_ids.length - 1];
        var rest = new uint8[source.checker_ids.length - 1];
        for (var i = 0; i < rest.length; i++) {
            rest[i] = source.checker_ids[i];
        }
        if (rest.length == 0) {
            stacks[from.raw_value ()] = null;
        } else {
            stacks[from.raw_value ()] = new PointStack.with_ids (source.color, rest);
        }

        if (to == null) {
            if (source.color == CheckerColor.WHITE) {
                white_borne_off_ids = ArrUtil.append_u8 (white_borne_off_ids, moving_id);
            } else {
                black_borne_off_ids = ArrUtil.append_u8 (black_borne_off_ids, moving_id);
            }
            return;
        }

        var target = stacks[to.raw_value ()];
        if (target != null && target.color == source.color) {
            var ids = new uint8[target.checker_ids.length + 1];
            for (var i = 0; i < target.checker_ids.length; i++) {
                ids[i] = target.checker_ids[i];
            }
            ids[ids.length - 1] = moving_id;
            stacks[to.raw_value ()] = new PointStack.with_ids (target.color, ids);
        } else {
            stacks[to.raw_value ()] = new PointStack.with_ids (source.color, new uint8[] { moving_id });
        }
    }

    /** Находит позицию фишки по ID (ячейку или вынос и индекс в стопке). */
    public bool find_checker_location (uint8 id, out BoardPoint? point, out int stack_index) {
        point = null;
        stack_index = -1;
        for (var raw = 1; raw <= 24; raw++) {
            var stack = stacks[raw];
            if (stack != null) {
                for (var i = 0; i < stack.checker_ids.length; i++) {
                    if (stack.checker_ids[i] == id) {
                        point = (BoardPoint) raw;
                        stack_index = i;
                        return true;
                    }
                }
            }
        }
        for (var i = 0; i < white_borne_off_ids.length; i++) {
            if (white_borne_off_ids[i] == id) {
                point = null;
                stack_index = i;
                return true;
            }
        }
        for (var i = 0; i < black_borne_off_ids.length; i++) {
            if (black_borne_off_ids[i] == id) {
                point = null;
                stack_index = i;
                return true;
            }
        }
        return false;
    }

    /** Хэш-сигнатура позиции для отсечения дубликатов в поиске ИИ. */
    public string position_signature () {
        var sb = new StringBuilder ();
        for (var raw = 1; raw <= 24; raw++) {
            var s = stacks[raw];
            if (s == null || s.checker_ids.length == 0) {
                sb.append_c ('.');
            } else {
                sb.append_c (s.color == CheckerColor.WHITE ? 'W' : 'B');
                sb.append_printf ("%d", s.checker_ids.length);
            }
            sb.append_c (',');
        }
        sb.append_printf ("w%d,b%d", white_borne_off_ids.length, black_borne_off_ids.length);
        return sb.str;
    }

    /** Быстрое точное сравнение расположения всех фишек на доске и в накопителях. */
    public bool equals_exact (GameBoard other) {
        if (white_borne_off_ids.length != other.white_borne_off_ids.length ||
            black_borne_off_ids.length != other.black_borne_off_ids.length) {
            return false;
        }
        for (var i = 0; i < white_borne_off_ids.length; i++) {
            if (white_borne_off_ids[i] != other.white_borne_off_ids[i]) {
                return false;
            }
        }
        for (var i = 0; i < black_borne_off_ids.length; i++) {
            if (black_borne_off_ids[i] != other.black_borne_off_ids[i]) {
                return false;
            }
        }
        for (var raw = 1; raw <= 24; raw++) {
            var s1 = stacks[raw];
            var s2 = other.stacks[raw];
            if (s1 == null && s2 == null) {
                continue;
            }
            if (s1 == null || s2 == null || s1.color != s2.color ||
                s1.checker_ids.length != s2.checker_ids.length) {
                return false;
            }
            for (var i = 0; i < s1.checker_ids.length; i++) {
                if (s1.checker_ids[i] != s2.checker_ids[i]) {
                    return false;
                }
            }
        }
        return true;
    }

    /** Глубокая копия доски (для ИИ и отмены ходов). */
    public GameBoard clone () {
        var copy = new GameBoard ();
        for (var raw = 1; raw <= 24; raw++) {
            var stack = stacks[raw];
            if (stack != null) {
                var ids = new uint8[stack.checker_ids.length];
                for (var i = 0; i < ids.length; i++) {
                    ids[i] = stack.checker_ids[i];
                }
                copy.stacks[raw] = new PointStack.with_ids (stack.color, ids);
            }
        }
        copy.set_borne_off (white_borne_off_ids, black_borne_off_ids);
        return copy;
    }
}

} /* namespace Longbackgammon */