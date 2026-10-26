/* player_score_block.vala
 *
 * Интерактивный блок «Очки / Прогресс партии» с 3D-анимацией переворота карточки:
 * лицевая сторона — оставшееся число очков (Pip Count),
 * оборотная сторона — процент продвижения шашек в дом и снятия с доски.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Виджет отображения счёта или прогресса игрока.
 * Поддерживает 3D-переворот по клику мыши (перспективное преобразование Gsk)
 * и плавный подъём карточки при наведении курсора.
 */
public class PlayerScoreBlock : Gtk.Widget {
    private weak PlayerPanel panel;
    private Gtk.Box card;
    private Gtk.Stack faces;
    private Gtk.Label pips_value;
    private Gtk.Label pips_caption;
    private Gtk.Label progress_caption;
    private Gtk.Label progress_value;
    private Gtk.ProgressBar progress_bar;

    // Параметры анимаций переворота и наведения
    private double angle = 0;          // Текущий угол поворота вокруг вертикальной оси (в градусах)
    private double angle_from = 0;
    private double angle_to = 0;
    private int64 angle_start = 0;
    private double hover = 0;          // 0…1 (масштаб от 1.0 до 1.03)
    private double hover_from = 0;
    private double hover_to = 0;
    private int64 hover_start = 0;
    private uint tick_id = 0;

    public PlayerScoreBlock (PlayerPanel panel) {
        this.panel = panel;
        overflow = Gtk.Overflow.VISIBLE;

        card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        card.add_css_class ("lb-card");
        card.add_css_class ("lb-card-padded");
        card.set_parent (this);

        faces = new Gtk.Stack ();
        faces.transition_type = Gtk.StackTransitionType.NONE;
        faces.vhomogeneous = true;
        faces.hhomogeneous = true;
        card.append (faces);

        // Лицевая сторона: Pip Count (сумма оставшихся шагов до дома и выброса)
        var score_face = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
        score_face.halign = Gtk.Align.CENTER;
        score_face.valign = Gtk.Align.CENTER;
        pips_caption = new Gtk.Label ("");
        pips_caption.add_css_class ("lb-caption-bold");
        pips_caption.add_css_class ("lb-secondary");
        pips_value = new Gtk.Label ("");
        pips_value.add_css_class ("lb-title3-bold");
        score_face.append (pips_caption);
        score_face.append (pips_value);
        faces.add_named (score_face, "score");

        // Оборотная сторона: процент прогресса партии и полоса заполнения
        var progress_face = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
        progress_face.halign = Gtk.Align.CENTER;
        progress_face.valign = Gtk.Align.CENTER;
        progress_caption = new Gtk.Label ("");
        progress_caption.add_css_class ("lb-caption-bold");
        progress_caption.add_css_class ("lb-secondary");
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
        row.halign = Gtk.Align.CENTER;
        progress_value = new Gtk.Label ("");
        progress_value.add_css_class ("lb-title3-bold");
        progress_bar = new Gtk.ProgressBar ();
        progress_bar.add_css_class ("lb-progress");
        progress_bar.set_size_request (60, -1);
        progress_bar.valign = Gtk.Align.CENTER;
        row.append (progress_value);
        row.append (progress_bar);
        progress_face.append (progress_caption);
        progress_face.append (row);
        faces.add_named (progress_face, "progress");

        var settings = SettingsStore.shared ();
        angle = settings.score_display_mode == ScoreDisplayMode.PROGRESS ? 180 : 0;
        angle_from = angle;
        angle_to = angle;

        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect (() => { set_hover (true); });
        motion.leave.connect (() => { set_hover (false); });
        add_controller (motion);

        var click = new Gtk.GestureClick ();
        click.released.connect (() => {
            var s = SettingsStore.shared ();
            s.set_score_display_mode (s.score_display_mode == ScoreDisplayMode.SCORE
                ? ScoreDisplayMode.PROGRESS : ScoreDisplayMode.SCORE);
        });
        add_controller (click);

        panel.session.changed.connect (refresh);
        settings.changed.connect (() => {
            var target = SettingsStore.shared ().score_display_mode == ScoreDisplayMode.PROGRESS ? 180.0 : 0.0;
            if (target != angle_to) {
                angle_from = angle;
                angle_to = target;
                angle_start = GLib.get_monotonic_time ();
                ensure_tick ();
            }
            refresh ();
        });
        refresh ();
    }

