/* ui_kit.vala
 *
 * Общие элементы пользовательского интерфейса: стили всплывающих окон,
 * векторные пиктограммы, анимируемые контейнеры,
 * секции настроек, сегментные переключатели и кнопки.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Палитра акцентных цветов интерфейса. */
namespace MacColors {
    public const string BLUE = "#007aff";
    public const string PINK = "#ff2d55";
    public const string GREEN = "#34c759";
    public const string RED = "#ff3b30";
    public const string PURPLE = "#af52de";
    public const string CYAN = "#32ade6";
    public const string GRAY = "#8e8e93";
    public const string ORANGE = "#ff9500";
    public const string TEAL = "#30b0c7";
    public const string YELLOW = "#ffcc00";
    public const string BROWN = "#a2845e";
    public const string INDIGO = "#5856d6";
}

public class UiKit {
    private static bool css_loaded = false;

    /** CSS всплывающих окон (popupWindowStyle, SettingsSection, кнопки и т.д.). */
    public static void ensure_css () {
        if (css_loaded) {
            return;
        }
        css_loaded = true;
        var css = new Gtk.CssProvider ();
        css.load_from_string (
            // Карточка всплывающего окна: радиус 18, тень, тонкая рамка
            ".lb-popup { background-color: var(--window-bg-color, @window_bg_color); border-radius: 18px;" +
            "  box-shadow: 0 10px 20px alpha(black, 0.5); border: 1px solid alpha(currentColor, 0.1); }" +
            ".lb-popup.lb-flash { box-shadow: inset 0 0 0 3px #ff3b30, 0 10px 20px alpha(black, 0.5);" +
            "  transition: box-shadow 150ms ease-in-out; }" +
            ".lb-popup-rules { border-radius: 16px; border: none; box-shadow: 0 15px 30px alpha(black, 0.4); }" +
            ".lb-popup-stats { box-shadow: 0 10px 20px alpha(black, 0.3); }" +
            ".lb-popup-gameover { border-radius: 24px; border: none; box-shadow: 0 15px 30px alpha(black, 0.4); }" +
            ".lb-popup-header { padding: 12px 14px; }" +
            // Типографика интерфейса
            ".lb-title { font-size: 24px; font-weight: bold; }" +
            ".lb-title2 { font-size: 18px; font-weight: bold; }" +
            ".lb-title3 { font-size: 16px; }" +
            ".lb-headline { font-size: 14px; font-weight: bold; }" +
            ".lb-body { font-size: 14px; }" +
            ".lb-subheadline { font-size: 12px; }" +
            ".lb-caption { font-size: 11px; }" +
            ".lb-caption-bold { font-size: 11px; font-weight: bold; }" +
            ".lb-caption2-bold { font-size: 10px; font-weight: bold; }" +
            ".lb-mono-bold { font-family: monospace; font-weight: bold; font-size: 14px; }" +
            ".lb-mono-title3 { font-family: monospace; font-weight: bold; font-size: 17px; }" +
            ".lb-secondary { color: alpha(currentColor, 0.55); }" +
            ".lb-accent { color: @accent_color; }" +
            ".lb-red { color: #ff3b30; }" +
            ".lb-orange { color: #ff9500; }" +
            ".lb-green { color: #34c759; }" +
            // Секция настроек (SettingsSection) и строки
            ".lb-section { background-color: alpha(var(--view-bg-color, @view_bg_color), 0.6); border-radius: 10px;" +
            "  border: 1px solid alpha(currentColor, 0.07); }" +
            ".lb-row { padding: 8px 12px; min-height: 28px; }" +
            ".lb-row-sep { margin-left: 44px; }" +
            // Кнопки
            ".lb-btn { border-radius: 10px; padding: 8px 40px; font-size: 14px; font-weight: bold; color: white;" +
            "  box-shadow: none; border: none; background-image: none; }" +
            ".lb-btn:hover { filter: brightness(1.08); }" +
            ".lb-btn:active { filter: brightness(0.92); }" +
            ".lb-btn:disabled { color: alpha(white, 0.8); }" +
            ".lb-btn-blue { background-color: #007aff; }" +
            ".lb-btn-gray { background-color: #8e8e93; }" +
            ".lb-btn-red { background-color: #ff3b30; }" +
            ".lb-btn-red80 { background-color: alpha(#ff3b30, 0.8); }" +
            ".lb-btn-wide { padding: 12px 0; border-radius: 12px; }" +
            ".lb-btn-mid { padding: 10px 0; border-radius: 10px; }" +
            ".lb-btn-narrow { padding: 8px 24px; }" +
            ".lb-plain { background: none; border: none; box-shadow: none; padding: 0; min-width: 0; min-height: 0; }" +
            ".lb-plain:hover { filter: brightness(1.15); }" +
            // Сегментный переключатель (Picker .segmented)
            ".lb-seg > button { padding: 1px 6px; min-height: 22px; font-size: 12px; }" +
            ".lb-entry { min-height: 26px; font-size: 13px; }" +
            // Карточка правила (RuleSection)
            ".lb-rule-card { padding: 16px; border-radius: 14px; background-color: alpha(currentColor, 0.04);" +
            "  border: 1px solid alpha(currentColor, 0.08); }" +
            // Затемнение (диалоги восстановления и подтверждения)
            ".lb-dim { background-color: alpha(black, 0.15); }" +
            // Статистика
            ".lb-stats-head { background-color: alpha(currentColor, 0.08); padding: 8px 24px; }" +
            ".lb-stats-row { background-color: alpha(currentColor, 0.02); padding: 8px 24px; }" +
            ".lb-stats-total { background-color: alpha(currentColor, 0.05); padding: 12px 24px; }" +
            ".lb-stats-table { background-color: alpha(currentColor, 0.03); }" +
            ".lb-stats-list { background: transparent; }" +
            ".lb-stats-list > row { padding: 4px 10px; border-radius: 6px; margin: 1px 8px; }" +
            // Экран победы
            ".lb-go-name { font-size: 26px; font-weight: bold; }" +
            ".lb-go-total { font-size: 20px; font-weight: bold; }" +
            ".lb-go-plus { font-size: 32px; font-weight: bold; }" +
            ".lb-go-info { font-size: 9px; font-weight: bold; color: alpha(currentColor, 0.38); }" +
            ".lb-go-capsule { padding: 6px 12px; border-radius: 999px; font-size: 11px; font-weight: bold; }" +
            ".lb-go-capsule.orange { background-color: alpha(#ff9500, 0.12); color: #ff9500; }" +
            ".lb-go-capsule.red { background-color: alpha(#ff3b30, 0.12); color: #ff3b30; }" +
            ".lb-go-btn { padding: 13px 0; border-radius: 12px; font-size: 14px; font-weight: bold; color: white;" +
            "  border: none; transition: all 250ms ease-out; }" +
            ".lb-go-btn.orange { background-image: linear-gradient(135deg, #ff9500, alpha(#ff9500, 0.85));" +
            "  box-shadow: 0 3px 6px alpha(#ff9500, 0.2); }" +
            ".lb-go-btn.orange:hover { box-shadow: 0 5px 10px alpha(#ff9500, 0.35); transform: scale(1.015); }" +
            ".lb-go-btn.red { background-image: linear-gradient(135deg, #ff3b30, alpha(#ff3b30, 0.85));" +
            "  box-shadow: 0 3px 6px alpha(#ff3b30, 0.2); }" +
            ".lb-go-btn.red:hover { box-shadow: 0 5px 10px alpha(#ff3b30, 0.35); transform: scale(1.015); }" +
            ".lb-go-close { padding: 8px; min-width: 0; min-height: 0; border-radius: 999px; border: none;" +
            "  box-shadow: none; background-color: alpha(currentColor, 0.06); }" +
            ".lb-go-close:hover { background-color: alpha(currentColor, 0.12); }" +
            // Стили кнопки закрытия окна (с резервным стилем GNOME Adwaita при отсутствии темы)
            "windowcontrols { border-spacing: 3px; }" +
            "windowcontrols > button.close { min-width: 24px; min-height: 24px; padding: 5px; background: none; border: none; box-shadow: none; border-radius: 9999px; }" +
            "windowcontrols > button.close > image, windowcontrols > button.close > .lb-gnome-close-icon {" +
            "  background-color: alpha(currentColor, 0.1); border-radius: 9999px; padding: 4px; min-width: 16px; min-height: 16px;" +
            "  transition: background-color 200ms ease-out; }" +
            "windowcontrols > button.close:hover > image, windowcontrols > button.close:hover > .lb-gnome-close-icon {" +
            "  background-color: alpha(currentColor, 0.16); }" +
            "windowcontrols > button.close:active > image, windowcontrols > button.close:active > .lb-gnome-close-icon {" +
            "  background-color: alpha(currentColor, 0.3); }" +
            // Кнопки заголовка окна (TitleBarButton)
            ".lb-tb-btn { min-width: 22px; min-height: 22px; padding: 0; border-radius: 5px; box-shadow: none;" +
            "  background-image: none; background-color: alpha(var(--view-bg-color, @view_bg_color), 0.5);" +
            "  border: 1px solid alpha(currentColor, 0.15); }" +
            ".lb-tb-btn:hover { background-color: alpha(currentColor, 0.08); }" +
            ".lb-tb-btn.active { background-color: alpha(@accent_bg_color, 0.35); border-color: @accent_bg_color; }"
        );
        var display = Gdk.Display.get_default ();
        if (display != null) {
            add_style_provider (display, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2);
        }
    }

