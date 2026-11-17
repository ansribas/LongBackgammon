/* game_log_store.vala
 *
 * Архив завершённых партий. Хранение — структурированный JSON (game_logs.json).
 * Без внешних библиотек (встроенный легковесный парсер и форматированный сериализатор).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

// MARK: - Модели данных структурированного лога

public class GameLogPlayer : Object {
    public string name;
    public bool is_computer;
    public string? ai_difficulty;

    public GameLogPlayer (string name, bool is_computer, string? ai_difficulty = null) {
        this.name = name;
        this.is_computer = is_computer;
        this.ai_difficulty = ai_difficulty;
    }
}

public class GameLogPlayers : Object {
    public GameLogPlayer white;
    public GameLogPlayer black;

    public GameLogPlayers (GameLogPlayer white, GameLogPlayer black) {
        this.white = white;
        this.black = black;
    }
}

public class GameLogSettings : Object {
    public string game_speed;
    public string board_theme;
    public string board_side;
    public bool is_first_move_rolloff_enabled;

    public GameLogSettings (string game_speed, string board_theme, string board_side, bool is_first_move_rolloff_enabled) {
        this.game_speed = game_speed;
        this.board_theme = board_theme;
        this.board_side = board_side;
        this.is_first_move_rolloff_enabled = is_first_move_rolloff_enabled;
    }
}

public class GameLogPipCount : Object {
    public int white;
    public int black;

    public GameLogPipCount (int white, int black) {
        this.white = white;
        this.black = black;
    }
}

public class GameLogResult : Object {
    public string winner;
    public string winner_name;
    public string loser;
    public string loser_name;
    public string victory_type;
    public int points;
    public bool is_forfeit;
    public int total_turns;
    public GameLogPipCount final_pip_count;

    public GameLogResult (string winner, string winner_name, string loser, string loser_name,
                          string victory_type, int points, bool is_forfeit, int total_turns,
                          GameLogPipCount final_pip_count) {
        this.winner = winner;
        this.winner_name = winner_name;
        this.loser = loser;
        this.loser_name = loser_name;
        this.victory_type = victory_type;
        this.points = points;
        this.is_forfeit = is_forfeit;
        this.total_turns = total_turns;
        this.final_pip_count = final_pip_count;
    }
}

public class GameLogRollOffRound : Object {
    public int round;
    public int white_die;
    public int black_die;
    public bool is_tie;

    public GameLogRollOffRound (int round, int white_die, int black_die, bool is_tie) {
        this.round = round;
        this.white_die = white_die;
        this.black_die = black_die;
        this.is_tie = is_tie;
    }
}

public class GameLogRollOff : Object {
    public GameLogRollOffRound[] rounds;
    public string winner;
    public string winner_name;

    public GameLogRollOff (GameLogRollOffRound[] rounds, string winner, string winner_name) {
        this.rounds = rounds;
        this.winner = winner;
        this.winner_name = winner_name;
    }
}

public class GameLogMove : Object {
    public int from;
    public int? to;
    public bool is_bear_off;
    public int[]? path;

    public GameLogMove (int from, int? to, bool is_bear_off, int[]? path = null) {
        this.from = from;
        this.to = to;
        this.is_bear_off = is_bear_off;
        this.path = path;
    }
}

public class GameLogTurn : Object {
    public int turn;
    public string player;
    public string player_name;
    public int[] dice;
    public bool is_double;
    public GameLogMove[] moves;
    public string notation;
    public int[]? skipped_dice;

    public GameLogTurn (int turn, string player, string player_name, int[] dice, bool is_double,
                        GameLogMove[] moves, string notation, int[]? skipped_dice = null) {
        this.turn = turn;
        this.player = player;
        this.player_name = player_name;
        this.dice = dice;
        this.is_double = is_double;
        this.moves = moves;
        this.notation = notation;
        this.skipped_dice = skipped_dice;
    }
}

public class GameLogPointStack : Object {
    public int point;
    public string color;
    public int count;

    public GameLogPointStack (int point, string color, int count) {
        this.point = point;
        this.color = color;
        this.count = count;
    }
}

/** Одна запись завершённой партии в архиве game_logs.json. */
public class GameLogEntry : Object {
    public string id;
    public string date;
    public GameLogPlayers players;
    public GameLogSettings settings;
    public GameLogResult result;
    public GameLogRollOff? roll_off;
    public GameLogTurn[] turns;
    public GameLogPointStack[] final_board;

