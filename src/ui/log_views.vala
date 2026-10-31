/* log_views.vala
 *
 * Отображение истории ходов в боковой панели игрока:
 * ячейки завершённых ходов (LogCellView), глобальное состояние всплывающих подсказок (LogTooltipState)
 * и оверлей подсказки с детализацией шагов хода (LogTooltipView).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Глобальное состояние всплывающей подсказки истории ходов.
 * Хранит координаты курсора и сторону игрока для позиционирования плашки с текстом хода.
 */
public class LogTooltipState : Object {
    private static LogTooltipState? _shared = null;
    public static LogTooltipState shared () {
        if (_shared == null) {
            _shared = new LogTooltipState ();
        }
        return _shared;
    }

    public double hovered_x = 0;
    public double hovered_y = 0;
    public int hovered_side = -1;   // −1 — нет активного наведения, иначе (int) CheckerColor
    /** Контейнер верхнего уровня, относительно которого рассчитываются экранные координаты. */
    public weak Gtk.Widget? container = null;
    public signal void changed ();
}

/**
 * Слой всплывающей подсказки: плашка с расшифровкой шагов записи хода под курсором мыши.
 * Каждая подсказка имеет собственную плавную анимацию появления и затухания (0.20 с easeInOut + масштаб 0.95..1.0),
 * благодаря чему при перемещении курсора между строками лога старая подсказка плавно гаснет, а новая плавно появляется.
 */
public class LogTooltipView : Gtk.Widget {
    private class TooltipItem {
        public int record_id;
        public int side;
        public double x;
        public double y;
        public Gtk.Label label;
        public bool target_visible;
        public double progress;
        public double start_val;
        public int64 start_us;
    }

    private GameSession session;
    private TooltipItem[] items = new TooltipItem[0];
    private uint tick_id = 0;

    public LogTooltipView (GameSession session) {
        this.session = session;
        PanelStyle.ensure_css ();
        can_target = false;
        can_focus = false;
        session.changed.connect (refresh);
        LogTooltipState.shared ().changed.connect (refresh);
        SettingsStore.shared ().changed.connect (refresh);
    }

    public override void dispose () {
        if (tick_id != 0) {
            remove_tick_callback (tick_id);
            tick_id = 0;
        }
        foreach (var item in items) {
            if (item.label != null) {
                item.label.unparent ();
                item.label = null;
            }
        }
        items = new TooltipItem[0];
        base.dispose ();
    }

    private int64 now_us () {
        var fc = get_frame_clock ();
        if (fc != null) {
            var ft = fc.get_frame_time ();
            if (ft > 0) {
                return ft;
            }
        }
        return GLib.get_monotonic_time ();
    }

    private void refresh () {
        var st = LogTooltipState.shared ();
        string msg = "";
        int active_id = -1;
        int active_side = -1;
        if (st.hovered_side >= 0 && session.highlighted_log_id >= 0) {
            var side = (CheckerColor) st.hovered_side;
            var log = side == CheckerColor.WHITE ? session.white_turn_log : session.black_turn_log;
            TurnRecord? record = null;
            foreach (var r in log) {
                if (r.id == session.highlighted_log_id) {
                    record = r;
                    break;
                }
            }
            if (record == null && session.current_player == side && session.current_turn_record != null
                && session.current_turn_record.id == session.highlighted_log_id) {
                record = session.current_turn_record;
            }
            if (record != null) {
                msg = record.formatted_message (side, session);
                if (msg != "") {
                    active_id = record.id;
                    active_side = st.hovered_side;
                }
            }
        }

        var now = now_us ();
        var need_tick = false;
        TooltipItem? found_active = null;

        foreach (var item in items) {
            if (active_id >= 0 && item.record_id == active_id && item.side == active_side) {
                found_active = item;
                item.label.label = msg;
                item.x = st.hovered_x;
                item.y = st.hovered_y;
                if (!item.target_visible) {
                    item.target_visible = true;
                    item.start_val = item.progress;
                    item.start_us = now;
                    need_tick = true;
                }
            } else {
                if (item.target_visible) {
                    item.target_visible = false;
                    item.start_val = item.progress;
                    item.start_us = now;
                    need_tick = true;
                }
            }
        }

        if (active_id >= 0 && found_active == null) {
            var item = new TooltipItem ();
            item.record_id = active_id;
            item.side = active_side;
            item.x = st.hovered_x;
            item.y = st.hovered_y;
            item.target_visible = true;
            item.progress = 0.0;
            item.start_val = 0.0;
            item.start_us = now;
            item.label = new Gtk.Label (msg);
            item.label.add_css_class ("lb-tooltip");
            item.label.wrap = true;
            item.label.wrap_mode = Pango.WrapMode.WORD;
            item.label.justify = Gtk.Justification.CENTER;
            item.label.opacity = 0.0;
            item.label.set_parent (this);
            items += item;
            need_tick = true;
        }

        if (need_tick && tick_id == 0) {
            tick_id = add_tick_callback (on_anim_tick);
        }
        queue_allocate ();
    }

