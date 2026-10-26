/* player_path.vala
 *
 * Навигационный движок маршрутов для белых и чёрных фишек.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Оперирует маршрутами движения фишек по доске. */
public class PlayerPath {
    /** Маршрут белых: от 24 ячейки к 1 (вид сверху вниз). */
    public static BoardPoint[] white () {
        return new BoardPoint[] {
            BoardPoint.P24, BoardPoint.P23, BoardPoint.P22, BoardPoint.P21, BoardPoint.P20, BoardPoint.P19,
            BoardPoint.P18, BoardPoint.P17, BoardPoint.P16, BoardPoint.P15, BoardPoint.P14, BoardPoint.P13,
            BoardPoint.P12, BoardPoint.P11, BoardPoint.P10, BoardPoint.P9, BoardPoint.P8, BoardPoint.P7,
            BoardPoint.P6, BoardPoint.P5, BoardPoint.P4, BoardPoint.P3, BoardPoint.P2, BoardPoint.P1
        };
    }

    /** Маршрут чёрных: от 12 к 1, затем перескок на верхнюю панель от 24 к 13. */
    public static BoardPoint[] black () {
        return new BoardPoint[] {
            BoardPoint.P12, BoardPoint.P11, BoardPoint.P10, BoardPoint.P9, BoardPoint.P8, BoardPoint.P7,
            BoardPoint.P6, BoardPoint.P5, BoardPoint.P4, BoardPoint.P3, BoardPoint.P2, BoardPoint.P1,
            BoardPoint.P24, BoardPoint.P23, BoardPoint.P22, BoardPoint.P21, BoardPoint.P20, BoardPoint.P19,
            BoardPoint.P18, BoardPoint.P17, BoardPoint.P16, BoardPoint.P15, BoardPoint.P14, BoardPoint.P13
        };
    }

    /** Полный массив ячеек-маршрута для цвета игрока. */
    public static BoardPoint[] path (CheckerColor color) {
        return (color == CheckerColor.WHITE) ? white () : black ();
    }

    /** Стартовая точка («голова»): у белых — 24, у чёрных — 12. */
    public static BoardPoint start_point (CheckerColor color) {
        return (color == CheckerColor.WHITE) ? BoardPoint.P24 : BoardPoint.P12;
    }

    /** Последняя ячейка на доске перед выносом за борт. */
    public static BoardPoint finish_point (CheckerColor color) {
        return path (color)[path (color).length - 1];
    }

    /** Точка на расстоянии `steps` от `start` по маршруту; null — фаза выноса. */
    public static BoardPoint? point_from (BoardPoint start, int steps, CheckerColor color) {
        if (steps <= 0) {
            return start;
        }
        var route = path (color);
        var index = find_index (route, start);
        if (index < 0) {
            return null;
        }
        var target_index = index + steps;
        if (target_index >= route.length) {
            return null;
        }
        return route[target_index];
    }

    /** Точное расстояние в шагах между двумя точками маршрута (или −1). */
    public static int steps_between (BoardPoint from, BoardPoint to, CheckerColor color) {
        var route = path (color);
        var from_index = find_index (route, from);
        var to_index = find_index (route, to);
        if (from_index < 0 || to_index < 0 || to_index <= from_index) {
            return -1;
        }
        return to_index - from_index;
    }

    /** Индекс точки в маршруте или −1. */
    public static int find_index (BoardPoint[] route, BoardPoint point) {
        for (var i = 0; i < route.length; i++) {
            if (route[i] == point) {
                return i;
            }
        }
        return -1;
    }
}

} /* namespace Longbackgammon */