    public GameLogEntry (string id, string date, GameLogPlayers players, GameLogSettings settings,
                         GameLogResult result, GameLogRollOff? roll_off, GameLogTurn[] turns,
                         GameLogPointStack[] final_board) {
        this.id = id;
        this.date = date;
        this.players = players;
        this.settings = settings;
        this.result = result;
        this.roll_off = roll_off;
        this.turns = turns;
        this.final_board = final_board;
    }

    /** Сериализация отдельной записи в JSON (с отступом). */
    public void to_json (StringBuilder b, int indent) {
        var sp = string.nfill (indent, ' ');
        var sp2 = string.nfill (indent + 2, ' ');
        var sp4 = string.nfill (indent + 4, ' ');
        var sp6 = string.nfill (indent + 6, ' ');

        b.append (sp).append ("{\n");

        b.append (sp2).append ("\"date\" : \"").append (JsonUtil.escape (date)).append ("\",\n");

        // finalBoard
        b.append (sp2).append ("\"finalBoard\" : [\n");
        for (var i = 0; i < final_board.length; i++) {
            var fb = final_board[i];
            b.append (sp4).append ("{\n");
            b.append (sp6).append ("\"color\" : \"").append (JsonUtil.escape (fb.color)).append ("\",\n");
            b.append (sp6).append ("\"count\" : ").append (fb.count.to_string ()).append (",\n");
            b.append (sp6).append ("\"point\" : ").append (fb.point.to_string ()).append ("\n");
            b.append (sp4).append ("}").append (i + 1 < final_board.length ? ",\n" : "\n");
        }
        b.append (sp2).append ("],\n");

        b.append (sp2).append ("\"id\" : \"").append (JsonUtil.escape (id)).append ("\",\n");

        // players
        b.append (sp2).append ("\"players\" : {\n");
        // black
        b.append (sp4).append ("\"black\" : {\n");
        if (players.black.ai_difficulty != null) {
            b.append (sp6).append ("\"aiDifficulty\" : \"").append (JsonUtil.escape (players.black.ai_difficulty)).append ("\",\n");
        } else {
            b.append (sp6).append ("\"aiDifficulty\" : null,\n");
        }
        b.append (sp6).append ("\"isComputer\" : ").append (players.black.is_computer ? "true" : "false").append (",\n");
        b.append (sp6).append ("\"name\" : \"").append (JsonUtil.escape (players.black.name)).append ("\"\n");
        b.append (sp4).append ("},\n");
        // white
        b.append (sp4).append ("\"white\" : {\n");
        if (players.white.ai_difficulty != null) {
            b.append (sp6).append ("\"aiDifficulty\" : \"").append (JsonUtil.escape (players.white.ai_difficulty)).append ("\",\n");
        } else {
            b.append (sp6).append ("\"aiDifficulty\" : null,\n");
        }
        b.append (sp6).append ("\"isComputer\" : ").append (players.white.is_computer ? "true" : "false").append (",\n");
        b.append (sp6).append ("\"name\" : \"").append (JsonUtil.escape (players.white.name)).append ("\"\n");
        b.append (sp4).append ("}\n");
        b.append (sp2).append ("},\n");

        // result
        b.append (sp2).append ("\"result\" : {\n");
        b.append (sp4).append ("\"finalPipCount\" : {\n");
        b.append (sp6).append ("\"black\" : ").append (result.final_pip_count.black.to_string ()).append (",\n");
        b.append (sp6).append ("\"white\" : ").append (result.final_pip_count.white.to_string ()).append ("\n");
        b.append (sp4).append ("},\n");
        b.append (sp4).append ("\"isForfeit\" : ").append (result.is_forfeit ? "true" : "false").append (",\n");
        b.append (sp4).append ("\"loser\" : \"").append (JsonUtil.escape (result.loser)).append ("\",\n");
        b.append (sp4).append ("\"loserName\" : \"").append (JsonUtil.escape (result.loser_name)).append ("\",\n");
        b.append (sp4).append ("\"points\" : ").append (result.points.to_string ()).append (",\n");
        b.append (sp4).append ("\"totalTurns\" : ").append (result.total_turns.to_string ()).append (",\n");
        b.append (sp4).append ("\"victoryType\" : \"").append (JsonUtil.escape (result.victory_type)).append ("\",\n");
        b.append (sp4).append ("\"winner\" : \"").append (JsonUtil.escape (result.winner)).append ("\",\n");
        b.append (sp4).append ("\"winnerName\" : \"").append (JsonUtil.escape (result.winner_name)).append ("\"\n");
        b.append (sp2).append ("},\n");

        // rollOff
        if (roll_off != null) {
            b.append (sp2).append ("\"rollOff\" : {\n");
            b.append (sp4).append ("\"rounds\" : [\n");
            for (var i = 0; i < roll_off.rounds.length; i++) {
                var r = roll_off.rounds[i];
                b.append (sp6).append ("{\n");
                var sp8 = string.nfill (indent + 8, ' ');
                b.append (sp8).append ("\"blackDie\" : ").append (r.black_die.to_string ()).append (",\n");
                b.append (sp8).append ("\"isTie\" : ").append (r.is_tie ? "true" : "false").append (",\n");
                b.append (sp8).append ("\"round\" : ").append (r.round.to_string ()).append (",\n");
                b.append (sp8).append ("\"whiteDie\" : ").append (r.white_die.to_string ()).append ("\n");
                b.append (sp6).append ("}").append (i + 1 < roll_off.rounds.length ? ",\n" : "\n");
            }
            b.append (sp4).append ("],\n");
            b.append (sp4).append ("\"winner\" : \"").append (JsonUtil.escape (roll_off.winner)).append ("\",\n");
            b.append (sp4).append ("\"winnerName\" : \"").append (JsonUtil.escape (roll_off.winner_name)).append ("\"\n");
            b.append (sp2).append ("},\n");
        } else {
            b.append (sp2).append ("\"rollOff\" : null,\n");
        }

        // settings
        b.append (sp2).append ("\"settings\" : {\n");
        b.append (sp4).append ("\"boardSide\" : \"").append (JsonUtil.escape (settings.board_side)).append ("\",\n");
        b.append (sp4).append ("\"boardTheme\" : \"").append (JsonUtil.escape (settings.board_theme)).append ("\",\n");
        b.append (sp4).append ("\"gameSpeed\" : \"").append (JsonUtil.escape (settings.game_speed)).append ("\",\n");
        b.append (sp4).append ("\"isFirstMoveRollOffEnabled\" : ").append (settings.is_first_move_rolloff_enabled ? "true" : "false").append ("\n");
        b.append (sp2).append ("},\n");

        // turns
        b.append (sp2).append ("\"turns\" : [\n");
        for (var i = 0; i < turns.length; i++) {
            var t = turns[i];
            b.append (sp4).append ("{\n");
            // dice
            b.append (sp6).append ("\"dice\" : [\n");
            for (var d = 0; d < t.dice.length; d++) {
                var sp8 = string.nfill (indent + 8, ' ');
                b.append (sp8).append (t.dice[d].to_string ()).append (d + 1 < t.dice.length ? ",\n" : "\n");
            }
            b.append (sp6).append ("],\n");
            b.append (sp6).append ("\"isDouble\" : ").append (t.is_double ? "true" : "false").append (",\n");
            // moves
            b.append (sp6).append ("\"moves\" : [\n");
            for (var m = 0; m < t.moves.length; m++) {
                var mv = t.moves[m];
                var sp8 = string.nfill (indent + 8, ' ');
                var sp10 = string.nfill (indent + 10, ' ');
                b.append (sp8).append ("{\n");
                b.append (sp10).append ("\"from\" : ").append (mv.from.to_string ()).append (",\n");
                b.append (sp10).append ("\"isBearOff\" : ").append (mv.is_bear_off ? "true" : "false").append (",\n");
                if (mv.path != null) {
                    b.append (sp10).append ("\"path\" : [\n");
                    for (var p = 0; p < mv.path.length; p++) {
                        var sp12 = string.nfill (indent + 12, ' ');
                        b.append (sp12).append (mv.path[p].to_string ()).append (p + 1 < mv.path.length ? ",\n" : "\n");
                    }
                    b.append (sp10).append ("],\n");
                } else {
                    b.append (sp10).append ("\"path\" : null,\n");
                }
                b.append (sp10).append ("\"to\" : ").append (mv.to != null ? mv.to.to_string () : "null").append ("\n");
                b.append (sp8).append ("}").append (m + 1 < t.moves.length ? ",\n" : "\n");
            }
            b.append (sp6).append ("],\n");
            b.append (sp6).append ("\"notation\" : \"").append (JsonUtil.escape (t.notation)).append ("\",\n");
            b.append (sp6).append ("\"player\" : \"").append (JsonUtil.escape (t.player)).append ("\",\n");
            b.append (sp6).append ("\"playerName\" : \"").append (JsonUtil.escape (t.player_name)).append ("\",\n");
            if (t.skipped_dice != null) {
                b.append (sp6).append ("\"skippedDice\" : [\n");
                for (var sk = 0; sk < t.skipped_dice.length; sk++) {
                    var sp8 = string.nfill (indent + 8, ' ');
                    b.append (sp8).append (t.skipped_dice[sk].to_string ()).append (sk + 1 < t.skipped_dice.length ? ",\n" : "\n");
                }
                b.append (sp6).append ("],\n");
            } else {
                b.append (sp6).append ("\"skippedDice\" : null,\n");
            }
            b.append (sp6).append ("\"turn\" : ").append (t.turn.to_string ()).append ("\n");
            b.append (sp4).append ("}").append (i + 1 < turns.length ? ",\n" : "\n");
        }
        b.append (sp2).append ("]\n");

        b.append (sp).append ("}");
    }