    public override void dispose () {
        if (tick_id != 0) {
            remove_tick_callback (tick_id);
            tick_id = 0;
        }
        if (card != null) {
            card.unparent ();
            card = null;
        }
        base.dispose ();
    }

    private void set_hover (bool on) {
        var target = on ? 1.0 : 0.0;
        if (hover_to == target && hover == target) {
            return;
        }
        hover_from = hover;
        hover_to = target;
        hover_start = GLib.get_monotonic_time ();
        if (on) {
            card.add_css_class ("lb-card-hover");
        } else {
            card.remove_css_class ("lb-card-hover");
        }
        ensure_tick ();
    }

    private const double FLIP_DURATION = 0.45;
    private const double HOVER_DURATION = 0.20;

    private void ensure_tick () {
        if (tick_id != 0) {
            return;
        }
        tick_id = add_tick_callback ((w, clock) => {
            var now = GLib.get_monotonic_time ();

            if (angle != angle_to) {
                var ta = (now - angle_start) / 1000000.0;
                var progress = double.min (1.0, ta / FLIP_DURATION);
                var pa = PanelStyle.ease_in_out (progress);
                angle = angle_from + (angle_to - angle_from) * pa;

                if (progress >= 1.0) {
                    angle = angle_to;
                }
            }

            if (hover != hover_to) {
                var th = (now - hover_start) / 1000000.0;
                var progress = double.min (1.0, th / HOVER_DURATION);
                var ph = PanelStyle.ease_in_out (progress);
                hover = hover_from + (hover_to - hover_from) * ph;

                if (progress >= 1.0) {
                    hover = hover_to;
                }
            }

            update_face ();
            queue_draw ();

            if (angle == angle_to && hover == hover_to) {
                tick_id = 0;
                return GLib.Source.REMOVE;
            }
            return GLib.Source.CONTINUE;
        });
    }

    private void update_face () {
        var name = (angle > 90) ? "progress" : "score";
        if (faces.visible_child_name != name) {
            faces.visible_child_name = name;
        }
    }

    private void refresh () {
        var session = panel.session;
        var color = panel.color;
        pips_caption.label = Localization.pip_count_label ().replace (":", "");
        pips_value.label = (color == CheckerColor.WHITE ? session.white_pip_count : session.black_pip_count).to_string ();
        progress_caption.label = Localization.settings_score_display_progress ();
        var progress = session.progress_percentage (color);
        progress_value.label = "%.0f%%".printf (progress);
        progress_bar.fraction = progress / 100.0;
        update_face ();
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        card.measure (orientation, for_size, out minimum, out natural, null, null);
        minimum_baseline = -1;
        natural_baseline = -1;
    }

    public override void size_allocate (int width, int height, int baseline) {
        card.allocate (width, height, -1, null);
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        var w = (float) get_width ();
        var h = (float) get_height ();
        var scale = (float) (1.0 + 0.03 * hover);
        // При повороте больше 90 градусов задняя грань отображается инвертированной
        var a = (float) (angle > 90 ? angle - 180 : angle);

        bool has_rotation = Math.fabs (a) > 0.05f;
        bool has_scale = Math.fabs (scale - 1.0f) > 0.001f;

        if (has_rotation || has_scale) {
            snapshot.save ();
            snapshot.translate ({ w / 2, h / 2 });
            if (has_rotation) {
                snapshot.perspective (w * 4);
                snapshot.rotate_3d (a, Graphene.Vec3.y_axis ());
            }
            if (has_scale) {
                snapshot.scale (scale, scale);
            }
            snapshot.translate ({ -w / 2, -h / 2 });
            snapshot_child (card, snapshot);
            snapshot.restore ();
        } else {
            snapshot_child (card, snapshot);
        }
    }
}

} /* namespace Longbackgammon */
