/* game_over_view.vala
 *
 * Экран завершения игры: имя игрока и его счёт, тип исхода (Оин, Марс, Домашний марс) или поражение,
 * таблица статистики партии с пошаговым подсчётом, звёзды за победу (или списание за поражение),
 * которые по очереди влетают в бейдж общего счёта, и праздничный салют при Марсе/Домашнем марсе.
 *
 * Последовательность появления:
 * 1. Имя игрока и счёт + анимированная иконка результата
 * 2. Тип победы / плашка поражения
 * 3. Ожидание окончания победного трека (или звука поражения)
 * 4. Таблица статистики партии с подсчётом чисел
 * 5. Звёзды (1-2-3 в зависимости от типа победы) по очереди под таблицей
 * 6. Полёт звёзд в общий счёт игрока (зачисление или списание)
 * 7. Салют (только Марс / Домашний марс)
 * 8. Кнопка «Закрыть» появляется последней
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public delegate void TweenFn (double progress);

/**
 * Подпрыгивающий и покачивающийся эмодзи результата партии
 * с плавной синусоидальной анимацией масштабирования и вертикального смещения.
 */
public class BouncingEmoji : Gtk.DrawingArea {
    private string emoji;
    private int64 t0;
    private uint tick = 0;
    private Cairo.ImageSurface? emoji_surf = null;
    private int emoji_lw = 0;
    private int emoji_lh = 0;
    private int emoji_sf = 0;

    public BouncingEmoji (string emoji) {
        this.emoji = emoji;
        content_width = 96;
        content_height = 96;
        t0 = GLib.get_monotonic_time ();
        set_draw_func (draw);
        tick = add_tick_callback ((w, clock) => {
            queue_draw ();
            return GLib.Source.CONTINUE;
        });
    }

    public override void dispose () {
        if (tick != 0) {
            remove_tick_callback (tick);
            tick = 0;
        }
        base.dispose ();
    }

    private static double ping_pong (double t, double period) {
        var u = t / period;
        var k = (int) Math.floor (u);
        var f = u - k;
        return (k % 2 == 0) ? f : 1 - f;
    }

    private void ensure_emoji_surface (Gtk.DrawingArea area) {
        var sf = int.max (1, get_scale_factor ());
        if (emoji_surf != null && emoji_sf == sf) {
            return;
        }
        emoji_sf = sf;
        var layout = area.create_pango_layout (emoji);
        var fd = new Pango.FontDescription ();
        fd.set_absolute_size (64 * Pango.SCALE);
        layout.set_font_description (fd);
        layout.get_pixel_size (out emoji_lw, out emoji_lh);
        var pw = int.max (1, emoji_lw * sf);
        var ph = int.max (1, emoji_lh * sf);
        emoji_surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
        emoji_surf.set_device_scale (sf, sf);
        var ecr = new Cairo.Context (emoji_surf);
        Pango.cairo_show_layout (ecr, layout);
    }

    private void draw (Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
        var fc = get_frame_clock ();
        var now = (fc != null && fc.get_frame_time () > 0) ? fc.get_frame_time () : GLib.get_monotonic_time ();
        var t = (now - t0) / 1000000.0;
        // Масштаб 0.85 ↔ 1.08 с периодом 0.6 с, смещение 6 ↔ −4 с периодом 1.5 с
        var sc = 0.85 + 0.23 * PanelStyle.ease_in_out (ping_pong (t, 0.6));
        var dy = 6 - 10 * PanelStyle.ease_in_out (ping_pong (t, 1.5));
        ensure_emoji_surface (area);
        cr.translate (w / 2.0, h / 2.0 + dy);
        cr.scale (sc, sc);
        if (emoji_surf != null) {
            cr.set_source_surface (emoji_surf, -emoji_lw / 2.0, -emoji_lh / 2.0);
            cr.paint ();
        }
    }
}