    private bool on_anim_tick (Gtk.Widget w, Gdk.FrameClock clock) {
        var ft = clock.get_frame_time ();
        var now = ft > 0 ? ft : GLib.get_monotonic_time ();
        const double duration = 0.20;
        var next_items = new TooltipItem[0];
        var still_animating = false;

        foreach (var item in items) {
            var target = item.target_visible ? 1.0 : 0.0;
            if (Math.fabs (item.progress - target) > 1e-4) {
                var elapsed = double.max (0.0, (now - item.start_us) / 1000000.0);
                var p = double.min (1.0, elapsed / duration);
                var ease = PanelStyle.ease_in_out (p);
                item.progress = item.start_val + (target - item.start_val) * ease;
                if (p < 1.0) {
                    still_animating = true;
                } else {
                    item.progress = target;
                }
            }
            if (item.label != null) {
                item.label.opacity = item.progress;
            }
            if (!item.target_visible && item.progress <= 0.001) {
                if (item.label != null) {
                    item.label.unparent ();
                    item.label = null;
                }
            } else {
                next_items += item;
            }
        }

        items = next_items;
        queue_allocate ();

        if (!still_animating) {
            tick_id = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        minimum = 0;
        natural = 0;
        minimum_baseline = -1;
        natural_baseline = -1;
    }

    public override void size_allocate (int width, int height, int baseline) {
        const int MAX_WIDTH = 170;
        foreach (var item in items) {
            if (item.label == null) {
                continue;
            }
            int min_w, nat_w, mb, nb;
            item.label.measure (Gtk.Orientation.HORIZONTAL, -1, out min_w, out nat_w, out mb, out nb);
            var w = int.max (min_w, int.min (nat_w, MAX_WIDTH));
            int min_h, nat_h;
            item.label.measure (Gtk.Orientation.VERTICAL, w, out min_h, out nat_h, out mb, out nb);
            var h = nat_h;

            int x;
            if (item.side == (int) CheckerColor.WHITE || item.side == (int) CheckerColor.BLACK) {
                var is_right_side = BoardLayout.is_player_on_right_side ((CheckerColor) item.side);
                if (is_right_side) {
                    // Панель справа: правый край плашки выровнен по линии панели
                    var right_anchor = item.x + 85.0;
                    x = (int) (right_anchor - w);
                } else {
                    // Панель слева: левый край плашки выровнен по линии панели
                    var left_anchor = item.x - 85.0;
                    x = (int) left_anchor;
                }
            } else {
                x = (int) (item.x - w / 2.0);
            }
            var y = (int) (item.y - h / 2.0);
            x = int.max (0, int.min (width - w, x));
            y = int.max (0, int.min (height - h, y));
            var scale = (float) (0.95 + 0.05 * item.progress);
            var cx = (float) x + w / 2.0f;
            var cy = (float) y + h / 2.0f;
            var t = new Gsk.Transform ()
                .translate ({ cx, cy })
                .scale (scale, scale)
                .translate ({ -w / 2.0f, -h / 2.0f });
            item.label.allocate (w, h, -1, t);
        }
    }
}

/**
 * Визуальная ячейка записи в истории ходов:
 * отображает миниатюры кубиков, бейдж дубля/розыгрыша и подсвечивает траектории при наведении.
 */
public class LogCellView : Gtk.DrawingArea {
    private weak PlayerPanel panel;
    public TurnRecord? record;   // null — активный текущий ход
    public bool is_active_cell;
    private bool hovered = false;

    public double clearing_opacity = 1.0;
    public double clearing_offset_y = 0.0;
    public double clearing_scale = 1.0;