    /** Десериализация из JsonVal с проверкой строгой схемы. */
    public static GameLogEntry? from_json (JsonVal val) {
        if (val.kind != JsonVal.Kind.OBJECT) return null;

        var id = val.get_string ("id");
        var date = val.get_string ("date");
        var p_obj = val.get_object ("players");
        var s_obj = val.get_object ("settings");
        var r_obj = val.get_object ("result");
        var t_arr = val.get_array ("turns");
        var b_arr = val.get_array ("finalBoard");

        // Строгая валидация наличия всех ключевых разделов (отсекает устаревший формат)
        if (id == null || date == null || p_obj == null || s_obj == null ||
            r_obj == null || t_arr == null || b_arr == null) {
            return null;
        }

        var pw = p_obj.get_object ("white");
        var pb = p_obj.get_object ("black");
        if (pw == null || pb == null) return null;
        var white_player = new GameLogPlayer (
            pw.get_string ("name") ?? "",
            pw.get_bool ("isComputer", false),
            pw.get_string ("aiDifficulty")
        );
        var black_player = new GameLogPlayer (
            pb.get_string ("name") ?? "",
            pb.get_bool ("isComputer", false),
            pb.get_string ("aiDifficulty")
        );
        var players = new GameLogPlayers (white_player, black_player);

        var settings = new GameLogSettings (
            s_obj.get_string ("gameSpeed") ?? "slow",
            s_obj.get_string ("boardTheme") ?? "wood",
            s_obj.get_string ("boardSide") ?? "left",
            s_obj.get_bool ("isFirstMoveRollOffEnabled", true)
        );

        var pip_obj = r_obj.get_object ("finalPipCount");
        if (pip_obj == null) return null;
        var pips = new GameLogPipCount (pip_obj.get_int ("white"), pip_obj.get_int ("black"));

        var result = new GameLogResult (
            r_obj.get_string ("winner") ?? "white",
            r_obj.get_string ("winnerName") ?? "",
            r_obj.get_string ("loser") ?? "black",
            r_obj.get_string ("loserName") ?? "",
            r_obj.get_string ("victoryType") ?? "oin",
            r_obj.get_int ("points", 1),
            r_obj.get_bool ("isForfeit", false),
            r_obj.get_int ("totalTurns", 0),
            pips
        );

        GameLogRollOff? roll_off = null;
        var ro_obj = val.get_object ("rollOff");
        if (ro_obj != null) {
            var rounds_arr = ro_obj.get_array ("rounds");
            var rounds = new GameLogRollOffRound[0];
            if (rounds_arr != null) {
                for (var i = 0; i < rounds_arr.arr_val.length; i++) {
                    var r_item = rounds_arr.arr_val.get (i);
                    rounds += new GameLogRollOffRound (
                        r_item.get_int ("round", i + 1),
                        r_item.get_int ("whiteDie", 1),
                        r_item.get_int ("blackDie", 1),
                        r_item.get_bool ("isTie", false)
                    );
                }
            }
            roll_off = new GameLogRollOff (
                rounds,
                ro_obj.get_string ("winner") ?? "white",
                ro_obj.get_string ("winnerName") ?? ""
            );
        }

        var turns = new GameLogTurn[0];
        for (var i = 0; i < t_arr.arr_val.length; i++) {
            var turn_item = t_arr.arr_val.get (i);
            var dice_arr = turn_item.get_array ("dice");
            var dice = new int[0];
            if (dice_arr != null) {
                for (var d = 0; d < dice_arr.arr_val.length; d++) {
                    dice += (int) dice_arr.arr_val.get (d).num_val;
                }
            }

            var moves_arr = turn_item.get_array ("moves");
            var moves = new GameLogMove[0];
            if (moves_arr != null) {
                for (var m = 0; m < moves_arr.arr_val.length; m++) {
                    var mv_item = moves_arr.arr_val.get (m);
                    int? to_val = null;
                    if (mv_item.has_key ("to") && mv_item.obj_val.lookup ("to").kind == JsonVal.Kind.NUMBER) {
                        to_val = (int) mv_item.obj_val.lookup ("to").num_val;
                    }
                    int[]? path_arr = null;
                    var p_arr = mv_item.get_array ("path");
                    if (p_arr != null) {
                        path_arr = new int[0];
                        for (var p = 0; p < p_arr.arr_val.length; p++) {
                            path_arr += (int) p_arr.arr_val.get (p).num_val;
                        }
                    }
                    moves += new GameLogMove (
                        mv_item.get_int ("from"),
                        to_val,
                        mv_item.get_bool ("isBearOff", false),
                        path_arr
                    );
                }
            }

            int[]? skipped_dice = null;
            var sk_arr = turn_item.get_array ("skippedDice");
            if (sk_arr != null) {
                skipped_dice = new int[0];
                for (var sk = 0; sk < sk_arr.arr_val.length; sk++) {
                    skipped_dice += (int) sk_arr.arr_val.get (sk).num_val;
                }
            }

            turns += new GameLogTurn (
                turn_item.get_int ("turn", i + 1),
                turn_item.get_string ("player") ?? "white",
                turn_item.get_string ("playerName") ?? "",
                dice,
                turn_item.get_bool ("isDouble", false),
                moves,
                turn_item.get_string ("notation") ?? "",
                skipped_dice
            );
        }

        var final_board = new GameLogPointStack[0];
        for (var i = 0; i < b_arr.arr_val.length; i++) {
            var fb_item = b_arr.arr_val.get (i);
            final_board += new GameLogPointStack (
                fb_item.get_int ("point"),
                fb_item.get_string ("color") ?? "white",
                fb_item.get_int ("count", 1)
            );
        }

        return new GameLogEntry (id, date, players, settings, result, roll_off, turns, final_board);
    }
}