/** Рисование объёмной звезды: золотой при победе, кораллово-красной при поражении. */
public class StarArt : Object {
    public static void draw_star (Cairo.Context cr, double cx, double cy, double radius, bool defeat, double alpha = 1.0) {
        if (radius <= 0.1) {
            return;
        }
        // Мягкая тень под звездой
        star_path (cr, cx, cy + 1.5, radius);
        cr.set_source_rgba (0, 0, 0, 0.28 * alpha);
        cr.fill ();

        star_path (cr, cx, cy, radius);
        var lg = new Cairo.Pattern.linear (0, cy - radius, 0, cy + radius);
        if (defeat) {
            lg.add_color_stop_rgba (0.0, 1.0, 0.45, 0.45, alpha);
            lg.add_color_stop_rgba (0.5, 0.95, 0.22, 0.22, alpha);
            lg.add_color_stop_rgba (1.0, 0.80, 0.10, 0.10, alpha);
        } else {
            lg.add_color_stop_rgba (0.0, 1.0, 0.94, 0.40, alpha);
            lg.add_color_stop_rgba (0.5, 1.0, 0.72, 0.10, alpha);
            lg.add_color_stop_rgba (1.0, 0.95, 0.50, 0.05, alpha);
        }
        cr.set_source (lg);
        cr.fill ();
    }

    public static void draw_halo (Cairo.Context cr, double cx, double cy, double radius, bool defeat, double alpha = 1.0) {
        if (radius <= 0.1) {
            return;
        }
        var rg = new Cairo.Pattern.radial (cx, cy, 2, cx, cy, radius);
        if (defeat) {
            rg.add_color_stop_rgba (0.0, 1.0, 0.2, 0.2, 0.45 * alpha);
            rg.add_color_stop_rgba (0.5, 1.0, 0.58, 0.0, 0.15 * alpha);
        } else {
            rg.add_color_stop_rgba (0.0, 1.0, 0.92, 0.2, 0.45 * alpha);
            rg.add_color_stop_rgba (0.5, 1.0, 0.58, 0.0, 0.15 * alpha);
        }
        rg.add_color_stop_rgba (1.0, 1.0, 0.58, 0.0, 0.0);
        cr.set_source (rg);
        cr.arc (cx, cy, radius, 0, 2 * Math.PI);
        cr.fill ();
    }

    private static void star_path (Cairo.Context cr, double cx, double cy, double radius) {
        cr.new_path ();
        for (var i = 0; i < 10; i++) {
            var a = -Math.PI / 2 + i * Math.PI / 5;
            var r = (i % 2 == 0) ? radius : radius * 0.42;
            var x = cx + r * Math.cos (a);
            var y = cy + 0.03 * radius + r * Math.sin (a);
            if (i == 0) {
                cr.move_to (x, y);
            } else {
                cr.line_to (x, y);
            }
        }
        cr.close_path ();
        cr.set_line_join (Cairo.LineJoin.ROUND);
    }
}

/** Звезда-награда под таблицей: пружинное появление (pop 0 → 1) с ореолом. */
public class RewardStar : Gtk.DrawingArea {
    public double pop = 0.0;
    public bool hidden = false;
    private bool defeat;
    private double base_radius;

    public RewardStar (bool defeat, int total) {
        this.defeat = defeat;
        base_radius = (total == 1) ? 21.0 : 17.5;
        content_width = 52;
        content_height = 52;
        can_target = false;
        set_draw_func (draw);
    }

    public void set_pop (double value) {
        pop = value;
        queue_draw ();
    }

    public void set_hidden (bool value) {
        hidden = value;
        queue_draw ();
    }

    private void draw (Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
        if (hidden || pop <= 0.001) {
            return;
        }
        var cx = w / 2.0;
        var cy = h / 2.0;
        StarArt.draw_halo (cr, cx, cy, 26.0 * pop, defeat);
        StarArt.draw_star (cr, cx, cy, base_radius * pop, defeat);
    }
}

/**
 * Прозрачный слой поверх окна результата: рисует летящую звезду по дуге
 * и кольцевые вспышки (появление звезды под таблицей, попадание в бейдж счёта).
 */
public class StarFlightLayer : Gtk.DrawingArea {
    private struct Burst {
        double x;
        double y;
        int64 t0;
        bool big;
    }

    private bool flying = false;
    private double progress = 0.0;
    private double sx = 0;
    private double sy = 0;
    private double tx = 0;
    private double ty = 0;
    private bool defeat;
    private Burst[] bursts = new Burst[0];
    private uint tick = 0;

