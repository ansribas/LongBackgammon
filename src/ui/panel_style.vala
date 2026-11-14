/* panel_style.vala
 *
 * Оформление и вспомогательные функции рисования для боковых панелей:
 * внедрение CSS-стилей, расчёт пружинных кривых, типографика и отрисовка декоративных символов.
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
            ".lb-card { background-color: var(--popover-bg-color, @popover_bg_color); border-radius: 12px;" +
            "  border: 1px solid alpha(currentColor, 0.12); box-shadow: 0 4px 10px alpha(black, 0.12); }" +
            ".lb-card-dice { border: none; }" +
            ".lb-header-strip { min-height: 36px; background-color: alpha(currentColor, 0.06); border-bottom: 1px solid alpha(currentColor, 0.08); transition: background-color 250ms ease-in-out, border-color 250ms ease-in-out; }" +
            ".lb-header-strip-active { min-height: 36px; background-color: alpha(#ff9500, 0.12); border-bottom: 1px solid alpha(#ff9500, 0.25); transition: background-color 250ms ease-in-out, border-color 250ms ease-in-out; }" +
            ".lb-card-padded { padding: 8px 6px; }" +
            ".lb-card-hover { filter: brightness(105%); }" +
            ".lb-status-strip { background-color: alpha(currentColor, 0.08); }" +
            ".lb-subheadline-bold { font-size: 0.85rem; font-weight: bold; transition: color 250ms ease-in-out; }" +
            ".lb-caption-bold { font-size: 0.75rem; font-weight: bold; }" +
            ".lb-caption2-bold { font-size: 0.7rem; font-weight: bold; }" +
            ".lb-title3-bold { font-size: 1.05rem; font-weight: bold; font-feature-settings: \"tnum\"; }" +
            ".lb-secondary { color: alpha(currentColor, 0.6); }" +
            ".lb-tertiary { color: alpha(currentColor, 0.35); }" +
            ".lb-orange { color: #ff9500; }" +
            ".lb-log-scroller scrollbar { min-width: 0; min-height: 0; padding: 0; margin: 0; border: none; opacity: 0; }" +
            ".lb-log-scroller overshoot { opacity: 0; }" +
            ".lb-progress, .lb-progress trough { min-width: 20px; }" +
            ".lb-progress trough { min-height: 4px; border-radius: 2px; }" +
            ".lb-progress progress { min-width: 0; min-height: 4px; border-radius: 2px; background-color: @success_color; }" +
            ".lb-tooltip { background-color: alpha(var(--window-bg-color, @window_bg_color), 0.85);" +
            "  border-radius: 8px; padding: 6px 10px; box-shadow: 0 5px 10px alpha(black, 0.2);" +
            "  font-size: 0.75rem; font-weight: bold; }\n");
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

    private static Pango.FontDescription? shared_fd = null;

    private static Pango.FontDescription get_shared_fd (double px, int weight) {
        if (shared_fd == null) {
            shared_fd = new Pango.FontDescription ();
            shared_fd.set_family ("Sans");
        }
        shared_fd.set_absolute_size (px * Pango.SCALE);
        shared_fd.set_weight ((Pango.Weight) weight);
        return shared_fd;
    }

    /** Отрисовка центрированного текста через Pango. */
    public static double draw_text_centered (Cairo.Context cr, Gtk.Widget w, string text, double cx, double y,
                                             double px, int weight, double letter_spacing = 0) {
        var layout = w.create_pango_layout (text);
        layout.set_font_description (get_shared_fd (px, weight));
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
        layout.set_font_description (get_shared_fd (px, weight));
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

    /** Иконка кубка для победы. */
    public static void draw_trophy (Cairo.Context cr, double cx, double cy, double s) {
        var w = s * 0.95;
        var h = s * 0.95;
        var top = cy - h / 2.0;

        // Ручки кубка
        cr.save ();
        cr.set_line_width (s * 0.12);
        cr.new_sub_path ();
        cr.arc (cx - w * 0.24, top + h * 0.24, w * 0.22, -Math.PI / 2, Math.PI / 2);
        cr.stroke ();
        cr.new_sub_path ();
        cr.arc (cx + w * 0.24, top + h * 0.24, w * 0.22, -Math.PI / 2, Math.PI / 2);
        cr.stroke ();
        cr.restore ();

        // Чаша
        cr.move_to (cx - w * 0.35, top);
        cr.line_to (cx + w * 0.35, top);
        cr.line_to (cx + w * 0.30, top + h * 0.26);
        cr.curve_to (cx + w * 0.25, top + h * 0.50, cx + w * 0.12, top + h * 0.54, cx + w * 0.09, top + h * 0.60);
        cr.line_to (cx + w * 0.09, top + h * 0.74);
        cr.line_to (cx - w * 0.09, top + h * 0.74);
        cr.line_to (cx - w * 0.09, top + h * 0.60);
        cr.curve_to (cx - w * 0.12, top + h * 0.54, cx - w * 0.25, top + h * 0.50, cx - w * 0.30, top + h * 0.26);
        cr.close_path ();
        cr.fill ();

        // Подставка
        DiceDrawing.rounded_rect (cr, cx - w * 0.30, top + h * 0.74, w * 0.60, h * 0.20, 1.5);
        cr.fill ();
    }

    /** Иконка флага для поражения. */
    public static void draw_flag (Cairo.Context cr, double cx, double cy, double s) {
        var w = s * 0.90;
        var h = s * 0.95;
        var left = cx - w / 2.0;
        var top = cy - h / 2.0;

        // Древко
        cr.rectangle (left, top, w * 0.14, h);
        cr.fill ();

        // Полотнище флага
        cr.move_to (left + w * 0.14, top + h * 0.05);
        cr.curve_to (left + w * 0.45, top - h * 0.03, left + w * 0.65, top + h * 0.12, left + w, top + h * 0.06);
        cr.line_to (left + w, top + h * 0.52);
        cr.curve_to (left + w * 0.65, top + h * 0.58, left + w * 0.45, top + h * 0.43, left + w * 0.14, top + h * 0.50);
        cr.close_path ();
        cr.fill ();
    }
}

} /* namespace Longbackgammon */
