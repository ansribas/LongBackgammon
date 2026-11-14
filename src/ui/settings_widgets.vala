/* settings_widgets.vala
 *
 * Вспомогательные элементы управления и секции для диалогов настроек и всплывающих окон.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

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

/** Строка настроек: 1-я строка (иконка, заголовок, элемент управления), 2-я строка — подсказка во всю ширину. */
public class SettingsRow : Gtk.Box {
    public Gtk.Label title_label;
    public Gtk.Label? subtitle_label = null;

    public SettingsRow (string glyph, string tile_color, string title, Gtk.Widget control, string? subtitle = null) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
        add_css_class ("lb-row");

        var top_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        var icon = SFIcon.tile (glyph, tile_color);
        icon.valign = Gtk.Align.CENTER;
        top_row.append (icon);

        title_label = UiKit.label (title, "lb-body");
        title_label.valign = Gtk.Align.CENTER;
        title_label.xalign = 0.0f;
        title_label.wrap = true;
        title_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        title_label.hexpand = true;
        top_row.append (title_label);

        control.valign = Gtk.Align.CENTER;
        top_row.append (control);
        append (top_row);

        if (subtitle != null && subtitle != "") {
            subtitle_label = UiKit.label (subtitle, "lb-caption lb-secondary");
            subtitle_label.xalign = 0.0f;
            subtitle_label.wrap = true;
            subtitle_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            subtitle_label.hexpand = true;
            append (subtitle_label);
        }
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

} /* namespace Longbackgammon */
