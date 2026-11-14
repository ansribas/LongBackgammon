/* status_message_plate.vala
 *
 * Нижняя плашка со статусом текущего хода и удвоения куша.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Нижняя плашка со статусом текущего хода и удвоения куша (аналог StatusMessagePlateView в Swift):
 * плавная смена и затухание сообщений (0.25 с easeInOut), световая вспышка (0.38 с easeOut)
 * и анимация появления индикатора удвоения куша.
 */
internal class StatusMessagePlate : Gtk.DrawingArea {
    private string current_msg = "";
    private string prev_msg = "";
    private double msg_progress = 1.0;
    private double prev_start_alpha = 0.0;
    private int64 msg_start_us = 0;

    private int64 flash_start_us = 0;
    private double flash_opacity = 0.0;

    private bool target_doubling = false;
    private double doubling_progress = 0.0;
    private double doubling_start_val = 0.0;
    private int64 doubling_start_us = 0;

    private bool initialized = false;
    private uint tick_id = 0;

    public StatusMessagePlate () {
        add_css_class ("lb-status-strip");
        set_content_height (48);
        set_size_request (-1, 48);
        vexpand = false;
        hexpand = true;
        set_draw_func (draw_cb);
    }

    private int64 now_us () {
        return GLib.get_monotonic_time ();
    }

    public void update_state (string message, bool is_doubling, bool is_active, bool is_current_turn) {
        var want_doubling = is_doubling && is_active;
        var effective_msg = (!is_doubling || !is_current_turn) ? message : "";
        var now = now_us ();

        if (!initialized) {
            initialized = true;
            current_msg = effective_msg;
            prev_msg = "";
            msg_progress = 1.0;
            target_doubling = want_doubling;
            doubling_progress = want_doubling ? 1.0 : 0.0;
            if (effective_msg != "") {
                flash_opacity = 1.0;
                flash_start_us = now;
                ensure_tick ();
            }
            queue_draw ();
            return;
        }

        var need_tick = false;
        if (effective_msg != current_msg) {
            var cur_ease = PanelStyle.ease_in_out (msg_progress);
            prev_msg = current_msg;
            prev_start_alpha = cur_ease;
            current_msg = effective_msg;
            msg_progress = 0.0;
            msg_start_us = now;
            if (effective_msg != "") {
                flash_opacity = 1.0;
                flash_start_us = now;
            } else {
                flash_opacity = 0.0;
                flash_start_us = 0;
            }
            need_tick = true;
        }

        if (want_doubling != target_doubling) {
            target_doubling = want_doubling;
            doubling_start_val = doubling_progress;
            doubling_start_us = now;
            need_tick = true;
        }

        if (need_tick) {
            ensure_tick ();
        }
        queue_draw ();
    }

    private void ensure_tick () {
        if (tick_id == 0) {
            tick_id = add_tick_callback (on_tick);
        }
    }

