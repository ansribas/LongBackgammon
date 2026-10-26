/* player_panel.vala
 *
 * Боковая панель игрока (PlayerPanel):
 * карточка статуса и кубиков хода, блок очков/прогресса и вертикальный лог партии.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Оформление и вспомогательные функции рисования для боковых панелей:
 * внедрение CSS-стилей, расчёт пружинных кривых, типографика и отрисовка декоративных символов.
 */
public class PanelStyle {
    private static bool css_loaded = false;

    /** Подключает CSS-классы оформления карточек, шрифтов и бейджей. */
    public static void ensure_css () {
        if (css_loaded) {
            return;
        }
        css_loaded = true;
        var css = new Gtk.CssProvider ();
        css.load_from_string (
            ".lb-card { background-color: var(--card-bg-color, @card_bg_color); border-radius: 12px;" +
            "  border: 1px solid alpha(currentColor, 0.12); box-shadow: 0 4px 10px alpha(black, 0.12); }" +
            ".lb-card-dice { border: none; }" +
            ".lb-header-strip { background-color: alpha(currentColor, 0.06); border-bottom: 1px solid alpha(currentColor, 0.08); transition: background-color 250ms ease-in-out, border-color 250ms ease-in-out; }" +
            ".lb-header-strip-active { background-color: alpha(#ff9500, 0.12); border-bottom: 1px solid alpha(#ff9500, 0.25); transition: background-color 250ms ease-in-out, border-color 250ms ease-in-out; }" +
            ".lb-card-padded { padding: 8px 6px; }" +
            ".lb-card-hover { filter: brightness(105%); }" +
            ".lb-status-strip { background-color: alpha(currentColor, 0.08); }" +
            ".lb-subheadline-bold { font-size: 12px; font-weight: bold; transition: color 250ms ease-in-out; }" +
            ".lb-caption-bold { font-size: 11px; font-weight: bold; }" +
            ".lb-caption2-bold { font-size: 10px; font-weight: bold; }" +
            ".lb-title3-bold { font-size: 16px; font-weight: bold; font-feature-settings: \"tnum\"; }" +
            ".lb-secondary { color: alpha(currentColor, 0.55); }" +
            ".lb-tertiary { color: alpha(currentColor, 0.30); }" +
            ".lb-orange { color: #ff9500; }" +
            ".lb-log-scroller scrollbar { min-width: 0; min-height: 0; padding: 0; margin: 0; border: none; opacity: 0; }" +
            ".lb-log-scroller overshoot { opacity: 0; }" +
            ".lb-progress, .lb-progress trough, .lb-progress progress { min-width: 20px; }" +
            ".lb-progress trough { min-height: 4px; border-radius: 2px; }" +
            ".lb-progress progress { min-height: 4px; border-radius: 2px; background-color: #34c759; }" +
            ".lb-tooltip { background-color: alpha(var(--window-bg-color, @window_bg_color), 0.85);" +
            "  border-radius: 8px; padding: 6px 10px; box-shadow: 0 5px 10px alpha(black, 0.2);" +
            "  font-size: 11px; font-weight: bold; }\n");
        var display = Gdk.Display.get_default ();
        if (display != null) {
            add_style_provider (display, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
        }
    }

    [CCode (cname = "gtk_style_context_add_provider_for_display")]
    private extern static void add_style_provider (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

    /**
     * Пружинная кривая затухающих колебаний от 0 до 1.
     * @param t Время от старта анимации (секунды).
     * @param response Период собственных колебаний системы.
     * @param damping Коэффициент затухания (1.0 — критическое, <1.0 — с отскоком).
     */
    public static double spring (double t, double response, double damping) {
        if (t <= 0) {
            return 0;
        }
        var w = 2.0 * Math.PI / response;
        if (damping >= 1.0) {
            return 1.0 - Math.exp (-w * t) * (1.0 + w * t);
        }
        var wd = w * Math.sqrt (1.0 - damping * damping);
        return 1.0 - Math.exp (-damping * w * t) * (Math.cos (wd * t) + (damping * w / wd) * Math.sin (wd * t));
    }

    /** Плавная S-образная кривая Безье (0.42, 0, 0.58, 1). */
    public static double ease_in_out (double t) {
        if (t <= 0) {
            return 0;
        }
        if (t >= 1) {
            return 1;
        }
        double u = t;
        for (var i = 0; i < 8; i++) {
            var x = 3 * (1 - u) * (1 - u) * u * 0.42 + 3 * (1 - u) * u * u * 0.58 + u * u * u - t;
            var dx = 3 * (1 - u) * (1 - u) * 0.42 + 6 * (1 - u) * u * (0.58 - 0.42) + 3 * u * u * (1 - 0.58);
            if (Math.fabs (dx) < 1e-6) {
                break;
            }
            u = double.max (0.0, double.min (1.0, u - x / dx));
        }
        return 3 * (1 - u) * u * u + u * u * u;
    }

    /** Основной цвет текста виджета. */
    public static Gdk.RGBA fg (Gtk.Widget w) {
        return w.get_color ();
    }

    public static void set_fg (Cairo.Context cr, Gtk.Widget w, double alpha) {
        var c = fg (w);
        cr.set_source_rgba (c.red, c.green, c.blue, alpha);
    }

    /** Отрисовка центрированного текста через Pango. */
    public static double draw_text_centered (Cairo.Context cr, Gtk.Widget w, string text, double cx, double y,
                                             double px, int weight, double letter_spacing = 0) {
        var layout = w.create_pango_layout (text);
        var fd = new Pango.FontDescription ();
        fd.set_family ("Sans");
        fd.set_absolute_size (px * Pango.SCALE);
        fd.set_weight ((Pango.Weight) weight);
        layout.set_font_description (fd);
        if (letter_spacing > 0) {
            var attrs = new Pango.AttrList ();
            attrs.insert (Pango.attr_letter_spacing_new ((int) (letter_spacing * Pango.SCALE)));
            layout.set_attributes (attrs);
        }
        int tw, th;
        layout.get_pixel_size (out tw, out th);
        cr.move_to (cx - tw / 2.0, y);
        Pango.cairo_show_layout (cr, layout);
        return th;
    }

    public static double text_width (Gtk.Widget w, string text, double px, int weight, double letter_spacing = 0) {
        var layout = w.create_pango_layout (text);
        var fd = new Pango.FontDescription ();
        fd.set_family ("Sans");
        fd.set_absolute_size (px * Pango.SCALE);
        fd.set_weight ((Pango.Weight) weight);
        layout.set_font_description (fd);
        if (letter_spacing > 0) {
            var attrs = new Pango.AttrList ();
            attrs.insert (Pango.attr_letter_spacing_new ((int) (letter_spacing * Pango.SCALE)));
            layout.set_attributes (attrs);
        }
        int tw, th;
        layout.get_pixel_size (out tw, out th);
        return tw;
    }

    /** Отрисовка кубика с эффектами: подсветка отсутствия ходов или вспышка дубля. */
    public static void draw_effect_die (Cairo.Context cr, GameSession session, double cx, double cy, double size,
                                        int value, double alpha = 1.0) {
        DiceDrawing.draw_full (cr, cx, cy, size, value, alpha, true);
        var r = size * 0.18;
        if (session.is_no_moves_flashing) {
            cr.save ();
            cr.set_source_rgba (1.0, 0.23, 0.19, 1.0);
            cr.set_line_width (2.0);
            DiceDrawing.rounded_rect (cr, cx - size / 2 + 1, cy - size / 2 + 1, size - 2, size - 2, r - 1);
            cr.stroke ();
            cr.restore ();
        }
        if (session.is_dice_flash_active && session.dice_flash_opacity > 0.0) {
            var flash_alpha = session.dice_flash_opacity;
            cr.save ();
            for (var i = 4; i >= 1; i--) {
                var g = 20.0 * i / 4.0;
                cr.set_source_rgba (1, 1, 1, 0.8 / 4.0 * 0.5 * flash_alpha);
                DiceDrawing.rounded_rect (cr, cx - size / 2 - g / 2, cy - size / 2 - g / 2, size + g, size + g, r + g / 2);
                cr.fill ();
            }
            cr.set_source_rgba (1, 1, 1, 0.9 * flash_alpha);
            DiceDrawing.rounded_rect (cr, cx - size / 2, cy - size / 2, size, size, r);
            cr.fill ();
            cr.restore ();
        }
    }

    /** Отрисовка кубика в ячейке истории: полупрозрачность и красный крест при пропуске. */
    public static void draw_log_die (Cairo.Context cr, double cx, double cy, double size, TurnDie die) {
        var crossed = !die.is_used || die.is_skipped;
        DiceDrawing.draw_full (cr, cx, cy, size, die.value, crossed ? 0.88 : 1.0, true);
        if (crossed) {
            DiceDrawing.draw_red_cross (cr, cx, cy, size);
        }
    }

    /** Иконка блеска/искры для заголовка дубля. */
    public static void draw_sparkles (Cairo.Context cr, double cx, double cy, double s) {
        star (cr, cx - s * 0.12, cy + s * 0.08, s * 0.42);
        star (cr, cx + s * 0.32, cy - s * 0.30, s * 0.20);
        star (cr, cx + s * 0.30, cy + s * 0.36, s * 0.14);
    }

    private static void star (Cairo.Context cr, double cx, double cy, double r) {
        var k = r * 0.28;
        cr.move_to (cx, cy - r);
        cr.curve_to (cx + k * 0.3, cy - k, cx + k, cy - k * 0.3, cx + r, cy);
        cr.curve_to (cx + k, cy + k * 0.3, cx + k * 0.3, cy + k, cx, cy + r);
        cr.curve_to (cx - k * 0.3, cy + k, cx - k, cy + k * 0.3, cx - r, cy);
        cr.curve_to (cx - k, cy - k * 0.3, cx - k * 0.3, cy - k, cx, cy - r);
        cr.close_path ();
        cr.fill ();
    }

    /** Иконка короны для победителя розыгрыша первого хода. */
    public static void draw_crown (Cairo.Context cr, double cx, double cy, double s) {
        var w = s * 1.1;
        var h = s * 0.85;
        var x = cx - w / 2;
        var y = cy - h / 2;
        cr.move_to (x, y + h * 0.25);
        cr.line_to (x + w * 0.28, y + h * 0.55);
        cr.line_to (x + w * 0.5, y);
        cr.line_to (x + w * 0.72, y + h * 0.55);
        cr.line_to (x + w, y + h * 0.25);
        cr.line_to (x + w * 0.88, y + h * 0.85);
        cr.line_to (x + w * 0.12, y + h * 0.85);
        cr.close_path ();
        cr.fill ();
        cr.rectangle (x + w * 0.12, y + h * 0.9, w * 0.76, h * 0.12);
        cr.fill ();
    }
}

/**
 * Боковая панель игрока (белых или чёрных):
 * собирает имя, состояние хода, карточку кубиков, карточку очков и историю выполненных ходов.
 */
public class PlayerPanel : Gtk.Box {
    public GameSession session { get; construct set; }
    public CheckerColor color { get; construct set; }

    private Gtk.Overlay overlay;
    private DiceCardBox dice_card;
    private Gtk.Box header_box;
    private Gtk.Label name_label;
    private PlayerDiceZone dice_zone;
    private Gtk.Label doubled_label;
    private Gtk.Label status_label;
    private PlayerScoreBlock score_block;
    private Gtk.Box log_card;
    private Gtk.ScrolledWindow log_scroller;
    private Gtk.Box log_list;
    private Gtk.Label footer;
    private FlyingLayer flying_layer;

    private LogCellView? active_cell = null;
    private Gtk.Revealer? active_cell_revealer = null;
    private LogCellView[] record_cells = new LogCellView[0];
    private string log_signature = "";
    private int last_log_count = -1;

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
    private int[] pending_skipped = new int[0];
    private int[] pending_fly = new int[0];
    private int[] pending_unfly = new int[0];
    private TurnDie[] previous_turn_dice = new TurnDie[0];
    private int last_rolloff_anim_id = 0;
    private uint fly_tick = 0;
    private int64[] skipped_cross_started_us = new int64[4];
    private uint skipped_cross_tick = 0;

    public PlayerPanel (GameSession session, CheckerColor color) {
        Object (session: session, color: color, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
    }

    construct {
        PanelStyle.ensure_css ();
        set_vexpand (true);

        overlay = new Gtk.Overlay ();
        overlay.set_vexpand (true);
        append (overlay);

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 7);
        content.margin_top = 10;
        content.margin_bottom = 10;
        content.margin_start = 10;
        content.margin_end = 10;
        content.set_vexpand (true);
        overlay.set_child (content);

        // 1. Карточка кубиков и текущего статуса
        dice_card = new DiceCardBox ();

        header_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        header_box.add_css_class ("lb-header-strip");

        name_label = new Gtk.Label ("");
        name_label.add_css_class ("lb-subheadline-bold");
        name_label.add_css_class ("lb-secondary");
        name_label.margin_top = 8;
        name_label.margin_bottom = 8;
        name_label.margin_start = 8;
        name_label.margin_end = 8;
        name_label.ellipsize = Pango.EllipsizeMode.END;
        header_box.append (name_label);
        dice_card.append (header_box);

        dice_zone = new PlayerDiceZone (this);
        dice_zone.margin_bottom = 6;
        dice_card.append (dice_zone);

        var strip = new Gtk.Box (Gtk.Orientation.VERTICAL, 1);
        strip.add_css_class ("lb-status-strip");
        strip.set_size_request (-1, 48);
        strip.vexpand = false;
        var strip_inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
        strip_inner.valign = Gtk.Align.CENTER;
        strip_inner.vexpand = true;
        strip_inner.margin_top = 2;
        strip_inner.margin_bottom = 2;
        strip_inner.margin_start = 6;
        strip_inner.margin_end = 6;
        doubled_label = new Gtk.Label (Localization.status_double_doubled ());
        doubled_label.add_css_class ("lb-caption2-bold");
        doubled_label.add_css_class ("lb-orange");
        doubled_label.wrap = true;
        doubled_label.wrap_mode = Pango.WrapMode.WORD;
        doubled_label.justify = Gtk.Justification.CENTER;
        doubled_label.valign = Gtk.Align.CENTER;
        status_label = new Gtk.Label ("");
        status_label.add_css_class ("lb-caption-bold");
        status_label.wrap = true;
        status_label.wrap_mode = Pango.WrapMode.WORD;
        status_label.justify = Gtk.Justification.CENTER;
        status_label.valign = Gtk.Align.CENTER;
        status_label.vexpand = true;
        strip_inner.append (doubled_label);
        strip_inner.append (status_label);
        strip.append (strip_inner);
        dice_card.append (strip);
        content.append (dice_card);

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
        SettingsStore.shared ().changed.connect (() => {
            log_signature = "";
            on_session_changed ();
        });
        on_session_changed ();
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
        if (session.is_first_move_rolloff_in_progress) {
            if (color == CheckerColor.WHITE && session.white_rolloff_dice != null) {
                return true;
            }
            if (color == CheckerColor.BLACK && session.black_rolloff_dice != null) {
                return true;
            }
            return session.white_rolloff_dice == null ? color == CheckerColor.WHITE : color == CheckerColor.BLACK;
        }
        return session.current_player == color;
    }

    private bool is_my_turn_to_act () {
        if (session.is_first_move_rolloff_in_progress) {
            if (session.white_rolloff_dice == null) {
                return color == CheckerColor.WHITE;
            }
            if (session.black_rolloff_dice == null) {
                return color == CheckerColor.BLACK;
            }
            return false;
        }
        return session.current_player == color;
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
        foreach (var p in pending_skipped) {
            if (p == id) {
                return true;
            }
        }
        return false;
    }

    public bool is_pending_fly (int id) {
        foreach (var p in pending_fly) {
            if (p == id) {
                return true;
            }
        }
        return false;
    }

    public bool is_pending_unfly (int id) {
        foreach (var p in pending_unfly) {
            if (p == id) {
                return true;
            }
        }
        return false;
    }

    public void add_pending_fly (int id) {
        if (!is_pending_fly (id)) {
            pending_fly += id;
            dice_zone.queue_draw ();
            foreach (var c in all_cells ()) {
                c.queue_draw ();
            }
        }
    }

    public void remove_pending_fly (int id) {
        var r = new int[0];
        foreach (var p in pending_fly) {
            if (p != id) {
                r += p;
            }
        }
        pending_fly = r;
        dice_zone.queue_draw ();
        foreach (var c in all_cells ()) {
            c.queue_draw ();
        }
    }

    public void add_pending_unfly (int id) {
        if (!is_pending_unfly (id)) {
            pending_unfly += id;
            dice_zone.queue_draw ();
            foreach (var c in all_cells ()) {
                c.queue_draw ();
            }
        }
    }

    public void remove_pending_unfly (int id) {
        var r = new int[0];
        foreach (var p in pending_unfly) {
            if (p != id) {
                r += p;
            }
        }
        pending_unfly = r;
        dice_zone.queue_draw ();
        foreach (var c in all_cells ()) {
            c.queue_draw ();
        }
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
        name_label.label = color == CheckerColor.WHITE ? session.white_player_name : session.black_player_name;
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
            var fc = get_frame_clock ();
            transition_start_time = fc != null ? fc.get_frame_time () : GLib.get_monotonic_time ();
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

        doubled_label.label = Localization.status_double_doubled ();
        doubled_label.visible = session.is_doubling && active;
        status_label.visible = !session.is_doubling || !my_turn;
        status_label.label = (my_turn && session.is_game_started) ? session.status_message : "";
        dice_zone.queue_draw ();

        // При броске костей автоматически прокручиваем лог к началу
        if (session.is_rolling && session.current_player == color && !session.is_first_move_rolloff_in_progress) {
            var adj = log_scroller.get_vadjustment ();
            adj.set_value (adj.get_lower ());
        }

        rebuild_log_if_needed ();
        foreach (var c in all_cells ()) {
            c.queue_draw ();
        }
        update_footer ();

        handle_dice_state_change ();
        if (session.rolloff_animation_id != last_rolloff_anim_id) {
            last_rolloff_anim_id = session.rolloff_animation_id;
            if (session.rolloff_animation_id != 0) {
                var dice = color == CheckerColor.WHITE ? session.white_rolloff_dice : session.black_rolloff_dice;
                if (dice != null) {
                    animate_rolloff_dice_to_log (dice);
                }
            }
        }
        flying_layer.queue_draw ();
    }

    private string compute_signature () {
        var sb = new StringBuilder ();
        var active = shows_active_cell ();
        sb.append (active ? "A%d;".printf (session.current_turn_dice.length) : "-;");
        foreach (var r in my_log ()) {
            sb.append_printf ("%d;", r.id);
        }
        return sb.str;
    }

    private void rebuild_log_if_needed () {
        var sig = compute_signature ();
        if (sig == log_signature) {
            return;
        }
        log_signature = sig;

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
            }
        } else {
            if (active_cell_revealer != null) {
                log_list.remove (active_cell_revealer);
                active_cell_revealer = null;
                active_cell = null;
            }
        }

        foreach (var c in record_cells) {
            log_list.remove (c);
        }
        record_cells = new LogCellView[0];
        foreach (var r in my_log ()) {
            var cell = new LogCellView (this, r, false);
            record_cells += cell;
            log_list.append (cell);
        }

        var count = my_log ().length;
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
        if (session.is_first_move_rolloff_in_progress) {
            footer.visible = false;
            return;
        }
        footer.visible = true;
        var completed = 0;
        foreach (var r in my_log ()) {
            if (!r.is_rolloff) {
                completed++;
            }
        }
        var turn_number = (session.current_player == color && !session.is_game_over) ? completed + 1 : int.max (1, completed);
        footer.label = Localization.badge_turn_number (turn_number);
    }