// MARK: - Вспомогательный JSON AST и парсер

public class JsonUtil {
    public static string escape (string s) {
        return s.replace ("\\", "\\\\")
                .replace ("\"", "\\\"")
                .replace ("\n", "\\n")
                .replace ("\r", "\\r")
                .replace ("\t", "\\t");
    }
}

public class JsonVal : Object {
    public enum Kind { NULL, BOOL, NUMBER, STRING, ARRAY, OBJECT }
    public Kind kind;
    public bool bool_val;
    public double num_val;
    public string str_val;
    public GenericArray<JsonVal> arr_val;
    public HashTable<string, JsonVal> obj_val;

    public JsonVal (Kind kind = Kind.NULL) {
        this.kind = kind;
        if (kind == Kind.ARRAY) {
            arr_val = new GenericArray<JsonVal> ();
        } else if (kind == Kind.OBJECT) {
            obj_val = new HashTable<string, JsonVal> (str_hash, str_equal);
        }
    }

    public static JsonVal make_string (string s) {
        var v = new JsonVal (Kind.STRING);
        v.str_val = s;
        return v;
    }

    public static JsonVal make_number (double n) {
        var v = new JsonVal (Kind.NUMBER);
        v.num_val = n;
        return v;
    }

    public static JsonVal make_bool (bool b) {
        var v = new JsonVal (Kind.BOOL);
        v.bool_val = b;
        return v;
    }

