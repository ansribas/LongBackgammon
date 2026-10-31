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

    // Тест анимации перелёта кубиков розыгрыша (roll-off) в лог: защита от мигания
    var s_rolloff = new GameSession ();
    var panel_w = new PlayerPanel (s_rolloff, CheckerColor.WHITE);
    s_rolloff.is_first_move_rolloff_in_progress = true;
    s_rolloff.white_rolloff_dice = new DiceRoll (4, 6);
    s_rolloff.rolloff_animation_id = 1;
    s_rolloff.changed ();
    if (!panel_w.is_flying (100)) {
        stderr.printf ("FAIL: expected die 100 to be flying immediately\n");
        return 1;
    }
    if (!panel_w.is_pending_fly (101)) {
        stderr.printf ("FAIL: expected die 101 to be pending_fly to prevent flicker in log\n");
        return 1;
    }
    if (!wait_until (() => panel_w.is_flying (101), 2.0)) {
        stderr.printf ("FAIL: expected die 101 to transition to flying after stagger delay\n");
        return 1;
    }
    if (panel_w.is_pending_fly (101)) {
        stderr.printf ("FAIL: expected die 101 not to be pending_fly once flying\n");
        return 1;
    }

    // Проверка центров слотов: и при roll-off, и на обычном ходу расстояние между центрами единообразно равно 53px (spacing=5)
    double ro_x1, ro_y1, ro_x2, ro_y2;
    panel_w.get_dice_slot_centers (out ro_x1, out ro_y1, out ro_x2, out ro_y2);
    var ro_dist = ro_x2 - ro_x1;
    if (Math.fabs (ro_dist - 53.0) > 0.01) {
        stderr.printf ("FAIL: expected roll-off slot centers distance 53.0, got %f\n", ro_dist);
        return 1;
    }

    s_rolloff.is_first_move_rolloff_in_progress = false;
    double norm_x1, norm_y1, norm_x2, norm_y2;
    panel_w.get_dice_slot_centers (out norm_x1, out norm_y1, out norm_x2, out norm_y2);
    var norm_dist = norm_x2 - norm_x1;
    if (Math.fabs (norm_dist - 53.0) > 0.01) {
        stderr.printf ("FAIL: expected normal turn slot centers distance 53.0, got %f\n", norm_dist);
        return 1;
    }

    stderr.printf ("ui_test OK\n");
    return 0;
}
