/* ui_kit.vala
 *
 * Общие элементы пользовательского интерфейса: стили всплывающих окон,
 * векторные пиктограммы, анимируемые контейнеры,
 * секции настроек, сегментные переключатели и кнопки.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Палитра цветов интерфейса в соответствии с GNOME HIG Palette.
 * https://developer.gnome.org/hig/reference/palette.html
 */
namespace AdwColors {
    public const string BLUE = "#3584e4";    // GNOME Blue 3 (Default Accent)
    public const string GREEN = "#33d17a";   // GNOME Green 3 (Success)
    public const string YELLOW = "#f6d32d";  // GNOME Yellow 3 (Warning / Stars)
    public const string ORANGE = "#ff7800";  // GNOME Orange 3
    public const string RED = "#e01b24";     // GNOME Red 3 (Destructive / Error)
    public const string PURPLE = "#9141ac";  // GNOME Purple 3
    public const string BROWN = "#986a44";   // GNOME Brown 3
    public const string TEAL = "#2aa1b3";    // GNOME Teal 3
    public const string CYAN = "#3584e4";    // GNOME Blue 3
    public const string PINK = "#c061cb";    // GNOME Purple 2
    public const string INDIGO = "#613583";  // GNOME Purple 5
    public const string GRAY = "#77767b";    // GNOME Dark 1
}

/** Псевдоним для обратной совместимости. */
namespace MacColors {
    public const string BLUE = AdwColors.BLUE;
    public const string PINK = AdwColors.PINK;
    public const string GREEN = AdwColors.GREEN;
    public const string RED = AdwColors.RED;
    public const string PURPLE = AdwColors.PURPLE;
    public const string CYAN = AdwColors.CYAN;
    public const string GRAY = AdwColors.GRAY;
    public const string ORANGE = AdwColors.ORANGE;
    public const string TEAL = AdwColors.TEAL;
    public const string YELLOW = AdwColors.YELLOW;
    public const string BROWN = AdwColors.BROWN;
    public const string INDIGO = AdwColors.INDIGO;
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
            ".lb-popup.lb-flash { box-shadow: inset 0 0 0 3px @destructive_color, 0 10px 20px alpha(black, 0.5);" +
            "  transition: box-shadow 150ms ease-in-out; }" +
            ".lb-popup-rules { border-radius: 16px; border: none; box-shadow: 0 15px 30px alpha(black, 0.4); }" +
            ".lb-popup-stats { box-shadow: 0 10px 20px alpha(black, 0.3); }" +
            ".lb-popup-gameover { border-radius: 24px; border: none; box-shadow: 0 15px 30px alpha(black, 0.4); }" +
            ".lb-popup-header { padding: 12px 14px; }" +
            // Типографика интерфейса по стандарту GNOME HIG (относительные единицы rem)
            ".lb-title { font-size: 1.5rem; font-weight: 800; }" +
            ".lb-title2 { font-size: 1.25rem; font-weight: 700; }" +
            ".lb-title3 { font-size: 1.05rem; font-weight: 600; }" +
            ".lb-headline { font-size: 0.95rem; font-weight: 700; }" +
            ".lb-body { font-size: 0.95rem; }" +
            ".lb-subheadline { font-size: 0.85rem; }" +
            ".lb-caption { font-size: 0.75rem; }" +
            ".lb-caption-bold { font-size: 0.75rem; font-weight: 700; }" +
            ".lb-caption2-bold { font-size: 0.7rem; font-weight: 700; }" +
            ".lb-mono-bold { font-family: monospace; font-weight: bold; font-size: 0.95rem; }" +
            ".lb-mono-title3 { font-family: monospace; font-weight: bold; font-size: 1.1rem; }" +
            ".lb-secondary { color: alpha(currentColor, 0.6); }" +
            ".lb-accent { color: @accent_color; }" +
            ".lb-red { color: @destructive_color; }" +
            ".lb-orange { color: #ff9500; }" +
            ".lb-green { color: @success_color; }" +
            // Секция настроек (SettingsSection) и строки
            ".lb-section { background-color: alpha(var(--view-bg-color, @view_bg_color), 0.6); border-radius: 10px;" +
            "  border: 1px solid alpha(currentColor, 0.07); }" +
            ".lb-row { padding: 8px 12px; min-height: 32px; }" +
            // Кнопки по стандартам GNOME HIG
            ".lb-btn { border-radius: 10px; padding: 8px 36px; min-height: 36px; font-size: 0.95rem; font-weight: bold; color: white;" +
            "  box-shadow: none; border: none; background-image: none; transition: all 150ms ease-in-out; }" +
            ".lb-btn:hover { filter: brightness(1.08); }" +
            ".lb-btn:active { filter: brightness(0.92); }" +
            ".lb-btn:disabled { color: alpha(white, 0.8); }" +
            ".lb-btn-blue { background-color: @accent_bg_color; color: @accent_fg_color; }" +
            ".lb-btn-gray { background-color: alpha(currentColor, 0.15); color: currentColor; }" +
            ".lb-btn-red { background-color: @destructive_bg_color; color: @destructive_fg_color; }" +
            ".lb-btn-red80 { background-color: alpha(@destructive_bg_color, 0.85); color: @destructive_fg_color; }" +
            ".lb-btn-wide { padding: 12px 0; border-radius: 12px; }" +
            ".lb-btn-mid { padding: 10px 0; border-radius: 10px; }" +
            ".lb-btn-narrow { padding: 8px 24px; }" +
            ".lb-plain { background: none; border: none; box-shadow: none; padding: 0; min-width: 0; min-height: 0; }" +
            ".lb-plain:hover { filter: brightness(1.15); }" +
            // Сегментный переключатель (Picker .segmented) с поддержкой системного акцентного цвета
            ".lb-seg > button { padding: 3px 8px; min-height: 28px; font-size: 0.85rem; transition: all 150ms ease-in-out; }" +
            ".lb-seg > button:checked { background-color: @accent_bg_color; color: @accent_fg_color; background-image: none; font-weight: 600; }" +
            ".lb-seg > button:checked:hover { filter: brightness(1.08); }" +
            ".lb-seg > button:checked:active { filter: brightness(0.92); }" +
            ".lb-entry { min-height: 32px; font-size: 0.95rem; }" +
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
            ".lb-go-name { font-size: 1.6rem; font-weight: bold; }" +
            ".lb-go-total { font-size: 1.25rem; font-weight: bold; }" +
            ".lb-go-plus { font-size: 2rem; font-weight: bold; }" +
            ".lb-go-info { font-size: 0.7rem; font-weight: bold; color: alpha(currentColor, 0.45); }" +
            ".lb-go-capsule { padding: 7px 16px; border-radius: 999px; font-size: 0.875rem; font-weight: bold; }" +
            ".lb-go-capsule.orange { background-color: alpha(#ff9500, 0.14); color: #ff9500; }" +
            ".lb-go-capsule.red { background-color: alpha(@destructive_color, 0.12); color: @destructive_color; border: 1px solid alpha(@destructive_color, 0.35); }" +
            ".lb-go-cell { background-color: alpha(currentColor, 0.04); border-radius: 6px; transition: background-color 150ms ease-out; }" +
            ".lb-go-cell.head { background-color: alpha(currentColor, 0.08); }" +
            ".lb-go-cell.active { background-color: alpha(#ff9500, 0.14); }" +
            ".lb-go-value { font-size: 1rem; font-weight: bold; }" +
            ".lb-go-cell.active.winner .lb-go-value { color: #ff9500; }" +
            ".lb-go-badge { padding: 4px 10px; border-radius: 999px; background-color: alpha(currentColor, 0.06);" +
            "  transition: background-color 250ms ease-in-out; }" +
            ".lb-go-badge.up { background-color: alpha(@success_color, 0.18); }" +
            ".lb-go-badge.down { background-color: alpha(@destructive_color, 0.18); }" +
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
            // Кнопки заголовка окна (TitleBarButton) в соответствии с GNOME HIG
            ".lb-tb-btn.active { background-color: alpha(@accent_bg_color, 0.25); color: @accent_color; }"
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