    public StarFlightLayer (bool defeat) {
        this.defeat = defeat;
        can_target = false;
        hexpand = true;
        vexpand = true;
        set_draw_func (draw);
    }

    public override void dispose () {
        if (tick != 0) {
            remove_tick_callback (tick);
            tick = 0;
        }
        base.dispose ();
    }

    public void begin_flight (double sx, double sy, double tx, double ty) {
        this.sx = sx;
        this.sy = sy;
        this.tx = tx;
        this.ty = ty;
        progress = 0.0;
        flying = true;
        ensure_tick ();
        queue_draw ();
    }

    public void set_progress (double p) {
        progress = p;
        queue_draw ();
    }

    public void end_flight () {
        flying = false;
        queue_draw ();
    }

    /** Кольцевая вспышка: big — при появлении звезды, иначе — при попадании в бейдж. */
    public void add_burst (double x, double y, bool big) {
        var b = Burst ();
        b.x = x;
        b.y = y;
        b.t0 = GLib.get_monotonic_time ();
        b.big = big;
        bursts += b;
        ensure_tick ();
        queue_draw ();
    }

    private void ensure_tick () {
        if (tick != 0) {
            return;
        }
        tick = add_tick_callback (() => {
            var now = GLib.get_monotonic_time ();
            var keep = new Burst[0];
            foreach (var b in bursts) {
                var dur = b.big ? 0.48 : 0.36;
                if ((now - b.t0) / 1000000.0 < dur) {
                    keep += b;
                }
            }
            bursts = keep;
            queue_draw ();
            if (!flying && bursts.length == 0) {
                tick = 0;
                return GLib.Source.REMOVE;
            }
            return GLib.Source.CONTINUE;
        });
    }

    private void draw (Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
        var now = GLib.get_monotonic_time ();
        foreach (var b in bursts) {
            var dur = b.big ? 0.48 : 0.36;
            var p = UiKit.ease_out (double.min (1.0, ((now - b.t0) / 1000000.0) / dur));
            var alpha = 1.0 - p;
            var ring_r = (b.big ? 22.0 : 13.0) * (b.big ? 0.2 + 2.0 * p : 0.4 + 2.2 * p);
            if (defeat) {
                cr.set_source_rgba (1.0, 0.25, 0.25, alpha);
            } else {
                cr.set_source_rgba (1.0, 0.72, 0.12, alpha);
            }
            cr.set_line_width (2.5);
            cr.arc (b.x, b.y, ring_r, 0, 2 * Math.PI);
            cr.stroke ();

            var glow_r = (b.big ? 27.0 : 16.0) * (b.big ? 0.1 + 1.8 * p : 0.2 + 1.6 * p);
            var rg = new Cairo.Pattern.radial (b.x, b.y, 1, b.x, b.y, double.max (2.0, glow_r));
            rg.add_color_stop_rgba (0.0, 1, 1, 1, 0.95 * alpha);
            if (defeat) {
                rg.add_color_stop_rgba (0.5, 1.0, 0.2, 0.2, 0.8 * alpha);
            } else {
                rg.add_color_stop_rgba (0.5, 1.0, 0.92, 0.2, 0.75 * alpha);
            }
            rg.add_color_stop_rgba (1.0, 1.0, 0.58, 0.0, 0.0);
            cr.set_source (rg);
            cr.arc (b.x, b.y, double.max (2.0, glow_r), 0, 2 * Math.PI);
            cr.fill ();
        }

        if (flying) {
            var t = progress;
            // Квадратичная кривая Безье с изгибом дуги в сторону целевой звезды
            var mid_x = (sx + tx) / 2.0;
            var mid_y = (sy + ty) / 2.0;
            var dir = (tx >= w / 2.0) ? 1.0 : -1.0;
            var ctl_x = mid_x + dir * 50.0;
            var ctl_y = mid_y - 15.0;
            var omt = 1.0 - t;
            var x = omt * omt * sx + 2.0 * omt * t * ctl_x + t * t * tx;
            var y = omt * omt * sy + 2.0 * omt * t * ctl_y + t * t * ty;
            var scale = double.max (0.01, 1.0 - t * 0.42);
            var alpha = (t > 0.9) ? double.max (0.0, 1.0 - (t - 0.9) / 0.1) : 1.0;
            StarArt.draw_halo (cr, x, y, 24.0 * scale, defeat, alpha * 1.8);
            StarArt.draw_star (cr, x, y, 19.0 * scale, defeat, alpha);
        }
    }
}

