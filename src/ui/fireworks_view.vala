/* fireworks_view.vala
 *
 * Праздничный салют для экрана победы: каскад разноцветных кометных искр со шлейфами,
 * мерцающих звёздочек, светящихся шаров и золотой пыли. Рисуется на прозрачном слое
 * поверх всего окна и вылетает далеко за границы карточки результата.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class FireworksView : Gtk.DrawingArea {
    private enum Kind {
        STREAK,   // искра с огненным шлейфом
        SPARKLE,  // 4-лучевая звёздочка
        ORB,      // крупный светящийся шар
        GLITTER   // мелкая мерцающая пыль
    }

    private struct Spark {
        int id;
        double ox;
        double oy;
        double angle;
        double speed;
        int color;
        double size;
        double delay;
        double life;
        Kind kind;
    }

    private const double[,] PALETTE = {
        { 1.00, 0.92, 0.30 },  // яркое золото
        { 1.00, 0.58, 0.12 },  // янтарно-оранжевый
        { 1.00, 0.28, 0.48 },  // неоновый рубин
        { 0.25, 0.88, 1.00 },  // электрический циан
        { 0.35, 1.00, 0.50 },  // изумрудно-зелёный
        { 0.92, 0.45, 1.00 },  // пурпурный
        { 1.00, 0.75, 0.85 },  // нежно-розовый
        { 1.00, 1.00, 1.00 }   // белый
    };

    private Spark[] sparks = new Spark[0];
    private int64 t0 = 0;
    private double total_duration = 0.0;
    private uint tick = 0;

    /** Смещение центра салюта относительно центра слоя (пикселей). */
    public double center_dy = -40.0;

    public FireworksView () {
        can_target = false;
        hexpand = true;
        vexpand = true;
        visible = false;
        set_draw_func (draw);
    }

    public override void dispose () {
        stop ();
        base.dispose ();
    }

    public void stop () {
        if (tick != 0) {
            remove_tick_callback (tick);
            tick = 0;
        }
        visible = false;
        sparks = new Spark[0];
    }

    /** Запускает залпы. Тайминги подогнаны под пики звука fireworks.wav. */
    public void start () {
        stop ();
        // (x, y, задержка, количество искр)
        double[,] bursts = {
            { -160, -130, 0.08, 38 }, { 160, -120, 0.26, 38 }, { 0, -190, 0.40, 42 }, { -70, -220, 0.70, 40 },
            { -210, -80, 1.54, 42 }, { 210, -90, 1.68, 42 }, { 0, -120, 1.94, 44 },
            { -150, -180, 2.20, 46 }, { 150, -170, 2.46, 46 }, { 0, -250, 2.68, 56 }
        };
        var list = new Spark[0];
        var id = 0;
        total_duration = 0.0;
        for (var b = 0; b < bursts.length[0]; b++) {
            var count = (int) bursts[b, 3];
            for (var i = 0; i < count; i++) {
                var s = Spark ();
                s.id = id++;
                s.ox = bursts[b, 0];
                s.oy = bursts[b, 1];
                s.delay = bursts[b, 2];
                s.angle = GLib.Random.double_range (0, 2 * Math.PI);
                s.speed = GLib.Random.double_range (90, 290);
                s.color = GLib.Random.int_range (0, 8);
                s.life = GLib.Random.double_range (2.2, 3.4);
                var roll = i % 10;
                if (roll < 4) {
                    s.kind = Kind.STREAK;
                    s.size = GLib.Random.double_range (8, 14);
                } else if (roll < 7) {
                    s.kind = Kind.SPARKLE;
                    s.size = GLib.Random.double_range (6, 11);
                } else if (roll < 9) {
                    s.kind = Kind.ORB;
                    s.size = GLib.Random.double_range (10, 16);
                } else {
                    s.kind = Kind.GLITTER;
                    s.size = GLib.Random.double_range (3.5, 5.5);
                }
                total_duration = double.max (total_duration, s.delay + s.life);
                list += s;
            }
        }
        sparks = list;
        t0 = GLib.get_monotonic_time ();
        visible = true;
        tick = add_tick_callback (() => {
            var t = (GLib.get_monotonic_time () - t0) / 1000000.0;
            if (t > total_duration) {
                stop ();
                return GLib.Source.REMOVE;
            }
            queue_draw ();
            return GLib.Source.CONTINUE;
        });
    }

    private void draw (Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
        if (sparks.length == 0) {
            return;
        }
        var elapsed = (GLib.get_monotonic_time () - t0) / 1000000.0;
        var cx = w / 2.0;
        var cy = h / 2.0 + center_dy;
        cr.set_line_cap (Cairo.LineCap.ROUND);

        foreach (var sp in sparks) {
            var t = elapsed - sp.delay;
            if (t <= 0 || t >= sp.life) {
                continue;
            }
            var progress = t / sp.life;
            // Затухание скорости + мягкая гравитация
            var cur_speed = sp.speed * (1.0 - progress * 0.45);
            var dist = cur_speed * t;
            var x = cx + sp.ox + Math.cos (sp.angle) * dist;
            var y = cy + sp.oy + Math.sin (sp.angle) * dist + 42.0 * t * t;
            var flicker = 0.82 + 0.18 * Math.sin (t * 32.0 + sp.id * 11);
            var alpha = double.max (0.0, (1.0 - progress) * flicker);
            var size = sp.size * (1.0 - progress * 0.35);
            var r = PALETTE[sp.color, 0];
            var g = PALETTE[sp.color, 1];
            var b = PALETTE[sp.color, 2];

            switch (sp.kind) {
            case Kind.STREAK:
                var tail = double.max (6.0, cur_speed * 0.14 * (1.0 - progress * 0.6));
                cr.set_source_rgba (r, g, b, alpha * 0.85);
                cr.set_line_width (size * 0.65);
                cr.move_to (x - Math.cos (sp.angle) * tail, y - Math.sin (sp.angle) * tail);
                cr.line_to (x, y);
                cr.stroke ();
                cr.set_source_rgba (1, 1, 1, alpha * 0.95);
                cr.arc (x, y, size * 0.4, 0, 2 * Math.PI);
                cr.fill ();
                break;
            case Kind.SPARKLE:
                var ray = size * 2.2;
                cr.set_source_rgba (r, g, b, alpha * 0.9);
                cr.set_line_width (double.max (1.5, size * 0.35));
                cr.move_to (x - ray, y);
                cr.line_to (x + ray, y);
                cr.move_to (x, y - ray);
                cr.line_to (x, y + ray);
                cr.stroke ();
                cr.set_source_rgba (1, 1, 1, alpha);
                cr.arc (x, y, size * 0.375, 0, 2 * Math.PI);
                cr.fill ();
                break;
            case Kind.ORB:
                cr.set_source_rgba (r, g, b, alpha * 0.32);
                cr.arc (x, y, size * 1.1, 0, 2 * Math.PI);
                cr.fill ();
                cr.set_source_rgba (r, g, b, alpha);
                cr.arc (x, y, size / 2, 0, 2 * Math.PI);
                cr.fill ();
                cr.set_source_rgba (1, 1, 1, alpha * 0.9);
                cr.arc (x, y, size * 0.2, 0, 2 * Math.PI);
                cr.fill ();
                break;
            default:
                var gs = size * (0.8 + 0.4 * Math.sin (t * 40.0 + sp.id));
                cr.set_source_rgba (r, g, b, alpha * 0.9);
                cr.arc (x, y, gs / 2, 0, 2 * Math.PI);
                cr.fill ();
                break;
            }
        }
    }
}

} /* namespace Longbackgammon */