    [CCode (cname = "gtk_style_context_add_provider_for_display")]
    private extern static void add_style_provider (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

    public static Gdk.RGBA rgba (string spec, double alpha = 1.0) {
        var c = Gdk.RGBA ();
        c.parse (spec);
        c.alpha = (float) alpha;
        return c;
    }

    public static Gtk.Label label (string text, string css_classes, float xalign = 0.0f) {
        var l = new Gtk.Label (text);
        foreach (var c in css_classes.split (" ")) {
            if (c != "") {
                l.add_css_class (c);
            }
        }
        l.xalign = xalign;
        return l;
    }

    /** Кнопка действия (цветная заливка, контрастный жирный текст). */
    public static Gtk.Button button (string text, string color_class, string extra = "") {
        var b = new Gtk.Button.with_label (text);
        b.add_css_class ("lb-btn");
        b.add_css_class (color_class);
        foreach (var c in extra.split (" ")) {
            if (c != "") {
                b.add_css_class (c);
            }
        }
        b.set_cursor_from_name ("pointer");
        return b;
    }

    public static Gtk.Widget spacer () {
        var s = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        s.hexpand = true;
        return s;
    }

    public static void clear_box (Gtk.Box box) {
        Gtk.Widget? c = box.get_first_child ();
        while (c != null) {
            var next = c.get_next_sibling ();
            box.remove (c);
            c = next;
        }
    }

    /**
     * Проверяет, должна ли кнопка закрытия располагаться слева согласно настройкам GNOME / GTK
     * (свойство gtk-decoration-layout, например "close,minimize,maximize:" или ":minimize,maximize,close").
     */
    public static bool is_close_button_left () {
        var settings = Gtk.Settings.get_default ();
        if (settings == null || settings.gtk_decoration_layout == null) {
            return false;
        }
        var parts = settings.gtk_decoration_layout.split (":", 2);
        if (parts.length > 0) {
            foreach (var token in parts[0].split (",")) {
                if (token.strip () == "close") {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Проверяет доступность стандартной системной иконки закрытия окна в текущей теме пиктограмм.
     */
    public static bool has_theme_close_icon () {
        var display = Gdk.Display.get_default ();
        if (display != null) {
            var theme = Gtk.IconTheme.get_for_display (display);
            if (theme != null) {
                return theme.has_icon ("window-close-symbolic") || theme.has_icon ("window-close");
            }
        }
        return false;
    }

    public static double ease_out (double t) {
        return cubic_bezier_timing (t, 0.0, 0.0, 0.58, 1.0);
    }

    public static double ease_in (double t) {
        return cubic_bezier_timing (t, 0.42, 0.0, 1.0, 1.0);
    }

    public static double popup_open_curve (double t) {
        return cubic_bezier_timing (t, 0.22, 1.0, 0.36, 1.0);
    }

    public static double popup_close_curve (double t) {
        return cubic_bezier_timing (t, 0.32, 0.0, 0.67, 0.0);
    }

    /** Расчёт прогресса анимации по кубической кривой Безье методом Ньютона: решение x(u) = t. */
    private static double cubic_bezier_timing (double t, double x1, double y1, double x2, double y2) {
        if (t <= 0.0) return 0.0;
        if (t >= 1.0) return 1.0;
        double u = t;
        for (var i = 0; i < 8; i++) {
            var one_minus_u = 1.0 - u;
            var x = 3 * one_minus_u * one_minus_u * u * x1
                + 3 * one_minus_u * u * u * x2 + u * u * u - t;
            var dx = 3 * one_minus_u * one_minus_u * x1
                + 6 * one_minus_u * u * (x2 - x1) + 3 * u * u * (1.0 - x2);
            if (Math.fabs (dx) < 1e-6) break;
            u = double.max (0.0, double.min (1.0, u - x / dx));
        }
        return 3 * (1.0 - u) * (1.0 - u) * u * y1
            + 3 * (1.0 - u) * u * u * y2 + u * u * u;
    }
}

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

// MARK: - Анимируемые контейнеры

/** Контейнер с одним дочерним виджетом: масштаб, прозрачность и сдвиг по Y (scaleEffect/opacity/offset). */
public class FxBin : Gtk.Widget {
    protected Gtk.Widget? child = null;
    public double fx_scale = 1.0;
    public double fx_opacity = 1.0;
    public double fx_dy = 0.0;

    public FxBin (Gtk.Widget child) {
        this.child = child;
        child.set_parent (this);
    }

    public override void dispose () {
        if (child != null) {
            child.unparent ();
            child = null;
        }
        base.dispose ();
    }

    public void set_fx (double scale, double opacity, double dy = 0.0) {
        if (scale == fx_scale && opacity == fx_opacity && dy == fx_dy) {
            return;
        }
        fx_scale = scale;
        fx_opacity = opacity;
        fx_dy = dy;
        queue_draw ();
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return child != null ? child.get_request_mode () : Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        minimum_baseline = -1;
        natural_baseline = -1;
        if (child == null) {
            minimum = 0;
            natural = 0;
            return;
        }
        int mb, nb;
        child.measure (orientation, for_size, out minimum, out natural, out mb, out nb);
    }

    public override void size_allocate (int width, int height, int baseline) {
        if (child != null) {
            child.allocate (width, height, baseline, null);
        }
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        if (child == null || fx_opacity <= 0.001) {
            return;
        }
        var has_transform = Math.fabs (fx_scale - 1.0) > 1e-4 || Math.fabs (fx_dy) > 1e-4;
        var use_opacity = fx_opacity < 0.999;
        if (!has_transform && !use_opacity) {
            snapshot_child (child, snapshot);
            return;
        }
        var w = get_width ();
        var h = get_height ();
        snapshot.save ();
        if (has_transform) {
            Graphene.Point c = { (float) (w / 2.0), (float) (h / 2.0 + fx_dy) };
            snapshot.translate (c);
            snapshot.scale ((float) fx_scale, (float) fx_scale);
            Graphene.Point back = { (float) (-w / 2.0), (float) (-h / 2.0) };
            snapshot.translate (back);
        }
        if (use_opacity) {
            snapshot.push_opacity (double.min (1.0, fx_opacity));
        }
        snapshot_child (child, snapshot);
        if (use_opacity) {
            snapshot.pop ();
        }
        snapshot.restore ();
    }
}

/** Всплывающее окно: плавное появление/исчезание с GPU-кэшированием текстуры на время анимации. */
public class PopupHost : FxBin {
    public signal void hidden ();
    private double progress = 0.0;
    private double start_progress = 0.0;
    private double target_progress = 1.0;
    private int64 anim_start_us = 0;
    private uint tick_id = 0;
    public bool closing = false;

    // Предрендеренная GPU-текстура карточки окна (включая внешнюю тень) на время scale/opacity-анимации
    private Gdk.Texture? cached_texture = null;
    private int cached_w = 0;
    private int cached_h = 0;
    private int cached_sf = 0;
    private const float SHADOW_PAD = 48.0f;

    public PopupHost (Gtk.Widget content) {
        base (content);
        halign = Gtk.Align.CENTER;
        valign = Gtk.Align.CENTER;
        apply ();
    }

    public override void dispose () {
        if (tick_id != 0) {
            remove_tick_callback (tick_id);
            tick_id = 0;
        }
        cached_texture = null;
        base.dispose ();
    }

    public Gtk.Widget content { get { return child; } }

    private void apply () {
        var clamped = double.max (0.0, double.min (1.0, progress));
        set_fx (0.94 + 0.06 * clamped, clamped);
    }

    public void animate_in () {
        closing = false;
        can_target = true;
        if (progress < 0.02) {
            progress = 0.02;
            apply ();
        }
        start_anim (1.0);
    }

    public void animate_out () {
        closing = true;
        can_target = false;
        start_anim (0.0);
    }

    private void start_anim (double to) {
        start_progress = progress;
        target_progress = to;
        anim_start_us = 0;
        if (tick_id == 0) {
            tick_id = add_tick_callback (on_anim_tick);
        }
    }

    private bool on_anim_tick (Gtk.Widget widget, Gdk.FrameClock clock) {
        var ft = clock.get_frame_time ();
        var now = ft > 0 ? ft : GLib.get_monotonic_time ();
        if (anim_start_us == 0) {
            anim_start_us = now;
            queue_draw ();
            return GLib.Source.CONTINUE;
        }
        var duration = closing ? 0.17 : 0.22;
        var elapsed = (now - anim_start_us) / 1000000.0;
        var t = double.min (1.0, double.max (0.0, elapsed / duration));
        var eased = closing ? UiKit.popup_close_curve (t) : UiKit.popup_open_curve (t);
        progress = start_progress + (target_progress - start_progress) * eased;
        apply ();

        if (t >= 1.0) {
            progress = target_progress;
            tick_id = 0;
            cached_texture = null;
            apply ();
            if (target_progress <= 0.0) {
                hidden ();
            }
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    private void ensure_cached_texture (int w, int h) {
        var sf = int.max (1, get_scale_factor ());
        if (cached_texture != null && cached_w == w && cached_h == h && cached_sf == sf) {
            return;
        }
        if (w <= 0 || h <= 0 || child == null) {
            return;
        }
        var native = get_native ();
        var renderer = native != null ? native.get_renderer () : null;
        if (renderer == null || !renderer.is_realized ()) {
            return;
        }
        var child_snap = new Gtk.Snapshot ();
        child_snap.scale ((float) sf, (float) sf);
        Graphene.Point pad_pt = { SHADOW_PAD, SHADOW_PAD };
        child_snap.translate (pad_pt);
        snapshot_child (child, child_snap);
        var node = child_snap.free_to_node ();
        if (node == null) {
            return;
        }
        var vp = Graphene.Rect ().init (0.0f, 0.0f,
            (w + SHADOW_PAD * 2.0f) * sf,
            (h + SHADOW_PAD * 2.0f) * sf);
        cached_texture = renderer.render_texture (node, vp);
        cached_w = w;
        cached_h = h;
        cached_sf = sf;
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        if (child == null || fx_opacity <= 0.001) {
            return;
        }
        var is_animating = tick_id != 0 || Math.fabs (fx_scale - 1.0) > 1e-4 || fx_opacity < 0.999;
        if (is_animating && (child is PopupView || closing)) {
            var w = get_width ();
            var h = get_height ();
            ensure_cached_texture (w, h);
            if (cached_texture != null) {
                snapshot.save ();
                Graphene.Point c = { (float) (w / 2.0), (float) (h / 2.0 + fx_dy) };
                snapshot.translate (c);
                snapshot.scale ((float) fx_scale, (float) fx_scale);
                Graphene.Point back = { (float) (-w / 2.0), (float) (-h / 2.0) };
                snapshot.translate (back);
                if (fx_opacity < 0.999) {
                    snapshot.push_opacity (double.min (1.0, fx_opacity));
                }
                var bounds = Graphene.Rect ().init (-SHADOW_PAD, -SHADOW_PAD,
                    w + SHADOW_PAD * 2.0f, h + SHADOW_PAD * 2.0f);
                snapshot.append_scaled_texture (cached_texture, Gsk.ScalingFilter.TRILINEAR, bounds);
                if (fx_opacity < 0.999) {
                    snapshot.pop ();
                }
                snapshot.restore ();
                return;
            }
        }
        base.snapshot (snapshot);
    }
}

// MARK: - Элементы настроек

/** Контейнер элементов управления окном со стандартным CSS-именем windowcontrols. */
public class WindowControlsBox : Gtk.Box {
    static construct {
        set_css_name ("windowcontrols");
    }

    public WindowControlsBox () {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
    }
}

/** Резервная векторная пиктограмма крестика закрытия окна в стиле GNOME Adwaita (16×16). */
public class GnomeCloseFallbackIcon : Gtk.DrawingArea {
    public GnomeCloseFallbackIcon () {
        content_width = 16;
        content_height = 16;
        add_css_class ("lb-gnome-close-icon");
        can_target = false;
        set_draw_func (draw);
    }

    private void draw (Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
        if (w <= 0 || h <= 0) {
            return;
        }
        var s = double.min (w, h);
        var ox = (w - s) / 2.0;
        var oy = (h - s) / 2.0;
        cr.save ();
        cr.translate (ox, oy);
        cr.scale (s / 16.0, s / 16.0);
        var c = get_color ();
        cr.set_source_rgba (c.red, c.green, c.blue, c.alpha);

        // Стандартный путь крестика GNOME Adwaita (16×16)
        cr.move_to (4.0, 4.0);
        cr.line_to (5.03, 4.0);
        cr.curve_to (5.28, 4.01, 5.54, 4.13, 5.72, 4.31);
        cr.line_to (8.0, 6.59);
        cr.line_to (10.31, 4.31);
        cr.curve_to (10.58, 4.08, 10.76, 4.01, 11.0, 4.0);
        cr.line_to (12.0, 4.0);
        cr.line_to (12.0, 5.0);
        cr.curve_to (12.0, 5.29, 11.96, 5.55, 11.75, 5.75);
        cr.line_to (9.47, 8.03);
        cr.line_to (11.72, 10.28);
        cr.curve_to (11.91, 10.47, 12.0, 10.73, 12.0, 11.0);
        cr.line_to (12.0, 12.0);
        cr.line_to (11.0, 12.0);
        cr.curve_to (10.73, 12.0, 10.47, 11.91, 10.28, 11.72);
        cr.line_to (8.0, 9.44);
        cr.line_to (5.72, 11.72);
        cr.curve_to (5.53, 11.91, 5.27, 12.0, 5.0, 12.0);
        cr.line_to (4.0, 12.0);
        cr.line_to (4.0, 11.0);
        cr.curve_to (4.0, 10.73, 4.09, 10.47, 4.28, 10.28);
        cr.line_to (6.56, 8.03);
        cr.line_to (4.28, 5.75);
        cr.curve_to (4.07, 5.55, 3.98, 5.28, 4.0, 5.0);
        cr.close_path ();
        cr.fill ();
        cr.restore ();
    }
}

/** Кнопка закрытия окна со стилем стандартного крестика заголовка темы («window-close-symbolic») и GNOME-резервом. */
public class XCloseButton : Gtk.Button {
    private Gtk.Widget? current_icon = null;
    private ulong icon_theme_handler = 0;

    public XCloseButton () {
        add_css_class ("image-button");
        add_css_class ("close");
        valign = Gtk.Align.CENTER;
        focus_on_click = false;
        set_cursor_from_name ("pointer");
        update_icon ();

        var display = Gdk.Display.get_default ();
        if (display != null) {
            var theme = Gtk.IconTheme.get_for_display (display);
            if (theme != null) {
                icon_theme_handler = theme.changed.connect (update_icon);
            }
        }
    }

    private void update_icon () {
        if (UiKit.has_theme_close_icon ()) {
            if (!(current_icon is Gtk.Image)) {
                current_icon = new Gtk.Image.from_icon_name ("window-close-symbolic");
                set_child (current_icon);
            }
        } else {
            if (!(current_icon is GnomeCloseFallbackIcon)) {
                current_icon = new GnomeCloseFallbackIcon ();
                set_child (current_icon);
            }
        }
    }

    public override void dispose () {
        if (icon_theme_handler != 0) {
            var display = Gdk.Display.get_default ();
            if (display != null) {
                var theme = Gtk.IconTheme.get_for_display (display);
                if (theme != null) {
                    theme.disconnect (icon_theme_handler);
                }
            }
            icon_theme_handler = 0;
        }
        base.dispose ();
    }
}

/** Сегментный переключатель (Picker .segmented). */
public class Segmented : Gtk.Box {
    public signal void changed (int index);
    private Gtk.ToggleButton[] buttons = new Gtk.ToggleButton[0];
    private bool updating = false;

    public Segmented (string[] labels, int selected, int width) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class ("linked");
        add_css_class ("lb-seg");
        homogeneous = true;
        width_request = width;
        valign = Gtk.Align.CENTER;
        Gtk.ToggleButton? first = null;
        for (var i = 0; i < labels.length; i++) {
            var b = new Gtk.ToggleButton.with_label (labels[i]);
            if (first == null) {
                first = b;
            } else {
                b.set_group (first);
            }
            b.active = (i == selected);
            var idx = i;
            b.toggled.connect (() => {
                if (!updating && b.active) {
                    changed (idx);
                }
            });
            buttons += b;
            append (b);
        }
    }

    public int selected_index {
        get {
            for (var i = 0; i < buttons.length; i++) {
                if (buttons[i].active) return i;
            }
            return -1;
        }
    }

    public void set_selected (int i) {
        updating = true;
        if (i >= 0 && i < buttons.length) {
            buttons[i].active = true;
        }
        updating = false;
    }
}

/** Строка настроек: цветная плитка-иконка, заголовок, элемент управления справа. */
public class SettingsRow : Gtk.Box {
    public Gtk.Label title_label;

    public SettingsRow (string glyph, string tile_color, string title, Gtk.Widget control) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
        add_css_class ("lb-row");
        var icon = SFIcon.tile (glyph, tile_color);
        icon.valign = Gtk.Align.CENTER;
        append (icon);
        title_label = UiKit.label (title, "lb-body");
        title_label.valign = Gtk.Align.CENTER;
        title_label.xalign = 0.0f;
        title_label.wrap = true;
        title_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        title_label.hexpand = true;
        append (title_label);
        control.valign = Gtk.Align.CENTER;
        append (control);
    }
}

/** Секция настроек со скруглённым фоном и разделителями между строками. */
public class SettingsSection : Gtk.Box {
    private int count = 0;

    public SettingsSection () {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class ("lb-section");
        overflow = Gtk.Overflow.HIDDEN;
    }

    public void add_row (Gtk.Widget row) {
        if (count > 0) {
            var sep = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            sep.add_css_class ("lb-row-sep");
            append (sep);
        }
        append (row);
        count++;
    }

    /** Группа: заголовок (caption, secondary), секция, необязательная подпись снизу. */
    public static Gtk.Box group (string header, SettingsSection section, string? footer = null) {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        var h = UiKit.label (header, "lb-caption lb-secondary");
        h.margin_start = 10;
        box.append (h);
        if (footer != null) {
            section.margin_bottom = 2;
        }
        box.append (section);
        if (footer != null) {
            var f = UiKit.label (footer, "lb-caption lb-secondary");
            f.wrap = true;
            f.margin_start = 10;
            f.margin_end = 10;
            box.append (f);
        }
        return box;
    }
}

/** Стандартный заголовок всплывающего окна: центрированный title2 bold и крестик слева или справа по настройкам GNOME. */
public class PopupHeader : Gtk.Box {
    public Gtk.Label title_label;
    public XCloseButton? close_button = null;
    private WindowControlsBox? controls_box = null;
    private Gtk.CenterBox center_box;
    private ulong layout_handler = 0;

    public PopupHeader (string title, bool with_close) {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class ("lb-popup-header");

        center_box = new Gtk.CenterBox ();
        center_box.hexpand = true;

        title_label = UiKit.label (title, "lb-title2", 0.5f);
        title_label.wrap = true;
        title_label.justify = Gtk.Justification.CENTER;
        title_label.halign = Gtk.Align.CENTER;
        center_box.set_center_widget (title_label);

        if (with_close) {
            close_button = new XCloseButton ();
            controls_box = new WindowControlsBox ();
            controls_box.append (close_button);
            update_close_position ();
            var settings = Gtk.Settings.get_default ();
            if (settings != null) {
                layout_handler = settings.notify["gtk-decoration-layout"].connect (update_close_position);
            }
        }

        append (center_box);
    }

    private void update_close_position () {
        if (controls_box == null) {
            return;
        }
        if (UiKit.is_close_button_left ()) {
            controls_box.remove_css_class ("end");
            controls_box.add_css_class ("start");
            if (center_box.get_end_widget () == controls_box) {
                center_box.set_end_widget (null);
            }
            center_box.set_start_widget (controls_box);
        } else {
            controls_box.remove_css_class ("start");
            controls_box.add_css_class ("end");
            if (center_box.get_start_widget () == controls_box) {
                center_box.set_start_widget (null);
            }
            center_box.set_end_widget (controls_box);
        }
    }

    public override void dispose () {
        if (layout_handler != 0) {
            var settings = Gtk.Settings.get_default ();
            if (settings != null) {
                settings.disconnect (layout_handler);
            }
            layout_handler = 0;
        }
        base.dispose ();
    }
}

/** Эффект привлечения внимания: циклическое мигание красной рамкой (3 фазы по 200 мс). */
public class Flasher : Object {
    private weak Gtk.Widget target;
    private int phase = 0;
    private uint source = 0;

    public Flasher (Gtk.Widget target) {
        this.target = target;
    }

    public void flash () {
        if (source != 0) {
            Source.remove (source);
            source = 0;
        }
        phase = 1;
        apply ();
        source = Timeout.add (200, () => {
            phase++;
            if (phase > 7) {
                phase = 0;
                apply ();
                source = 0;
                return false;
            }
            apply ();
            return true;
        });
    }

    private void apply () {
        if (target == null) {
            return;
        }
        if (phase > 0 && phase % 2 == 0) {
            target.add_css_class ("lb-flash");
        } else {
            target.remove_css_class ("lb-flash");
        }
    }

    public void stop () {
        if (source != 0) {
            Source.remove (source);
            source = 0;
        }
    }
}

} /* namespace Longbackgammon */
