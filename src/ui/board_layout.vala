/* board_layout.vala
 *
 * Нормализованные координаты (0…1) якорей фишек на доске.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class BoardLayout {
    /** Центр основания треугольника для точки доски (нормализованные координаты). */
    public static void position (BoardPoint point, double board_side, out double x, out double y) {
        // Таблица нормализованных горизонтальных координат X для каждой из 24 лунок (1..24)
        double px;
        switch (point.raw_value ()) {
        case 1:  px = 0.861; break;
        case 2:  px = 0.800; break;
        case 3:  px = 0.739; break;
        case 4:  px = 0.680; break;
        case 5:  px = 0.619; break;
        case 6:  px = 0.559; break;
        case 7:  px = 0.438; break;
        case 8:  px = 0.378; break;
        case 9:  px = 0.318; break;
        case 10: px = 0.258; break;
        case 11: px = 0.197; break;
        case 12: px = 0.136; break;

        case 13: px = 0.138; break;
        case 14: px = 0.199; break;
        case 15: px = 0.260; break;
        case 16: px = 0.320; break;
        case 17: px = 0.380; break;
        case 18: px = 0.440; break;
        case 19: px = 0.561; break;
        case 20: px = 0.621; break;
        case 21: px = 0.681; break;
        case 22: px = 0.741; break;
        case 23: px = 0.801; break;
        default: px = 0.861; break; // 24
        }
        var py = point.is_top_half () ? 0.066 : 0.936;
        x = px * board_side;
        y = py * board_side;
    }

    /** Диаметр фишки как доля стороны доски. */
    public static double checker_diameter (double board_side) {
        return board_side * 0.045;
    }

    /** Расстояние между центрами соседних фишек в стопке. */
    public static double stack_spacing (double diameter) {
        return diameter * 1.01;
    }

    /** Смещение i-й фишки в стопке (0 — у основания). */
    public static double stack_offset (int index, double diameter, int direction) {
        if (index <= 0) {
            return 0;
        }
        return (double) index * stack_spacing (diameter) * (double) direction;
    }

    /** Позиция вынесенной за борт фишки. */
    public static void bear_off_position (CheckerColor color, int index, double board_side, out double x, out double y) {
        double ax;
        double ay;
        int direction;
        if (color == CheckerColor.WHITE) {
            ax = 0.943;
            ay = 0.936;
            direction = -1;
        } else {
            ax = 0.057;
            ay = 0.066;
            direction = 1;
        }
        var diameter = checker_diameter (board_side);
        var spacing = diameter * 1.01;
        x = ax * board_side;
        y = (ay * board_side) + ((double) index * spacing * (double) direction);
    }
}

} /* namespace Longbackgammon */