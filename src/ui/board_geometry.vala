/* board_geometry.vala
 *
 * Геометрия игрового поля: координаты фишек на пунктах и в зонах выноса,
 * определение попадания (hit-testing) и математические функции интерполяции траекторий.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Позиция фишки для анимации (в долях стороны доски, чтобы не зависеть от размеров). */
public class CPoint {
    public double x;
    public double y;

    public CPoint (double x, double y) {
        this.x = x;
        this.y = y;
    }
}

/** Активное перемещение фишки (координаты в долях стороны доски). */
public class CMove {
    public double sx;
    public double sy;
    public double ex;
    public double ey;
    public double t0;
    public double duration;
    /** true — пружина (возврат после неудачного перетаскивания), false — easeInOut. */
    public bool spring;
    public double arc_scale;
    public bool is_top_half;
    public double scale;
    public double lift;
    public CheckerColor color;
    public bool is_drag_drop;
    public int stack_index;

    public CMove (double sx, double sy, double ex, double ey, double t0, double duration,
                  bool spring = false, double arc_scale = 0.0, bool is_top_half = false,
                  CheckerColor color = CheckerColor.WHITE, bool is_drag_drop = false,
                  int stack_index = 0) {
        this.sx = sx;
        this.sy = sy;
        this.ex = ex;
        this.ey = ey;
        this.t0 = t0;
        this.duration = duration;
        this.spring = spring;
        this.arc_scale = arc_scale;
        this.is_top_half = is_top_half;
        this.scale = is_drag_drop ? 1.08 : 1.0;
        this.lift = is_drag_drop ? 0.4 : 0.0;
        this.color = color;
        this.is_drag_drop = is_drag_drop;
        this.stack_index = stack_index;
    }
}

public class BoardGeometry {

    /** Позиция фишки index в стопке точки (пиксели доски). */
    public static void stack_position (BoardPoint point, int index, double side, out double x, out double y, BoardSide? side_option = null) {
        var diameter = BoardLayout.checker_diameter (side);
        BoardLayout.position (point, side, out x, out y, side_option);
        var dir = point.stack_direction_for (side_option ?? SettingsStore.shared ().board_side);
        y += BoardLayout.stack_offset (index, diameter, dir);
    }

    /** Целевые позиции всех фишек в долях стороны доски. */
    public static HashTable<uint8, CPoint> build_positions (GameBoard board, BoardSide? side_option = null) {
        var map = new HashTable<uint8, CPoint> (null, null);
        for (var raw = 1; raw <= 24; raw++) {
            var point = (BoardPoint) raw;
            var stack = board.stack_at (point);
            if (stack == null) {
                continue;
            }
            for (var i = 0; i < stack.checker_ids.length; i++) {
                double x, y;
                stack_position (point, i, 1.0, out x, out y, side_option);
                map.insert (stack.checker_ids[i], new CPoint (x, y));
            }
        }
        uint8[] wb = board.white_borne_off_ids;
        for (var i = 0; i < wb.length; i++) {
            double bx, by;
            BoardLayout.bear_off_position (CheckerColor.WHITE, i, 1.0, out bx, out by, side_option);
            map.insert (wb[i], new CPoint (bx, by));
        }
        uint8[] bb = board.black_borne_off_ids;
        for (var i = 0; i < bb.length; i++) {
            double bx, by;
            BoardLayout.bear_off_position (CheckerColor.BLACK, i, 1.0, out bx, out by, side_option);
            map.insert (bb[i], new CPoint (bx, by));
        }
        return map;
    }

    public static bool contains_point (BoardPoint[] arr, BoardPoint p) {
        foreach (var x in arr) {
            if (x == p) {
                return true;
            }
        }
        return false;
    }

    /** Зелёная мишень хода (верхний слой, zIndex 1000). */
    public static BoardPoint? green_target_at (GameSession session, double px, double py, double side) {
        if (session.selected_point == null || session.is_computer_turn) {
            return null;
        }
        var r = BoardLayout.checker_diameter (side) / 2.0;
        foreach (var t in session.target_points ()) {
            var stack = session.board.stack_at (t);
            var count = (stack == null) ? 0 : stack.checker_ids.length;
            double tx, ty;
            stack_position (t, count, side, out tx, out ty);
            if (Math.hypot (px - tx, py - ty) <= r) {
                return t;
            }
        }
        return null;
    }