/**
 * Модальное окно результата партии. Закрывается только кнопкой «Закрыть».
 */
public class GameOverView : Gtk.Box {
    public signal void new_game_requested ();
    public signal void close_requested ();
    /** Запрос запуска салюта (рисуется окном поверх всего интерфейса). */
    public signal void salute_requested ();

    private GameSession session;
    private CheckerColor winner;
    private CheckerColor loser;
    private CheckerColor primary_color;
    private VictoryType victory_type;
    private bool is_defeat;
    private bool is_right_side_white;
    private bool is_winner_left;
    private int score_points;
    private int start_points;
    private int final_total;
    private int displayed_total;
    private bool cancelled = false;
    private bool started = false;
    private Flasher flasher;

    private Gtk.Overlay ov;
    private StarFlightLayer flight;
    private FxBin header_fx;
    private FxBin emoji_fx;
    private FxBin capsule_fx;
    private FxBin table_fx;
    private FxBin table_head_fx;
    private FxBin badge_fx;
    private FxBin btn_fx;
    private Gtk.Box badge_box;
    private Gtk.Label total_label;
    private SFIcon? badge_star = null;
    private FxBin[] row_fx = new FxBin[0];
    private Gtk.Label[] left_labels = new Gtk.Label[0];
    private Gtk.Label[] right_labels = new Gtk.Label[0];
    private Gtk.Widget[] left_cells = new Gtk.Widget[0];
    private Gtk.Widget[] right_cells = new Gtk.Widget[0];
    private int[] left_targets = new int[0];
    private int[] right_targets = new int[0];
    private RewardStar[] stars = new RewardStar[0];

    public GameOverView (GameSession session) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        UiKit.ensure_css ();
        this.session = session;
        width_request = 400;
        add_css_class ("lb-popup");
        add_css_class ("lb-popup-gameover");
        overflow = Gtk.Overflow.HIDDEN;
        flasher = new Flasher (this);

        winner = session.board.is_winner (CheckerColor.WHITE) ? CheckerColor.WHITE : CheckerColor.BLACK;
        loser = winner.opposite ();
        is_defeat = session.is_computer_player (winner);
        primary_color = is_defeat ? loser : winner;
        victory_type = session.board.victory_type (loser);
        score_points = is_defeat ? 1 : victory_type.points ();
        is_right_side_white = (SettingsStore.shared ().board_side == BoardSide.RIGHT);
        var left_color = is_right_side_white ? CheckerColor.BLACK : CheckerColor.WHITE;
        is_winner_left = (winner == left_color);

        // Счёт игрока: при поражении очки уже списаны перед показом окна
        var primary_name = session.player_name (primary_color);
        var st = StatsStore.shared ().player_stats.lookup (primary_name);
        final_total = st != null ? st.total_points : 0;
        if (is_defeat) {
            start_points = final_total + score_points;
        } else {
            start_points = int.max (0, final_total - score_points);
        }
        displayed_total = start_points;

        var color_class = is_defeat ? "red" : "orange";

        ov = new Gtk.Overlay ();
        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
        content.margin_start = 28;
        content.margin_end = 28;
        content.margin_top = 28;
        content.margin_bottom = 28;
        ov.set_child (content);
        flight = new StarFlightLayer (is_defeat);
        ov.add_overlay (flight);
        ov.set_measure_overlay (flight, false);
        append (ov);

