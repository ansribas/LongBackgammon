/* player_panel.vala
 *
 * Боковая панель игрока (PlayerPanel):
 * карточка статуса и кубиков хода, блок очков/прогресса и вертикальный лог партии.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Боковая панель игрока (белых или чёрных):
 * собирает имя, состояние хода, карточку кубиков, карточку очков и историю выполненных ходов.
 */
public class PlayerPanel : Gtk.Box {
    public GameSession session { get; construct set; }
    public CheckerColor color { get; construct set; }
    public double current_board_width = 600.0;

    private Gtk.Overlay overlay;
    private DiceCardBox dice_card;
    private DiceCardMover dice_card_mover;
    private Gtk.Box header_box;
    private Gtk.Label name_label;
    private PlayerDiceZone dice_zone;
    private StatusMessagePlate status_plate;
    private PlayerScoreBlock score_block;
    private Gtk.Box log_card;
    private Gtk.ScrolledWindow log_scroller;
    private Gtk.Box log_list;
    private Gtk.Label footer;
    private FlyingLayer flying_layer;

    private LogCellView? active_cell = null;
    private Gtk.Revealer? active_cell_revealer = null;
    private Gtk.Revealer? result_cell_revealer = null;
    private int animated_result_id = -1;
    private LogCellView[] record_cells = new LogCellView[0];
    private string log_signature = "";
    private int last_log_count = -1;
    private int last_highlighted_log_id = -1;

    // Анимация плавного растворения/истаивания лога при очистке
    private LogCellView[] clearing_cells = new LogCellView[0];
    private Gtk.Revealer? clearing_active_revealer = null;
    private Gtk.Revealer? clearing_result_revealer = null;
    private int64 clear_anim_start_us = 0;
    private uint clear_anim_tick_id = 0;
    private bool is_clearing_log = false;

    // Анимация плавного каскадного появления строк лога при возобновлении партии
    private LogCellView[] restoring_cells = new LogCellView[0];
    private int64 restore_anim_start_us = 0;
    private uint restore_anim_tick_id = 0;
    private bool is_restoring_log = false;

    // Плавная анимация подсветки активного игрока при смене хода
    private uint turn_tick_id = 0;
    private double current_highlight = 0.0;
    private double target_highlight = 0.0;
    private double current_card_opacity = 1.0;
    private double target_card_opacity = 1.0;
    private int64 transition_start_time = 0;
    private double start_highlight = 0.0;
    private double start_opacity = 1.0;
    private bool initialized_transition = false;

    // Анимации перелёта кубиков между верхней зоной и логом
    private FlyingDie[] flying = new FlyingDie[0];
    private int[] flown_rolloff_ids = new int[0];
    private int[] landed_rolloff_ids = new int[0];
    private int[] pending_skipped = new int[0];
    private int[] pending_fly = new int[0];
    private int[] pending_unfly = new int[0];
    private TurnDie[] previous_turn_dice = new TurnDie[0];
    private int last_rolloff_anim_id = 0;
    private uint fly_tick = 0;
    private int64[] skipped_cross_started_us = new int64[4];
    private uint skipped_cross_tick = 0;

    // Анимация обмена местами верхней карточки игрока при перевороте доски
    private BoardSide last_board_side = SettingsStore.shared ().board_side;
    private double swap_start_offset = 0.0;
    private int64 swap_start_us = 0;
    private uint swap_tick_id = 0;

    public PlayerPanel (GameSession session, CheckerColor color) {
        Object (session: session, color: color, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
    }

    construct {
        PanelStyle.ensure_css ();
        set_vexpand (true);
        overflow = Gtk.Overflow.VISIBLE;

        overlay = new Gtk.Overlay ();
        overlay.set_vexpand (true);
        overlay.overflow = Gtk.Overflow.VISIBLE;
        append (overlay);

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 7);
        content.margin_top = 10;
        content.margin_bottom = 10;
        content.margin_start = 10;
        content.margin_end = 10;
        content.set_vexpand (true);
        content.overflow = Gtk.Overflow.VISIBLE;
        overlay.set_child (content);

        // 1. Карточка кубиков и текущего статуса
        dice_card = new DiceCardBox ();

        header_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        header_box.add_css_class ("lb-header-strip");
        header_box.set_size_request (-1, 36);

        name_label = new Gtk.Label ("");
        name_label.add_css_class ("lb-subheadline-bold");
        name_label.add_css_class ("lb-secondary");
        name_label.valign = Gtk.Align.CENTER;
        name_label.halign = Gtk.Align.CENTER;
        name_label.yalign = 0.5f;
        name_label.xalign = 0.5f;
        name_label.vexpand = true;
        name_label.hexpand = true;
        name_label.margin_start = 8;
        name_label.margin_end = 8;
        name_label.single_line_mode = true;
        name_label.ellipsize = Pango.EllipsizeMode.END;
        UiKit.attach_instant_tooltip (name_label);
        header_box.append (name_label);
        dice_card.append (header_box);

        dice_zone = new PlayerDiceZone (this);
        dice_zone.margin_bottom = 6;
        dice_card.append (dice_zone);

        status_plate = new StatusMessagePlate ();
        dice_card.append (status_plate);
        dice_card_mover = new DiceCardMover (dice_card);
        content.append (dice_card_mover);

        // 2. Карточка счёта и прогресса
        score_block = new PlayerScoreBlock (this);
        content.append (score_block);

        // 3. Скроллер истории ходов
        log_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
        log_card.add_css_class ("lb-card");
        log_card.add_css_class ("lb-card-padded");
        log_card.set_vexpand (true);
        log_scroller = new Gtk.ScrolledWindow ();
        log_scroller.add_css_class ("lb-log-scroller");
        log_scroller.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.EXTERNAL);
        log_scroller.set_vexpand (true);
        var vsb = log_scroller.get_vscrollbar ();
        if (vsb != null) {
            vsb.set_visible (false);
        }

