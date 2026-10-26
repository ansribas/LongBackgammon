/* saved_game_store.vala
 *
 * Модель и хранилище сохранённой незавершённой партии.
 * Хранение — INI (GLib.KeyFile), без внешних зависимостей.
 * Сериализуемые данные: расположение фишек на доске, выпавшие кубики,
 * розыгрыш первого хода, статистика партии, история ходов и стек Undo.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Данные одной стопки для сохранения. */
public class StackData : Object {
    public CheckerColor color;
    public uint8[] checker_ids;
}

/** Полное состояние партии для сохранения/восстановления. */
public class SavedGameData : Object {
    public StackData?[] stacks;
    public uint8[] white_borne_off_ids;
    public uint8[] black_borne_off_ids;

    public CheckerColor current_player;
    public bool is_game_started;
    public bool is_game_over;
    public bool showing_game_over_result;
    public bool is_white_first_turn;
    public bool is_black_first_turn;
    public bool is_first_move_rolloff_in_progress;
    public int white_rolloff_die1;    // 0 = нет значения
    public int white_rolloff_die2;
    public int black_rolloff_die1;
    public int black_rolloff_die2;

    public int dice_roll_die1;        // 0 = кубики не брошены
    public int dice_roll_die2;
    public int[] remaining_dice;

    public int white_moves_count;
    public int black_moves_count;
    public int white_doubles_count;
    public int black_doubles_count;
    public int white_total_dice_sum;
    public int black_total_dice_sum;
    public int white_burned_dice_sum;
    public int black_burned_dice_sum;

    public TurnRecord[] white_turn_log;
    public TurnRecord[] black_turn_log;

    public string white_player_name;
    public string black_player_name;
    public bool is_black_computer;
    public bool is_auto_playing_black;

    public int checkers_moved_from_head_this_turn;

    public TurnRecord? current_turn_record;
    public MoveSnapshot[] move_history;

    public SavedGameData () {
        stacks = new StackData?[25];
        white_borne_off_ids = new uint8[0];
        black_borne_off_ids = new uint8[0];
        remaining_dice = new int[0];
        white_turn_log = new TurnRecord[0];
        black_turn_log = new TurnRecord[0];
        white_player_name = "";
        black_player_name = "";
        current_turn_record = null;
        move_history = new MoveSnapshot[0];
    }
}

/** Хранилище сохранённых игр (Singleton). */
public class SavedGameStore : Object {
    private static SavedGameStore? _shared = null;

    public static SavedGameStore shared () {
        if (_shared == null) {
            _shared = new SavedGameStore ();
        }
        return _shared;
    }

    public void save (SavedGameData data) {
        StoragePaths.write_text_file (
            StoragePaths.file_path (GameConfig.SAVED_GAME_FILE_NAME),
            encode (data));
    }

    public SavedGameData? load () {
        var text = StoragePaths.read_text_file (StoragePaths.file_path (GameConfig.SAVED_GAME_FILE_NAME));
        if (text == null || text == "") {
            return null;
        }
        return decode (text);
    }

    public void clear () {
        try {
            var file = File.new_for_path (StoragePaths.file_path (GameConfig.SAVED_GAME_FILE_NAME));
            if (file.query_exists ()) {
                file.delete ();
            }
        } catch (Error e) {
            warning ("Cannot delete saved game: %s", e.message);
        }
    }

    public bool has_saved_game {
        get { return load () != null; }
    }

    // MARK: - Доска <-> данные

    /** Стопки доски в формате сохранения. */
    public static StackData?[] stacks_from_board (GameBoard board) {
        var result = new StackData?[25];
        for (var raw = 1; raw <= 24; raw++) {
            var stack = board.stack_at ((BoardPoint) raw);
            if (stack != null) {
                var sd = new StackData ();
                sd.color = stack.color;
                sd.checker_ids = copy_u8 (stack.checker_ids);
                result[raw] = sd;
            }
        }
        return result;
    }