    public static JsonVal make_null () {
        return new JsonVal (Kind.NULL);
    }

    public static JsonVal make_array () {
        return new JsonVal (Kind.ARRAY);
    }

    public static JsonVal make_object () {
        return new JsonVal (Kind.OBJECT);
    }

    public string? get_string (string key) {
        if (kind != Kind.OBJECT || obj_val == null) return null;
        var item = obj_val.lookup (key);
        return (item != null && item.kind == Kind.STRING) ? item.str_val : null;
    }

    public bool get_bool (string key, bool default_val = false) {
        if (kind != Kind.OBJECT || obj_val == null) return default_val;
        var item = obj_val.lookup (key);
        return (item != null && item.kind == Kind.BOOL) ? item.bool_val : default_val;
    }

    public int get_int (string key, int default_val = 0) {
        if (kind != Kind.OBJECT || obj_val == null) return default_val;
        var item = obj_val.lookup (key);
        return (item != null && item.kind == Kind.NUMBER) ? (int) item.num_val : default_val;
    }

    public JsonVal? get_object (string key) {
        if (kind != Kind.OBJECT || obj_val == null) return null;
        var item = obj_val.lookup (key);
        return (item != null && item.kind == Kind.OBJECT) ? item : null;
    }

    public JsonVal? get_array (string key) {
        if (kind != Kind.OBJECT || obj_val == null) return null;
        var item = obj_val.lookup (key);
        return (item != null && item.kind == Kind.ARRAY) ? item : null;
    }

