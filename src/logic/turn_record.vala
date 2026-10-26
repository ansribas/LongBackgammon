/* turn_record.vala
 *
 * Структуры лога ходов, используемые в игровой сессии,
 * сохранении игры и интерфейсе.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Один шаг перемещения фишки. */
public class LogStep : Object {
    public BoardPoint from;
    public BoardPoint? to;   // null — вынос за борт

    public LogStep (BoardPoint from, BoardPoint? to) {
        this.from = from;
        this.to = to;
    }
}

/** Один ход, состоящий из последовательности шагов. */
public class LogMove : Object {
    public LogStep[] steps;

    public LogMove (LogStep[] steps) {
        this.steps = steps;
    }
}

/** Состояние кубика текущего хода: значение, флаг использования и флаг пропуска хода. */
public class TurnDie : Object {
    public int id;
    public int value;
    public bool is_used;
    public bool is_skipped;

    public TurnDie (int id, int value, bool is_used = false, bool is_skipped = false) {
        this.id = id;
        this.value = value;
        this.is_used = is_used;
        this.is_skipped = is_skipped;
    }

    public TurnDie clone () {
        return new TurnDie (id, value, is_used, is_skipped);
    }

    public static TurnDie[] clone_array (TurnDie[] src) {
        var r = new TurnDie[src.length];
        for (var i = 0; i < src.length; i++) {
            r[i] = src[i].clone ();
        }
        return r;
    }
}

/** Запись одного хода (одного броска кубиков) в логе партии. */
public class TurnRecord : Object {
    /** Глобальный счётчик уникальных последовательных идентификаторов. */
    private static int next_unique_id = 1;

    /** Уникальный идентификатор записи (используется для подсветки лога). */
    public int id;
    public int turn_number;
    public DiceRoll dice_roll;
    public string[] move_strings;
    public LogMove[] moves;
    public bool is_rolloff;
    public bool is_rolloff_winner = false;
    public TurnDie[] dice = new TurnDie[0];

    /** Глубокая копия (для снимков отмены хода). */
    public TurnRecord clone () {
        var r = new TurnRecord.with_dice (turn_number, new DiceRoll (dice_roll.die1, dice_roll.die2));
        r.move_strings = new string[move_strings.length];
        for (var i = 0; i < move_strings.length; i++) {
            r.move_strings[i] = move_strings[i];
        }
        r.moves = new LogMove[moves.length];
        for (var i = 0; i < moves.length; i++) {
            r.moves[i] = moves[i];
        }
        r.is_rolloff = is_rolloff;
        r.is_rolloff_winner = is_rolloff_winner;
        r.dice = TurnDie.clone_array (dice);
        r.id = id;   // Сохраняем оригинальный идентификатор записи для связки с UI
        return r;
    }

    /** Набор кубиков для отображения в ячейке истории лога. */
    public TurnDie[] display_dice () {
        var expected = dice_roll.is_double ? 4 : 2;
        if (dice.length == expected) {
            return dice;
        }
        if (is_rolloff) {
            return { new TurnDie (0, dice_roll.die1, true), new TurnDie (1, dice_roll.die2, true) };
        }
        var skipped = extract_skipped_dice_values ();
        int[] all = dice_roll.is_double
            ? new int[] { dice_roll.die1, dice_roll.die1, dice_roll.die1, dice_roll.die1 }
            : new int[] { dice_roll.die1, dice_roll.die2 };
        var result = new TurnDie[0];
        for (var i = 0; i < all.length; i++) {
            var found = -1;
            for (var k = 0; k < skipped.length; k++) {
                if (skipped[k] == all[i]) {
                    found = k;
                    break;
                }
            }
            if (found >= 0) {
                skipped[found] = -1;
                result += new TurnDie (i, all[i], false, true);
            } else {
                result += new TurnDie (i, all[i], true, false);
            }
        }
        return result;
    }

    /** Значения пропущенных кубиков из строки «(пропущено 3, 5)» / «(skipped 3, 5)». */
    public int[] extract_skipped_dice_values () {
        var res = new int[0];
        foreach (var str in move_strings) {
            var t = str.strip ();
            string? raw = null;
            if (t.has_prefix ("(пропущено ") && t.has_suffix (")")) {
                raw = t.substring ("(пропущено ".length, t.length - "(пропущено ".length - 1);
            } else if (t.has_prefix ("(skipped ") && t.has_suffix (")")) {
                raw = t.substring ("(skipped ".length, t.length - "(skipped ".length - 1);
            }
            if (raw != null) {
                foreach (var part in raw.split (",")) {
                    var v = int.parse (part.strip ());
                    if (v > 0) {
                        res += v;
                    }
                }
                return res;
            }
        }
        return res;
    }

    public TurnRecord () {
        id = next_unique_id++;
        turn_number = 0;
        dice_roll = new DiceRoll (1, 1);
        move_strings = new string[0];
        moves = new LogMove[0];
        is_rolloff = false;
    }

    public TurnRecord.with_dice (int turn_number, DiceRoll dice_roll) {
        id = next_unique_id++;
        this.turn_number = turn_number;
        this.dice_roll = dice_roll;
        move_strings = new string[0];
        moves = new LogMove[0];
        is_rolloff = false;
    }
}

/** Промежуточный шаг составного хода. */
public class IntermediateStep : Object {
    public BoardPoint from;
    public BoardPoint? to;

    public IntermediateStep (BoardPoint from, BoardPoint? to) {
        this.from = from;
        this.to = to;
    }
}

/** Снимок состояния для отмены хода. */
public class MoveSnapshot : Object {
    public GameBoard board;
    public int[] remaining_dice;
    public int head_count;
    public string status;
    public TurnRecord? current_turn_record;
    public TurnDie[] current_turn_dice;

    public MoveSnapshot (GameBoard board, int[] remaining_dice, int head_count, string status,
                         TurnRecord? current_turn_record, TurnDie[] current_turn_dice = new TurnDie[0]) {
        this.board = board;
        this.remaining_dice = remaining_dice;
        this.head_count = head_count;
        this.status = status;
        this.current_turn_record = current_turn_record == null ? null : current_turn_record.clone ();
        this.current_turn_dice = TurnDie.clone_array (current_turn_dice);
    }
}

} /* namespace Longbackgammon */