    /** Восстанавливает доску из сохранённых стопок. */
    public static GameBoard board_from_data (StackData?[] stacks, uint8[] white_off, uint8[] black_off) {
        var board = new GameBoard ();
        for (var raw = 1; raw <= 24 && raw < stacks.length; raw++) {
            var sd = stacks[raw];
            if (sd != null && sd.checker_ids.length > 0) {
                board.set_stack ((BoardPoint) raw, sd.color, copy_u8 (sd.checker_ids));
            }
        }
        board.set_borne_off (copy_u8 (white_off), copy_u8 (black_off));
        return board;
    }

    private static uint8[] copy_u8 (uint8[] src) {
        var r = new uint8[src.length];
        for (var i = 0; i < src.length; i++) {
            r[i] = src[i];
        }
        return r;
    }

    // MARK: - Вспомогательные конвертеры

    private static string join_ids (uint8[] ids) {
        var parts = new string[ids.length];
        for (var i = 0; i < ids.length; i++) {
            parts[i] = ids[i].to_string ();
        }
        return string.joinv (",", parts);
    }

    private static uint8[] split_ids (string s) {
        var result = new uint8[0];
        if (s == "") {
            return result;
        }
        foreach (var p in s.split (",")) {
            var v = int.parse (p);
            if (v >= 0) {
                result += (uint8) v;
            }
        }
        return result;
    }

    private static string join_ints (int[] vals) {
        var parts = new string[vals.length];
        for (var i = 0; i < vals.length; i++) {
            parts[i] = vals[i].to_string ();
        }
        return string.joinv (",", parts);
    }

    private static int[] split_ints (string s) {
        var result = new int[0];
        if (s == "") {
            return result;
        }
        foreach (var p in s.split (",")) {
            result += int.parse (p);
        }
        return result;
    }

    // MARK: - Кодирование

    private static void encode_board (KeyFile kf, string group, StackData?[] stacks, uint8[] white_off, uint8[] black_off) {
        for (var raw = 1; raw <= 24 && raw < stacks.length; raw++) {
            var stack = stacks[raw];
            if (stack != null) {
                kf.set_string (group, "stack%d".printf (raw),
                    "%s|%s".printf (stack.color.to_string (), join_ids (stack.checker_ids)));
            }
        }
        kf.set_string (group, "white_off", join_ids (white_off));
        kf.set_string (group, "black_off", join_ids (black_off));
    }

    private static void decode_board (KeyFile kf, string group, out StackData?[] stacks, out uint8[] white_off, out uint8[] black_off) {
        stacks = new StackData?[25];
        white_off = new uint8[0];
        black_off = new uint8[0];
        for (var raw = 1; raw <= 24; raw++) {
            try {
                var key = "stack%d".printf (raw);
                if (!kf.has_key (group, key)) {
                    continue;
                }
                var parts = kf.get_string (group, key).split ("|");
                if (parts.length == 2) {
                    var sd = new StackData ();
                    sd.color = CheckerColor.from_string (parts[0]);
                    sd.checker_ids = split_ids (parts[1]);
                    stacks[raw] = sd;
                }
            } catch (Error e) {
            }
        }
        try {
            white_off = split_ids (kf.get_string (group, "white_off"));
            black_off = split_ids (kf.get_string (group, "black_off"));
        } catch (Error e) {
        }
    }

    private static string encode_dice (TurnDie[] dice) {
        var parts = new string[dice.length];
        for (var i = 0; i < dice.length; i++) {
            var d = dice[i];
            parts[i] = "%d:%d:%d:%d".printf (d.id, d.value, d.is_used ? 1 : 0, d.is_skipped ? 1 : 0);
        }
        return string.joinv (",", parts);
    }

    private static TurnDie[] decode_dice (string s) {
        var result = new TurnDie[0];
        if (s == "") {
            return result;
        }
        foreach (var p in s.split (",")) {
            var f = p.split (":");
            if (f.length >= 3) {
                result += new TurnDie (int.parse (f[0]), int.parse (f[1]),
                                       f[2] == "1", f.length >= 4 && f[3] == "1");
            }
        }
        return result;
    }

