/* dice_drawing.vala
 *
 * Отрисовка игральной кости на Cairo (значения 1…6):
 * линейный градиент корпуса белый → светло-серый, скругление фаски,
 * мягкая тень и точки на пропорциональной сетке 28%/50%/72%.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class DiceDrawing {
    /** Рисует кубик с центром в (cx, cy) и размером стороны `size`. */
    public static void draw (Cairo.Context cr, double cx, double cy, double size, int value, CheckerColor? accent = null) {
        draw_full (cr, cx, cy, size, value, 1.0, true);
    }

    /**
     * Рисует кубик с прозрачностью `alpha`.
     * `with_shadow` — флаг отрисовки мягкой тени под кубиком.
     */
    public static void draw_full (Cairo.Context cr, double cx, double cy, double size, int value,
                                  double alpha, bool with_shadow) {
        var half = size / 2.0;
        var radius = size * 0.18;
        var x = cx - half;
        var y = cy - half;

        cr.save ();
        if (with_shadow) {
            draw_soft_shadow (cr, x, y + 1.0, size, size, radius, 2.0, 0.25 * alpha);
        }

        // Тело кубика: линейный градиент от белого (верх-лево) к 0.82 (низ-право)
        var grad = new Cairo.Pattern.linear (x, y, x + size, y + size);
        grad.add_color_stop_rgba (0.0, 1.0, 1.0, 1.0, alpha);
        grad.add_color_stop_rgba (1.0, 0.82, 0.82, 0.82, alpha);
        rounded_rect (cr, x, y, size, size, radius);
        cr.set_source (grad);
        cr.fill ();

        // Точки
        var pip_r = size * 0.14 / 2.0;
        cr.set_source_rgba (0, 0, 0, 0.85 * alpha);
        double[] pts = pip_positions (value);
        for (var i = 0; i + 1 < pts.length; i += 2) {
            cr.arc (x + pts[i] * size, y + pts[i + 1] * size, pip_r, 0, 2 * Math.PI);
            cr.fill ();
        }
        cr.restore ();
    }

    /** Красный крест поверх неиспользованного или пропущенного кубика с поддержкой прогресса появления. */
    public static void draw_red_cross (Cairo.Context cr, double cx, double cy, double size,
                                       double progress = 1.0) {
        progress = double.max (0.0, double.min (1.0, progress));
        if (progress <= 0.0) {
            return;
        }
        var half = size / 2.0;
        var scale = 0.3 + 0.7 * progress;
        var x = -half;
        var y = -half;
        var pad = size * 0.14;
        var stroke = double.max (2.0, size * 0.075);

        cr.save ();
        cr.translate (cx, cy);
        cr.scale (scale, scale);
        cr.set_line_cap (Cairo.LineCap.ROUND);
        // Тень креста
        cr.set_source_rgba (0, 0, 0, 0.12 * progress);
        cr.set_line_width (stroke + 0.6);
        cross_path (cr, x, y + 0.5, size, pad);
        cr.stroke ();
        // Сам крест — градиент красного
        var grad = new Cairo.Pattern.linear (x, y, x + size, y + size);
        grad.add_color_stop_rgba (0.0, 1.0, 0.22, 0.22, 0.60 * progress);
        grad.add_color_stop_rgba (1.0, 0.88, 0.08, 0.08, 0.60 * progress);
        cr.set_source (grad);
        cr.set_line_width (stroke);
        cross_path (cr, x, y, size, pad);
        cr.stroke ();
        cr.restore ();
    }

    private static void cross_path (Cairo.Context cr, double x, double y, double size, double pad) {
        cr.move_to (x + pad, y + pad);
        cr.line_to (x + size - pad, y + size - pad);
        cr.move_to (x + size - pad, y + pad);
        cr.line_to (x + pad, y + size - pad);
    }

    /** Координаты центров точек в долях стороны (x, y попарно). */
    public static double[] pip_positions (int value) {
        const double A = 0.28;
        const double B = 0.5;
        const double C = 0.72;
        switch (value) {
        case 1: return { B, B };
        case 2: return { A, A, C, C };
        case 3: return { A, A, B, B, C, C };
        case 4: return { A, A, C, A, A, C, C, C };
        case 5: return { A, A, C, A, B, B, A, C, C, C };
        case 6: return { A, A, C, A, A, B, C, B, A, C, C, C };
        default: return { B, B };
        }
    }

    /** Мягкая тень: несколько полупрозрачных слоёв, имитирующих гауссово размытие. */
    public static void draw_soft_shadow (Cairo.Context cr, double x, double y, double w, double h,
                                         double radius, double blur, double opacity) {
        var layers = 4;
        for (var i = layers; i >= 1; i--) {
            var grow = blur * (double) i / (double) layers;
            cr.set_source_rgba (0, 0, 0, opacity / (double) layers);
            rounded_rect (cr, x - grow, y - grow, w + 2 * grow, h + 2 * grow, radius + grow);
            cr.fill ();
        }
    }

    public static void rounded_rect (Cairo.Context cr, double x, double y, double w, double h, double r) {
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
        cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
        cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
        cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
        cr.close_path ();
    }
}

} /* namespace Longbackgammon */