    private bool on_tick (Gtk.Widget w, Gdk.FrameClock clock) {
        var ft = clock.get_frame_time ();
        var now = ft > 0 ? ft : GLib.get_monotonic_time ();
        var active_anim = false;

        if (msg_progress < 1.0) {
            var elapsed = double.max (0.0, (now - msg_start_us) / 1000000.0);
            msg_progress = double.min (1.0, elapsed / 0.25);
            if (msg_progress < 1.0) {
                active_anim = true;
            } else {
                prev_msg = "";
                prev_start_alpha = 0.0;
            }
        }

        if (flash_start_us > 0) {
            var elapsed = double.max (0.0, (now - flash_start_us) / 1000000.0);
            if (elapsed < 0.38) {
                var t = elapsed / 0.38;
                flash_opacity = 1.0 - UiKit.ease_out (t);
                active_anim = true;
            } else {
                flash_opacity = 0.0;
                flash_start_us = 0;
            }
        }

        var target_d = target_doubling ? 1.0 : 0.0;
        if (Math.fabs (doubling_progress - target_d) > 1e-4) {
            var elapsed = double.max (0.0, (now - doubling_start_us) / 1000000.0);
            var p = double.min (1.0, elapsed / 0.25);
            var ease = PanelStyle.ease_in_out (p);
            doubling_progress = doubling_start_val + (target_d - doubling_start_val) * ease;
            if (p < 1.0) {
                active_anim = true;
            } else {
                doubling_progress = target_d;
            }
        }

        queue_draw ();
        if (!active_anim) {
            tick_id = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    private void draw_cb (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        if (doubling_progress > 0.001) {
            draw_doubling_text (cr, width, height, doubling_progress);
        }

        var t = PanelStyle.ease_in_out (msg_progress);
        if (prev_msg != "" && t < 1.0) {
            var prev_a = prev_start_alpha * (1.0 - t);
            draw_status_text (cr, width, height, prev_msg, prev_a, 0.0);
        }
        if (current_msg != "" && t > 0.001) {
            draw_status_text (cr, width, height, current_msg, t, flash_opacity);
        }
    }

    private void draw_doubling_text (Cairo.Context cr, int width, int height, double progress) {
        var text = Localization.status_double_doubled ();
        if (text == "") {
            return;
        }
        var avail_w = int.max (20, width - 16);
        var layout = create_pango_layout (text);
        var fd = new Pango.FontDescription ();
        fd.set_family ("Sans");
        fd.set_weight (Pango.Weight.BOLD);
        fd.set_absolute_size (10.0 * Pango.SCALE);
        layout.set_font_description (fd);
        layout.set_width (avail_w * Pango.SCALE);
        layout.set_wrap (Pango.WrapMode.WORD_CHAR);
        layout.set_alignment (Pango.Alignment.CENTER);

        int tw, th;
        layout.get_pixel_size (out tw, out th);
        var x = (width - avail_w) / 2.0;
        var y = (height - th) / 2.0 - 8.0 * (1.0 - progress);

        cr.set_source_rgba (1.0, 0.584, 0.0, progress);
        cr.move_to (x, y);
        Pango.cairo_show_layout (cr, layout);
    }

    private void draw_status_text (Cairo.Context cr, int width, int height, string text, double alpha, double flash) {
        if (text == "" || alpha <= 0.001) {
            return;
        }
        var avail_w = int.max (20, width - 10);
        var layout = create_pango_layout (text);
        var fd = new Pango.FontDescription ();
        fd.set_family ("Sans");
        fd.set_weight (Pango.Weight.BOLD);
        fd.set_absolute_size (10.0 * Pango.SCALE);
        layout.set_font_description (fd);
        layout.set_width (avail_w * Pango.SCALE);
        layout.set_wrap (Pango.WrapMode.WORD_CHAR);
        layout.set_alignment (Pango.Alignment.CENTER);

        int tw, th;
        layout.get_pixel_size (out tw, out th);
        var x = (width - avail_w) / 2.0;
        var y = (height - th) / 2.0;

        if (flash > 0.01) {
            var glow_a = alpha * flash * 0.85;
            double[] offsets_x = { -1.5, 1.5, 0.0, 0.0, -1.0, 1.0, -1.0, 1.0 };
            double[] offsets_y = { 0.0, 0.0, -1.5, 1.5, -1.0, -1.0, 1.0, 1.0 };
            cr.set_source_rgba (1.0, 1.0, 1.0, glow_a / 8.0);
            for (var i = 0; i < 8; i++) {
                cr.move_to (x + offsets_x[i] * flash, y + offsets_y[i] * flash);
                Pango.cairo_show_layout (cr, layout);
            }
        }

        var fg = PanelStyle.fg (this);
        var boost = double.min (1.0, flash * 0.45);
        var r = fg.red + (1.0 - fg.red) * boost;
        var g = fg.green + (1.0 - fg.green) * boost;
        var b = fg.blue + (1.0 - fg.blue) * boost;
        cr.set_source_rgba (r, g, b, alpha);
        cr.move_to (x, y);
        Pango.cairo_show_layout (cr, layout);
    }
}

} /* namespace Longbackgammon */
