using Longbackgammon;

/** Тест: записи лога белых и чёрных находятся по глобальному номеру (hover-стрелки). */
int main (string[] args) {
    try {
        var tmp_dir = DirUtils.make_tmp ("longbackgammon_test_XXXXXX");
        Environment.set_variable ("XDG_DATA_HOME", tmp_dir, true);
    } catch (Error e) {
        warning ("Cannot create temp test dir: %s", e.message);
    }

    var settings = SettingsStore.shared ();
    settings.set_is_first_move_rolloff_enabled (false);
    settings.set_opponent (Opponent.HUMAN);

    var s = new GameSession ();
    s.new_game (true, false);
    if (!s.is_game_started) {
        stdout.printf ("FAIL: game not started\n");
        return 1;
    }

    // Ход белых, затем чёрных
    if (!play_one_move (s, CheckerColor.WHITE, (BoardPoint) 24)) {
        return 1;
    }
    if (!play_one_move (s, CheckerColor.BLACK, (BoardPoint) 12)) {
        return 1;
    }

    if (s.white_turn_log.length == 0 || s.black_turn_log.length == 0) {
        stdout.printf ("FAIL: logs empty (w=%d b=%d)\n", s.white_turn_log.length, s.black_turn_log.length);
        return 1;
    }

    // Проверка уникальности номеров ходов (основа hover-подсветки обоих панелей)
    var seen = new GLib.HashTable<int, bool> (null, null);
    foreach (var rec in s.white_turn_log) {
        if (seen.contains (rec.id)) { stdout.printf ("FAIL: duplicate id %d\n", rec.id); return 1; }
        seen.insert (rec.id, true);
    }
    foreach (var rec in s.black_turn_log) {
        if (seen.contains (rec.id)) { stdout.printf ("FAIL: duplicate id %d\n", rec.id); return 1; }
        seen.insert (rec.id, true);
    }

    // Симуляция hover: ищем по id запись каждого цвета
    var wrec = s.white_turn_log[0];
    var breach = s.black_turn_log[0];
    CheckerColor c1; CheckerColor c2;
    var r1 = find_record (s, wrec.id, out c1);
    var r2 = find_record (s, breach.id, out c2);
    if (r1 == null || c1 != CheckerColor.WHITE) { stdout.printf ("FAIL: white not found\n"); return 1; }
    if (r2 == null || c2 != CheckerColor.BLACK) { stdout.printf ("FAIL: black not found\n"); return 1; }

    // Тест составного хода
    var s2 = new GameSession ();
    s2.new_game (true, false);
    s2.current_player = CheckerColor.WHITE;
    s2.dice_roll = new DiceRoll (3, 4);
    s2.remaining_dice = new int[] { 3, 4 };
    s2.is_rolling = false;
    s2.is_animating = false;
    s2.current_turn_record = new TurnRecord.with_dice (1, s2.dice_roll);
    s2.update_available_moves_cache ();

    MoveOption? combined = null;
    foreach (var o in s2.options_from ((BoardPoint) 24)) {
        if (o.is_combined && o.to != null && (int) o.to == 17) {
            combined = o;
            break;
        }
    }
    if (combined == null) {
        stdout.printf ("FAIL: combined move 24->17 not found\n");
        return 1;
    }

    s2.apply_move (combined.to, combined.from);
    if (!wait_until (() => !s2.is_animating)) {
        stdout.printf ("FAIL: combined move animation stuck\n");
        return 1;
    }


    if (s2.current_turn_record.moves.length == 0) {
        stdout.printf ("FAIL: current_turn_record.moves empty\n");
        return 1;
    }
    var log_mv = s2.current_turn_record.moves[0];
    if (log_mv.steps.length < 2) {
        stdout.printf ("FAIL: intermediate steps not recorded in log (length=%d)\n", log_mv.steps.length);
        return 1;
    }
    if (s2.remaining_dice.length != 0) {
        stdout.printf ("FAIL: s2.remaining_dice has %d dice remaining (expected 0)\n", s2.remaining_dice.length);
        return 1;
    }
    stdout.printf ("OK: combined move executed and logged with %d steps: %s, remaining_dice=%d\n",
        log_mv.steps.length, s2.current_turn_record.move_strings[0], s2.remaining_dice.length);

    // Тест 3: Составной ход при дубле (3:3:3:3), ход на 2 кубика 24->18
    var s3 = new GameSession ();
    s3.new_game (true, false);
    s3.current_player = CheckerColor.WHITE;
    s3.dice_roll = new DiceRoll (3, 3);
    s3.remaining_dice = new int[] { 3, 3, 3, 3 };
    var d3 = new TurnDie[0];
    for (var i = 0; i < 4; i++) d3 += new TurnDie (i, 3);
    s3.current_turn_dice = d3;
    s3.current_turn_record = new TurnRecord.with_dice (1, s3.dice_roll);
    s3.current_turn_record.dice = TurnDie.clone_array (d3);
    s3.is_rolling = false;
    s3.is_animating = false;
    s3.update_available_moves_cache ();

    MoveOption? double_comb = null;
    foreach (var o in s3.options_from ((BoardPoint) 24)) {
        if (o.is_combined && o.to != null && (int) o.to == 18) {
            double_comb = o;
            break;
        }
    }
    if (double_comb == null) {
        stdout.printf ("FAIL: double combined move 24->18 not found\n");
        return 1;
    }
    stdout.printf ("Double combined move: to=%d, die=%d, die_indices.len=%d\n",
        (int) double_comb.to, double_comb.die, double_comb.die_indices.length);

    s3.apply_move (double_comb.to, double_comb.from);
    if (!wait_until (() => !s3.is_animating)) {
        stdout.printf ("FAIL: double combined move animation stuck\n");
        return 1;
    }
    stdout.printf ("After double combined 24->18: remaining_dice=%d (expected 2)\n", s3.remaining_dice.length);
    var used_count = 0;
    foreach (var td in s3.current_turn_dice) {
        if (td.is_used) used_count++;
    }
    stdout.printf ("current_turn_dice used count=%d (expected 2)\n", used_count);
    if (s3.remaining_dice.length != 2 || used_count != 2) {
        stdout.printf ("FAIL: double combined did not consume 2 dice!\n");
        return 1;
    }

    // Restore roll-off tie: dice clear and the first player gets to roll again.
    var tie_session = new GameSession ();
    tie_session.restore_from_store (rolloff_restore_data (5, 5, 6, 4));
    if (!wait_until (() => tie_session.white_rolloff_dice == null
                         && tie_session.black_rolloff_dice == null
                         && !tie_session.is_animating, 8.0)) {
        stdout.printf ("FAIL: restored roll-off tie did not resolve\n");
        return 1;
    }
    if (tie_session.current_player != CheckerColor.WHITE || !tie_session.is_first_move_rolloff_in_progress) {
        stdout.printf ("FAIL: roll-off tie did not return the roll to white\n");
        return 1;
    }

    // Restore roll-off win: phase ends and the winner becomes the current player.
    var win_session = new GameSession ();
    win_session.restore_from_store (rolloff_restore_data (6, 5, 1, 2));
    if (!wait_until (() => !win_session.is_first_move_rolloff_in_progress
                         && !win_session.is_animating, 8.0)) {
        stdout.printf ("FAIL: restored roll-off win did not resolve\n");
        return 1;
    }
    if (win_session.current_player != CheckerColor.WHITE
        || win_session.white_rolloff_dice != null || win_session.black_rolloff_dice != null) {
        stdout.printf ("FAIL: roll-off winner was not restored correctly\n");
        return 1;
    }

    var test_sess = new GameSession ();
    test_sess.board = GameBoard.in_tray ();
    bool placement_done = false;
    test_sess.animate_placement (GameBoard.initial_long (), false, false, () => {
        placement_done = true;
    });
    if (!wait_until (() => placement_done, 10.0)) {
        stdout.printf ("FAIL: placement animation timed out\n");
        return 1;
    }

    stdout.printf ("OK: logs matched (%d white, %d black), ids unique\n", s.white_turn_log.length, s.black_turn_log.length);
    return 0;
}

