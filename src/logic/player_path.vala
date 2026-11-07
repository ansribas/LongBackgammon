/* player_path.vala
 *
 * Навигационный движок маршрутов для белых и чёрных фишек.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Оперирует маршрутами движения фишек по доске. */
public class PlayerPath {
    private const BoardPoint[] WHITE_ROUTE = {
        BoardPoint.P24, BoardPoint.P23, BoardPoint.P22, BoardPoint.P21, BoardPoint.P20, BoardPoint.P19,
        BoardPoint.P18, BoardPoint.P17, BoardPoint.P16, BoardPoint.P15, BoardPoint.P14, BoardPoint.P13,
        BoardPoint.P12, BoardPoint.P11, BoardPoint.P10, BoardPoint.P9, BoardPoint.P8, BoardPoint.P7,
        BoardPoint.P6, BoardPoint.P5, BoardPoint.P4, BoardPoint.P3, BoardPoint.P2, BoardPoint.P1
    };

    private const BoardPoint[] BLACK_ROUTE = {
        BoardPoint.P12, BoardPoint.P11, BoardPoint.P10, BoardPoint.P9, BoardPoint.P8, BoardPoint.P7,
        BoardPoint.P6, BoardPoint.P5, BoardPoint.P4, BoardPoint.P3, BoardPoint.P2, BoardPoint.P1,
        BoardPoint.P24, BoardPoint.P23, BoardPoint.P22, BoardPoint.P21, BoardPoint.P20, BoardPoint.P19,
        BoardPoint.P18, BoardPoint.P17, BoardPoint.P16, BoardPoint.P15, BoardPoint.P14, BoardPoint.P13
    };

    /** Ссылка на статический массив ячеек-маршрута без выделения памяти в куче. */
    public static unowned BoardPoint[] route_ref (CheckerColor color) {
        return (color == CheckerColor.WHITE) ? WHITE_ROUTE : BLACK_ROUTE;
    }

    /** Индекс точки в маршруте игрока за O(1) без аллокаций. */
    public static int index_of (BoardPoint point, CheckerColor color) {
        var raw = point.raw_value ();
        if (raw < 1 || raw > 24) {
            return -1;
        }
        if (color == CheckerColor.WHITE) {
            return 24 - raw;
        }
        return (raw <= 12) ? (12 - raw) : (36 - raw);
    }

    /** Точка маршрута по индексу (0..23) за O(1) без аллокаций. */
    public static BoardPoint point_at (int index, CheckerColor color) {
        return (color == CheckerColor.WHITE) ? WHITE_ROUTE[index] : BLACK_ROUTE[index];
    }

    /** Маршрут белых: от 24 ячейки к 1 (вид сверху вниз). */
    public static BoardPoint[] white () {
        return WHITE_ROUTE;
    }

    /** Маршрут чёрных: от 12 к 1, затем перескок на верхнюю панель от 24 к 13. */
    public static BoardPoint[] black () {
        return BLACK_ROUTE;
    }

    /** Полный массив ячеек-маршрута для цвета игрока. */
    public static BoardPoint[] path (CheckerColor color) {
        return (color == CheckerColor.WHITE) ? WHITE_ROUTE : BLACK_ROUTE;
    }

    /** Стартовая точка («голова»): у белых — 24, у чёрных — 12. */
    public static BoardPoint start_point (CheckerColor color) {
        return (color == CheckerColor.WHITE) ? BoardPoint.P24 : BoardPoint.P12;
    }

    /** Последняя ячейка на доске перед выносом за борт. */
    public static BoardPoint finish_point (CheckerColor color) {
        return (color == CheckerColor.WHITE) ? BoardPoint.P1 : BoardPoint.P13;
    }

    /** Точка на расстоянии `steps` от `start` по маршруту; null — фаза выноса. */
    public static BoardPoint? point_from (BoardPoint start, int steps, CheckerColor color) {
        if (steps <= 0) {
            return start;
        }
        var index = index_of (start, color);
        if (index < 0) {
            return null;
        }
        var target_index = index + steps;
        if (target_index >= 24) {
            return null;
        }
        return point_at (target_index, color);
    }

    /** Точное расстояние в шагах между двумя точками маршрута (или −1). */
    public static int steps_between (BoardPoint from, BoardPoint to, CheckerColor color) {
        var from_index = index_of (from, color);
        var to_index = index_of (to, color);
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