    private static void encode_record (KeyFile kf, string group, string prefix, TurnRecord r) {
        kf.set_integer (group, prefix + "_turn", r.turn_number);
        kf.set_integer (group, prefix + "_die1", r.dice_roll.die1);
        kf.set_integer (group, prefix + "_die2", r.dice_roll.die2);
        kf.set_boolean (group, prefix + "_rolloff", r.is_rolloff);
        kf.set_boolean (group, prefix + "_rolloff_winner", r.is_rolloff_winner);
        kf.set_string_list (group, prefix + "_strings", r.move_strings);
        kf.set_string (group, prefix + "_dice", encode_dice (r.dice));

        var moves = new string[r.moves.length];
        for (var m = 0; m < r.moves.length; m++) {
            var move = r.moves[m];
            var steps = new string[move.steps.length];
            for (var s = 0; s < move.steps.length; s++) {
                var step = move.steps[s];
                steps[s] = "%d,%d".printf (step.from.raw_value (), step.to == null ? 0 : step.to.raw_value ());
            }
            moves[m] = string.joinv (";", steps);
        }
        kf.set_string_list (group, prefix + "_moves", moves);
    }

    private static TurnRecord? decode_record (KeyFile kf, string group, string prefix) {
        try {
            if (!kf.has_key (group, prefix + "_turn")) {
                return null;
            }
            var record = new TurnRecord ();
            record.turn_number = kf.get_integer (group, prefix + "_turn");
            record.dice_roll = new DiceRoll (
                kf.get_integer (group, prefix + "_die1"),
                kf.get_integer (group, prefix + "_die2"));
            record.is_rolloff = kf.get_boolean (group, prefix + "_rolloff");
            if (kf.has_key (group, prefix + "_rolloff_winner")) {
                record.is_rolloff_winner = kf.get_boolean (group, prefix + "_rolloff_winner");
            }
            record.move_strings = kf.get_string_list (group, prefix + "_strings");
            if (kf.has_key (group, prefix + "_dice")) {
                record.dice = decode_dice (kf.get_string (group, prefix + "_dice"));
            }

            var moves_enc = kf.get_string_list (group, prefix + "_moves");
            var moves = new LogMove[0];
            foreach (var me in moves_enc) {
                var steps = new LogStep[0];
                foreach (var se in me.split (";")) {
                    var parts = se.split (",");
                    if (parts.length != 2) {
                        continue;
                    }
                    var from = BoardPoint.from_raw (int.parse (parts[0]));
                    var to_raw = int.parse (parts[1]);
                    var to = (to_raw >= 1) ? BoardPoint.from_raw (to_raw) : null;
                    if (from != null) {
                        steps += new LogStep (from, to);
                    }
                }
                moves += new LogMove (steps);
            }
            record.moves = moves;
            return record;
        } catch (Error e) {
            warning ("Record decode error: %s", e.message);
            return null;
        }
    }

    private static void encode_log (KeyFile kf, string group, TurnRecord[] log) {
        kf.set_integer (group, "count", log.length);
        for (var i = 0; i < log.length; i++) {
            encode_record (kf, group, "rec%d".printf (i), log[i]);
        }
    }

    private static TurnRecord[] decode_log (KeyFile kf, string group) {
        var result = new TurnRecord[0];
        if (!kf.has_group (group)) {
            return result;
        }
        try {
            var n = kf.get_integer (group, "count");
            for (var i = 0; i < n; i++) {
                var r = decode_record (kf, group, "rec%d".printf (i));
                if (r != null) {
                    result += r;
                }
            }
        } catch (Error e) {
            warning ("Log decode error: %s", e.message);
        }
        return result;
    }