    /** Сокращает имя игрока до единого стандарта длины (не более N символов + многоточие). */
    public static string truncate_name (string text, int max_chars = GameConfig.MAX_PLAYER_NAME_DISPLAY_CHARACTERS) {
        if (text.char_count () <= max_chars) {
            return text;
        }
        return text.substring (0, text.index_of_nth_char (max_chars)) + "…";
    }

    /** Проверяет, обрезана ли метка (либо по лимиту 12 символов, либо визуально из-за нехватки ширины). */
    public static bool is_label_truncated (Gtk.Label l, string full_text) {
        if (full_text == "") {
            return false;
        }
        if (full_text.char_count () > GameConfig.MAX_PLAYER_NAME_DISPLAY_CHARACTERS) {
            return true;
        }
        var layout = l.get_layout ();
        if (layout != null && layout.is_ellipsized ()) {
            return true;
        }
        return false;
    }

    /** Подключает к метке мгновенную всплывающую подсказку (без системной задержки GTK, в стиле лога ходов). */
    public static void attach_instant_tooltip (Gtk.Label l) {
        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect (() => {
            var full = l.get_data<string> ("full_name") ?? "";
            if (!is_label_truncated (l, full)) {
                InstantTooltipState.shared ().hide (l);
                return;
            }
            var container = LogTooltipState.shared ().container;
            if (container == null) {
                return;
            }
            Graphene.Rect bounds;
            if (l.compute_bounds (container, out bounds)) {
                InstantTooltipState.shared ().show (full, bounds, l);
            }
        });
        motion.leave.connect (() => {
            InstantTooltipState.shared ().hide (l);
        });
        l.add_controller (motion);
        l.unmap.connect (() => {
            InstantTooltipState.shared ().hide (l);
        });
    }

    /** Обновляет имя игрока в существующей метке с учётом обрезки и мгновенной подсказки. */
    public static void set_name_label_text (Gtk.Label l, string full_text) {
        l.set_data<string> ("full_name", full_text);
        l.label = truncate_name (full_text);
        l.tooltip_text = null;
        if (!is_label_truncated (l, full_text)) {
            InstantTooltipState.shared ().hide (l);
        }
    }

    /** Метка с именем игрока: длинные имена сокращаются (≤12 символов + «…» или по ширине), полное имя мгновенно всплывает при наведении. */
    public static Gtk.Label name_label (string text, string css_classes, float xalign = 0.0f) {
        var l = label (truncate_name (text), css_classes, xalign);
        l.single_line_mode = true;
        l.ellipsize = Pango.EllipsizeMode.END;
        l.set_data<string> ("full_name", text);
        attach_instant_tooltip (l);
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
