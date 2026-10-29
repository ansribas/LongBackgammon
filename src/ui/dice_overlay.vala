/* dice_overlay.vala
 *
 * Полноэкранный слой 3D-анимации броска кубиков на доске.
 * Располагается поверх доски и боковых панелей (без clipping).
 * Кубики вылетают из зоны броска, кувыркаются в воздухе (с честными скругленными углами и фасками),
 * а затем быстро и эффектно улетают точно в слоты кубиков панели игрока.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

private class ProjectedDieFace {
    public int value;
    public double light;
    public double avg_z;
    public double center_x;
    public double center_y;
    public double ux_x;
    public double ux_y;
    public double vy_x;
    public double vy_y;
    public double q0_x; public double q0_y;
    public double q1_x; public double q1_y;
    public double q2_x; public double q2_y;
    public double q3_x; public double q3_y;
}

public class BoardDiceOverlayLayer : Gtk.Widget {
    private weak GameSession session;
    private weak PlayerPanel black_panel;
    private weak PlayerPanel white_panel;
    private uint tick_id = 0;
    private bool was_active = false;

    public BoardDiceOverlayLayer (GameSession session, PlayerPanel black_panel, PlayerPanel white_panel) {
        this.session = session;
        this.black_panel = black_panel;
        this.white_panel = white_panel;

        can_target = false;

        session.changed.connect (() => {
            var active = (session.board_dice_state != null);
            if (active) {
                was_active = true;
                ensure_tick ();
                queue_draw ();
            } else if (was_active) {
                was_active = false;
                queue_draw ();
            }
        });
        if (session.board_dice_state != null) {
            was_active = true;
            ensure_tick ();
        }
    }

    public override void dispose () {
        if (tick_id != 0) {
            remove_tick_callback (tick_id);
            tick_id = 0;
        }
        base.dispose ();
    }

    private void ensure_tick () {
        if (tick_id == 0) {
            tick_id = add_tick_callback (on_tick);
        }
    }

    private bool on_tick (Gtk.Widget widget, Gdk.FrameClock frame) {
        if (session.board_dice_state == null) {
            tick_id = 0;
            if (was_active) {
                was_active = false;
                queue_draw ();
            }
            return GLib.Source.REMOVE;
        }
        var bds = session.board_dice_state;
        var now = frame.get_frame_time ();
        if (now <= 0) {
            now = GLib.get_monotonic_time ();
        }
        var elapsed = (now - bds.start_time_us) / 1000000.0;
        var raw_t = elapsed / bds.duration;
        if (raw_t >= 0.35 && !bds.sound_played && !bds.is_transferring) {
            bds.sound_played = true;
            SoundManager.shared ().play_dice_roll ();
        }
        queue_draw ();
        return GLib.Source.CONTINUE;
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        if (session.board_dice_state == null) {
            return;
        }
        var width = get_width ();
        var height = get_height ();
        if (width <= 0 || height <= 0) {
            return;
        }
        var state = session.board_dice_state;
        var fc = get_frame_clock ();
        var now = (fc != null && fc.get_frame_time () > 0) ? fc.get_frame_time () : GLib.get_monotonic_time ();
        var elapsed = (now - state.start_time_us) / 1000000.0;
        var raw_t = double.min (1.0, double.max (0.0, elapsed / state.duration));
        var is_white = (state.color == CheckerColor.WHITE);

        var pw = (double) (GameConfig.CONTROL_PANEL_WIDTH / 2);
        var side = (double) (width - GameConfig.CONTROL_PANEL_WIDTH);
        if (side <= 0) {
            side = height;
        }

        // Центр зоны остановки на доске (в координатах оверлея):
        var board_x = pw;
        var board_y = (double) (height - side) / 2.0;
        var target_center_x = board_x + side * (is_white ? 0.71 : 0.29);
        var target_center_y = board_y + side * 0.50;

        var target1_x = target_center_x - 38.0 + state.jitter_x1;
        var target1_y = target_center_y - 34.0 + state.jitter_y1;
        var target_yaw1 = -0.14 + state.jitter_yaw1;

        var target2_x = target_center_x + 38.0 + state.jitter_x2;
        var target2_y = target_center_y + 34.0 + state.jitter_y2;
        var target_yaw2 = 0.18 + state.jitter_yaw2;

        // Точки начала вылета:
        // Белые: вылетают из зоны над правой панелью
        // Черные: вылетают из зоны над левой панелью
        var start1_x = is_white ? (board_x + side + 65.0) : (board_x - 65.0);
        var start1_y = target_center_y - 65.0;
        var start2_x = is_white ? (board_x + side + 85.0) : (board_x - 85.0);
        var start2_y = target_center_y + 65.0;

        // Конечные точки слотов кубиков в панели управления:
        double s1x, s1y, s2x, s2y;
        double slot1_x, slot1_y, slot2_x, slot2_y;
        if (is_white) {
            white_panel.get_dice_slot_centers (out s1x, out s1y, out s2x, out s2y);
            slot1_x = board_x + side + s1x;
            slot1_y = s1y;
            slot2_x = board_x + side + s2x;
            slot2_y = s2y;
        } else {
            black_panel.get_dice_slot_centers (out s1x, out s1y, out s2x, out s2y);
            slot1_x = s1x;
            slot1_y = s1y;
            slot2_x = s2x;
            slot2_y = s2y;
        }

        double x1, y1, pitch1, yaw1, roll1, scale1, alt1;
        double shadow_rad1, shadow_y1, shadow_op1;

        if (state.is_transferring) {
            var tr_elapsed = (now - state.transfer_start_time_us) / 1000000.0;
            var u1 = double.min (1.0, double.max (0.0, tr_elapsed / 0.26));
            var ease_u1 = 0.5 * (1.0 - Math.cos (u1 * Math.PI));
            x1 = target1_x + (slot1_x - target1_x) * ease_u1;
            y1 = target1_y + (slot1_y - target1_y) * ease_u1;
            yaw1 = target_yaw1 * (1.0 - ease_u1);
            pitch1 = 0.0; roll1 = 0.0; scale1 = 1.0; alt1 = 0.0;
            shadow_rad1 = 3.5; shadow_y1 = 2.5; shadow_op1 = 0.30 * (1.0 - ease_u1 * 0.4);
        } else {
            var eff_t1 = double.min (1.0, raw_t * 1.02);
            double pos_f1, sc_p1;
            compute_motion (eff_t1, out pos_f1, out alt1, out sc_p1);
            x1 = start1_x + (target1_x - start1_x) * pos_f1;
            y1 = start1_y + (target1_y - start1_y) * pos_f1 - alt1;
            compute_3d_rotation (eff_t1, target_yaw1, state.spin_pitch1, state.spin_roll1, state.spin_yaw1, is_white,
                                 out pitch1, out yaw1, out roll1);
            scale1 = 1.0 + sc_p1;
            shadow_rad1 = 3.5 + alt1 * 0.35;
            shadow_y1 = 2.5 + alt1 * 0.30;
            shadow_op1 = (eff_t1 >= 0.82 ? 0.30 : (0.12 + 0.18 * (1.0 - double.min (1.0, alt1 / 75.0))));
        }

        double x2, y2, pitch2, yaw2, roll2, scale2, alt2;
        double shadow_rad2, shadow_y2, shadow_op2;

        if (state.is_transferring) {
            var tr_elapsed = (now - state.transfer_start_time_us) / 1000000.0;
            var u2 = double.min (1.0, double.max (0.0, (tr_elapsed - 0.08) / 0.26));
            var ease_u2 = 0.5 * (1.0 - Math.cos (u2 * Math.PI));
            x2 = target2_x + (slot2_x - target2_x) * ease_u2;
            y2 = target2_y + (slot2_y - target2_y) * ease_u2;
            yaw2 = target_yaw2 * (1.0 - ease_u2);
            pitch2 = 0.0; roll2 = 0.0; scale2 = 1.0; alt2 = 0.0;
            shadow_rad2 = 3.5; shadow_y2 = 2.5; shadow_op2 = 0.30 * (1.0 - ease_u2 * 0.4);
        } else {
            var eff_t2 = double.min (1.0, double.max (0.0, (raw_t - 0.08) / 0.92));
            double pos_f2, sc_p2;
            compute_motion (eff_t2, out pos_f2, out alt2, out sc_p2);
            x2 = start2_x + (target2_x - start2_x) * pos_f2;
            y2 = start2_y + (target2_y - start2_y) * pos_f2 - alt2;
            compute_3d_rotation (eff_t2, target_yaw2, state.spin_pitch2, state.spin_roll2, state.spin_yaw2, is_white,
                                 out pitch2, out yaw2, out roll2);
            scale2 = 1.0 + sc_p2;
            shadow_rad2 = 3.5 + alt2 * 0.35;
            shadow_y2 = 2.5 + alt2 * 0.30;
            shadow_op2 = (eff_t2 >= 0.82 ? 0.30 : (0.12 + 0.18 * (1.0 - double.min (1.0, alt2 / 75.0))));
        }

        // Ограничивающий прямоугольник двух кубиков и их теней, чтобы не перерисовывать всё окно:
        var r1 = 48.0 * scale1 * 0.85 + shadow_rad1 + 8.0;
        var r2 = 48.0 * scale2 * 0.85 + shadow_rad2 + 8.0;
        var min_x = double.max (0.0, Math.floor (double.min (x1 - r1, x2 - r2)));
        var min_y = double.max (0.0, Math.floor (double.min (y1 - r1, y2 - r2)));
        var max_x = double.min ((double) width, Math.ceil (double.max (x1 + r1, x2 + r2)));
        var max_y = double.min ((double) height, Math.ceil (double.max (y1 + alt1 + shadow_y1 + r1, y2 + alt2 + shadow_y2 + r2)));
        if (max_x <= min_x || max_y <= min_y) {
            return;
        }
        var bounds = Graphene.Rect ().init ((float) min_x, (float) min_y, (float) (max_x - min_x), (float) (max_y - min_y));
        var cr = snapshot.append_cairo (bounds);

        // 1. Отрисовка теней под обоими кубиками
        draw_die_shadow (cr, x1, y1 + alt1 + shadow_y1, 48.0 * scale1, shadow_rad1, shadow_op1);
        draw_die_shadow (cr, x2, y2 + alt2 + shadow_y2, 48.0 * scale2, shadow_rad2, shadow_op2);

        // 2. Отрисовка кубиков
        draw_single_3d_die (cr, x1, y1, 48.0, scale1, state.roll.die1, pitch1, yaw1, roll1);
        draw_single_3d_die (cr, x2, y2, 48.0, scale2, state.roll.die2, pitch2, yaw2, roll2);
    }

    private static void compute_motion (double t, out double pos_fraction, out double altitude, out double scale_progress) {
        const double impact_t = 0.35;
        if (t <= impact_t) {
            var u = t / impact_t;
            // Баллистическая траектория броска: кубик стартует с максимальной высоты
            // и приземляется точно в момент первого касания (35% времени анимации).
            pos_fraction = 0.72 * (1.0 - Math.pow (1.0 - u, 1.4));
            altitude = 75.0 * (1.0 - u * u);
            scale_progress = (altitude / 75.0) * 0.14;
        } else if (t <= 0.65) {
            var u = (t - impact_t) / 0.30;
            pos_fraction = 0.72 + 0.18 * (1.0 - Math.pow (1.0 - u, 1.6));
            altitude = Math.sin (u * Math.PI) * 16.0;
            scale_progress = (altitude / 16.0) * 0.04;
        } else if (t <= 0.83) {
            var u = (t - 0.65) / 0.18;
            pos_fraction = 0.90 + 0.08 * (1.0 - Math.pow (1.0 - u, 1.8));
            altitude = Math.sin (u * Math.PI) * 4.0;
            scale_progress = 0.0;
        } else {
            var u = (t - 0.83) / 0.17;
            pos_fraction = 0.98 + 0.02 * (1.0 - Math.pow (1.0 - u, 2.0));
            altitude = 0.0;
            scale_progress = 0.0;
        }
    }

    private static void compute_3d_rotation (double t, double target_yaw, double spin_pitch, double spin_roll, double spin_yaw,
                                             bool is_white, out double pitch, out double yaw, out double roll) {
        if (t >= 0.82) {
            pitch = 0.0;
            yaw = target_yaw;
            roll = 0.0;
            return;
        }
        const double impact_t = 0.35;
        double decay;
        if (t <= impact_t) {
            var u = t / impact_t;
            decay = 1.0 - 0.60 * u;
        } else {
            var u = (t - impact_t) / (0.82 - impact_t);
            decay = 0.40 * Math.pow (1.0 - u, 2.0);
        }
        var direction_sign = is_white ? 1.0 : -1.0;
        pitch = spin_pitch * 2.0 * Math.PI * decay * direction_sign;
        roll = spin_roll * 2.0 * Math.PI * decay * (-direction_sign);
        yaw = target_yaw + (spin_yaw * 2.0 * Math.PI * decay * direction_sign);
    }

    private void draw_die_shadow (Cairo.Context cr, double cx, double cy, double size, double radius, double opacity) {
        if (opacity <= 0.01) {
            return;
        }
        cr.save ();
        var r_max = size * 0.55 + radius;
        var pat = new Cairo.Pattern.radial (cx, cy, size * 0.1, cx, cy, r_max);
        pat.add_color_stop_rgba (0.0, 0.0, 0.0, 0.0, opacity);
        pat.add_color_stop_rgba (0.6, 0.0, 0.0, 0.0, opacity * 0.35);
        pat.add_color_stop_rgba (1.0, 0.0, 0.0, 0.0, 0.0);
        cr.set_source (pat);
        cr.arc (cx, cy, r_max, 0, 2 * Math.PI);
        cr.fill ();
        cr.restore ();
    }

    private void draw_single_3d_die (Cairo.Context cr, double cx, double cy, double size, double scale,
                                     int target_value, double pitch, double yaw, double roll) {
        var s = size * scale;
        draw_projected_3d_cube (cr, cx, cy, s, target_value, pitch, yaw, roll);
    }

    private static void get_side_values (int target_value, out int s_posY, out int s_negY, out int s_posX, out int s_negX) {
        switch (target_value) {
        case 1:
            s_posY = 2; s_negY = 5; s_posX = 3; s_negX = 4;
            break;
        case 2:
            s_posY = 6; s_negY = 1; s_posX = 3; s_negX = 4;
            break;
        case 3:
            s_posY = 1; s_negY = 6; s_posX = 5; s_negX = 2;
            break;
        case 4:
            s_posY = 1; s_negY = 6; s_posX = 2; s_negX = 5;
            break;
        case 5:
            s_posY = 1; s_negY = 6; s_posX = 3; s_negX = 4;
            break;
        case 6:
            s_posY = 5; s_negY = 2; s_posX = 3; s_negX = 4;
            break;
        default:
            s_posY = 2; s_negY = 5; s_posX = 3; s_negX = 4;
            break;
        }
    }

    private static void rotate_3d (double x, double y, double z,
                                   double pitch, double roll, double yaw,
                                   out double rx, out double ry, out double rz) {
        // 1. Вращение тангажа (pitch) вокруг оси X в плоскости Y-Z
        var y1 = y * Math.cos (pitch) - z * Math.sin (pitch);
        var z1 = y * Math.sin (pitch) + z * Math.cos (pitch);
        var x1 = x;

        // 2. Вращение крена (roll) вокруг оси Y в плоскости X-Z
        var x2 = x1 * Math.cos (roll) + z1 * Math.sin (roll);
        var z2 = -x1 * Math.sin (roll) + z1 * Math.cos (roll);
        var y2 = y1;

        // 3. Вращение рыскания (yaw) вокруг оси Z в плоскости X-Y (экран)
        rx = x2 * Math.cos (yaw) - y2 * Math.sin (yaw);
        ry = x2 * Math.sin (yaw) + y2 * Math.cos (yaw);
        rz = z2;
    }

    private void draw_projected_3d_cube (Cairo.Context cr, double cx, double cy, double s,
                                         int target_value, double pitch, double yaw, double roll) {
        var h = s / 2.0;
        var r = s * 0.16;
        var h_inner = h - r;

        int s_posY, s_negY, s_posX, s_negX;
        get_side_values (target_value, out s_posY, out s_negY, out s_posX, out s_negX);

        // 6 граней кубика:
        // Cx, Cy, Cz — центр грани в долях от h
        // Ux, Uy, Uz — локальная ось X грани
        // Vx, Vy, Vz — локальная ось Y грани
        // Nx, Ny, Nz — внешняя нормаль грани
        double[,] face_defs = {
            {  0,  0,  1,     1,  0,  0,    0,  1,  0,    0,  0,  1 }, // 0: +Z (Лицевая, target_value)
            {  0,  0, -1,    -1,  0,  0,    0,  1,  0,    0,  0, -1 }, // 1: -Z (Задняя, 7 - target_value)
            {  0,  1,  0,     1,  0,  0,    0,  0, -1,    0,  1,  0 }, // 2: +Y (Верхняя, s_posY)
            {  0, -1,  0,     1,  0,  0,    0,  0,  1,    0, -1,  0 }, // 3: -Y (Нижняя, s_negY)
            {  1,  0,  0,     0,  0, -1,    0,  1,  0,    1,  0,  0 }, // 4: +X (Правая, s_posX)
            { -1,  0,  0,     0,  0,  1,    0,  1,  0,   -1,  0,  0 }  // 5: -X (Левая, s_negX)
        };
        int[] face_vals = { target_value, 7 - target_value, s_posY, s_negY, s_posX, s_negX };

        var visible = new ProjectedDieFace[0];

        for (var fi = 0; fi < 6; fi++) {
            double cx_in = face_defs[fi, 0] * h;
            double cy_in = face_defs[fi, 1] * h;
            double cz_in = face_defs[fi, 2] * h;

            double ux_in = face_defs[fi, 3];
            double uy_in = face_defs[fi, 4];
            double uz_in = face_defs[fi, 5];

            double vx_in = face_defs[fi, 6];
            double vy_in = face_defs[fi, 7];
            double vz_in = face_defs[fi, 8];

            double nx_in = face_defs[fi, 9];
            double ny_in = face_defs[fi, 10];
            double nz_in = face_defs[fi, 11];

            double cr_x, cr_y, cr_z;
            rotate_3d (cx_in, cy_in, cz_in, pitch, roll, yaw, out cr_x, out cr_y, out cr_z);

            double nr_x, nr_y, nr_z;
            rotate_3d (nx_in, ny_in, nz_in, pitch, roll, yaw, out nr_x, out nr_y, out nr_z);

            // Отсечение невидимых граней (нормаль направлена от камеры)
            if (nr_z <= 0.001) {
                continue;
            }

            double ur_x, ur_y, ur_z;
            rotate_3d (ux_in, uy_in, uz_in, pitch, roll, yaw, out ur_x, out ur_y, out ur_z);

            double vr_x, vr_y, vr_z;
            rotate_3d (vx_in, vy_in, vz_in, pitch, roll, yaw, out vr_x, out vr_y, out vr_z);

            var f = new ProjectedDieFace ();
            f.value = face_vals[fi];
            f.avg_z = cr_z;
            f.center_x = cx + cr_x;
            f.center_y = cy + cr_y;
            f.ux_x = ur_x;
            f.ux_y = ur_y;
            f.vy_x = vr_x;
            f.vy_y = vr_y;

            var dot = double.max (0.0, -0.35 * nr_x - 0.45 * nr_y + 0.82 * nr_z);
            f.light = double.min (1.0, 0.65 + 0.35 * dot);

            // 4 внутренних угла для скругленной фаски (beveled hull)
            double q0x, q0y, q0z, q1x, q1y, q1z, q2x, q2y, q2z, q3x, q3y, q3z;
            rotate_3d (nx_in * h_inner - ux_in * h_inner - vx_in * h_inner,
                       ny_in * h_inner - uy_in * h_inner - vy_in * h_inner,
                       nz_in * h_inner - uz_in * h_inner - vz_in * h_inner,
                       pitch, roll, yaw, out q0x, out q0y, out q0z);
            rotate_3d (nx_in * h_inner + ux_in * h_inner - vx_in * h_inner,
                       ny_in * h_inner + uy_in * h_inner - vy_in * h_inner,
                       nz_in * h_inner + uz_in * h_inner - vz_in * h_inner,
                       pitch, roll, yaw, out q1x, out q1y, out q1z);
            rotate_3d (nx_in * h_inner + ux_in * h_inner + vx_in * h_inner,
                       ny_in * h_inner + uy_in * h_inner + vy_in * h_inner,
                       nz_in * h_inner + uz_in * h_inner + vz_in * h_inner,
                       pitch, roll, yaw, out q2x, out q2y, out q2z);
            rotate_3d (nx_in * h_inner - ux_in * h_inner + vx_in * h_inner,
                       ny_in * h_inner - uy_in * h_inner + vy_in * h_inner,
                       nz_in * h_inner - uz_in * h_inner + vz_in * h_inner,
                       pitch, roll, yaw, out q3x, out q3y, out q3z);

            f.q0_x = cx + q0x; f.q0_y = cy + q0y;
            f.q1_x = cx + q1x; f.q1_y = cy + q1y;
            f.q2_x = cx + q2x; f.q2_y = cy + q2y;
            f.q3_x = cx + q3x; f.q3_y = cy + q3y;

            visible += f;
        }

        // Сортировка по Z (алгоритм художника: дальние грани рисуются первыми)
        for (var a = 0; a < visible.length - 1; a++) {
            for (var b = a + 1; b < visible.length; b++) {
                if (visible[a].avg_z > visible[b].avg_z) {
                    var tmp = visible[a];
                    visible[a] = visible[b];
                    visible[b] = tmp;
                }
            }
        }

        // 1. Отрисовка скругленного тела кубика (Minkowski beveled hull)
        foreach (var f in visible) {
            cr.save ();
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.set_line_width (2.0 * r);
            cr.move_to (f.q0_x, f.q0_y);
            cr.line_to (f.q1_x, f.q1_y);
            cr.line_to (f.q2_x, f.q2_y);
            cr.line_to (f.q3_x, f.q3_y);
            cr.close_path ();
            cr.set_source_rgba (0.86 * f.light, 0.86 * f.light, 0.86 * f.light, 1.0);
            cr.fill_preserve ();
            cr.stroke ();
            cr.restore ();
        }

        // 2. Отрисовка лицевых пластин граней со скругленными углами и точками
        foreach (var f in visible) {
            cr.save ();
            var mat = Cairo.Matrix (
                f.ux_x, f.ux_y,
                f.vy_x, f.vy_y,
                f.center_x, f.center_y
            );
            cr.transform (mat);

            var half = s / 2.0;
            var radius = s * 0.18;
            var x = -half;
            var y = -half;

            // Градиент керамики/слоновой кости от белого к светло-серому с учётом освещения
            var grad = new Cairo.Pattern.linear (x, y, x + s, y + s);
            grad.add_color_stop_rgba (0.0, 1.0 * f.light, 1.0 * f.light, 1.0 * f.light, 1.0);
            grad.add_color_stop_rgba (1.0, 0.82 * f.light, 0.82 * f.light, 0.82 * f.light, 1.0);
            DiceDrawing.rounded_rect (cr, x, y, s, s, radius);
            cr.set_source (grad);
            cr.fill_preserve ();

            // Внутренний контур скругленной фаски для реалистичного 3D-объёма
            cr.set_line_width (1.0);
            cr.set_source_rgba (0.76 * f.light, 0.76 * f.light, 0.76 * f.light, 0.35);
            cr.stroke ();

            // Мягкий рассеянный блик в верхне-левой части грани
            var highlight = new Cairo.Pattern.radial (x + s * 0.30, y + s * 0.30, 0,
                                                      x + s * 0.30, y + s * 0.30, s * 0.60);
            highlight.add_color_stop_rgba (0.0, 1.0, 1.0, 1.0, 0.35 * f.light);
            highlight.add_color_stop_rgba (1.0, 1.0, 1.0, 1.0, 0.0);
            DiceDrawing.rounded_rect (cr, x, y, s, s, radius);
            cr.set_source (highlight);
            cr.fill ();

            // Точки (пипсы): диаметр 14%, координаты 28%, 50%, 72%
            var pip_r = s * 0.14 / 2.0;
            cr.set_source_rgba (0.08, 0.08, 0.08, 0.88);
            double[] pips = DiceDrawing.pip_positions (f.value);
            for (var i = 0; i + 1 < pips.length; i += 2) {
                cr.arc (x + pips[i] * s, y + pips[i + 1] * s, pip_r, 0, 2 * Math.PI);
                cr.fill ();
            }
            cr.restore ();
        }
    }
}

} /* namespace Longbackgammon */