        var scroll_ctrl = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL | Gtk.EventControllerScrollFlags.BOTH_AXES);
        scroll_ctrl.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
        scroll_ctrl.scroll.connect ((dx, dy) => {
            var adj = log_scroller.get_vadjustment ();
            var new_val = double.min (adj.get_upper () - adj.get_page_size (), double.max (adj.get_lower (), adj.get_value () + dy * 35.0));
            adj.set_value (new_val);
            return true;
        });
        log_scroller.add_controller (scroll_ctrl);
        log_list = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
        log_list.valign = Gtk.Align.START;
        log_scroller.set_child (log_list);
        log_card.append (log_scroller);
        footer = new Gtk.Label ("");
        footer.add_css_class ("lb-caption2-bold");
        footer.add_css_class ("lb-tertiary");
        footer.margin_top = 2;
        log_card.append (footer);
        content.append (log_card);

        log_scroller.get_vadjustment ().value_changed.connect (() => {
            foreach (var c in all_cells ()) {
                if (c.is_hovered ()) {
                    c.update_tooltip_position ();
                }
            }
            flying_layer.queue_draw ();
        });

        // 4. Оверлей анимации перелёта костей
        flying_layer = new FlyingLayer (this);
        overlay.add_overlay (flying_layer);

        // Клик по нейтральному фону панели отменяет выбор фишки на доске
        var bg_click = new Gtk.GestureClick ();
        bg_click.released.connect (() => { session.select_point_none (); });
        add_controller (bg_click);

        session.changed.connect (on_session_changed);
        session.clearing_logs_animated.connect (start_log_clearing_animation);
        session.restoring_logs_animated.connect (start_log_restoring_animation);
        SettingsStore.shared ().changed.connect (() => {
            var cur_side = SettingsStore.shared ().board_side;
            if (cur_side != last_board_side) {
                last_board_side = cur_side;
                start_name_swap_animation ();
            }
            on_session_changed ();
            foreach (var c in all_cells ()) {
                c.queue_draw ();
            }
        });
        on_session_changed ();
    }

    private void start_name_swap_animation () {
        var pw = get_width () > 0 ? (double) get_width () : (double) (GameConfig.CONTROL_PANEL_WIDTH / 2);
        var bw = current_board_width > 0 ? current_board_width : 600.0;
        var swap_distance = bw + pw;
        var is_left_panel = !BoardLayout.is_player_on_right_side (color);
        swap_start_offset = is_left_panel ? swap_distance : -swap_distance;
        dice_card_mover.offset_x = swap_start_offset;
        swap_start_us = frame_now_us ();
        if (swap_tick_id == 0) {
            swap_tick_id = add_tick_callback (on_swap_tick);
        }
        dice_card_mover.queue_draw ();
    }

    private bool on_swap_tick (Gtk.Widget w, Gdk.FrameClock clock) {
        var ft = clock.get_frame_time ();
        var now = ft > 0 ? ft : GLib.get_monotonic_time ();
        var elapsed = double.max (0.0, (now - swap_start_us) / 1000000.0);
        var total_duration = 1.00;
        if (elapsed >= total_duration) {
            dice_card_mover.offset_x = 0.0;
            dice_card_mover.queue_draw ();
            swap_tick_id = 0;
            return GLib.Source.REMOVE;
        }
        var p = PanelStyle.ease_in_out (elapsed / total_duration);
        dice_card_mover.offset_x = swap_start_offset * (1.0 - p);
        dice_card_mover.queue_draw ();
        return GLib.Source.CONTINUE;
    }

    /** Вычисляет координаты центров слотов кубиков в локальной системе координат PlayerPanel. */
    public void get_dice_slot_centers (out double x1, out double y1, out double x2, out double y2) {
        Graphene.Rect b;
        if (dice_zone.compute_bounds (this, out b) && b.get_width () > 20) {
            var r0 = dice_zone.top_slot_rect (0, 2);
            var r1 = dice_zone.top_slot_rect (1, 2);
            x1 = b.get_x () + r0.get_x () + r0.get_width () / 2.0;
            y1 = b.get_y () + r0.get_y () + r0.get_height () / 2.0;
            x2 = b.get_x () + r1.get_x () + r1.get_width () / 2.0;
            y2 = b.get_y () + r1.get_y () + r1.get_height () / 2.0;
            return;
        }
        x1 = 43.5;
        y1 = 82.0;
        x2 = 96.5;
        y2 = 82.0;
    }

    /** Проверяет, активна ли панель текущего игрока. */
    public bool is_active () {
        if (!session.is_game_in_progress) {
            return false;
        }
        if (session.is_first_move_rolloff_in_progress) {
            if (color == CheckerColor.WHITE && session.white_rolloff_dice != null) {
                return true;
            }
            if (color == CheckerColor.BLACK && session.black_rolloff_dice != null) {
                return true;
            }
            if (session.rolloff_active_player != null) {
                return session.rolloff_active_player == color;
            }
            return true;
        }
        return session.current_player == color;
    }

    private bool is_my_turn_to_act () {
        if (!session.is_game_in_progress) {
            return false;
        }
        if (session.is_first_move_rolloff_in_progress) {
            return session.rolloff_active_player == color;
        }
        return session.current_player == color;
    }

    public bool has_flown_rolloff (int id) {
        return ArrUtil.contains_int (flown_rolloff_ids, id);
    }

    public bool has_landed_rolloff (int id) {
        return ArrUtil.contains_int (landed_rolloff_ids, id);
    }

    public int get_log_cell_width () {
        if (log_list != null && log_list.get_width () > 0) {
            return log_list.get_width ();
        }
        if (log_scroller != null && log_scroller.get_width () > 0) {
            return log_scroller.get_width ();
        }
        return get_width () > 32 ? get_width () - 32 : 114;
    }

    public bool is_flying (int id) {
        foreach (var f in flying) {
            if (f.id == id) {
                return true;
            }
        }
        return false;
    }

    public bool is_pending_skip (int id) {
        return ArrUtil.contains_int (pending_skipped, id);
    }

    public bool is_pending_fly (int id) {
        return ArrUtil.contains_int (pending_fly, id);
    }

    public bool is_pending_unfly (int id) {
        return ArrUtil.contains_int (pending_unfly, id);
    }

    private void queue_draw_top_cells () {
        if (active_cell != null) {
            active_cell.queue_draw ();
        }
        if (record_cells.length > 0) {
            record_cells[0].queue_draw ();
        }
    }

    public void add_pending_fly (int id) {
        if (!is_pending_fly (id)) {
            pending_fly += id;
            dice_zone.queue_draw ();
            queue_draw_top_cells ();
        }
    }

    public void remove_pending_fly (int id) {
        pending_fly = ArrUtil.remove_int (pending_fly, id);
        dice_zone.queue_draw ();
        queue_draw_top_cells ();
    }

    public void add_pending_unfly (int id) {
        if (!is_pending_unfly (id)) {
            pending_unfly += id;
            dice_zone.queue_draw ();
            queue_draw_top_cells ();
        }
    }

    public void remove_pending_unfly (int id) {
        pending_unfly = ArrUtil.remove_int (pending_unfly, id);
        dice_zone.queue_draw ();
        queue_draw_top_cells ();
    }

    private TurnRecord[] my_log () {
        return color == CheckerColor.WHITE ? session.white_turn_log : session.black_turn_log;
    }

    private bool shows_active_cell () {
        return session.current_player == color && session.current_turn_dice.length > 0
               && !session.is_first_move_rolloff_in_progress && !session.is_game_over;
    }

    private LogCellView[] all_cells () {
        var r = new LogCellView[0];
        if (active_cell != null) {
            r += active_cell;
        }
        foreach (var c in record_cells) {
            r += c;
        }
        return r;
    }

    private void on_session_changed () {
        var full_name = color == CheckerColor.WHITE ? session.white_player_name : session.black_player_name;
        UiKit.set_name_label_text (name_label, full_name);
        var active = is_active ();
        var my_turn = is_my_turn_to_act ();
        var is_game_in_progress = session.is_game_in_progress;

        var new_target_opacity = is_game_in_progress ? (active ? 1.0 : 0.6) : 1.0;
        var new_target_highlight = my_turn ? 1.0 : 0.0;

        if (!initialized_transition) {
            initialized_transition = true;
            target_card_opacity = new_target_opacity;
            current_card_opacity = new_target_opacity;
            target_highlight = new_target_highlight;
            current_highlight = new_target_highlight;
            dice_card.opacity = current_card_opacity;
            dice_card.highlight = current_highlight;
            dice_card.queue_draw ();
        } else if (new_target_opacity != target_card_opacity || new_target_highlight != target_highlight) {
            target_card_opacity = new_target_opacity;
            target_highlight = new_target_highlight;
            start_opacity = current_card_opacity;
            start_highlight = current_highlight;
            transition_start_time = GLib.get_monotonic_time ();
            if (turn_tick_id == 0) {
                turn_tick_id = add_tick_callback (on_turn_transition_tick);
            }
        }

        if (my_turn) {
            header_box.remove_css_class ("lb-header-strip");
            header_box.add_css_class ("lb-header-strip-active");
            name_label.remove_css_class ("lb-secondary");
            name_label.add_css_class ("lb-orange");
        } else {
            header_box.remove_css_class ("lb-header-strip-active");
            header_box.add_css_class ("lb-header-strip");
            name_label.remove_css_class ("lb-orange");
            name_label.add_css_class ("lb-secondary");
        }

        string current_status_msg = "";
        if (session.is_game_in_progress) {
            if (session.is_first_move_rolloff_in_progress && session.rolloff_active_player == null) {
                current_status_msg = session.status_message;
            } else if (my_turn) {
                if (!session.is_computer_turn && session.is_rolling) {
                    current_status_msg = "";
                } else {
                    current_status_msg = session.status_message;
                }
            }
        }
        var is_doubling_for_plate = session.is_doubling && (session.dice_roll != null && session.dice_roll.is_double) && my_turn;
        status_plate.update_state (current_status_msg, is_doubling_for_plate, active, my_turn);
        dice_zone.queue_draw ();

        // При броске костей автоматически прокручиваем лог к началу
        if (session.is_rolling && session.current_player == color && !session.is_first_move_rolloff_in_progress) {
            var adj = log_scroller.get_vadjustment ();
            adj.set_value (adj.get_lower ());
        }

        rebuild_log_if_needed ();
        handle_dice_state_change ();
        var my_rd = color == CheckerColor.WHITE ? session.white_rolloff_dice : session.black_rolloff_dice;
        if ((my_rd == null || !session.is_first_move_rolloff_in_progress) && (flown_rolloff_ids.length > 0 || landed_rolloff_ids.length > 0)) {
            flown_rolloff_ids = new int[0];
            landed_rolloff_ids = new int[0];
        }
        if (session.rolloff_animation_id != last_rolloff_anim_id) {
            last_rolloff_anim_id = session.rolloff_animation_id;
            flown_rolloff_ids = new int[0];
            landed_rolloff_ids = new int[0];
            if (session.rolloff_animation_id != 0) {
                if (my_rd != null) {
                    animate_rolloff_dice_to_log (my_rd);
                }
            } else {
                remove_pending_fly (100);
                remove_pending_fly (101);
            }
        }
        dice_zone.queue_draw ();
        queue_draw_top_cells ();
        if (session.highlighted_log_id != last_highlighted_log_id) {
            foreach (var c in record_cells) {
                var rid = c.record_id ();
                if (rid == session.highlighted_log_id || rid == last_highlighted_log_id) {
                    c.queue_draw ();
                }
            }
            last_highlighted_log_id = session.highlighted_log_id;
        }
        update_footer ();
        if (flying.length > 0) {
            flying_layer.queue_draw ();
        }
    }

    private string compute_records_signature (TurnRecord[] log) {
        var sb = new StringBuilder ();
        foreach (var r in log) {
            sb.append_printf ("%d;", r.id);
        }
        return sb.str;
    }

    private void rebuild_log_if_needed () {
        if (is_clearing_log) {
            if (my_log ().length > 0) {
                finish_log_clearing ();
            } else {
                return;
            }
        }
        if (is_restoring_log) {
            if (my_log ().length == 0) {
                finish_log_restoring ();
            } else {
                return;
            }
        }

        var should_show_active = shows_active_cell ();
        if (should_show_active) {
            if (active_cell == null) {
                active_cell = new LogCellView (this, null, true);
                active_cell_revealer = new Gtk.Revealer ();
                active_cell_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
                active_cell_revealer.transition_duration = 240;
                active_cell_revealer.set_child (active_cell);
                active_cell_revealer.reveal_child = false;
                log_list.prepend (active_cell_revealer);
                var rev = active_cell_revealer;
                Idle.add (() => {
                    if (rev != null) {
                        rev.reveal_child = true;
                    }
                    return Source.REMOVE;
                });
            } else {
                active_cell.set_content_height ((int) active_cell.compute_height ());
            }
        } else {
            if (active_cell_revealer != null) {
                log_list.remove (active_cell_revealer);
                active_cell_revealer = null;
                active_cell = null;
            }
        }

        var log = my_log ();
        var sig = compute_records_signature (log);
        if (sig == log_signature) {
            return;
        }
        log_signature = sig;

        // Проверяем возможность инкрементального добавления новых записей в начало списка
        var can_prepend = false;
        var added_count = log.length - record_cells.length;
        if (record_cells.length > 0 && added_count > 0 && result_cell_revealer == null) {
            can_prepend = true;
            for (var i = 0; i < record_cells.length; i++) {
                if (record_cells[i].record == null || record_cells[i].record.id != log[added_count + i].id) {
                    can_prepend = false;
                    break;
                }
            }
        }

        if (can_prepend) {
            record_cells[0].queue_draw ();
            var new_cells = new LogCellView[log.length];
            for (var i = 0; i < record_cells.length; i++) {
                new_cells[added_count + i] = record_cells[i];
            }
            for (var k = added_count - 1; k >= 0; k--) {
                var r = log[k];
                var cell = new LogCellView (this, r, false);
                new_cells[k] = cell;
                if (r.game_result_is_win != null && r.id != animated_result_id) {
                    animated_result_id = r.id;
                    result_cell_revealer = new Gtk.Revealer ();
                    result_cell_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
                    result_cell_revealer.transition_duration = 280;
                    result_cell_revealer.set_child (cell);
                    result_cell_revealer.reveal_child = false;
                    log_list.insert_child_after (result_cell_revealer, active_cell_revealer);
                    var rev = result_cell_revealer;
                    Idle.add (() => {
                        if (rev != null) {
                            rev.reveal_child = true;
                        }
                        return Source.REMOVE;
                    });
                } else {
                    log_list.insert_child_after (cell, active_cell_revealer);
                }
            }
            record_cells = new_cells;
        } else {
            if (result_cell_revealer != null) {
                if (result_cell_revealer.get_parent () == log_list) {
                    log_list.remove (result_cell_revealer);
                }
                result_cell_revealer = null;
            }
            foreach (var c in record_cells) {
                if (c.get_parent () == log_list) {
                    log_list.remove (c);
                }
            }
            record_cells = new LogCellView[0];
            if (log.length == 0 || log[0].game_result_is_win == null) {
                animated_result_id = -1;
            }
            foreach (var r in log) {
                var cell = new LogCellView (this, r, false);
                record_cells += cell;
                if (r.game_result_is_win != null && r.id != animated_result_id) {
                    animated_result_id = r.id;
                    result_cell_revealer = new Gtk.Revealer ();
                    result_cell_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
                    result_cell_revealer.transition_duration = 280;
                    result_cell_revealer.set_child (cell);
                    result_cell_revealer.reveal_child = false;
                    log_list.append (result_cell_revealer);
                    var rev = result_cell_revealer;
                    Idle.add (() => {
                        if (rev != null) {
                            rev.reveal_child = true;
                        }
                        return Source.REMOVE;
                    });
                } else {
                    log_list.append (cell);
                }
            }
        }

        var count = log.length;
        if (count != last_log_count) {
            last_log_count = count;
            Idle.add (() => {
                var adj = log_scroller.get_vadjustment ();
                adj.value = adj.lower;
                return Source.REMOVE;
            });
        }
    }

    private void update_footer () {
        if (is_clearing_log || is_restoring_log) {
            return;
        }
        if (session.is_first_move_rolloff_in_progress || !session.is_game_started) {
            footer.visible = false;
            return;
        }
        footer.visible = true;
        var completed = 0;
        foreach (var r in my_log ()) {
            if (!r.is_rolloff && r.game_result_is_win == null) {
                completed++;
            }
        }
        var turn_number = (session.current_player == color && !session.is_game_over) ? completed + 1 : int.max (1, completed);
        footer.label = Localization.badge_turn_number (turn_number);
    }

    /** Запуск плавной каскадной анимации растворения записей лога при очистке. */
    public void start_log_clearing_animation () {
        if (is_clearing_log) {
            finish_log_clearing ();
        }
        var cells = all_cells ();
        if (cells.length == 0) {
            update_footer ();
            return;
        }

        // Скрываем активную подсказку
        var st = LogTooltipState.shared ();
        if (st.hovered_side == (int) color) {
            st.hovered_side = -1;
            st.changed ();
        }

        is_clearing_log = true;
        clearing_cells = cells;
        clearing_active_revealer = active_cell_revealer;
        clearing_result_revealer = result_cell_revealer;

        active_cell = null;
        active_cell_revealer = null;
        result_cell_revealer = null;
        animated_result_id = -1;
        record_cells = new LogCellView[0];
        log_signature = "";
        last_log_count = 0;

        clear_anim_start_us = 0;
        if (clear_anim_tick_id == 0) {
            clear_anim_tick_id = add_tick_callback (on_clear_anim_tick);
        }
    }

    private bool on_clear_anim_tick (Gtk.Widget widget, Gdk.FrameClock clock) {
        var ft = clock.get_frame_time ();
        var now = ft > 0 ? ft : GLib.get_monotonic_time ();
        if (clear_anim_start_us == 0) {
            clear_anim_start_us = now;
            return GLib.Source.CONTINUE;
        }

        var count = clearing_cells.length;
        if (count == 0) {
            finish_log_clearing ();
            return GLib.Source.REMOVE;
        }

        var elapsed = (now - clear_anim_start_us) / 1000000.0;
        const double CELL_DURATION = 0.56;
        var step_delay = double.min (0.060, 0.700 / double.max (1, count));
        var total_duration = (count - 1) * step_delay + CELL_DURATION;

        for (var i = 0; i < count; i++) {
            var cell = clearing_cells[i];
            var start = i * step_delay;
            if (elapsed < start) {
                cell.set_clearing_fx (1.0, 0.0, 1.0);
            } else {
                var t = double.min (1.0, (elapsed - start) / CELL_DURATION);
                var ease = UiKit.ease_out (t);
                var opacity = double.max (0.0, 1.0 - ease);
                var offset_y = -ease * 18.0;
                var scale = 1.0 - ease * 0.05;
                cell.set_clearing_fx (opacity, offset_y, scale);
            }
        }

        if (footer.visible) {
            var f_t = double.min (1.0, elapsed / 0.50);
            footer.opacity = double.max (0.0, 1.0 - UiKit.ease_out (f_t));
        }

        if (elapsed >= total_duration) {
            finish_log_clearing ();
            return GLib.Source.REMOVE;
        }

        return GLib.Source.CONTINUE;
    }

    private void finish_log_clearing () {
        if (clear_anim_tick_id != 0) {
            remove_tick_callback (clear_anim_tick_id);
            clear_anim_tick_id = 0;
        }
        if (clearing_active_revealer != null) {
            if (clearing_active_revealer.get_parent () == log_list) {
                log_list.remove (clearing_active_revealer);
            }
            clearing_active_revealer = null;
        }
        if (clearing_result_revealer != null) {
            if (clearing_result_revealer.get_parent () == log_list) {
                log_list.remove (clearing_result_revealer);
            }
            clearing_result_revealer = null;
        }
        foreach (var c in clearing_cells) {
            if (c.get_parent () == log_list) {
                log_list.remove (c);
            }
        }
        clearing_cells = new LogCellView[0];
        is_clearing_log = false;
        footer.opacity = 1.0;
        footer.visible = false;
        var adj = log_scroller.get_vadjustment ();
        adj.value = adj.lower;
    }

    /** Запуск плавной каскадной анимации появления записей лога при возобновлении партии. */
    public void start_log_restoring_animation () {
        if (is_clearing_log) {
            finish_log_clearing ();
        }
        if (is_restoring_log) {
            finish_log_restoring ();
        }
        var cells = all_cells ();
        if (cells.length == 0) {
            update_footer ();
            return;
        }

        is_restoring_log = true;
        restoring_cells = cells;
        restore_anim_start_us = 0;

        if (active_cell_revealer != null) {
            active_cell_revealer.reveal_child = true;
        }
        if (result_cell_revealer != null) {
            result_cell_revealer.reveal_child = true;
        }

        foreach (var c in cells) {
            c.set_clearing_fx (0.0, -18.0, 0.95);
        }
        if (footer.visible) {
            footer.opacity = 0.0;
        }

        var adj = log_scroller.get_vadjustment ();
        adj.value = adj.lower;

        if (restore_anim_tick_id == 0) {
            restore_anim_tick_id = add_tick_callback (on_restore_anim_tick);
        }
    }

    private bool on_restore_anim_tick (Gtk.Widget widget, Gdk.FrameClock clock) {
        var ft = clock.get_frame_time ();
        var now = ft > 0 ? ft : GLib.get_monotonic_time ();
        if (restore_anim_start_us == 0) {
            restore_anim_start_us = now;
            return GLib.Source.CONTINUE;
        }

        var count = restoring_cells.length;
        if (count == 0) {
            finish_log_restoring ();
            return GLib.Source.REMOVE;
        }

        var elapsed = (now - restore_anim_start_us) / 1000000.0;
        const double CELL_DURATION = 0.56;
        var step_delay = double.min (0.060, 0.700 / double.max (1, count));
        var total_duration = (count - 1) * step_delay + CELL_DURATION;

        for (var i = 0; i < count; i++) {
            var cell = restoring_cells[i];
            var start = i * step_delay;
            if (elapsed < start) {
                cell.set_clearing_fx (0.0, -18.0, 0.95);
            } else {
                var t = double.min (1.0, (elapsed - start) / CELL_DURATION);
                var ease = UiKit.ease_out (t);
                var opacity = ease;
                var offset_y = -18.0 * (1.0 - ease);
                var scale = 0.95 + ease * 0.05;
                cell.set_clearing_fx (opacity, offset_y, scale);
            }
        }

        if (footer.visible) {
            var f_t = double.min (1.0, elapsed / 0.50);
            footer.opacity = UiKit.ease_out (f_t);
        }

        if (elapsed >= total_duration) {
            finish_log_restoring ();
            return GLib.Source.REMOVE;
        }

        return GLib.Source.CONTINUE;
    }

    private void finish_log_restoring () {
        if (restore_anim_tick_id != 0) {
            remove_tick_callback (restore_anim_tick_id);
            restore_anim_tick_id = 0;
        }
        foreach (var c in restoring_cells) {
            c.set_clearing_fx (1.0, 0.0, 1.0);
        }
        restoring_cells = new LogCellView[0];
        is_restoring_log = false;
        footer.opacity = 1.0;
        update_footer ();
    }

    private void handle_dice_state_change () {
        if (!session.is_game_started) {
            flying = new FlyingDie[0];
            flown_rolloff_ids = new int[0];
            landed_rolloff_ids = new int[0];
            pending_skipped = new int[0];
            pending_fly = new int[0];
            pending_unfly = new int[0];
            previous_turn_dice = new TurnDie[0];
            for (var i = 0; i < skipped_cross_started_us.length; i++) {
                skipped_cross_started_us[i] = 0;
            }
            return;
        }
        var new_dice = session.current_turn_dice;
        if (session.current_player != color) {
            previous_turn_dice = TurnDie.clone_array (new_dice);
            return;
        }
        if (new_dice.length == 0) {
            remove_non_rolloff_flying ();
            pending_skipped = new int[0];
            remove_non_rolloff_pending_fly ();
            pending_unfly = new int[0];
            previous_turn_dice = new TurnDie[0];
            for (var i = 0; i < skipped_cross_started_us.length; i++) {
                skipped_cross_started_us[i] = 0;
            }
            return;
        }
        if (previous_turn_dice.length == 0 || previous_turn_dice.length != new_dice.length) {
            previous_turn_dice = TurnDie.clone_array (new_dice);
            pending_skipped = new int[0];
            remove_non_rolloff_pending_fly ();
            pending_unfly = new int[0];
            for (var i = 0; i < skipped_cross_started_us.length; i++) {
                skipped_cross_started_us[i] = 0;
            }
            return;
        }

        var to_log = new TurnDie[0];
        var from_log = new TurnDie[0];
        for (var i = 0; i < new_dice.length; i++) {
            var prev = previous_turn_dice[i];
            var nd = new_dice[i];
            var became_used = !prev.is_used && nd.is_used;
            var became_skipped = !prev.is_skipped && nd.is_skipped;
            if (became_skipped) {
                pending_skipped += nd.id;
                start_skipped_cross_animation (nd.id);
            }
            if (became_used || became_skipped) {
                to_log += nd.clone ();
            } else if (prev.is_used && !nd.is_used) {
                from_log += nd.clone ();
            }
        }
        previous_turn_dice = TurnDie.clone_array (new_dice);

        if (to_log.length > 0) {
            var adj = log_scroller.get_vadjustment ();
            adj.set_value (adj.get_lower ());
        }

        for (var s = 0; s < to_log.length; s++) {
            var die = to_log[s];
            var stagger = s * 0.08;
            if (die.is_skipped) {
                var pause = SettingsStore.shared ().animation_speed.intermediate_step_delay;
                var skip_delay = pause + stagger;
                Timeout.add ((uint) (skip_delay * 1000), () => {
                    if (!is_pending_skip (die.id)) {
                        return Source.REMOVE;
                    }
                    remove_pending (die.id);
                    start_flying (die.id, die.value, true, true);
                    return Source.REMOVE;
                });
            } else if (stagger > 0) {
                add_pending_fly (die.id);
                Timeout.add ((uint) (stagger * 1000), () => {
                    if (!is_pending_fly (die.id)) {
                        return Source.REMOVE;
                    }
                    remove_pending_fly (die.id);
                    start_flying (die.id, die.value, true, false);
                    return Source.REMOVE;
                });
            } else {
                start_flying (die.id, die.value, true, false);
            }
        }
        for (var s = 0; s < from_log.length; s++) {
            var die = from_log[s];
            var delay = s * 0.08;
            if (delay > 0) {
                add_pending_unfly (die.id);
                Timeout.add ((uint) (delay * 1000), () => {
                    if (!is_pending_unfly (die.id)) {
                        return Source.REMOVE;
                    }
                    remove_pending_unfly (die.id);
                    start_flying (die.id, die.value, false, false);
                    return Source.REMOVE;
                });
            } else {
                start_flying (die.id, die.value, false, false);
            }
        }
    }

    private void remove_pending (int id) {
        pending_skipped = ArrUtil.remove_int (pending_skipped, id);
        dice_zone.queue_draw ();
        queue_draw_top_cells ();
    }

    private void remove_non_rolloff_flying () {
        var r = new FlyingDie[0];
        foreach (var f in flying) {
            if (f.id >= 100) {
                r += f;
            }
        }
        flying = r;
    }

    private void remove_non_rolloff_pending_fly () {
        var r = new int[0];
        foreach (var p in pending_fly) {
            if (p >= 100) {
                r += p;
            }
        }
        pending_fly = r;
    }

    private void animate_rolloff_dice_to_log (DiceRoll dice) {
        var adj = log_scroller.get_vadjustment ();
        adj.set_value (adj.get_lower ());
        int[] values = { dice.die1, dice.die2 };
        for (var idx = 0; idx < 2; idx++) {
            var fly_id = idx == 0 ? 100 : 101;
            var val = values[idx];
            if (idx == 0) {
                if (!has_flown_rolloff (fly_id)) {
                    flown_rolloff_ids += fly_id;
                }
                start_flying (fly_id, val, true, false);
            } else {
                add_pending_fly (fly_id);
                Timeout.add (80, () => {
                    remove_pending_fly (fly_id);
                    if (session.rolloff_animation_id != 0) {
                        if (!has_flown_rolloff (fly_id)) {
                            flown_rolloff_ids += fly_id;
                        }
                        start_flying (fly_id, val, true, false);
                    }
                    return Source.REMOVE;
                });
            }
        }
    }

    private Graphene.Rect fallback_slot_rect (int id, bool top) {
        var is_dbl = id < 100 && ((session.dice_roll != null && session.dice_roll.is_double) || session.current_turn_dice.length > 2);
        var pw = (double) get_width ();
        var size = top ? (is_dbl ? 34.0 : 48.0) : 40.0;
        var spacing = top ? 5.0 : (is_dbl ? 5.0 : 6.0);
        var start_x = (pw - (size * 2 + spacing)) / 2.0;
        var base_y = top ? 48.0 : (id >= 100 ? 262.0 : 250.0);
        var dbl_base_y = top ? 40.0 : 255.0;

        if (id >= 100) {
            var idx = id == 100 ? 0 : 1;
            var x = start_x + idx * (size + spacing);
            return Graphene.Rect ().init ((float) x, (float) base_y, (float) size, (float) size);
        }
        if (is_dbl) {
            var row = id / 2;
            var col = id % 2;
            var x = start_x + col * (size + spacing);
            var y = dbl_base_y + row * (size + 3);
            return Graphene.Rect ().init ((float) x, (float) y, (float) size, (float) size);
        } else {
            var x = start_x + id * (size + spacing);
            return Graphene.Rect ().init ((float) x, (float) base_y, (float) size, (float) size);
        }
    }

    private int64 frame_now_us () {
        return GLib.get_monotonic_time ();
    }

    private void start_flying (int id, int value, bool to_log, bool is_skipped) {
        var r = new FlyingDie[0];
        foreach (var f in flying) {
            if (f.id != id) {
                r += f;
            }
        }
        var fd = new FlyingDie ();
        fd.id = id;
        fd.value = value;
        fd.to_log = to_log;
        fd.is_skipped = is_skipped;
        fd.start_us = frame_now_us ();
        var dur = SettingsStore.shared ().animation_speed.checker_move_duration;
        fd.duration = dur > 0.05 ? dur : 0.35;

        Graphene.Rect top_r;
        Graphene.Rect log_r;
        var ok_top = slot_rect (id, true, out top_r);
        var ok_log = slot_rect (id, false, out log_r);
        if (!ok_top) {
            top_r = fallback_slot_rect (id, true);
        }
        if (!ok_log) {
            log_r = fallback_slot_rect (id, false);
        }

        fd.from_rect = to_log ? top_r : log_r;
        fd.to_rect = to_log ? log_r : top_r;

        r += fd;
        flying = r;
        dice_zone.queue_draw ();
        if (active_cell != null) {
            active_cell.queue_draw ();
        }
        if (record_cells.length > 0) {
            record_cells[0].queue_draw ();
        }
        if (fly_tick == 0) {
            fly_tick = add_tick_callback (on_fly_tick);
        }
    }

    /** Прогресс анимации появления перечёркивания кубика (0.0..1.0 за 250мс). */
    public double skipped_cross_progress (int id) {
        if (id < 0 || id >= skipped_cross_started_us.length || skipped_cross_started_us[id] == 0) {
            return 1.0;
        }
        var t = (frame_now_us () - skipped_cross_started_us[id]) / 250000.0;
        t = double.max (0.0, double.min (1.0, t));
        return UiKit.ease_out (t);
    }

    private void start_skipped_cross_animation (int id) {
        if (id < 0 || id >= skipped_cross_started_us.length) {
            return;
        }
        skipped_cross_started_us[id] = frame_now_us ();
        if (skipped_cross_tick == 0) {
            skipped_cross_tick = dice_zone.add_tick_callback (on_skipped_cross_tick);
        }
    }

    private bool on_skipped_cross_tick (Gtk.Widget widget, Gdk.FrameClock clock) {
        dice_zone.queue_draw ();
        var ft = clock.get_frame_time ();
        var now = ft > 0 ? ft : GLib.get_monotonic_time ();
        foreach (var started in skipped_cross_started_us) {
            if (started != 0 && now - started < 250000) {
                return GLib.Source.CONTINUE;
            }
        }
        skipped_cross_tick = 0;
        return GLib.Source.REMOVE;
    }

    private bool on_turn_transition_tick (Gtk.Widget w, Gdk.FrameClock clock) {
        var now = clock.get_frame_time ();
        var elapsed_s = (now - transition_start_time) / 1000000.0;
        var duration = 0.25; // 250 мс для сглаженного перехода хода
        var progress = double.min (1.0, double.max (0.0, elapsed_s / duration));

        var ease = progress < 0.5 ? 2.0 * progress * progress : 1.0 - Math.pow (-2.0 * progress + 2.0, 2) / 2.0;

        current_highlight = start_highlight + (target_highlight - start_highlight) * ease;
        current_card_opacity = start_opacity + (target_card_opacity - start_opacity) * ease;

        dice_card.opacity = current_card_opacity;
        dice_card.highlight = current_highlight;
        dice_card.queue_draw ();

        if (progress >= 1.0) {
            current_highlight = target_highlight;
            current_card_opacity = target_card_opacity;
            dice_card.opacity = current_card_opacity;
            dice_card.highlight = current_highlight;
            dice_card.queue_draw ();
            turn_tick_id = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    private bool on_fly_tick (Gtk.Widget w, Gdk.FrameClock clock) {
        var ft = clock.get_frame_time ();
        var now = ft > 0 ? ft : GLib.get_monotonic_time ();
        var r = new FlyingDie[0];
        var removed = false;
        foreach (var f in flying) {
            if (f.to_log) {
                Graphene.Rect real_rect;
                if (slot_rect (f.id, false, out real_rect)) {
                    f.to_rect = real_rect;
                }
            }
            var elapsed = (now - f.start_us) / 1000000.0;
            if (elapsed < f.duration + 0.05) {
                r += f;
            } else {
                if ((f.id == 100 || f.id == 101) && !has_landed_rolloff (f.id)) {
                    landed_rolloff_ids += f.id;
                }
                removed = true;
            }
        }
        flying = r;
        flying_layer.queue_draw ();
        if (removed) {
            dice_zone.queue_draw ();
            if (active_cell != null) {
                active_cell.queue_draw ();
            }
            if (record_cells.length > 0) {
                record_cells[0].queue_draw ();
            }
        }
        if (flying.length == 0) {
            fly_tick = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    /** Прямоугольник слота кубика в системе координат слоя анимации flying_layer. */
    private bool slot_rect (int id, bool top, out Graphene.Rect rect) {
        rect = Graphene.Rect ().init (0, 0, 0, 0);
        Gtk.Widget src;
        Graphene.Rect local;
        if (id >= 100) {
            var idx = id == 100 ? 0 : 1;
            if (top) {
                if (!dice_zone.get_mapped () || dice_zone.get_width () <= 0) {
                    return false;
                }
                src = dice_zone;
                local = dice_zone.rolloff_slot_rect (idx);
            } else {
                if (record_cells.length == 0 || !record_cells[0].record.is_rolloff) {
                    return false;
                }
                src = record_cells[0];
                local = record_cells[0].die_rect (idx);
            }
        } else {
            if (top) {
                if (!dice_zone.get_mapped () || dice_zone.get_width () <= 0) {
                    return false;
                }
                src = dice_zone;
                var count = session.current_turn_dice.length > 0 ? session.current_turn_dice.length : 2;
                local = dice_zone.top_slot_rect (id, count);
            } else {
                if (active_cell != null) {
                    src = active_cell;
                    local = active_cell.die_rect (id);
                } else if (record_cells.length > 0 && !record_cells[0].record.is_rolloff) {
                    src = record_cells[0];
                    local = record_cells[0].die_rect (id);
                } else {
                    return false;
                }
            }
        }
        Graphene.Point p;
        if (src.get_mapped () && src.get_width () > 0 && src.get_height () > 0) {
            if (!src.compute_point (flying_layer, Graphene.Point ().init (local.get_x (), local.get_y ()), out p)) {
                return false;
            }
        } else if (!top && log_scroller.get_mapped () && log_scroller.get_width () > 0) {
            if (!log_scroller.compute_point (flying_layer, Graphene.Point ().init (local.get_x (), local.get_y ()), out p)) {
                return false;
            }
        } else {
            return false;
        }
        rect = Graphene.Rect ().init (p.x, p.y, local.get_width (), local.get_height ());
        return true;
    }

    /** Отрисовка траектории полёта кубика через Gtk.Snapshot только при наличии активных кубиков. */
    public void snapshot_flying (Gtk.Snapshot snapshot, Gtk.Widget layer) {
        if (flying.length == 0) {
            return;
        }
        var w = (float) layer.get_width ();
        var h = (float) layer.get_height ();
        if (w <= 0 || h <= 0) {
            return;
        }
        var now = frame_now_us ();
        float min_x = w, min_y = h, max_x = 0, max_y = 0;
        foreach (var f in flying) {
            if (f.to_log) {
                Graphene.Rect real_rect;
                if (slot_rect (f.id, false, out real_rect)) {
                    f.to_rect = real_rect;
                }
            } else {
                Graphene.Rect real_top;
                if (slot_rect (f.id, true, out real_top)) {
                    f.to_rect = real_top;
                }
            }
            var elapsed = (now - f.start_us) / 1000000.0;
            var progress = double.min (1.0, double.max (0.0, elapsed / f.duration));
            var p = PanelStyle.ease_in_out (progress);

            var fx = f.from_rect.get_x () + f.from_rect.get_width () / 2.0;
            var fy = f.from_rect.get_y () + f.from_rect.get_height () / 2.0;
            var tx = f.to_rect.get_x () + f.to_rect.get_width () / 2.0;
            var ty = f.to_rect.get_y () + f.to_rect.get_height () / 2.0;

            var cx = (float) (fx + (tx - fx) * p);
            var cy = (float) (fy + (ty - fy) * p);
            var size = (float) (f.from_rect.get_width () + (f.to_rect.get_width () - f.from_rect.get_width ()) * p);
            var pad = size * 0.85f + 16.0f;

            if (cx - pad < min_x) min_x = cx - pad;
            if (cy - pad < min_y) min_y = cy - pad;
            if (cx + pad > max_x) max_x = cx + pad;
            if (cy + pad > max_y) max_y = cy + pad;
        }
        min_x = float.max (0.0f, (float) Math.floor (min_x));
        min_y = float.max (0.0f, (float) Math.floor (min_y));
        max_x = float.min (w, (float) Math.ceil (max_x));
        max_y = float.min (h, (float) Math.ceil (max_y));
        if (max_x <= min_x || max_y <= min_y) {
            return;
        }
        var bounds = Graphene.Rect ().init (min_x, min_y, max_x - min_x, max_y - min_y);
        var cr = snapshot.append_cairo (bounds);
        draw_flying (cr, now);
    }

    /** Отрисовка траектории полёта кубика: масштаб, динамическая тень и наклон по синусоиде. */
    public void draw_flying (Cairo.Context cr, int64 now) {
        foreach (var f in flying) {
            var elapsed = (now - f.start_us) / 1000000.0;
            var progress = double.min (1.0, double.max (0.0, elapsed / f.duration));
            var p = PanelStyle.ease_in_out (progress);

            var fx = f.from_rect.get_x () + f.from_rect.get_width () / 2.0;
            var fy = f.from_rect.get_y () + f.from_rect.get_height () / 2.0;
            var tx = f.to_rect.get_x () + f.to_rect.get_width () / 2.0;
            var ty = f.to_rect.get_y () + f.to_rect.get_height () / 2.0;

            var cx = fx + (tx - fx) * p;
            var cy = fy + (ty - fy) * p;
            var size = f.from_rect.get_width () + (f.to_rect.get_width () - f.from_rect.get_width ()) * p;

            // Подъём по синусоиде: увеличение масштаба до 1.08, удлинение тени и наклон ±7° в апогее траектории
            var lift = Math.sin (progress * Math.PI);
            var tilt_deg = (f.id >= 100) ? (f.id == 100 ? -7.0 : 7.0) : (f.id % 2 == 0 ? -7.0 : 7.0);
            var scale = 1.0 + 0.08 * lift;

            cr.save ();
            cr.translate (cx, cy);
            cr.rotate (tilt_deg * lift * Math.PI / 180.0);
            cr.scale (scale, scale);
            DiceDrawing.draw_soft_shadow (cr, -size / 2, -size / 2 + 1 + 7 * lift, size, size, size * 0.18,
                                          2 + 8 * lift, 0.25 + 0.10 * lift);
            DiceDrawing.draw_full (cr, 0, 0, size, f.value, f.is_skipped ? 0.88 : 1.0, false);
            if (f.is_skipped) {
                DiceDrawing.draw_red_cross (cr, 0, 0, size);
            }
            cr.restore ();
        }
    }

    public override void dispose () {
        finish_log_clearing ();
        base.dispose ();
    }
}

} /* namespace Longbackgammon */
