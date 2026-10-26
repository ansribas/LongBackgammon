/* models.vala
 *
 * Базовые модели игры «Длинные нарды»:
 * - BoardPoint  — ячейка доски (1…24)
 * - CheckerColor — цвет фишки (белые/чёрные)
 * - PointStack  — стопка фишек на одной ячейке
 * - MoveOption  — легальный вариант хода
 * - DiceRoll    — результат броска пары кубиков
 * Модели игровых сущностей и структур состояния партии.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Ячейка доски. Визуально: низ (1…12) справа налево, верх (13…24) слева направо. */
public enum BoardPoint {
    P1 = 1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12,
    P13, P14, P15, P16, P17, P18, P19, P20, P21, P22, P23, P24;

    /** Безопасное преобразование числа 1…24 в точку доски. */
    public static BoardPoint? from_raw (int raw) {
        if (raw < 1 || raw > 24) {
            return null;
        }
        return (BoardPoint) raw;
    }

    /** Числовое значение точки (1…24). */
    public int raw_value () {
        return (int) this;
    }

    /** true, если точка на верхней половине доски (13…24). */
    public bool is_top_half () {
        return (int) this >= 13;
    }

    /** Направление роста стопки: вниз (+1) наверху, вверх (−1) внизу. */
    public int stack_direction () {
        return is_top_half () ? 1 : -1;
    }
}

/** Цвет игровых фишек. */
public enum CheckerColor {
    WHITE,
    BLACK;

    /** Противоположный цвет. */
    public CheckerColor opposite () {
        return (this == CheckerColor.WHITE) ? CheckerColor.BLACK : CheckerColor.WHITE;
    }

    public string to_string () {
        return (this == CheckerColor.WHITE) ? "white" : "black";
    }

    public static CheckerColor from_string (string s) {
        return (s == "black") ? CheckerColor.BLACK : CheckerColor.WHITE;
    }
}

/**
 * Стопка фишек, расположенная на одной конкретной ячейке доски.
 * Последний элемент массива id — самая верхняя фишка в стопке.
 */
public class PointStack : Object {
    public CheckerColor color;
    public uint8[] checker_ids;

    /** Создание стартовой стопки из определённого количества фишек с уникальными id. */
    public PointStack.with_count (CheckerColor color, int count) {
        this.color = color;
        uint8 offset = (color == CheckerColor.WHITE) ? 0 : 15;
        var ids = new uint8[0];
        for (var i = 0; i < count; i++) {
            ids += (uint8) (offset + i);
        }
        checker_ids = ids;
    }

    public PointStack.with_ids (CheckerColor color, uint8[] ids) {
        this.color = color;
        checker_ids = ids;
    }

    /** Количество фишек в стопке. */
    public int count { get { return checker_ids.length; } }
}

/** Легальный вариант перемещения фишки. */
public class MoveOption : Object {
    /** Откуда совершается ход. */
    public BoardPoint from;
    /** Куда совершается ход; null — вынос за борт. */
    public BoardPoint? to;
    /** Суммарное значение кубиков, использованных для хода. */
    public int die;
    /** Индексы использованных кубиков в массиве remaining_dice. */
    public int[] die_indices;
    /** true, если ход использует несколько кубиков (combo). */
    public bool is_combined;
    /** true, если ход создаёт запрещённый блок из 6 фишек (prime). */
    public bool is_illegal_prime;

    public MoveOption (BoardPoint from, BoardPoint? to, int die, int[] die_indices, bool is_combined, bool is_illegal_prime = false) {
        this.from = from;
        this.to = to;
        this.die = die;
        this.die_indices = die_indices;
        this.is_combined = is_combined;
        this.is_illegal_prime = is_illegal_prime;
    }

    public MoveOption copy () {
        return new MoveOption (
            from, to, die, die_indices, is_combined, is_illegal_prime);
    }
}

/** Результат броска пары игральных костей. */
public class DiceRoll : Object {
    public int die1;
    public int die2;

    public DiceRoll (int die1, int die2) {
        this.die1 = int.min (6, int.max (1, die1));
        this.die2 = int.min (6, int.max (1, die2));
    }

    /** Случайный бросок. */
    public static DiceRoll random () {
        return new DiceRoll (GLib.Random.int_range (1, 7), GLib.Random.int_range (1, 7));
    }

    /** Дубль? */
    public bool is_double { get { return die1 == die2; } }
}

/** Состояние кубиков, анимируемых на доске (3D физика броска). */
public class BoardDiceState : Object {
    public string id;
    public CheckerColor color;
    public DiceRoll roll;
    public bool is_rolling;
    public bool is_transferring;
    public double duration;
    public double jitter_x1;
    public double jitter_y1;
    public double jitter_yaw1;
    public double jitter_x2;
    public double jitter_y2;
    public double jitter_yaw2;
    public double spin_pitch1;
    public double spin_roll1;
    public double spin_yaw1;
    public double spin_pitch2;
    public double spin_roll2;
    public double spin_yaw2;
    public int64 start_time_us;
    public int64 transfer_start_time_us;
    public bool sound_played;

    public BoardDiceState (CheckerColor color, DiceRoll roll, double duration = 1.75) {
        this.id = GLib.Uuid.string_random ();
        this.color = color;
        this.roll = roll;
        this.is_rolling = true;
        this.is_transferring = false;
        this.duration = duration;
        this.jitter_x1 = GLib.Random.double_range (-3.0, 3.0);
        this.jitter_y1 = GLib.Random.double_range (-3.0, 3.0);
        this.jitter_yaw1 = GLib.Random.double_range (-0.08, 0.08);
        this.jitter_x2 = GLib.Random.double_range (-3.0, 3.0);
        this.jitter_y2 = GLib.Random.double_range (-3.0, 3.0);
        this.jitter_yaw2 = GLib.Random.double_range (-0.08, 0.08);
        this.spin_pitch1 = GLib.Random.double_range (1.4, 1.8);
        this.spin_roll1 = GLib.Random.double_range (0.25, 0.55);
        this.spin_yaw1 = GLib.Random.double_range (0.20, 0.45);
        this.spin_pitch2 = GLib.Random.double_range (1.2, 1.6);
        this.spin_roll2 = GLib.Random.double_range (-0.55, -0.25);
        this.spin_yaw2 = GLib.Random.double_range (-0.45, -0.20);
        this.start_time_us = GLib.get_monotonic_time ();
        this.transfer_start_time_us = 0;
        this.sound_played = false;
    }
}

/**
 * Целевая позиция фишки при восстановлении или расстановке партии из сохранения:
 * идентификатор фишки, цвет, целевая ячейка доски (null — сброшена) и индекс в стопке.
 */
public class TargetPlacementLocation : Object {
    public uint8 id;
    public CheckerColor color;
    public BoardPoint? point;
    public int stack_index;

    public TargetPlacementLocation (uint8 id, CheckerColor color, BoardPoint? point, int stack_index) {
        this.id = id;
        this.color = color;
        this.point = point;
        this.stack_index = stack_index;
    }
}

} /* namespace Longbackgammon */