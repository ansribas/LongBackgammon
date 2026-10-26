/* game_over_view.vala
 *
 * Экран завершения игры: объявление победителя, тип исхода (Оин, Марс, Домашний марс),
 * начисление очков в общую статистику и детальная сводка по броскам и ходам.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Подпрыгивающий и покачивающийся эмодзи кубка/праздника (🏆/🎉)
 * с плавной синусоидальной анимацией масштабирования и вертикального смещения.
 */
public class BouncingEmoji : Gtk.DrawingArea {
    private string emoji;
    private int64 t0;
    private uint tick = 0;

    public BouncingEmoji (string emoji) {
        this.emoji = emoji;
        content_width = 96;
        content_height = 96;
        t0 = GLib.get_monotonic_time ();
        set_draw_func (draw);
        tick = add_tick_callback (() => { queue_draw (); return GLib.Source.CONTINUE; });
    }

    private static double ping_pong (double t, double period) {
        var u = t / period;
        var k = (int) Math.floor (u);
        var f = u - k;
        return (k % 2 == 0) ? f : 1 - f;
    }

    private void draw (Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
        var t = (GLib.get_monotonic_time () - t0) / 1000000.0;
        // Масштаб 0.8 ↔ 1.05 с периодом 0.6 с, смещение 10 ↔ −4 с периодом 1.5 с
        var sc = 0.8 + 0.25 * PanelStyle.ease_in_out (ping_pong (t, 0.6));
        var dy = 10 - 14 * PanelStyle.ease_in_out (ping_pong (t, 1.5));
        var layout = area.create_pango_layout (emoji);
        var fd = new Pango.FontDescription ();
        fd.set_absolute_size (64 * Pango.SCALE);
        layout.set_font_description (fd);
        int lw, lh;
        layout.get_pixel_size (out lw, out lh);
        cr.translate (w / 2.0, h / 2.0 + dy);
        cr.scale (sc, sc);
        cr.move_to (-lw / 2.0, -lh / 2.0);
        Pango.cairo_show_layout (cr, layout);
    }
}

/**
 * Карточка набранных очков («+1 / +2 / +3») с пульсирующей подсветкой контура.
 */
public class GainedPointsCard : Gtk.Box {
    public double pulse = 0.0;

    public GainedPointsCard () {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 2);
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        var w = get_width ();
        var h = get_height ();
        Graphene.Rect r = { { 0, 0 }, { w, h } };
        var cr = snapshot.append_cairo (r);
        var c = get_color ();
        var rad = 14.0;
        cr.new_sub_path ();
        cr.arc (w - rad, rad, rad, -Math.PI / 2, 0);
        cr.arc (w - rad, h - rad, rad, 0, Math.PI / 2);
        cr.arc (rad, h - rad, rad, Math.PI / 2, Math.PI);
        cr.arc (rad, rad, rad, Math.PI, 3 * Math.PI / 2);
        cr.close_path ();
        cr.set_source_rgba (c.red, c.green, c.blue, 0.04 + 0.08 * pulse);
        cr.fill_preserve ();
        cr.set_source_rgba (c.red, c.green, c.blue, 0.08 + 0.12 * pulse);
        cr.set_line_width (1);
        cr.stroke ();
        base.snapshot (snapshot);
    }
}

/**
 * Модальное окно победы с каскадным таймлайном анимаций:
 * появление победителя -> пульсация начисленных очков -> анимация суммарного счёта -> появление таблицы ходов.
 */
public class GameOverView : Gtk.Box {
    public signal void new_game_requested ();
    public signal void close_requested ();

    private GameSession session;
    private CheckerColor winner;
    private bool is_red;
    private int score_points;
    private bool is_computer;
    private int final_total;
    private int64 t0;
    private uint tick_id = 0;

    private FxBin winner_fx;
    private Gtk.Label total_label;
    private FxBin? total_fx = null;
    private FxBin? gained_fx = null;
    private GainedPointsCard? gained_card = null;
    private FxBin table_fx;
    private Gtk.Label[] stat_labels = new Gtk.Label[0];
    private int[] stat_values = new int[0];