    private static string encode (SavedGameData d) {
        var kf = new KeyFile ();

        encode_board (kf, "board", d.stacks, d.white_borne_off_ids, d.black_borne_off_ids);

        kf.set_string ("game", "current_player", d.current_player.to_string ());
        kf.set_boolean ("game", "is_game_started", d.is_game_started);
        kf.set_boolean ("game", "is_game_over", d.is_game_over);
        kf.set_boolean ("game", "showing_game_over_result", d.showing_game_over_result);
        kf.set_boolean ("game", "is_white_first_turn", d.is_white_first_turn);
        kf.set_boolean ("game", "is_black_first_turn", d.is_black_first_turn);
        kf.set_boolean ("game", "is_first_move_rolloff_in_progress", d.is_first_move_rolloff_in_progress);
        kf.set_integer ("game", "white_rolloff_die1", d.white_rolloff_die1);
        kf.set_integer ("game", "white_rolloff_die2", d.white_rolloff_die2);
        kf.set_integer ("game", "black_rolloff_die1", d.black_rolloff_die1);
        kf.set_integer ("game", "black_rolloff_die2", d.black_rolloff_die2);
        kf.set_integer ("game", "dice_roll_die1", d.dice_roll_die1);
        kf.set_integer ("game", "dice_roll_die2", d.dice_roll_die2);
        kf.set_string ("game", "remaining_dice", join_ints (d.remaining_dice));

        kf.set_integer ("game", "white_moves_count", d.white_moves_count);
        kf.set_integer ("game", "black_moves_count", d.black_moves_count);
        kf.set_integer ("game", "white_doubles_count", d.white_doubles_count);
        kf.set_integer ("game", "black_doubles_count", d.black_doubles_count);
        kf.set_integer ("game", "white_total_dice_sum", d.white_total_dice_sum);
        kf.set_integer ("game", "black_total_dice_sum", d.black_total_dice_sum);
        kf.set_integer ("game", "white_burned_dice_sum", d.white_burned_dice_sum);
        kf.set_integer ("game", "black_burned_dice_sum", d.black_burned_dice_sum);

        kf.set_string ("game", "white_player_name", d.white_player_name);
        kf.set_string ("game", "black_player_name", d.black_player_name);
        kf.set_boolean ("game", "is_black_computer", d.is_black_computer);
        kf.set_boolean ("game", "is_auto_playing_black", d.is_auto_playing_black);
        kf.set_integer ("game", "checkers_moved_from_head", d.checkers_moved_from_head_this_turn);

        encode_log (kf, "white_log", d.white_turn_log);
        encode_log (kf, "black_log", d.black_turn_log);

        if (d.current_turn_record != null) {
            encode_record (kf, "current", "rec", d.current_turn_record);
        }

        // История отмены ходов
        kf.set_integer ("history", "count", d.move_history.length);
        for (var i = 0; i < d.move_history.length; i++) {
            var snap = d.move_history[i];
            var group = "history%d".printf (i);
            encode_board (kf, group, stacks_from_board (snap.board),
                          snap.board.white_borne_off_ids, snap.board.black_borne_off_ids);
            kf.set_string (group, "remaining_dice", join_ints (snap.remaining_dice));
            kf.set_integer (group, "head_count", snap.head_count);
            kf.set_string (group, "status", snap.status);
            kf.set_string (group, "turn_dice", encode_dice (snap.current_turn_dice));
            if (snap.current_turn_record != null) {
                encode_record (kf, group, "rec", snap.current_turn_record);
            }
        }

        return kf.to_data ();
    }

    // MARK: - Декодирование

    private static int get_int_or (KeyFile kf, string group, string key, int def) {
        try {
            if (kf.has_key (group, key)) {
                return kf.get_integer (group, key);
            }
        } catch (Error e) {
        }
        return def;
    }