    public bool has_key (string key) {
        return kind == Kind.OBJECT && obj_val != null && obj_val.contains (key);
    }
}

public class JsonParser {
    private string text;
    private int pos;
    private int len;

    public JsonParser (string json) {
        this.text = json;
        this.pos = 0;
        this.len = json.length;
    }

    private void skip_whitespace () {
        while (pos < len) {
            char c = text[pos];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                pos++;
            } else {
                break;
            }
        }
    }

    public JsonVal? parse () {
        skip_whitespace ();
        if (pos >= len) return null;
        return parse_value ();
    }

    private JsonVal? parse_value () {
        skip_whitespace ();
        if (pos >= len) return null;
        char c = text[pos];
        if (c == '{') return parse_object ();
        if (c == '[') return parse_array ();
        if (c == '"') {
            var s = parse_string ();
            return s != null ? JsonVal.make_string (s) : null;
        }
        if (c == 't' || c == 'f') return parse_bool ();
        if (c == 'n') return parse_null ();
        if (c == '-' || (c >= '0' && c <= '9')) return parse_number ();
        return null;
    }

    private JsonVal? parse_object () {
        pos++; // '{'
        var obj = JsonVal.make_object ();
        skip_whitespace ();
        if (pos < len && text[pos] == '}') {
            pos++;
            return obj;
        }
        while (pos < len) {
            skip_whitespace ();
            if (pos >= len || text[pos] != '"') return null;
            var key = parse_string ();
            if (key == null) return null;
            skip_whitespace ();
            if (pos >= len || text[pos] != ':') return null;
            pos++; // ':'
            var val = parse_value ();
            if (val == null) return null;
            obj.obj_val.insert (key, val);
            skip_whitespace ();
            if (pos < len && text[pos] == ',') {
                pos++;
            } else if (pos < len && text[pos] == '}') {
                pos++;
                return obj;
            } else {
                return null;
            }
        }
        return null;
    }

    private JsonVal? parse_array () {
        pos++; // '['
        var arr = JsonVal.make_array ();
        skip_whitespace ();
        if (pos < len && text[pos] == ']') {
            pos++;
            return arr;
        }
        while (pos < len) {
            var val = parse_value ();
            if (val == null) return null;
            arr.arr_val.add (val);
            skip_whitespace ();
            if (pos < len && text[pos] == ',') {
                pos++;
            } else if (pos < len && text[pos] == ']') {
                pos++;
                return arr;
            } else {
                return null;
            }
        }
        return null;
    }

    private string? parse_string () {
        if (pos >= len || text[pos] != '"') return null;
        pos++; // '"'
        var sb = new StringBuilder ();
        while (pos < len) {
            char c = text[pos++];
            if (c == '"') {
                return sb.str;
            }
            if (c == '\\') {
                if (pos >= len) return null;
                char esc = text[pos++];
                if (esc == '"') sb.append_c ('"');
                else if (esc == '\\') sb.append_c ('\\');
                else if (esc == '/') sb.append_c ('/');
                else if (esc == 'b') sb.append_c ('\b');
                else if (esc == 'f') sb.append_c ('\f');
                else if (esc == 'n') sb.append_c ('\n');
                else if (esc == 'r') sb.append_c ('\r');
                else if (esc == 't') sb.append_c ('\t');
                else if (esc == 'u') {
                    if (pos + 4 <= len) {
                        pos += 4;
                    }
                } else {
                    sb.append_c (esc);
                }
            } else {
                sb.append_c (c);
            }
        }
        return null;
    }

    private JsonVal? parse_bool () {
        if (pos + 4 <= len && text.substring (pos, 4) == "true") {
            pos += 4;
            return JsonVal.make_bool (true);
        }
        if (pos + 5 <= len && text.substring (pos, 5) == "false") {
            pos += 5;
            return JsonVal.make_bool (false);
        }
        return null;
    }

    private JsonVal? parse_null () {
        if (pos + 4 <= len && text.substring (pos, 4) == "null") {
            pos += 4;
            return JsonVal.make_null ();
        }
        return null;
    }

    private JsonVal? parse_number () {
        int start = pos;
        if (pos < len && text[pos] == '-') pos++;
        while (pos < len && text[pos] >= '0' && text[pos] <= '9') pos++;
        if (pos < len && text[pos] == '.') {
            pos++;
            while (pos < len && text[pos] >= '0' && text[pos] <= '9') pos++;
        }
        if (pos < len && (text[pos] == 'e' || text[pos] == 'E')) {
            pos++;
            if (pos < len && (text[pos] == '+' || text[pos] == '-')) pos++;
            while (pos < len && text[pos] >= '0' && text[pos] <= '9') pos++;
        }
        var num_str = text.substring (start, pos - start);
        return JsonVal.make_number (double.parse (num_str));
    }
}