    public void set_clearing_fx (double opacity, double offset_y, double scale) {
        clearing_opacity = opacity;
        clearing_offset_y = offset_y;
        clearing_scale = scale;
        this.opacity = opacity;
        queue_draw ();
    }

    private const double DIE = 40;
    private const double CARD_W = 98;

    public LogCellView (PlayerPanel panel, TurnRecord? record, bool is_active_cell) {
        this.panel = panel;
        this.record = record;
        this.is_active_cell = is_active_cell;
        set_content_width (98);
        set_hexpand (true);
        set_content_height ((int) compute_height ());
        set_draw_func (draw_cb);

        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect (() => { on_hover (true); });
        motion.leave.connect (() => { on_hover (false); });
        add_controller (motion);

        var click = new Gtk.GestureClick ();
        click.pressed.connect ((n, x, y) => {
            if (n == 2 && !is_active_cell && SettingsStore.shared ().enable_debug_export) {
                get_clipboard ().set_text (panel.session.debug_export_text ());
                panel.session.show_debug_copied_status ();
            }
        });
        add_controller (click);
    }

    private GameSession session { get { return panel.session; } }

    public int record_id () {
        if (is_active_cell) {
            return session.current_turn_record != null ? session.current_turn_record.id : -1;
        }
        return record.id;
    }

    private bool is_double () {
        if (is_active_cell) {
            return session.current_turn_dice.length > 2;
        }
        return !record.is_rolloff && record.dice_roll.is_double;
    }

    public double compute_height () {
        if (!is_active_cell && record.is_rolloff) {
            return 2 + 4 + 11 + 3 + DIE + 4 + 2;
        }
        if (is_double ()) {
            return 2 + 4 + 11 + 3 + DIE * 2 + 3 + 4 + 2;
        }
        return 2 + 4 + DIE + 4 + 2;
    }

    private double card_x () {
        return double.max (0.0, (get_width () - CARD_W) / 2.0);
    }

    /** Прямоугольник слота кубика в координатах ячейки. */
    public Graphene.Rect die_rect (int die_index) {
        var x0 = card_x () + 6;
        var y0 = 2.0 + 4;
        if (!is_active_cell && record.is_rolloff) {
            y0 += 11 + 3;
            return Graphene.Rect ().init ((float) (x0 + die_index * (DIE + 6)), (float) y0, (float) DIE, (float) DIE);
        }
        if (is_double ()) {
            y0 += 11 + 3;
            var row = die_index / 2;
            var col = die_index % 2;
            var inner_w = DIE * 2 + 5;
            var sx = card_x () + (CARD_W - inner_w) / 2.0;
            return Graphene.Rect ().init ((float) (sx + col * (DIE + 5)), (float) (y0 + row * (DIE + 3)),
                                          (float) DIE, (float) DIE);
        }
        return Graphene.Rect ().init ((float) (x0 + die_index * (DIE + 6)), (float) y0, (float) DIE, (float) DIE);
    }

    private void on_hover (bool on) {
        if (on && clearing_opacity < 0.99) {
            return;
        }
        hovered = on;
        var id = record_id ();
        if (id < 0) {
            return;
        }
        if (on) {
            update_tooltip_position ();
            session.highlighted_log_id = id;
        } else if (session.highlighted_log_id == id) {
            session.highlighted_log_id = -1;
        }
        session.changed ();
    }

    /** Пересчёт позиции всплывающей подсказки относительно ячейки. */
    public void update_tooltip_position () {
        var st = LogTooltipState.shared ();
        if (st.container == null) {
            return;
        }
        Graphene.Rect b;
        if (!compute_bounds (st.container, out b)) {
            return;
        }
        var is_right_side = BoardLayout.is_player_on_right_side (panel.color);
        st.hovered_x = is_right_side ? b.get_x () - 95 : b.get_x () + b.get_width () + 95;
        st.hovered_y = b.get_y () + b.get_height () / 2;
        st.hovered_side = (int) panel.color;
        st.changed ();
    }

    public bool is_hovered () {
        return hovered;
    }

    private void draw_cb (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        if (clearing_opacity <= 0.001) {
            return;
        }
        cr.save ();
        if (clearing_offset_y != 0.0 || clearing_scale != 1.0) {
            var cx = width / 2.0;
            var cy = height / 2.0;
            cr.translate (cx, cy + clearing_offset_y);
            cr.scale (clearing_scale, clearing_scale);
            cr.translate (-cx, -cy);
        }

        draw_content (cr, width, height);

        cr.restore ();
    }

