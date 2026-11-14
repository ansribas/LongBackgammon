/* sf_icon.vala
 *
 * Векторные иконки (аналоги SF Symbols), нарисованные через Cairo.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

// MARK: - Векторные иконки (аналоги SF Symbols)

/** Иконка, нарисованная Cairo. Если задан tile_color — рисуется в цветной плитке (как SettingsRow). */
public class SFIcon : Gtk.DrawingArea {
    public string glyph;
    public Gdk.RGBA? color = null;      // null — основной цвет текста
    public double fg_alpha = 1.0;
    public Gdk.RGBA? tile_color = null;

    private Cairo.ImageSurface? cached_surface = null;
    private int cached_w = 0;
    private int cached_h = 0;
    private int cached_sf = 0;
    private float cached_r = -1.0f;
    private float cached_g = -1.0f;
    private float cached_b = -1.0f;
    private float cached_a = -1.0f;

    public SFIcon (string glyph, int size, Gdk.RGBA? color = null, double fg_alpha = 1.0) {
        this.glyph = glyph;
        this.color = color;
        this.fg_alpha = fg_alpha;
        content_width = size;
        content_height = size;
        can_target = false;
        set_draw_func (draw);
    }

    public static SFIcon tile (string glyph, string color_spec) {
        var i = new SFIcon (glyph, 28);
        i.tile_color = UiKit.rgba (color_spec);
        return i;
    }

    public void set_glyph (string g) {
        if (glyph == g) {
            return;
        }
        glyph = g;
        cached_surface = null;
        queue_draw ();
    }

    private void draw (Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
        if (w <= 0 || h <= 0) {
            return;
        }
        var sf = int.max (1, get_scale_factor ());
        Gdk.RGBA c;
        if (tile_color != null) {
            c = UiKit.rgba ("#ffffff");
        } else {
            c = (color != null) ? color : get_color ();
            c.alpha = (float) (c.alpha * fg_alpha);
        }

        if (cached_surface == null || cached_w != w || cached_h != h || cached_sf != sf
            || cached_r != c.red || cached_g != c.green || cached_b != c.blue || cached_a != c.alpha) {
            cached_w = w;
            cached_h = h;
            cached_sf = sf;
            cached_r = c.red;
            cached_g = c.green;
            cached_b = c.blue;
            cached_a = c.alpha;

            cached_surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w * sf, h * sf);
            cached_surface.set_device_scale (sf, sf);
            var icr = new Cairo.Context (cached_surface);

            double s = double.min (w, h);
            double ox = (w - s) / 2.0;
            double oy = (h - s) / 2.0;
            if (tile_color != null) {
                // Плитка 28×28, радиус 6, белый глиф ~16pt
                icr.set_source_rgba (tile_color.red, tile_color.green, tile_color.blue, tile_color.alpha);
                rounded (icr, ox, oy, s, s, s * 0.214);
                icr.fill ();
                var gs = s * 0.6;
                ox += (s - gs) / 2.0;
                oy += (s - gs) / 2.0;
                s = gs;
            }
            icr.save ();
            icr.translate (ox, oy);
            icr.scale (s, s);
            icr.push_group ();
            icr.set_source_rgba (c.red, c.green, c.blue, 1.0);
            draw_glyph (icr, glyph);
            icr.pop_group_to_source ();
            icr.paint_with_alpha (c.alpha);
            icr.restore ();
        }