    private static SavedGameData? decode (string text) {
        var kf = new KeyFile ();
        try {
            if (!kf.load_from_data (text, text.length, GLib.KeyFileFlags.NONE)) {
                return null;
            }
        } catch (Error e) {
            warning ("Saved game load error: %s", e.message);
            return null;
        }
        if (!kf.has_group ("game")) {
            return null;
        }

        var data = new SavedGameData ();
        StackData?[] stacks;
        uint8[] woff;
        uint8[] boff;
        decode_board (kf, "board", out stacks, out woff, out boff);
        data.stacks = stacks;
        data.white_borne_off_ids = woff;
        data.black_borne_off_ids = boff;

        try {
            data.current_player = CheckerColor.from_string (kf.get_string ("game", "current_player"));
            data.is_game_started = kf.get_boolean ("game", "is_game_started");
            data.is_game_over = kf.get_boolean ("game", "is_game_over");
            data.showing_game_over_result = kf.get_boolean ("game", "showing_game_over_result");
            data.is_white_first_turn = kf.get_boolean ("game", "is_white_first_turn");
            data.is_black_first_turn = kf.get_boolean ("game", "is_black_first_turn");
            data.is_first_move_rolloff_in_progress = kf.get_boolean ("game", "is_first_move_rolloff_in_progress");
            data.white_rolloff_die1 = get_int_or (kf, "game", "white_rolloff_die1", 0);
            data.white_rolloff_die2 = get_int_or (kf, "game", "white_rolloff_die2", 0);
            data.black_rolloff_die1 = get_int_or (kf, "game", "black_rolloff_die1", 0);
            data.black_rolloff_die2 = get_int_or (kf, "game", "black_rolloff_die2", 0);
            data.dice_roll_die1 = kf.get_integer ("game", "dice_roll_die1");
            data.dice_roll_die2 = kf.get_integer ("game", "dice_roll_die2");
            data.remaining_dice = split_ints (kf.get_string ("game", "remaining_dice"));

            data.white_moves_count = kf.get_integer ("game", "white_moves_count");
            data.black_moves_count = kf.get_integer ("game", "black_moves_count");
            data.white_doubles_count = kf.get_integer ("game", "white_doubles_count");
            data.black_doubles_count = kf.get_integer ("game", "black_doubles_count");
            data.white_total_dice_sum = kf.get_integer ("game", "white_total_dice_sum");
            data.black_total_dice_sum = kf.get_integer ("game", "black_total_dice_sum");
            data.white_burned_dice_sum = kf.get_integer ("game", "white_burned_dice_sum");
            data.black_burned_dice_sum = kf.get_integer ("game", "black_burned_dice_sum");

            data.white_player_name = kf.get_string ("game", "white_player_name");
            data.black_player_name = kf.get_string ("game", "black_player_name");
            data.is_black_computer = kf.get_boolean ("game", "is_black_computer");
            data.is_auto_playing_black = kf.get_boolean ("game", "is_auto_playing_black");
            data.checkers_moved_from_head_this_turn = kf.get_integer ("game", "checkers_moved_from_head");
        } catch (Error e) {
            warning ("Saved game decode error: %s", e.message);
        }

        data.white_turn_log = decode_log (kf, "white_log");
        data.black_turn_log = decode_log (kf, "black_log");
        data.current_turn_record = kf.has_group ("current") ? decode_record (kf, "current", "rec") : null;

        var history = new MoveSnapshot[0];
        var hn = get_int_or (kf, "history", "count", 0);
        for (var i = 0; i < hn; i++) {
            var group = "history%d".printf (i);
            if (!kf.has_group (group)) {
                continue;
            }
            StackData?[] hs;
            uint8[] hw;
            uint8[] hb;
            decode_board (kf, group, out hs, out hw, out hb);
            try {
                var snap = new MoveSnapshot (
                    board_from_data (hs, hw, hb),
                    split_ints (kf.get_string (group, "remaining_dice")),
                    kf.get_integer (group, "head_count"),
                    kf.get_string (group, "status"),
                    decode_record (kf, group, "rec"),
                    decode_dice (kf.get_string (group, "turn_dice")));
                history += snap;
            } catch (Error e) {
                warning ("History decode error: %s", e.message);
            }
        }
        data.move_history = history;

        return data;
    }
}

} /* namespace Longbackgammon */