    private void draw_content (Cairo.Context cr, int width, int height) {
        var highlighted = record_id () >= 0 && session.highlighted_log_id == record_id ();
        if (!is_active_cell && record.is_rolloff) {
            draw_rolloff (cr, highlighted);
            return;
        }
        var dbl = is_double ();
        var x = card_x ();
        var y = 2.0;
        var h = height - 4.0;
        DiceDrawing.rounded_rect (cr, x + 0.5, y + 0.5, CARD_W - 1, h - 1, 6);
        if (dbl) {
            var g = new Cairo.Pattern.linear (x, y, x + CARD_W, y + h);
            g.add_color_stop_rgba (0, 1.0, 0.584, 0.0, highlighted ? 0.12 : 0.05);
            g.add_color_stop_rgba (1, 1.0, 0.584, 0.0, highlighted ? 0.08 : 0.02);
            cr.set_source (g);
        } else {
            PanelStyle.set_fg (cr, this, highlighted ? 0.08 : 0.02);
        }
        cr.fill_preserve ();
        if (dbl) {
            cr.set_source_rgba (1.0, 0.584, 0.0, highlighted ? 0.50 : 0.28);
        } else {
            PanelStyle.set_fg (cr, this, highlighted ? 0.28 : 0.12);
        }
        cr.set_line_width (1);
        cr.stroke ();

        if (dbl) {
            draw_double_header (cr, x + CARD_W / 2, y + 4 + 1);
        }

        TurnDie[] dice = is_active_cell ? session.current_turn_dice : record.display_dice ();
        for (var i = 0; i < dice.length; i++) {
            var r = die_rect (i);
            var cx = r.get_x () + DIE / 2;
            var cy = r.get_y () + DIE / 2;
            if (is_active_cell) {
                draw_active_slot (cr, cx, cy, dice[i]);
            } else {
                PanelStyle.draw_log_die (cr, cx, cy, DIE, dice[i]);
            }
        }
    }

    private void draw_slot_placeholder (Cairo.Context cr, double cx, double cy) {
        var r = DIE * 0.18;
        cr.save ();
        DiceDrawing.rounded_rect (cr, cx - DIE / 2 + 0.75, cy - DIE / 2 + 0.75, DIE - 1.5, DIE - 1.5, r);
        PanelStyle.set_fg (cr, this, 0.02);
        cr.fill_preserve ();
        PanelStyle.set_fg (cr, this, 0.18);
        cr.set_line_width (1.5);
        cr.set_dash ({ 4.0, 3.0 }, 0);
        cr.stroke ();
        cr.restore ();
    }

    private void draw_active_slot (Cairo.Context cr, double cx, double cy, TurnDie die) {
        draw_slot_placeholder (cr, cx, cy);

        var is_flying = panel.is_flying (die.id);
        var is_pending_skip = panel.is_pending_skip (die.id);
        var is_pending_fly = panel.is_pending_fly (die.id);
        var is_pending_unfly = panel.is_pending_unfly (die.id);
        var show_solid = ((die.is_used && !is_pending_fly) || is_pending_unfly || (die.is_skipped && !is_pending_skip)) && !is_flying;
        if (show_solid) {
            DiceDrawing.draw_full (cr, cx, cy, DIE, die.value, (die.is_used && !die.is_skipped) ? 1.0 : 0.88, true);
            if (die.is_skipped) {
                DiceDrawing.draw_red_cross (cr, cx, cy, DIE);
            }
        }
    }

    private void draw_double_header (Cairo.Context cr, double cx, double top) {
        var text = Localization.badge_double ();
        var tw = PanelStyle.text_width (this, text, 7.5, 900, 0.5);
        var icon = 7.5;
        var total = icon + 3 + tw;
        var sx = cx - total / 2;
        cr.set_source_rgba (1.0, 0.584, 0.0, 1.0);
        PanelStyle.draw_sparkles (cr, sx + icon / 2, top + 5, icon);
        cr.set_source_rgba (1.0, 0.584, 0.0, 1.0);
        PanelStyle.draw_text_centered (cr, this, text, sx + icon + 3 + tw / 2, top, 7.5, 900, 0.5);
    }