    public GameOverView (GameSession session) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        UiKit.ensure_css ();
        this.session = session;
        width_request = 400;
        add_css_class ("lb-popup");
        add_css_class ("lb-popup-gameover");
        overflow = Gtk.Overflow.HIDDEN;

        winner = session.board.is_winner (CheckerColor.WHITE) ? CheckerColor.WHITE : CheckerColor.BLACK;
        var loser = winner.opposite ();
        var loser_off = session.board.borne_off_count (loser);
        var all_home = MoveValidator.are_all_checkers_in_home (session.board, loser);
        var is_home_mars = loser_off == 0 && all_home;
        var is_mars = loser_off == 0 && !all_home;
        is_red = is_mars || is_home_mars;
        score_points = is_home_mars ? 3 : (is_mars ? 2 : 1);
        var victory_title = is_home_mars ? Localization.victory_home_mars ()
                          : (is_mars ? Localization.victory_mars () : Localization.victory_oin ());
        is_computer = session.is_computer_player (winner);
        var wname = session.player_name (winner);
        var st = StatsStore.shared ().player_stats.lookup (wname);
        final_total = st != null ? st.total_points : 0;
        var color_class = is_red ? "red" : "orange";

        // Кнопка закрытия в правом верхнем углу
        var close_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        close_row.margin_top = 14;
        close_row.margin_start = 14;
        close_row.margin_end = 14;
        close_row.append (UiKit.spacer ());
        var close = new Gtk.Button ();
        close.add_css_class ("lb-go-close");
        close.set_child (new SFIcon ("xmark", 11, null, 0.55));
        close.set_cursor_from_name ("pointer");
        close.clicked.connect (() => { close_requested (); });
        close_row.append (close);
        append (close_row);

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 22);
        content.margin_start = 28;
        content.margin_end = 28;
        content.margin_bottom = 28;

        var emoji = new BouncingEmoji (is_red ? "🏆" : "🎉");
        emoji.halign = Gtk.Align.CENTER;
        content.append (emoji);

        // Имя победителя, текущий рейтинг и бейдж исхода (Оин/Марс/Домашний марс)
        var winner_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        var name_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        name_row.halign = Gtk.Align.CENTER;
        var name_label = UiKit.label (wname, "lb-go-name", 0.5f);
        name_label.wrap = true;
        name_label.lines = 2;
        name_label.justify = Gtk.Justification.CENTER;
        name_label.valign = Gtk.Align.BASELINE_FILL;
        name_row.append (name_label);
        total_label = UiKit.label ("", "lb-go-total");
        if (!is_computer) {
            var tb = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            var star = new SFIcon ("star.fill", 14, UiKit.rgba (MacColors.YELLOW));
            star.valign = Gtk.Align.CENTER;
            tb.append (star);
            tb.append (total_label);
            tb.valign = Gtk.Align.CENTER;
            total_fx = new FxBin (tb);
            total_fx.valign = Gtk.Align.CENTER;
            name_row.append (total_fx);
        }
        winner_box.append (name_row);
        var capsule = UiKit.label (victory_title, "lb-go-capsule " + color_class, 0.5f);
        capsule.halign = Gtk.Align.CENTER;
        winner_box.append (capsule);
        winner_fx = new FxBin (winner_box);
        content.append (winner_fx);

        // Карточка начисленных за партию очков
        if (!is_computer) {
            gained_card = new GainedPointsCard ();
            gained_card.halign = Gtk.Align.CENTER;
            var cap = UiKit.label (Localization.game_over_score_stat ().replace (":", ""), "lb-caption2-bold lb-secondary", 0.5f);
            cap.margin_top = 8;
            cap.margin_start = 24;
            cap.margin_end = 24;
            gained_card.append (cap);
            var plus = UiKit.label ("+%d".printf (score_points), "lb-go-plus lb-" + color_class, 0.5f);
            plus.margin_bottom = 8;
            plus.margin_start = 24;
            plus.margin_end = 24;
            gained_card.append (plus);
            gained_fx = new FxBin (gained_card);
            gained_fx.halign = Gtk.Align.CENTER;
            content.append (gained_fx);
        }

        // Таблица статистики матча и кнопка повтора
        var table = new Gtk.Box (Gtk.Orientation.VERTICAL, 22);
        var div = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        div.margin_start = 10;
        div.margin_end = 10;
        table.append (div);

        var head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        head.margin_start = 12;
        head.margin_end = 12;
        var bl = UiKit.label (session.black_player_name, "lb-caption2-bold lb-secondary");
        bl.width_request = 90;
        bl.max_width_chars = 1;
        bl.ellipsize = Pango.EllipsizeMode.END;
        head.append (bl);
        head.append (UiKit.spacer ());
        head.append (UiKit.label (Localization.info_section_title ().up (), "lb-go-info", 0.5f));
        head.append (UiKit.spacer ());
        var wl = UiKit.label (session.white_player_name, "lb-caption2-bold lb-secondary", 1.0f);
        wl.width_request = 90;
        wl.max_width_chars = 1;
        wl.ellipsize = Pango.EllipsizeMode.END;
        head.append (wl);
        table.append (head);

        var rows = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        rows.margin_start = 12;
        rows.margin_end = 12;
        rows.append (stat_row (Localization.game_over_moves_stat (), session.black_moves_count, session.white_moves_count));
        rows.append (stat_row (Localization.game_over_doubles_stat (), session.black_doubles_count, session.white_doubles_count));
        rows.append (stat_row (Localization.game_over_fellout_dice_stat (), session.black_total_dice_sum, session.white_total_dice_sum));
        rows.append (stat_row (Localization.game_over_burned_dice_stat (), session.black_burned_dice_sum, session.white_burned_dice_sum));
        table.append (rows);

        var btn = new Gtk.Button.with_label (Localization.game_over_button_new_game ());
        btn.add_css_class ("lb-go-btn");
        btn.add_css_class (color_class);
        btn.set_cursor_from_name ("pointer");
        btn.margin_top = 8;
        btn.clicked.connect (() => { new_game_requested (); });
        table.append (btn);
        table_fx = new FxBin (table);
        content.append (table_fx);
        append (content);

        t0 = GLib.get_monotonic_time ();
        update_animation ();
        tick_id = add_tick_callback (() => {
            update_animation ();
            return GLib.Source.CONTINUE;
        });
    }

    private Gtk.Widget stat_row (string title, int black_val, int white_val) {
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        var b = UiKit.label ("0", "lb-headline");
        b.width_request = 50;
        row.append (b);
        row.append (UiKit.spacer ());
        row.append (UiKit.label (title, "lb-subheadline lb-secondary", 0.5f));
        row.append (UiKit.spacer ());
        var w = UiKit.label ("0", "lb-headline", 1.0f);
        w.width_request = 50;
        row.append (w);
        stat_labels += b;
        stat_values += black_val;
        stat_labels += w;
        stat_values += white_val;
        return row;
    }

    /**
     * Пошаговый расчёт фаз анимации:
     * - 0.15 c .. 0.40 c: появление плашки победителя (масштаб + прозрачность);
     * - 0.65 c .. 1.90 c: появление и пульсация начисленных очков;
     * - 2.10 c .. 2.60 c: пружинное увеличение итогового счёта;
     * - table_start + 0.6 c: плавное нарастание чисел статистики в таблице.
     */
    private void update_animation () {
        var t = (GLib.get_monotonic_time () - t0) / 1000000.0;

        // Фаза 1: появление победителя
        var pw = UiKit.ease_out ((t - 0.15) / 0.25);
        winner_fx.set_fx (0.9 + 0.1 * pw, pw);

        double table_start;
        if (is_computer) {
            table_start = 0.55;
            total_label.label = final_total.to_string ();
        } else {
            table_start = 3.0;
            // Фаза 2: карточка начисленных очков
            var pg = UiKit.ease_out ((t - 0.65) / 0.25);
            double pulse = 0.0;
            if (t >= 0.65 && t < 1.65) {
                var u = (t - 0.65) / 0.25;
                var k = (int) Math.floor (u);
                var f = u - k;
                pulse = (k % 2 == 0) ? PanelStyle.ease_in_out (f) : 1 - PanelStyle.ease_in_out (f);
            } else if (t >= 1.65 && t < 1.9) {
                pulse = 1.0;
            } else if (t >= 1.9) {
                pulse = 1.0 - UiKit.ease_in ((t - 1.9) / 0.2);
            }
            gained_card.pulse = pulse;
            gained_card.queue_draw ();
            gained_fx.set_fx ((0.8 + 0.2 * pg) * (1 + 0.05 * pulse), pg);

            // Фаза 3: пружинное начисление очков в счетчик игрока
            var shown = t >= 2.1 ? final_total : int.max (0, final_total - score_points);
            total_label.label = shown.to_string ();
            double sc = 1.0;
            if (t >= 2.1 && t < 2.6) {
                sc = 1.0 + 0.4 * PanelStyle.spring (t - 2.1, 0.5, 0.6);
            } else if (t >= 2.6) {
                var from = 1.0 + 0.4 * PanelStyle.spring (0.5, 0.5, 0.6);
                sc = from + (1.0 - from) * PanelStyle.spring (t - 2.6, 0.4, 0.6);
            }
            total_fx.set_fx (sc, 1.0);
            if (t >= 2.1 && t < 2.6) {
                total_label.add_css_class ("lb-green");
            } else {
                total_label.remove_css_class ("lb-green");
            }
        }

        // Фаза 4: появление таблицы матча со счётчиками
        var pt = UiKit.ease_out ((t - table_start) / 0.25);
        table_fx.set_fx (1.0, pt, 20 * (1 - pt));
        var progress = UiKit.ease_out ((t - table_start) / 0.6);
        for (var i = 0; i < stat_labels.length; i++) {
            stat_labels[i].label = ((int) (stat_values[i] * progress)).to_string ();
        }

        if (t > table_start + 1.0 && tick_id != 0) {
            remove_tick_callback (tick_id);
            tick_id = 0;
        }
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        var w = get_width ();
        var h = get_height ();
        Graphene.Rect r = { { 0, 0 }, { w, h } };
        var cr = snapshot.append_cairo (r);
        // Радиальный градиент фонового свечения
        rounded_path (cr, w, h, 24);
        cr.clip ();
        var cx = w / 2.0;
        var cy = h / 2.0 - 80;
        var pat = new Cairo.Pattern.radial (cx, cy, 0, cx, cy, 165);
        double rr = is_red ? 1.0 : 1.0;
        double gg = is_red ? 0.23 : 0.58;
        double bb = is_red ? 0.19 : 0.0;
        pat.add_color_stop_rgba (0.0, rr, gg, bb, 0.12);
        pat.add_color_stop_rgba (0.55, rr, gg, bb, 0.10);
        pat.add_color_stop_rgba (1.0, rr, gg, bb, 0.0);
        cr.set_source (pat);
        cr.paint ();

        base.snapshot (snapshot);

        // Градиентная рамка карточки сверху вниз
        var cr2 = snapshot.append_cairo (r);
        rounded_path (cr2, w, h, 24, 0.75);
        var lg = new Cairo.Pattern.linear (0, 0, 0, h);
        lg.add_color_stop_rgba (0, rr, gg, bb, 0.3);
        lg.add_color_stop_rgba (1, rr, gg, bb, 0.0);
        cr2.set_source (lg);
        cr2.set_line_width (1.5);
        cr2.stroke ();
    }

    private static void rounded_path (Cairo.Context cr, double w, double h, double r, double inset = 0) {
        var x = inset;
        var y = inset;
        w -= inset * 2;
        h -= inset * 2;
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
        cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
        cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
        cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
        cr.close_path ();
    }
}

} /* namespace Longbackgammon */