// MARK: - Хранилище логов завершённых партий (Singleton)

public class GameLogStore : Object {
    private static GameLogStore? _shared = null;

    public static GameLogStore shared () {
        if (_shared == null) {
            _shared = new GameLogStore ();
        }
        return _shared;
    }

    public signal void changed ();

    private GameLogEntry[] entries;

    public GameLogStore () {
        entries = new GameLogEntry[0];
        load_from_disk ();
    }

    /** Добавляет новую структурированную запись и обрезает до максимума. */
    public void add_entry (GameLogEntry entry) {
        var new_entries = new GameLogEntry[entries.length + 1];
        new_entries[0] = entry;
        for (var i = 0; i < entries.length; i++) {
            new_entries[i + 1] = entries[i];
        }
        entries = new_entries;

        if (entries.length > GameConfig.LOG_MAX_ENTRIES) {
            var trimmed = new GameLogEntry[GameConfig.LOG_MAX_ENTRIES];
            for (var i = 0; i < trimmed.length; i++) {
                trimmed[i] = entries[i];
            }
            entries = trimmed;
        }
        save_to_disk ();
        changed ();
    }

    public GameLogEntry[] all_entries () {
        return entries;
    }

    public void clear_all () {
        entries = new GameLogEntry[0];
        save_to_disk ();
        changed ();
    }