    public static bool is_bear_off_available (GameSession session, CheckerColor color) {
        return session.current_player == color && session.can_bear_off_selected && !session.is_computer_turn;
    }

    /** Кнопки выноса: кружок на месте следующей фишки и капсула на весь столбец накопителя. */
    public static bool bear_off_area_hit (GameSession session, double px, double py, double side) {
        var color = session.current_player;
        if (!is_bear_off_available (session, color)) {
            return false;
        }
        var diameter = BoardLayout.checker_diameter (side);
        var count = session.board.borne_off_count (color);
        double nx, ny;
        BoardLayout.bear_off_position (color, count, side, out nx, out ny);
        if (Math.hypot (px - nx, py - ny) <= diameter / 2.0) {
            return true;
        }
        double sx, sy;
        BoardLayout.bear_off_position (color, 0, side, out sx, out sy);
        var cx = (sx + nx) / 2.0;
        var cy = (sy + ny) / 2.0;
        var spacing = diameter * 1.01;
        var h = count > 0 ? (count + 1) * spacing + diameter : diameter * 2;
        var w = diameter * 1.5;
        // Капсула: прямоугольник со скруглёнными концами радиуса w/2
        var dx = Math.fabs (px - cx);
        var dy = Math.fabs (py - cy);
        if (dx > w / 2.0 || dy > h / 2.0) {
            return false;
        }
        var straight = h / 2.0 - w / 2.0;
        if (dy <= straight) {
            return true;
        }
        return Math.hypot (dx, dy - straight) <= w / 2.0;
    }

    /** Фишка под курсором (верхняя по z: больший индекс в стопке рисуется выше). */
    public static BoardPoint? checker_at (GameSession session, double px, double py, double side, out int index) {
        var r = BoardLayout.checker_diameter (side) / 2.0;
        BoardPoint? best = null;
        int best_idx = -1;
        index = -1;
        for (var raw = 1; raw <= 24; raw++) {
            var point = (BoardPoint) raw;
            var stack = session.board.stack_at (point);
            var count = (stack == null) ? 0 : stack.checker_ids.length;
            if (count == 0) {
                continue;
            }
            double bx, by;
            BoardLayout.position (point, side, out bx, out by);
            if (Math.fabs (px - bx) > r) {
                continue;
            }
            for (var i = count - 1; i >= 0; i--) {
                if (i < best_idx) {
                    break;
                }
                double x, y;
                stack_position (point, i, side, out x, out y);
                if (Math.hypot (px - x, py - y) <= r) {
                    best = point;
                    best_idx = i;
                    break;
                }
            }
        }
        index = best_idx;
        return best;
    }

    /** Плавная интерполяция ease-in-out по кубической кривой Безье (0.42, 0, 0.58, 1). */
    public static double ease_in_out (double t) {
        if (t <= 0) {
            return 0;
        }
        if (t >= 1) {
            return 1;
        }
        // Решаем x(u) = t методом Ньютона для кривой Безье (0.42,0)-(0.58,1)
        double u = t;
        for (var i = 0; i < 8; i++) {
            var x = 3 * (1 - u) * (1 - u) * u * 0.42 + 3 * (1 - u) * u * u * 0.58 + u * u * u - t;
            var dx = 3 * (1 - u) * (1 - u) * 0.42 + 6 * (1 - u) * u * (0.58 - 0.42) + 3 * u * u * (1 - 0.58);
            if (Math.fabs (dx) < 1e-6) {
                break;
            }
            u -= x / dx;
            u = double.max (0, double.min (1, u));
        }
        return 3 * (1 - u) * u * u + u * u * u;
    }

    /** Затухающие гармонические колебания пружины (response, dampingFraction). */
    public static double spring_value (double t, double response = PlacementAnimation.SPRING_RESPONSE, double damping = PlacementAnimation.SPRING_DAMPING) {
        var resp = response > 0.001 ? response : PlacementAnimation.SPRING_RESPONSE;
        var damp = damping > 0.001 ? damping : PlacementAnimation.SPRING_DAMPING;
        var omega = 2 * Math.PI / resp;
        var zeta = damp;
        var wd = omega * Math.sqrt (1 - zeta * zeta);
        return 1.0 - Math.exp (-zeta * omega * t) * (Math.cos (wd * t) + zeta / Math.sqrt (1 - zeta * zeta) * Math.sin (wd * t));
    }
}

} /* namespace Longbackgammon */