    private void draw_rolloff (Cairo.Context cr, bool highlighted) {
        var is_tie = record.is_rolloff_tie ();
        var is_winner = record.is_rolloff_winner;
        var x = card_x ();
        var y = 2.0;
        var h = get_height () - 4.0;

        if (is_winner) {
            DiceDrawing.draw_soft_shadow (cr, x, y + 1, CARD_W, h, 6, 4, 0.15 * 0.6);
        }
        DiceDrawing.rounded_rect (cr, x + 0.5, y + 0.5, CARD_W - 1, h - 1, 6);
        if (is_winner) {
            var g = new Cairo.Pattern.linear (x, y, x + CARD_W, y + h);
            g.add_color_stop_rgba (0, 1.0, 0.584, 0.0, highlighted ? 0.20 : 0.13);
            g.add_color_stop_rgba (1, 1.0, 0.8, 0.0, highlighted ? 0.12 : 0.06);
            cr.set_source (g);
        } else if (is_tie) {
            PanelStyle.set_fg (cr, this, highlighted ? 0.06 : 0.025);
        } else {
            PanelStyle.set_fg (cr, this, highlighted ? 0.05 : 0.015);
        }
        cr.fill_preserve ();
        cr.save ();
        if (is_winner) {
            var g = new Cairo.Pattern.linear (x, y, x + CARD_W, y + h);
            g.add_color_stop_rgba (0, 1.0, 0.584, 0.0, 0.65);
            g.add_color_stop_rgba (1, 1.0, 0.8, 0.0, 0.40);
            cr.set_source (g);
            cr.set_line_width (1.2);
        } else if (is_tie) {
            PanelStyle.set_fg (cr, this, 0.19);
            cr.set_line_width (1);
            cr.set_dash ({ 4.0, 3.0 }, 0);
        } else {
            PanelStyle.set_fg (cr, this, 0.10);
            cr.set_line_width (1);
        }
        cr.stroke ();
        cr.restore ();

        var top = y + 4 + 1;
        var cx = x + CARD_W / 2;
        if (is_winner) {
            var text = Localization.badge_first_move ();
            var tw = PanelStyle.text_width (this, text, 7.5, 900, 0.5);
            var icon = 8.0;
            var sx = cx - (icon + 3 + tw) / 2;
            var g = new Cairo.Pattern.linear (0, top, 0, top + 9);
            g.add_color_stop_rgba (0, 1.0, 0.72, 0.15, 1);
            g.add_color_stop_rgba (1, 1.0, 0.584, 0.0, 1);
            cr.set_source (g);
            PanelStyle.draw_crown (cr, sx + icon / 2, top + 5, icon);
            var g2 = new Cairo.Pattern.linear (0, top, 0, top + 9);
            g2.add_color_stop_rgba (0, 1.0, 0.65, 0.10, 1);
            g2.add_color_stop_rgba (1, 1.0, 0.584, 0.0, 1);
            cr.set_source (g2);
            PanelStyle.draw_text_centered (cr, this, text, sx + icon + 3 + tw / 2, top, 7.5, 900, 0.5);
        } else if (is_tie) {
            var text = Localization.badge_tie ();
            var label = "=  " + text;
            PanelStyle.set_fg (cr, this, 0.55);
            PanelStyle.draw_text_centered (cr, this, label, cx, top, 7.5, 700, 0.5);
        } else {
            PanelStyle.set_fg (cr, this, 0.55 * 0.85);
            PanelStyle.draw_text_centered (cr, this, Localization.badge_rolloff (), cx, top, 7.5, 600, 0.5);
        }

        var log = panel.color == CheckerColor.WHITE ? session.white_turn_log : session.black_turn_log;
        var is_latest = log.length > 0 && log[0].id == record.id;
        for (var idx = 0; idx < 2; idx++) {
            var fly_id = idx == 0 ? 100 : 101;
            if (is_latest && (panel.is_flying (fly_id) || panel.is_pending_fly (fly_id))) {
                continue;
            }
            var r = die_rect (idx);
            DiceDrawing.draw (cr, r.get_x () + DIE / 2, r.get_y () + DIE / 2, DIE,
                              idx == 0 ? record.dice_roll.die1 : record.dice_roll.die2);
        }
    }
}

} /* namespace Longbackgammon */