    // MARK: - Сериализация на диск

    private void save_to_disk () {
        var b = new StringBuilder ();
        b.append ("[\n");
        for (var i = 0; i < entries.length; i++) {
            entries[i].to_json (b, 2);
            b.append (i + 1 < entries.length ? ",\n" : "\n");
        }
        b.append ("]\n");

        StoragePaths.write_text_file (
            StoragePaths.file_path (GameConfig.LOG_FILE_NAME),
            b.str);
    }

    private void load_from_disk () {
        var text = StoragePaths.read_text_file (StoragePaths.file_path (GameConfig.LOG_FILE_NAME));
        if (text == null || text.strip () == "") {
            entries = new GameLogEntry[0];
            return;
        }

        var parser = new JsonParser (text);
        var root = parser.parse ();
        if (root == null || root.kind != JsonVal.Kind.ARRAY) {
            message ("[GameLogStore] Log file does not match new structure, resetting log");
            clear_all ();
            return;
        }

        var loaded = new GameLogEntry[0];
        for (var i = 0; i < root.arr_val.length; i++) {
            var item = root.arr_val.get (i);
            var entry = GameLogEntry.from_json (item);
            if (entry == null) {
                message ("[GameLogStore] Log file item does not match new structure, resetting log");
                clear_all ();
                return;
            }
            loaded += entry;
        }

        if (loaded.length > GameConfig.LOG_MAX_ENTRIES) {
            var trimmed = new GameLogEntry[GameConfig.LOG_MAX_ENTRIES];
            for (var i = 0; i < trimmed.length; i++) {
                trimmed[i] = loaded[i];
            }
            entries = trimmed;
            save_to_disk ();
        } else {
            entries = loaded;
        }
    }
}

} /* namespace Longbackgammon */