    private void handle_dice_state_change () {
        var new_dice = session.current_turn_dice;
        if (session.current_player != color) {
            previous_turn_dice = TurnDie.clone_array (new_dice);
            return;
        }
        if (new_dice.length == 0) {
            remove_non_rolloff_flying ();
            pending_skipped = new int[0];
            pending_fly = new int[0];
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
            pending_fly = new int[0];
            pending_unfly = new int[0];
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

        for (var s = 0; s < to_log.length; s++) {
            var die = to_log[s];
            var stagger = s * 0.08;
            if (die.is_skipped) {
                var pause = SettingsStore.shared ().animation_speed.intermediate_step_delay;
                var skip_delay = pause + stagger;
                Timeout.add ((uint) (skip_delay * 1000), () => {
                    remove_pending (die.id);
                    start_flying (die.id, die.value, true, true);
                    return Source.REMOVE;
                });
            } else if (stagger > 0) {
                add_pending_fly (die.id);
                Timeout.add ((uint) (stagger * 1000), () => {
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
        var r = new int[0];
        foreach (var p in pending_skipped) {
            if (p != id) {
                r += p;
            }
        }
        pending_skipped = r;
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

    private void animate_rolloff_dice_to_log (DiceRoll dice) {
        int[] values = { dice.die1, dice.die2 };
        for (var idx = 0; idx < 2; idx++) {
            var fly_id = idx == 0 ? 100 : 101;
            var val = values[idx];
            if (idx == 0) {
                start_flying (fly_id, val, true, false);
            } else {
                Timeout.add (80, () => {
                    start_flying (fly_id, val, true, false);
                    return Source.REMOVE;
                });
            }
        }
    }

    private Graphene.Rect fallback_top_rect (int id) {
        var is_dbl = (session.dice_roll != null && session.dice_roll.is_double) || session.current_turn_dice.length > 2;
        var pw = (double) get_width ();
        var size = is_dbl ? 34.0 : 48.0;
        var spacing = 5.0;
        var start_x = (pw - (size * 2 + spacing)) / 2.0;
        if (id >= 100) {
            var idx = id == 100 ? 0 : 1;
            return dice_zone.rolloff_slot_rect (idx);
        }
        if (is_dbl) {
            var row = id / 2;
            var col = id % 2;
            var x = start_x + col * (size + spacing);
            var y = 40.0 + row * (size + 3);
            return Graphene.Rect ().init ((float) x, (float) y, (float) size, (float) size);
        } else {
            var x = start_x + id * (size + spacing);
            return Graphene.Rect ().init ((float) x, 48.0f, (float) size, (float) size);
        }
    }

    private Graphene.Rect fallback_log_rect (int id) {
        var is_dbl = (session.dice_roll != null && session.dice_roll.is_double) || session.current_turn_dice.length > 2;
        var pw = (double) get_width ();
        var size = 40.0;
        var spacing = is_dbl ? 5.0 : 6.0;
        var start_x = (pw - (size * 2 + spacing)) / 2.0;
        if (id >= 100) {
            var idx = id == 100 ? 0 : 1;
            var x = start_x + idx * (size + spacing);
            return Graphene.Rect ().init ((float) x, 262.0f, (float) size, (float) size);
        }
        if (is_dbl) {
            var row = id / 2;
            var col = id % 2;
            var x = start_x + col * (size + spacing);
            var y = 255.0 + row * (size + 3);
            return Graphene.Rect ().init ((float) x, (float) y, (float) size, (float) size);
        } else {
            var x = start_x + id * (size + spacing);
            return Graphene.Rect ().init ((float) x, 250.0f, (float) size, (float) size);
        }
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
        fd.start_us = GLib.get_monotonic_time ();
        var dur = SettingsStore.shared ().animation_speed.checker_move_duration;
        fd.duration = dur > 0.05 ? dur : 0.35;

        Graphene.Rect top_r;
        Graphene.Rect log_r;
        var ok_top = slot_rect (id, true, out top_r);
        var ok_log = slot_rect (id, false, out log_r);
        if (!ok_top) {
            top_r = fallback_top_rect (id);
        }
        if (!ok_log) {
            log_r = fallback_log_rect (id);
        }

        fd.from_rect = to_log ? top_r : log_r;
        fd.to_rect = to_log ? log_r : top_r;

        r += fd;
        flying = r;
        dice_zone.queue_draw ();
        foreach (var c in all_cells ()) {
            c.queue_draw ();
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
        var t = (GLib.get_monotonic_time () - skipped_cross_started_us[id]) / 250000.0;
        t = double.max (0.0, double.min (1.0, t));
        return UiKit.ease_out (t);
    }

    private void start_skipped_cross_animation (int id) {
        if (id < 0 || id >= skipped_cross_started_us.length) {
            return;
        }
        skipped_cross_started_us[id] = GLib.get_monotonic_time ();
        if (skipped_cross_tick == 0) {
            skipped_cross_tick = dice_zone.add_tick_callback (on_skipped_cross_tick);
        }
    }

    private bool on_skipped_cross_tick (Gtk.Widget widget, Gdk.FrameClock clock) {
        dice_zone.queue_draw ();
        var now = GLib.get_monotonic_time ();
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
        var now = GLib.get_monotonic_time ();
        var r = new FlyingDie[0];
        var removed = false;
        foreach (var f in flying) {
            var elapsed = (now - f.start_us) / 1000000.0;
            if (elapsed < f.duration + 0.05) {
                r += f;
            } else {
                removed = true;
            }
        }
        flying = r;
        flying_layer.queue_draw ();
        if (removed) {
            dice_zone.queue_draw ();
            foreach (var c in all_cells ()) {
                c.queue_draw ();
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
                src = dice_zone;
                var count = session.current_turn_dice.length > 0 ? session.current_turn_dice.length : 2;
                local = dice_zone.top_slot_rect (id, count);
            } else {
                if (active_cell != null && active_cell.get_mapped ()) {
                    src = active_cell;
                    local = active_cell.die_rect (id);
                } else if (record_cells.length > 0 && !record_cells[0].record.is_rolloff && record_cells[0].get_mapped ()) {
                    src = record_cells[0];
                    local = record_cells[0].die_rect (id);
                } else {
                    return false;
                }
            }
        }
        Graphene.Point p;
        if (!src.compute_point (flying_layer, Graphene.Point ().init (local.get_x (), local.get_y ()), out p)) {
            return false;
        }
        rect = Graphene.Rect ().init (p.x, p.y, local.get_width (), local.get_height ());
        return true;
    }

    /** Отрисовка траектории полёта кубика: масштаб, динамическая тень и наклон по синусоиде. */
    public void draw_flying (Cairo.Context cr, Gtk.Widget layer) {
        var now = GLib.get_monotonic_time ();
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
                                          2 + 8 * lift, 0.12 + 0.23 * lift);
            DiceDrawing.draw_full (cr, 0, 0, size, f.value, f.is_skipped ? 0.88 : 1.0, false);
            if (f.is_skipped) {
                DiceDrawing.draw_red_cross (cr, 0, 0, size);
            }
            cr.restore ();
        }
    }
}

} /* namespace Longbackgammon */