        cr.set_source_surface (cached_surface, 0, 0);
        cr.paint ();
    }

    private static void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
        cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
        cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
        cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
        cr.close_path ();
    }

    /** Рисует «вырез» (прозрачность) поверх уже нарисованного внутри группы. */
    private static void knockout_begin (Cairo.Context cr) {
        cr.save ();
        cr.set_operator (Cairo.Operator.CLEAR);
    }

    private static void knockout_end (Cairo.Context cr) {
        cr.restore ();
    }

    private static void person (Cairo.Context cr, double cx, double top, double k) {
        cr.arc (cx, top + 0.2 * k, 0.17 * k, 0, 2 * Math.PI);
        cr.fill ();
        cr.save ();
        cr.translate (cx, top + 0.92 * k);
        cr.scale (0.34 * k, 0.4 * k);
        cr.arc (0, 0, 1, Math.PI, 2 * Math.PI);
        cr.close_path ();
        cr.restore ();
        cr.fill ();
    }

    private static void draw_glyph (Cairo.Context cr, string g) {
        cr.set_line_cap (Cairo.LineCap.ROUND);
        cr.set_line_join (Cairo.LineJoin.ROUND);
        switch (g) {
        case "xmark.circle.fill":
            cr.arc (0.5, 0.5, 0.5, 0, 2 * Math.PI);
            cr.fill ();
            knockout_begin (cr);
            cr.set_line_width (0.09);
            cr.move_to (0.33, 0.33);
            cr.line_to (0.67, 0.67);
            cr.move_to (0.67, 0.33);
            cr.line_to (0.33, 0.67);
            cr.stroke ();
            knockout_end (cr);
            break;
        case "xmark":
            cr.set_line_width (0.16);
            cr.move_to (0.18, 0.18);
            cr.line_to (0.82, 0.82);
            cr.move_to (0.82, 0.18);
            cr.line_to (0.18, 0.82);
            cr.stroke ();
            break;
        case "gearshape.fill":
            int teeth = 8;
            cr.new_path ();
            for (var i = 0; i < teeth * 2; i++) {
                var a0 = (i * Math.PI / teeth) - Math.PI / (teeth * 2.2);
                var a1 = (i * Math.PI / teeth) + Math.PI / (teeth * 2.2);
                var r = (i % 2 == 0) ? 0.5 : 0.39;
                cr.arc (0.5, 0.5, r, a0, a1);
            }
            cr.close_path ();
            cr.fill ();
            knockout_begin (cr);
            cr.arc (0.5, 0.5, 0.16, 0, 2 * Math.PI);
            cr.fill ();
            knockout_end (cr);
            break;
        case "chart.bar.fill":
            rounded (cr, 0.06, 0.48, 0.24, 0.46, 0.05);
            rounded (cr, 0.38, 0.12, 0.24, 0.82, 0.05);
            rounded (cr, 0.70, 0.32, 0.24, 0.62, 0.05);
            cr.fill ();
            break;
        case "chart.bar.xaxis":
            rounded (cr, 0.14, 0.45, 0.16, 0.4, 0.04);
            rounded (cr, 0.42, 0.15, 0.16, 0.7, 0.04);
            rounded (cr, 0.70, 0.32, 0.16, 0.53, 0.04);
            cr.fill ();
            cr.set_line_width (0.06);
            cr.move_to (0.04, 0.93);
            cr.line_to (0.96, 0.93);
            cr.stroke ();
            break;
        case "speaker.wave.2.fill":
        case "speaker.slash.fill":
            cr.move_to (0.04, 0.36);
            cr.line_to (0.22, 0.36);
            cr.line_to (0.48, 0.12);
            cr.line_to (0.48, 0.88);
            cr.line_to (0.22, 0.64);
            cr.line_to (0.04, 0.64);
            cr.close_path ();
            cr.fill ();
            cr.set_line_width (0.08);
            if (g == "speaker.wave.2.fill") {
                cr.arc (0.48, 0.5, 0.2, -Math.PI / 4, Math.PI / 4);
                cr.stroke ();
                cr.arc (0.48, 0.5, 0.36, -Math.PI / 3.2, Math.PI / 3.2);
                cr.stroke ();
            } else {
                knockout_begin (cr);
                cr.set_line_width (0.2);
                cr.move_to (0.1, 0.06);
                cr.line_to (0.9, 0.94);
                cr.stroke ();
                knockout_end (cr);
                cr.set_line_width (0.08);
                cr.move_to (0.1, 0.06);
                cr.line_to (0.9, 0.94);
                cr.stroke ();
            }
            break;
        case "character.bubble":
            rounded (cr, 0.02, 0.06, 0.96, 0.7, 0.2);
            cr.fill ();
            cr.move_to (0.22, 0.7);
            cr.line_to (0.16, 0.96);
            cr.line_to (0.44, 0.74);
            cr.close_path ();
            cr.fill ();
            knockout_begin (cr);
            cr.set_line_width (0.08);
            cr.move_to (0.33, 0.6);
            cr.line_to (0.5, 0.2);
            cr.line_to (0.67, 0.6);
            cr.move_to (0.39, 0.47);
            cr.line_to (0.61, 0.47);
            cr.stroke ();
            knockout_end (cr);
            break;
        case "gauge":
            cr.set_line_width (0.1);
            cr.arc (0.5, 0.58, 0.42, Math.PI * 0.8, Math.PI * 2.2);
            cr.stroke ();
            cr.set_line_width (0.09);
            cr.move_to (0.5, 0.58);
            cr.line_to (0.5 + 0.28 * Math.cos (-Math.PI * 0.3), 0.58 + 0.28 * Math.sin (-Math.PI * 0.3));
            cr.stroke ();
            cr.arc (0.5, 0.58, 0.08, 0, 2 * Math.PI);
            cr.fill ();
            break;
        case "percent":
            cr.set_line_width (0.1);
            cr.move_to (0.8, 0.15);
            cr.line_to (0.2, 0.85);
            cr.stroke ();
            cr.arc (0.28, 0.28, 0.13, 0, 2 * Math.PI);
            cr.stroke ();
            cr.arc (0.72, 0.72, 0.13, 0, 2 * Math.PI);
            cr.stroke ();
            break;
        case "hand.draw.fill":
            // Ладонь с пальцами
            rounded (cr, 0.22, 0.42, 0.56, 0.5, 0.18);
            cr.fill ();
            double[] fx = { 0.25, 0.38, 0.51, 0.64 };
            double[] ft = { 0.16, 0.06, 0.08, 0.18 };
            for (var i = 0; i < 4; i++) {
                rounded (cr, fx[i], ft[i], 0.12, 0.5, 0.06);
                cr.fill ();
            }
            cr.save ();
            cr.translate (0.78, 0.6);
            cr.rotate (-0.7);
            rounded (cr, -0.06, -0.24, 0.12, 0.3, 0.06);
            cr.restore ();
            cr.fill ();
            break;
        case "person.fill":
            person (cr, 0.5, 0.04, 1.0);
            break;
        case "person.2.fill":
            person (cr, 0.66, 0.14, 0.8);
            person (cr, 0.36, 0.08, 0.86);
            break;
        case "desktopcomputer":
            rounded (cr, 0.02, 0.1, 0.96, 0.6, 0.08);
            cr.fill ();
            cr.rectangle (0.42, 0.7, 0.16, 0.14);
            cr.fill ();
            rounded (cr, 0.26, 0.82, 0.48, 0.08, 0.04);
            cr.fill ();
            break;
        case "cpu":
            // Процессор / графический чип с выводами
            rounded (cr, 0.20, 0.20, 0.60, 0.60, 0.12);
            cr.fill ();
            knockout_begin (cr);
            rounded (cr, 0.34, 0.34, 0.32, 0.32, 0.05);
            cr.fill ();
            knockout_end (cr);
            cr.set_line_width (0.08);
            double[] pins = { 0.34, 0.50, 0.66 };
            foreach (var p in pins) {
                cr.move_to (p, 0.06); cr.line_to (p, 0.20);
                cr.move_to (p, 0.80); cr.line_to (p, 0.94);
                cr.move_to (0.06, p); cr.line_to (0.20, p);
                cr.move_to (0.80, p); cr.line_to (0.94, p);
            }
            cr.stroke ();
            break;
        case "ant.fill":
            cr.arc (0.5, 0.17, 0.1, 0, 2 * Math.PI);
            cr.fill ();
            cr.save ();
            cr.translate (0.5, 0.4);
            cr.scale (0.11, 0.13);
            cr.arc (0, 0, 1, 0, 2 * Math.PI);
            cr.restore ();
            cr.fill ();
            cr.save ();
            cr.translate (0.5, 0.72);
            cr.scale (0.17, 0.22);
            cr.arc (0, 0, 1, 0, 2 * Math.PI);
            cr.restore ();
            cr.fill ();
            cr.set_line_width (0.06);
            double[] ly = { 0.32, 0.42, 0.52 };
            double[] ty = { 0.22, 0.42, 0.66 };
            for (var i = 0; i < 3; i++) {
                cr.move_to (0.42, ly[i]);
                cr.line_to (0.12, ty[i]);
                cr.move_to (0.58, ly[i]);
                cr.line_to (0.88, ty[i]);
            }
            cr.move_to (0.45, 0.1);
            cr.line_to (0.36, 0.0);
            cr.move_to (0.55, 0.1);
            cr.line_to (0.64, 0.0);
            cr.stroke ();
            break;
        case "paintpalette.fill":
            // Палитра художника с отверстием и красками
            cr.arc (0.5, 0.5, 0.44, 0, 2 * Math.PI);
            cr.fill ();
            knockout_begin (cr);
            cr.arc (0.7, 0.65, 0.1, 0, 2 * Math.PI);
            cr.fill ();
            double[] clx = { 0.3, 0.45, 0.35, 0.22 };
            double[] cly = { 0.25, 0.32, 0.52, 0.45 };
            for (var i = 0; i < 4; i++) {
                cr.arc (clx[i], cly[i], 0.06, 0, 2 * Math.PI);
                cr.fill ();
            }
            knockout_end (cr);
            break;
        case "brain.head.profile":
            // Профиль головы
            cr.arc (0.5, 0.35, 0.28, 0, 2 * Math.PI);
            cr.fill ();
            cr.move_to (0.35, 0.55);
            cr.line_to (0.35, 0.88);
            cr.line_to (0.65, 0.88);
            cr.line_to (0.65, 0.55);
            cr.close_path ();
            cr.fill ();
            cr.move_to (0.68, 0.4);
            cr.line_to (0.82, 0.46);
            cr.line_to (0.68, 0.52);
            cr.close_path ();
            cr.fill ();
            break;
        case "move.3d":
            // 3D изометрический куб / оси
            cr.set_line_width (0.08);
            cr.move_to (0.5, 0.1);
            cr.line_to (0.85, 0.3);
            cr.line_to (0.85, 0.7);
            cr.line_to (0.5, 0.9);
            cr.line_to (0.15, 0.7);
            cr.line_to (0.15, 0.3);
            cr.close_path ();
            cr.stroke ();
            cr.move_to (0.5, 0.5);
            cr.line_to (0.5, 0.9);
            cr.move_to (0.5, 0.5);
            cr.line_to (0.85, 0.3);
            cr.move_to (0.5, 0.5);
            cr.line_to (0.15, 0.3);
            cr.stroke ();
            break;
        case "arrowshape.turn.up.right.fill":
            // Изогнутая стрелка лога
            cr.set_line_width (0.12);
            cr.move_to (0.2, 0.8);
            cr.curve_to (0.2, 0.4, 0.4, 0.3, 0.7, 0.3);
            cr.stroke ();
            arrow_head (cr, 0.7, 0.3, 0);
            break;
        case "number.circle.fill":
            // Круг с решёткой
            cr.arc (0.5, 0.5, 0.44, 0, 2 * Math.PI);
            cr.fill ();
            knockout_begin (cr);
            cr.set_line_width (0.07);
            cr.move_to (0.38, 0.22); cr.line_to (0.34, 0.78);
            cr.move_to (0.62, 0.22); cr.line_to (0.58, 0.78);
            cr.move_to (0.22, 0.42); cr.line_to (0.78, 0.42);
            cr.move_to (0.22, 0.60); cr.line_to (0.78, 0.60);
            cr.stroke ();
            knockout_end (cr);
            break;
        case "die.face.5.fill":
        case "dice.fill":
            rounded (cr, 0.06, 0.06, 0.88, 0.88, 0.2);
            cr.fill ();
            knockout_begin (cr);
            double[] px = { 0.3, 0.7, 0.5, 0.3, 0.7 };
            double[] py = { 0.3, 0.3, 0.5, 0.7, 0.7 };
            for (var i = 0; i < 5; i++) {
                cr.arc (px[i], py[i], 0.08, 0, 2 * Math.PI);
                cr.fill ();
            }
            knockout_end (cr);
            break;
        case "arrow.triangle.2.circlepath":
            cr.set_line_width (0.08);
            // Верхняя дуга со стрелкой вправо, нижняя — со стрелкой влево
            cr.arc (0.5, 0.5, 0.34, Math.PI * 1.08, Math.PI * 1.85);
            cr.stroke ();
            arrow_head (cr, 0.5 + 0.34 * Math.cos (Math.PI * 1.85), 0.5 + 0.34 * Math.sin (Math.PI * 1.85), Math.PI * 1.85 + Math.PI / 2);
            cr.arc (0.5, 0.5, 0.34, Math.PI * 0.08, Math.PI * 0.85);
            cr.stroke ();
            arrow_head (cr, 0.5 + 0.34 * Math.cos (Math.PI * 0.85), 0.5 + 0.34 * Math.sin (Math.PI * 0.85), Math.PI * 0.85 + Math.PI / 2);
            break;
        case "star.fill":
            cr.new_path ();
            for (var i = 0; i < 10; i++) {
                var a = -Math.PI / 2 + i * Math.PI / 5;
                var r = (i % 2 == 0) ? 0.5 : 0.21;
                var x = 0.5 + r * Math.cos (a);
                var y = 0.53 + r * Math.sin (a);
                if (i == 0) {
                    cr.move_to (x, y);
                } else {
                    cr.line_to (x, y);
                }
            }
            cr.close_path ();
            cr.fill ();
            break;
        case "line.3.horizontal":
            cr.set_line_width (0.1);
            for (var i = 0; i < 3; i++) {
                cr.move_to (0.12, 0.22 + i * 0.28);
                cr.line_to (0.88, 0.22 + i * 0.28);
            }
            cr.stroke ();
            break;
        case "rectangle.lefthalf.inset.filled":
            cr.set_line_width (0.08);
            rounded (cr, 0.06, 0.16, 0.88, 0.68, 0.14);
            cr.stroke ();
            rounded (cr, 0.16, 0.26, 0.32, 0.48, 0.07);
            cr.fill ();
            break;
        default:
            break;
        }
    }

    private static void arrow_head (Cairo.Context cr, double x, double y, double angle) {
        var l = 0.2;
        cr.move_to (x + l * Math.cos (angle), y + l * Math.sin (angle));
        cr.line_to (x + l * 0.6 * Math.cos (angle + 2.2), y + l * 0.6 * Math.sin (angle + 2.2));
        cr.line_to (x + l * 0.6 * Math.cos (angle - 2.2), y + l * 0.6 * Math.sin (angle - 2.2));
        cr.close_path ();
        cr.fill ();
    }
}

} /* namespace Longbackgammon */
