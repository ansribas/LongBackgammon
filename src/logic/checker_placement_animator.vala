namespace Longbackgammon {

/**
 * Анимация физической расстановки фишек на доске:
 * последовательное снятие в накопители (трей) и вылет на пункты доски.
 */
public class CheckerPlacementAnimator {

    private class TrayStep {
        public uint8 id;
        public CheckerColor color;
        public BoardPoint from_point;
        public TrayStep (uint8 id, CheckerColor color, BoardPoint from_point) {
            this.id = id;
            this.color = color;
            this.from_point = from_point;
        }
    }

    private TargetPlacementLocation[] current_placement_targets = new TargetPlacementLocation[0];
    private int current_placement_index = 0;
    private GameBoard? current_placement_target_board = null;
    private bool current_placement_sound = true;
    private bool current_placement_new_game_sound = false;
    private GameSession.PlacementCompletion? current_placement_completion = null;
    private uint placement_timer_id = 0;
    private double placement_start_time = 0.0;

    public void cancel () {
        if (placement_timer_id > 0) {
            Source.remove (placement_timer_id);
            placement_timer_id = 0;
        }
        current_placement_targets = new TargetPlacementLocation[0];
        current_placement_completion = null;
        SoundManager.shared ().stop_placement ();
    }

    /**
     * Анимированно перемещает все находящиеся на доске фишки в накопители.
     */
    public void animate_checkers_to_tray (GameSession session, owned GameSession.PlacementCompletion? completion = null) {
        session.cancel_all_tasks ();
        SoundManager.shared ().stop_placement ();
        var cur_gen = session.gen;

        // Копия доски для моделирования снятия строго сверху стопок (.last)
        var temp_board = session.board.clone ();
        TrayStep[] steps = new TrayStep[0];

        // Белые: обходим пункты по направлению к выходу (от дома к голове: PlayerPath.white reversed)
        var white_points = PlayerPath.white ();
        for (var i = white_points.length - 1; i >= 0; i--) {
            var point = white_points[i];
            var stack = temp_board.stack_at (point);
            while (stack != null && stack.color == CheckerColor.WHITE && stack.checker_ids.length > 0) {
                var top_id = stack.checker_ids[stack.checker_ids.length - 1];
                steps += new TrayStep (top_id, CheckerColor.WHITE, point);
                temp_board.place_checker (top_id, CheckerColor.WHITE, null, temp_board.white_borne_off_ids.length);
                stack = temp_board.stack_at (point);
            }
        }

        // Чёрные: обходим пункты по направлению к выходу (от дома к голове: PlayerPath.black reversed)
        var black_points = PlayerPath.black ();
        for (var i = black_points.length - 1; i >= 0; i--) {
            var point = black_points[i];
            var stack = temp_board.stack_at (point);
            while (stack != null && stack.color == CheckerColor.BLACK && stack.checker_ids.length > 0) {
                var top_id = stack.checker_ids[stack.checker_ids.length - 1];
                steps += new TrayStep (top_id, CheckerColor.BLACK, point);
                temp_board.place_checker (top_id, CheckerColor.BLACK, null, temp_board.black_borne_off_ids.length);
                stack = temp_board.stack_at (point);
            }
        }

        // Если на доске нет фишек (все уже в накопителях) — сразу завершаем
        if (steps.length == 0) {
            session.board = GameBoard.in_tray ();
            session.is_animating = false;
            session.is_placing_checkers = false;
            if (completion != null) {
                var cb = (owned) completion;
                cb ();
            }
            session.notify_changed ();
            return;
        }

        session.is_animating = true;
        session.is_placing_checkers = true;

        SoundManager.shared ().play_dynamic_placement (steps.length, 0.30f);

        var start_time = GLib.get_monotonic_time () / 1000000.0;
        var step_idx = 0;

        placement_timer_id = Timeout.add (8, () => {
            if (cur_gen != session.gen || !session.is_placing_checkers) {
                session.is_placing_checkers = false;
                session.is_animating = false;
                placement_timer_id = 0;
                SoundManager.shared ().stop_placement ();
                return Source.REMOVE;
            }

            var now = GLib.get_monotonic_time () / 1000000.0;
            var elapsed = double.max (0.0, now - start_time);
            int target_count = int.min (
                (int) (elapsed / PlacementAnimation.STEP_INTERVAL) + 1,
                steps.length
            );

            bool changed = false;
            while (step_idx < target_count) {
                var s = steps[step_idx];
                var next_index = (s.color == CheckerColor.WHITE)
                    ? session.board.white_borne_off_ids.length
                    : session.board.black_borne_off_ids.length;
                session.board.place_checker (s.id, s.color, null, next_index);
                step_idx++;
                changed = true;
            }

            if (changed) {
                session.notify_changed ();
            }

            if (step_idx >= steps.length) {
                placement_timer_id = 0;
                session.after (PlacementAnimation.COMPLETION_DELAY, () => {
                    if (cur_gen != session.gen) {
                        session.is_placing_checkers = false;
                        session.is_animating = false;
                        return;
                    }
                    session.board = GameBoard.in_tray ();
                    session.is_animating = false;
                    session.is_placing_checkers = false;
                    if (completion != null) {
                        var cb = (owned) completion;
                        cb ();
                    }
                    session.notify_changed ();
                });
                return Source.REMOVE;
            }

            return Source.CONTINUE;
        });
    }

    /** Анимирует последовательную расстановку фишек на доске. */
    public void animate_placement (
        GameSession session,
        GameBoard target_board,
        bool play_placement_sound = true,
        bool play_new_game_sound_on_completion = false,
        owned GameSession.PlacementCompletion? completion = null
    ) {
        session.cancel_all_tasks ();
        current_placement_completion = (owned) completion;
        var cur_gen = session.gen;
        session.is_animating = true;
        session.is_placing_checkers = true;

        GameBoard effective_target_board;
        if (session.board.is_in_tray ()) {
            effective_target_board = target_board.normalized_for_placement_from_tray ();
        } else {
            effective_target_board = target_board;
        }

        var target_locations = new TargetPlacementLocation?[30];

        for (var raw = 1; raw <= 24; raw++) {
            var stack = effective_target_board.stacks[raw];
            if (stack != null) {
                var pt = BoardPoint.from_raw (raw);
                for (var idx = 0; idx < stack.checker_ids.length; idx++) {
                    var cid = stack.checker_ids[idx];
                    if (cid < 30) {
                        target_locations[cid] = new TargetPlacementLocation (
                            cid,
                            stack.color,
                            pt,
                            idx
                        );
                    }
                }
            }
        }

        for (var idx = 0; idx < effective_target_board.white_borne_off_ids.length; idx++) {
            var cid = effective_target_board.white_borne_off_ids[idx];
            if (cid < 30) {
                target_locations[cid] = new TargetPlacementLocation (
                    cid,
                    CheckerColor.WHITE,
                    null,
                    idx
                );
            }
        }

        for (var idx = 0; idx < effective_target_board.black_borne_off_ids.length; idx++) {
            var cid = effective_target_board.black_borne_off_ids[idx];
            if (cid < 30) {
                target_locations[cid] = new TargetPlacementLocation (
                    cid,
                    CheckerColor.BLACK,
                    null,
                    idx
                );
            }
        }

        TargetPlacementLocation[] moving_targets = new TargetPlacementLocation[0];
        for (uint8 id = 0; id < 30; id++) {
            var tgt = target_locations[id];
            if (tgt != null) {
                BoardPoint? cur_pt;
                int cur_idx;
                var found = session.board.find_checker_location (id, out cur_pt, out cur_idx);
                if (found) {
                    if (cur_pt != tgt.point || cur_idx != tgt.stack_index) {
                        moving_targets += tgt;
                    }
                } else {
                    moving_targets += tgt;
                }
            }
        }

        if (moving_targets.length == 0) {
            session.board = effective_target_board;
            session.is_animating = false;
            session.is_placing_checkers = false;
            if (play_new_game_sound_on_completion) {
                SoundManager.shared ().play_new_game_start ();
            }
            if (current_placement_completion != null) {
                var cb = (owned) current_placement_completion;
                cb ();
            }
            session.notify_changed ();
            return;
        }

        // Сортировка: белые перед чёрными, затем уровень стопки снизу вверх (stack_index), затем id
        for (var i = 0; i < moving_targets.length - 1; i++) {
            for (var j = i + 1; j < moving_targets.length; j++) {
                var a = moving_targets[i];
                var b = moving_targets[j];
                bool swap = false;
                if (a.color != b.color) {
                    swap = (a.color != CheckerColor.WHITE);
                } else if (a.stack_index != b.stack_index) {
                    swap = (a.stack_index > b.stack_index);
                } else {
                    swap = (a.id > b.id);
                }
                if (swap) {
                    moving_targets[i] = b;
                    moving_targets[j] = a;
                }
            }
        }

        current_placement_targets = moving_targets;
        current_placement_index = 0;
        current_placement_target_board = effective_target_board;
        current_placement_sound = play_placement_sound;
        current_placement_new_game_sound = play_new_game_sound_on_completion;

        if (play_placement_sound) {
            SoundManager.shared ().play_dynamic_placement (moving_targets.length, 0.30f);
        }

        placement_start_time = GLib.get_monotonic_time () / 1000000.0;
        start_placement_timer (session, cur_gen);
    }

    private void start_placement_timer (GameSession session, uint token) {
        if (placement_timer_id > 0) {
            Source.remove (placement_timer_id);
            placement_timer_id = 0;
        }

        // Первый шаг выполняем немедленно при t = 0
        tick_placement (session, token);

        placement_timer_id = Timeout.add (8, () => {
            return tick_placement (session, token);
        });
    }

    private bool tick_placement (GameSession session, uint token) {
        if (token != session.gen || !session.is_placing_checkers) {
            session.is_placing_checkers = false;
            placement_timer_id = 0;
            SoundManager.shared ().stop_placement ();
            return Source.REMOVE;
        }

        var now = GLib.get_monotonic_time () / 1000000.0;
        var elapsed = double.max (0.0, now - placement_start_time);

        int target_count = int.min (
            (int) (elapsed / PlacementAnimation.STEP_INTERVAL) + 1,
            current_placement_targets.length
        );

        bool changed = false;
        while (current_placement_index < target_count) {
            var t = current_placement_targets[current_placement_index];
            session.board.place_checker (t.id, t.color, t.point, t.stack_index);
            current_placement_index++;
            changed = true;
        }

        if (changed) {
            session.notify_changed ();
        }

        if (current_placement_index >= current_placement_targets.length) {
            placement_timer_id = 0;
            session.after (PlacementAnimation.COMPLETION_DELAY, () => {
                if (token != session.gen) {
                    session.is_placing_checkers = false;
                    return;
                }
                if (current_placement_target_board != null) {
                    session.board = current_placement_target_board;
                }
                session.is_animating = false;
                session.is_placing_checkers = false;
                if (current_placement_new_game_sound) {
                    SoundManager.shared ().play_new_game_start ();
                }
                if (current_placement_completion != null) {
                    var cb = (owned) current_placement_completion;
                    cb ();
                }
                session.notify_changed ();
            });
            return Source.REMOVE;
        }

        return Source.CONTINUE;
    }
}

} /* namespace Longbackgammon */

