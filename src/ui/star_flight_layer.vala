/* star_flight_layer.vala
 *
 * Анимации звёздного вознаграждения, кольцевых вспышек и покачивающегося эмодзи результата.
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

} /* namespace Longbackgammon */