static SavedGameData rolloff_restore_data (int white_die1, int white_die2,
                                           int black_die1, int black_die2) {
    var data = new SavedGameData ();
    data.stacks = new StackData?[25];
    data.current_player = CheckerColor.WHITE;
    data.is_game_started = true;
    data.is_first_move_rolloff_in_progress = true;
    data.white_rolloff_die1 = white_die1;
    data.white_rolloff_die2 = white_die2;
    data.black_rolloff_die1 = black_die1;
    data.black_rolloff_die2 = black_die2;
    data.white_player_name = "Player";
    data.black_player_name = "AI";
    data.is_black_computer = true;
    data.is_auto_playing_black = false;
    return data;
}

/** Крутит главный цикл, пока условие не выполнится (или не истечёт таймаут). */
static bool wait_until (owned GLib.SourceFunc cond, double timeout_sec = 15.0) {
    var ctx = GLib.MainContext.default ();
    var start = GLib.get_monotonic_time ();
    while (!cond ()) {
        if ((GLib.get_monotonic_time () - start) / 1000000.0 > timeout_sec) {
            return false;
        }
        if (!ctx.iteration (false)) {
            GLib.Thread.usleep (2000);
        }
    }
    return true;
}

/** Бросок + один ход + завершение хода (сессия работает в асинхронном режиме). */
static bool play_one_move (GameSession s, CheckerColor color, BoardPoint head) {
    if (!wait_until (() => s.current_player == color && s.can_roll)) {
        stdout.printf ("FAIL: cannot roll for %s\n", color.to_string ());
        return false;
    }
    s.roll_dice ();
    if (!wait_until (() => s.dice_roll != null && !s.is_rolling && !s.is_animating)) {
        stdout.printf ("FAIL: roll did not finish for %s\n", color.to_string ());
        return false;
    }
    if (s.current_player != color) {
        // Ходов не было — ход передан автоматически
        return true;
    }
    var opts = s.options_from (head);
    if (opts.length == 0) {
        // Если с головы нельзя — возьмём любой ход
        for (int r = 1; r <= 24; r++) {
            var o = s.options_from ((BoardPoint) r);
            if (o.length > 0) { opts = o; break; }
        }
    }
    if (opts.length > 0) {
        s.apply_move (opts[0].to, opts[0].from);
    }
    if (!wait_until (() => !s.is_animating)) {
        stdout.printf ("FAIL: move animation stuck for %s\n", color.to_string ());
        return false;
    }
    if (s.current_player == color) {
        s.end_turn ();
    }
    return true;
}

/** Копия логики BoardView.find_turn_record (без GTK). */
static TurnRecord? find_record (GameSession session, int turn_id, out CheckerColor color) {
    foreach (var rec in session.white_turn_log) {
        if (rec.id == turn_id) { color = CheckerColor.WHITE; return rec; }
    }
    foreach (var rec in session.black_turn_log) {
        if (rec.id == turn_id) { color = CheckerColor.BLACK; return rec; }
    }
    color = CheckerColor.WHITE;
    return null;
}
