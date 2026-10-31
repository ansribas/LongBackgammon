using Longbackgammon;
using Gtk;

static bool wait_until (owned GLib.SourceFunc condition, double timeout_sec = 20.0) {
    var context = GLib.MainContext.default ();
    var started = GLib.get_monotonic_time ();
    while (!condition ()) {
        if ((GLib.get_monotonic_time () - started) / 1000000.0 > timeout_sec) {
            return false;
        }
        if (!context.iteration (false)) {
            GLib.Thread.usleep (2000);
        }
    }
    return true;
}

int main (string[] args) {
    Gtk.init ();
    var s = new GameSession ();
    s.board = GameBoard.initial_long ();
    s.is_game_started = true;
    s.current_player = CheckerColor.WHITE;
    s.dice_roll = new DiceRoll (3, 5);
    s.remaining_dice = new int[] { 3, 5 };
    s.is_animating = false;
    s.is_rolling = false;
    s.update_available_moves_cache ();

    if (s.cached_legal_options.length == 0) {
        stderr.printf ("FAIL: no moves after roll\n");
        return 1;
    }

    var view = new BoardView (s);
    var side = 600.0;

    // Клик по фишке P24: должна выбрать её
    double ax, ay;
    BoardLayout.position (BoardPoint.P24, side, out ax, out ay);
    view.handle_board_click_at (ax, ay, 600, 600);
    stderr.printf ("selected=%s\n", s.selected_point == null ? "NULL" : s.selected_point.raw_value ().to_string ());
    if (s.selected_point != BoardPoint.P24) {
        stderr.printf ("FAIL: expected P24 selected\n");
        return 1;
    }

    // Клик по доступной точке P21: должен сходить
    double bx, by;
    BoardLayout.position (BoardPoint.P21, side, out bx, out by);
    view.handle_board_click_at (bx, by, 600, 600);
    var st = s.board.stack_at (BoardPoint.P21);
    stderr.printf ("stack21=%s\n", st == null ? "NULL" : st.checker_ids.length.to_string ());
    if (st == null || st.color != CheckerColor.WHITE || st.checker_ids.length != 1) {
        stderr.printf ("FAIL: move to P21 not applied\n");
        return 1;
    }
    if (!wait_until (() => !s.is_animating)) {
        stderr.printf ("FAIL: move animation did not finish\n");
        return 1;
    }

    // Клик по оставшимся фишкам на голове снова выбирает пункт
    double cx, cy;
    BoardLayout.position (BoardPoint.P24, side, out cx, out cy);
    view.handle_board_click_at (cx, cy, 600, 600);
    stderr.printf ("selected2=%s\n", s.selected_point == null ? "NULL" : s.selected_point.raw_value ().to_string ());
    if (s.selected_point != BoardPoint.P24) {
        stderr.printf ("FAIL: expected remaining checker on P24 to be selected\n");
        return 1;
    }

    // Тест расстановки с подключенным BoardView
    var s_place = new GameSession ();
    var v_place = new BoardView (s_place);
    assert (v_place != null);
    bool done = false;
    s_place.board = GameBoard.in_tray ();
    s_place.animate_placement (GameBoard.initial_long (), false, false, () => {
        done = true;
    });
    if (!wait_until (() => done, 30.0)) {
        stderr.printf ("FAIL: placement timed out\n");
        return 1;
    }

    // Тест анимации смены стороны доски на старте (без сохранения)
    var orig_side = SettingsStore.shared ().board_side;
    SettingsStore.shared ().set_board_side (BoardSide.RIGHT);
    var s_fresh = new GameSession ();
    var v_fresh = new BoardView (s_fresh);
    assert (v_fresh != null);
    // Меняем сторону на LEFT — все 30 фишек должны начать анимацию перемещения
    SettingsStore.shared ().set_board_side (BoardSide.LEFT);
    var moves_count = v_fresh.active_moves_count ();
    stderr.printf ("side_switch active_moves=%d\n", moves_count);
    if (moves_count != 30) {
        stderr.printf ("FAIL: expected 30 active moves during board side switch, got %d\n", moves_count);
        return 1;
    }
    SettingsStore.shared ().set_board_side (orig_side);

    // Тест прогресс-бара: при fraction = 0 полоса заполнения должна быть нулевой ширины
    PanelStyle.ensure_css ();
    var pb = new Gtk.ProgressBar ();
    pb.add_css_class ("lb-progress");
    pb.set_size_request (60, -1);
    pb.set_fraction (0.0);
    pb.allocate (60, 4, -1, null);
    var trough = pb.get_first_child ();
    if (trough != null) {
        var prog = trough.get_first_child ();
        if (prog != null && prog.get_width () != 0) {
            stderr.printf ("FAIL: expected progress bar width 0 at fraction 0.0, got %d\n", prog.get_width ());
            return 1;
        }
    }

    stderr.printf ("ui_test OK\n");
    return 0;
}
