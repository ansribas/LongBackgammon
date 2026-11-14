/* popup_host.vala
 *
 * Анимируемые контейнеры эффектов (FxBin) и модальный оверлей всплывающих диалогов (PopupHost).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

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

} /* namespace Longbackgammon */