        // 1. Имя игрока и текущий счёт со звездой
        var name_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
        name_row.halign = Gtk.Align.CENTER;
        var name_label = UiKit.name_label (primary_name, "lb-go-name", 0.5f);
        name_label.valign = Gtk.Align.CENTER;
        name_row.append (name_label);
        total_label = UiKit.label (displayed_total.to_string (), "lb-go-total");
        if (!session.is_computer_player (primary_color)) {
            badge_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 7);
            badge_box.add_css_class ("lb-go-badge");
            badge_star = new SFIcon ("star.fill", 22, UiKit.rgba (MacColors.YELLOW));
            badge_star.valign = Gtk.Align.CENTER;
            badge_box.append (badge_star);
            total_label.valign = Gtk.Align.CENTER;
            badge_box.append (total_label);
            badge_fx = new FxBin (badge_box);
            badge_fx.valign = Gtk.Align.CENTER;
            name_row.append (badge_fx);
        }
        header_fx = new FxBin (name_row);
        header_fx.set_fx (0.85, 0.0);
        content.append (header_fx);

        // Анимированная иконка результата (настраивается в GameConfig)
        var emoji = new BouncingEmoji (is_defeat ? GameConfig.ICON_DEFEAT : victory_type.icon ());
        emoji.halign = Gtk.Align.CENTER;
        emoji_fx = new FxBin (emoji);
        emoji_fx.halign = Gtk.Align.CENTER;
        emoji_fx.set_fx (0.85, 0.0);
        content.append (emoji_fx);

        // 2. Тип победы или плашка поражения
        var victory_title = is_defeat ? Localization.log_result_loss () : victory_title_for (victory_type);
        var capsule = UiKit.label (victory_title, "lb-go-capsule " + color_class, 0.5f);
        capsule.halign = Gtk.Align.CENTER;
        capsule_fx = new FxBin (capsule);
        capsule_fx.halign = Gtk.Align.CENTER;
        capsule_fx.set_fx (0.85, 0.0);
        content.append (capsule_fx);

        // 3. Таблица статистики партии
        var table = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
        table.hexpand = true;
        table.margin_start = 4;
        table.margin_end = 4;
        var left_player_name = is_right_side_white ? session.black_player_name : session.white_player_name;
        var right_player_name = is_right_side_white ? session.white_player_name : session.black_player_name;

        var head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
        var hl = UiKit.name_label (left_player_name, "lb-caption2-bold lb-secondary", 0.5f);
        head.append (cell (hl, 90, true));
        var ht = UiKit.label (Localization.game_over_table_title ().up (), "lb-go-info", 0.5f);
        var htc = cell (ht, 0, true);
        htc.hexpand = true;
        head.append (htc);
        var hr = UiKit.name_label (right_player_name, "lb-caption2-bold lb-secondary", 0.5f);
        head.append (cell (hr, 90, true));
        head.hexpand = true;
        table_head_fx = new FxBin (head);
        table_head_fx.hexpand = true;
        table_head_fx.set_fx (1.0, 0.0);
        table.append (table_head_fx);

        add_stat_row (table, Localization.game_over_moves_stat (),
            is_right_side_white ? session.black_moves_count : session.white_moves_count,
            is_right_side_white ? session.white_moves_count : session.black_moves_count);
        add_stat_row (table, Localization.game_over_doubles_stat (),
            is_right_side_white ? session.black_doubles_count : session.white_doubles_count,
            is_right_side_white ? session.white_doubles_count : session.black_doubles_count);
        add_stat_row (table, Localization.game_over_fellout_dice_stat (),
            is_right_side_white ? session.black_total_dice_sum : session.white_total_dice_sum,
            is_right_side_white ? session.white_total_dice_sum : session.black_total_dice_sum);
        add_stat_row (table, Localization.game_over_burned_dice_stat (),
            is_right_side_white ? session.black_burned_dice_sum : session.white_burned_dice_sum,
            is_right_side_white ? session.white_burned_dice_sum : session.black_burned_dice_sum);
        table_fx = new FxBin (table);
        table_fx.hexpand = true;
        content.append (table_fx);

        // 4. Звёзды за победу / списание за поражение
        var stars_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
        stars_box.halign = Gtk.Align.CENTER;
        stars_box.height_request = 52;
        for (var i = 0; i < score_points; i++) {
            var star = new RewardStar (is_defeat, score_points);
            stars += star;
            stars_box.append (star);
        }
        content.append (stars_box);

        // 5. Кнопка «Закрыть» (появляется последней)
        var btn = UiKit.button (Localization.game_over_button_new_game (), "lb-btn-blue");
        btn.halign = Gtk.Align.CENTER;
        btn.margin_top = 4;
        btn.clicked.connect (() => { new_game_requested (); });
        btn_fx = new FxBin (btn);
        btn_fx.halign = Gtk.Align.CENTER;
        btn_fx.set_fx (0.95, 0.0);
        btn_fx.can_target = false;
        content.append (btn_fx);

        map.connect (() => {
            if (!started) {
                started = true;
                run_animations.begin ();
            }
        });
        unrealize.connect (() => { cancelled = true; });
    }

    public override void dispose () {
        cancelled = true;
        flasher.stop ();
        base.dispose ();
    }

    /** Мигание красной рамкой при попытке открыть другое окно или клике мимо. */
    public void flash () {
        flasher.flash ();
    }

    private static string victory_title_for (VictoryType type) {
        switch (type) {
        case VictoryType.HOME_MARS: return Localization.victory_home_mars ();
        case VictoryType.MARS: return Localization.victory_mars ();
        default: return Localization.victory_oin ();
        }
    }

    // MARK: - Построение таблицы

    /**
     * Ячейка таблицы. Боковые ячейки имеют фиксированную ширину (width > 0) и не растягиваются,
     * средняя (width == 0) занимает всё оставшееся место.
     */
    private static Gtk.Widget cell (Gtk.Widget child, int width, bool head = false) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        box.add_css_class ("lb-go-cell");
        if (head) {
            box.add_css_class ("head");
        }
        box.height_request = 28;
        box.valign = Gtk.Align.CENTER;
        if (width > 0) {
            box.width_request = width;
            box.hexpand = false;
            box.halign = Gtk.Align.FILL;
        } else {
            box.hexpand = true;
            box.halign = Gtk.Align.FILL;
        }
        var label = child as Gtk.Label;
        if (label != null) {
            // Текст не должен раздвигать колонки: длинное обрезается многоточием
            label.ellipsize = Pango.EllipsizeMode.END;
            label.max_width_chars = 1;
            label.width_chars = 1;
        }
        child.halign = Gtk.Align.FILL;
        child.valign = Gtk.Align.CENTER;
        child.hexpand = true;
        child.margin_start = 4;
        child.margin_end = 4;
        box.append (child);
        return box;
    }

    private void add_stat_row (Gtk.Box table, string title, int left_val, int right_val) {
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
        var ll = UiKit.label ("0", "lb-go-value", 0.5f);
        var lc = cell (ll, 90);
        row.append (lc);
        var tl = UiKit.label (title, "lb-subheadline lb-secondary", 0.5f);
        tl.ellipsize = Pango.EllipsizeMode.END;
        var tc = cell (tl, 0);
        tc.hexpand = true;
        row.append (tc);
        var rl = UiKit.label ("0", "lb-go-value", 0.5f);
        var rc = cell (rl, 90);
        row.append (rc);
        row.hexpand = true;
        var fx = new FxBin (row);
        fx.hexpand = true;
        fx.set_fx (1.0, 0.0, 4.0);
        table.append (fx);
        row_fx += fx;
        left_labels += ll;
        right_labels += rl;
        left_cells += lc;
        right_cells += rc;
        left_targets += left_val;
        right_targets += right_val;
    }

    // MARK: - Помощники анимации

    private async void pause (double seconds) {
        SourceFunc cb = pause.callback;
        GLib.Timeout.add ((uint) (seconds * 1000.0), () => {
            cb ();
            return GLib.Source.REMOVE;
        });
        yield;
    }

    /** Покадровая анимация прогресса 0…1 за заданное время. */
    private async void tween (double duration, owned TweenFn fn) {
        var start = GLib.get_monotonic_time ();
        SourceFunc cb = tween.callback;
        add_tick_callback (() => {
            if (cancelled) {
                cb ();
                return GLib.Source.REMOVE;
            }
            var p = double.min (1.0, ((GLib.get_monotonic_time () - start) / 1000000.0) / duration);
            fn (p);
            if (p >= 1.0) {
                cb ();
                return GLib.Source.REMOVE;
            }
            return GLib.Source.CONTINUE;
        });
        yield;
    }

    private async void fade_in (FxBin fx, double duration, double from_scale = 0.85) {
        yield tween (duration, (p) => {
            var e = UiKit.ease_out (p);
            fx.set_fx (from_scale + (1.0 - from_scale) * e, e);
        });
    }

    private void set_total (int value) {
        displayed_total = value;
        total_label.label = value.to_string ();
    }

    private void set_active_cell (Gtk.Widget cell_widget, bool active, bool winner = false) {
        if (active) {
            cell_widget.add_css_class ("active");
            if (winner) {
                cell_widget.add_css_class ("winner");
            }
        } else {
            cell_widget.remove_css_class ("active");
            cell_widget.remove_css_class ("winner");
        }
    }

    /** Дискретный счётчик числа с тиками (по одному щелчку на каждое изменение). */
    private async void count_up (int target, bool is_winner, Gtk.Label label) {
        if (target <= 0) {
            label.label = "0";
            yield pause (0.08);
            return;
        }
        var steps = int.min (target, 10);
        var total_duration = double.min (0.32, double.max (0.08, steps * 0.05));
        var step_delay = total_duration / steps;
        var last = 0;
        for (var step = 1; step <= steps; step++) {
            if (cancelled) {
                return;
            }
            var val = (int) Math.round ((double) target * step / steps);
            if (val != last) {
                last = val;
                label.label = val.to_string ();
                SoundManager.shared ().play_tally_tick (is_winner);
            }
            yield pause (step_delay);
        }
        label.label = target.to_string ();
    }

    private void star_center (Gtk.Widget w, out double x, out double y) {
        Graphene.Point p;
        x = 0;
        y = 0;
        if (w.compute_point (flight, Graphene.Point () { x = (float) (w.get_width () / 2.0), y = (float) (w.get_height () / 2.0) }, out p)) {
            x = p.x;
            y = p.y;
        }
    }

    /** Полёт одной звезды в бейдж счёта и зачисление/списание очка. */
    private async void fly_star (int index) {
        double sx, sy, tx, ty;
        star_center (stars[index], out sx, out sy);
        star_center (badge_star, out tx, out ty);
        stars[index].set_hidden (true);
        flight.begin_flight (sx, sy, tx, ty);
        yield tween (0.53, (p) => { flight.set_progress (UiKit.ease_in (p)); });
        if (cancelled) {
            return;
        }
        flight.end_flight ();
        flight.add_burst (tx, ty, false);

        if (is_defeat) {
            SoundManager.shared ().play_score_deduct ();
            set_total (start_points - (index + 1));
            badge_box.add_css_class ("down");
            total_label.add_css_class ("lb-red");
        } else {
            SoundManager.shared ().play_score_count_up ();
            set_total (start_points + index + 1);
            badge_box.add_css_class ("up");
            total_label.add_css_class ("lb-green");
        }
        // Пружинный «удар» бейджа: 1.25 → 1.0
        yield tween (0.32, (p) => {
            badge_fx.set_fx (1.0 + 0.25 * (1.0 - PanelStyle.spring (p * 0.4, 0.4, 0.55)), 1.0);
        });
        badge_fx.set_fx (1.0, 1.0);
        badge_box.remove_css_class ("up");
        badge_box.remove_css_class ("down");
        total_label.remove_css_class ("lb-red");
        total_label.remove_css_class ("lb-green");
    }

    // MARK: - Сценарий

    private async void run_animations () {
        // 1. Имя игрока и счёт + иконка
        yield pause (0.25);
        if (cancelled) {
            return;
        }
        fade_in.begin (header_fx, 0.45);
        yield fade_in (emoji_fx, 0.45);
        if (cancelled) {
            return;
        }

        // 2. Тип победы / плашка поражения
        yield pause (0.15);
        if (cancelled) {
            return;
        }
        yield fade_in (capsule_fx, 0.4);

        // При победе ждём окончания победного трека (~6 с), при поражении — звука поражения (~3 с)
        yield pause (is_defeat ? 2.2 : 5.15);
        if (cancelled) {
            return;
        }

        // 3. Таблица статистики
        SoundManager.shared ().play_table_entrance ();
        yield fade_in (table_head_fx, 0.25, 1.0);
        yield pause (0.32);
        for (var i = 0; i < row_fx.length; i++) {
            if (cancelled) {
                return;
            }
            var idx = i;
            var rfx = row_fx[i];
            fade_row.begin (rfx);
            yield pause (0.14);
            if (cancelled) {
                return;
            }

            // Сначала считает победитель, затем проигравший
            var win_label = is_winner_left ? left_labels[i] : right_labels[i];
            var win_cell = is_winner_left ? left_cells[i] : right_cells[i];
            var win_target = is_winner_left ? left_targets[i] : right_targets[i];
            var lose_label = is_winner_left ? right_labels[i] : left_labels[i];
            var lose_cell = is_winner_left ? right_cells[i] : left_cells[i];
            var lose_target = is_winner_left ? right_targets[i] : left_targets[i];

            set_active_cell (win_cell, true, true);
            yield count_up (win_target, true, win_label);
            set_active_cell (win_cell, false);
            yield pause (0.12);
            if (cancelled) {
                return;
            }
            set_active_cell (lose_cell, true, false);
            yield count_up (lose_target, false, lose_label);
            set_active_cell (lose_cell, false);
            if (idx < row_fx.length - 1) {
                yield pause (0.22);
            }
        }

        yield pause (0.5);
        if (cancelled) {
            return;
        }

        // 4. Звёзды под таблицей по очереди
        for (var i = 0; i < score_points; i++) {
            yield pause (0.625);
            if (cancelled) {
                return;
            }
            SoundManager.shared ().play_star_pop (i);
            double cx, cy;
            star_center (stars[i], out cx, out cy);
            flight.add_burst (cx, cy, true);
            var star = stars[i];
            yield tween (0.5, (p) => { star.set_pop (PanelStyle.spring (p * 0.9, 0.44, 0.52)); });
            star.set_pop (1.0);
        }

        yield pause (0.6);
        if (cancelled) {
            return;
        }

        // 5. Полёт звёзд в бейдж общего счёта
        if (badge_star != null) {
            for (var i = 0; i < score_points; i++) {
                if (cancelled) {
                    return;
                }
                if (i == score_points - 1) {
                    // Когда последняя звезда улетает — плавно центрируем таблицу между шапкой и кнопкой
                    shift_table.begin ();
                }
                yield fly_star (i);
                if (i < score_points - 1) {
                    yield pause (0.16);
                }
            }
        }
        if (cancelled) {
            return;
        }

        // 6. Салют только при победе Марсом или Домашним марсом
        if (!is_defeat && victory_type.is_mars_or_home_mars ()) {
            yield pause (0.08);
            if (cancelled) {
                return;
            }
            SoundManager.shared ().play_fireworks ();
            salute_requested ();
            yield pause (3.8);
        } else {
            yield pause (0.5);
        }
        if (cancelled) {
            return;
        }

        // 7. Кнопка «Закрыть»
        btn_fx.can_target = true;
        yield fade_in (btn_fx, 0.4, 0.95);
    }

    private async void fade_row (FxBin fx) {
        yield tween (0.32, (p) => {
            var e = UiKit.ease_out (p);
            fx.set_fx (1.0, e, 4.0 * (1.0 - e));
        });
    }

    private async void shift_table () {
        yield tween (0.55, (p) => {
            table_fx.set_fx (1.0, 1.0, 35.0 * PanelStyle.spring (p * 0.9, 0.55, 0.8));
        });
        table_fx.set_fx (1.0, 1.0, 35.0);
    }

    // MARK: - Отрисовка карточки

    public override void snapshot (Gtk.Snapshot snapshot) {
        var w = get_width ();
        var h = get_height ();
        Graphene.Rect r = { { 0, 0 }, { w, h } };
        var cr = snapshot.append_cairo (r);
        // Радиальный градиент фонового свечения (янтарный при победе, сдержанно-красный при поражении)
        rounded_path (cr, w, h, 24);
        cr.clip ();
        double rr = 1.0;
        double gg = is_defeat ? 0.23 : 0.58;
        double bb = is_defeat ? 0.19 : 0.0;
        var cx = w / 2.0;
        var cy = h / 2.0 - 80;
        var pat = new Cairo.Pattern.radial (cx, cy, 0, cx, cy, 165);
        pat.add_color_stop_rgba (0.0, rr, gg, bb, is_defeat ? 0.09 : 0.12);
        pat.add_color_stop_rgba (0.55, rr, gg, bb, is_defeat ? 0.07 : 0.10);
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
