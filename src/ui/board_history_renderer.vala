/* board_history_renderer.vala
 *
 * Отрисовка подсветок истории ходов из лога партии на доске:
 * круги пройденных пунктов, номера пунктов и анимированные изогнутые стрелки перемещений.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class BoardHistoryRenderer {
    private const double LOG_BLUE_R = 0.0;
    private const double LOG_BLUE_G = 0.478;
    private const double LOG_BLUE_B = 1.0;

    private static Pango.FontDescription? cached_index_font = null;

    public static void draw_history_log (
        Cairo.Context cr,
        double side,
        GameSession session,
        int log_shown_id,
        double log_anim_t0,
        bool log_fading_out,
        double now_sec
    ) {
        if (!SettingsStore.shared ().highlight_log_paths || log_shown_id < 0) {
            return;
        }
        TurnRecord? record;
        CheckerColor color;
        if (!session.find_log_record (log_shown_id, out record, out color) || record == null) {
            return;
        }
        var t = (now_sec - log_anim_t0) / 0.2;
        var e = BoardGeometry.ease_in_out (double.min (1.0, double.max (0.0, t)));
        // Появление: стрелка «прорисовывается» (progress 0→1) и проявляется; исчезновение — растворение
        var progress = log_fading_out ? 1.0 : e;
        var alpha = log_fading_out ? 1.0 - e : e;
        if (alpha <= 0.001 || progress <= 0) {
            return;
        }

        var diameter = BoardLayout.checker_diameter (side);
        var radius = diameter * 0.52;
        var arrow_width = double.max (3.5, diameter * 0.08);

        cr.push_group ();

        // 1. Круги подсветки пройденных пунктов (с номерами индексов, если включено)
        var points = new BoardPoint[0];
        foreach (var m in record.moves) {
            foreach (var s in m.steps) {
                if (!BoardGeometry.contains_point (points, s.from)) {
                    points += s.from;
                }
                if (s.to != null && !BoardGeometry.contains_point (points, s.to)) {
                    points += s.to;
                }
            }
        }
        var show_indices = SettingsStore.shared ().show_cell_indices;
        var circle_opacity = show_indices ? 0.85 : 0.35;
        foreach (var p in points) {
            double x, y;
            BoardLayout.position (p, side, out x, out y);
            cr.set_source_rgba (LOG_BLUE_R, LOG_BLUE_G, LOG_BLUE_B, circle_opacity);
            cr.arc (x, y, diameter / 2.0, 0, 2 * Math.PI);
            cr.fill ();

            if (show_indices) {
                cr.set_source_rgba (1.0, 1.0, 1.0, 0.3);
                cr.set_line_width (1.0);
                cr.arc (x, y, diameter / 2.0 - 0.5, 0, 2 * Math.PI);
                cr.stroke ();

                var layout = Pango.cairo_create_layout (cr);
                if (cached_index_font == null) {
                    cached_index_font = new Pango.FontDescription ();
                    cached_index_font.set_family ("sans-serif");
                    cached_index_font.set_weight (Pango.Weight.BOLD);
                }
                cached_index_font.set_absolute_size (diameter * 0.44 * Pango.SCALE);
                layout.set_font_description (cached_index_font);
                layout.set_text (p.raw_value ().to_string (), -1);
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);

                cr.set_source_rgba (0.0, 0.0, 0.0, 0.4);
                cr.move_to (x - lw / 2.0, y - lh / 2.0 + 1.0);
                Pango.cairo_show_layout (cr, layout);

                cr.set_source_rgba (1.0, 1.0, 1.0, 1.0);
                cr.move_to (x - lw / 2.0, y - lh / 2.0);
                Pango.cairo_show_layout (cr, layout);
            }
        }

        // 2. Стрелки перемещения
        var log = (color == CheckerColor.WHITE) ? session.white_turn_log : session.black_turn_log;
        var turn_idx = -1;
        for (var i = 0; i < log.length; i++) {
            if (log[i].id == record.id) {
                turn_idx = i;
                break;
            }
        }
        // Фишки, вынесенные в более ранних (старых) ходах: лог хранится от новых к старым
        var older = 0;
        if (turn_idx >= 0) {
            for (var i = turn_idx + 1; i < log.length; i++) {
                foreach (var m in log[i].moves) {
                    older += count_bearoff_steps (m, m.steps.length);
                }
            }
        }

        var turn_prev = 0;
        for (var midx = 0; midx < record.moves.length; midx++) {
            var move = record.moves[midx];
            for (var sdx = 0; sdx < move.steps.length; sdx++) {
                var step = move.steps[sdx];
                double fx, fy, tx, ty;
                BoardLayout.position (step.from, side, out fx, out fy);
                if (step.to != null) {
                    BoardLayout.position (step.to, side, out tx, out ty);
                } else if (turn_idx < 0) {
                    BoardLayout.bear_off_position (color, 0, side, out tx, out ty);
                } else {
                    var idx = older + turn_prev + count_bearoff_steps (move, sdx);
                    BoardLayout.bear_off_position (color, idx, side, out tx, out ty);
                }
                draw_arrow (cr, fx, fy, tx, ty, progress, radius, radius, arrow_width, side);
            }
            turn_prev += count_bearoff_steps (move, move.steps.length);
        }

        cr.pop_group_to_source ();
        cr.paint_with_alpha (alpha);
    }

    /** Количество выносов среди первых `limit` шагов хода. */
    private static int count_bearoff_steps (LogMove move, int limit) {
        var n = 0;
        for (var i = 0; i < limit && i < move.steps.length; i++) {
            if (move.steps[i].to == null) {
                n++;
            }
        }
        return n;
    }

    private static void draw_arrow (
        Cairo.Context cr,
        double fx,
        double fy,
        double tx,
        double ty,
        double progress,
        double start_radius,
        double end_radius,
        double width,
        double side
    ) {
        var dx = tx - fx;
        var dy = ty - fy;
        var dist = Math.sqrt (dx * dx + dy * dy);
        if (dist <= 1 || progress <= 0) {
            return;
        }
        var mid_x = (fx + tx) / 2.0;
        var mid_y = (fy + ty) / 2.0;
        var arc_depth = double.max (16, dist * 0.18);
        var offset_y = mid_y < side / 2.0 ? arc_depth : -arc_depth;
        var cx = mid_x;
        var cy = mid_y + offset_y;

        var safe_start = double.min (start_radius, dist * 0.42);
        var safe_end = double.min (end_radius, dist * 0.42);

        double ax = fx, ay = fy;
        var out_dx = cx - fx;
        var out_dy = cy - fy;
        var out_len = Math.sqrt (out_dx * out_dx + out_dy * out_dy);
        if (out_len > 0 && safe_start > 0) {
            ax = fx + out_dx / out_len * safe_start;
            ay = fy + out_dy / out_len * safe_start;
        }
        double bx = tx, by = ty;
        var in_dx = tx - cx;
        var in_dy = ty - cy;
        var in_len = Math.sqrt (in_dx * in_dx + in_dy * in_dy);
        if (in_len > 0 && safe_end > 0) {
            bx = tx - in_dx / in_len * safe_end;
            by = ty - in_dy / in_len * safe_end;
        }

        // Обрезка кривой до progress (де Кастельжо)
        var t = double.min (1.0, progress);
        var c1x = ax + (cx - ax) * t;
        var c1y = ay + (cy - ay) * t;
        var tipx = Math.pow (1 - t, 2) * ax + 2 * (1 - t) * t * cx + t * t * bx;
        var tipy = Math.pow (1 - t, 2) * ay + 2 * (1 - t) * t * cy + t * t * by;

        var tanx = 2 * (1 - t) * (cx - ax) + 2 * t * (bx - cx);
        var tany = 2 * (1 - t) * (cy - ay) + 2 * t * (by - cy);
        var angle = Math.atan2 (tany, tanx);
        var head = double.min (15, double.max (10, dist * 0.15));
        var head_angle = Math.PI / 6;

        cr.set_line_width (width);
        cr.set_line_cap (Cairo.LineCap.ROUND);
        cr.set_line_join (Cairo.LineJoin.ROUND);

        // Тень (black 0.35, radius 2, y +1) — два смещённых слоя
        for (var pass = 0; pass < 3; pass++) {
            double ox = 0, oy = 0;
            if (pass == 0) {
                oy = 1.0;
                cr.set_source_rgba (0, 0, 0, 0.18);
                cr.set_line_width (width + 3);
            } else if (pass == 1) {
                oy = 1.0;
                cr.set_source_rgba (0, 0, 0, 0.22);
                cr.set_line_width (width + 1);
            } else {
                cr.set_source_rgba (LOG_BLUE_R, LOG_BLUE_G, LOG_BLUE_B, 0.92);
                cr.set_line_width (width);
            }
            cr.new_path ();
            // Квадратичная → кубическая кривая
            var q1x = ax + 2.0 / 3.0 * (c1x - ax);
            var q1y = ay + 2.0 / 3.0 * (c1y - ay);
            var q2x = tipx + 2.0 / 3.0 * (c1x - tipx);
            var q2y = tipy + 2.0 / 3.0 * (c1y - tipy);
            cr.move_to (ax + ox, ay + oy);
            cr.curve_to (q1x + ox, q1y + oy, q2x + ox, q2y + oy, tipx + ox, tipy + oy);
            cr.move_to (tipx + ox, tipy + oy);
            cr.line_to (tipx - head * Math.cos (angle - head_angle) + ox, tipy - head * Math.sin (angle - head_angle) + oy);
            cr.move_to (tipx + ox, tipy + oy);
            cr.line_to (tipx - head * Math.cos (angle + head_angle) + ox, tipy - head * Math.sin (angle + head_angle) + oy);
            cr.stroke ();
        }
    }
}

} /* namespace Longbackgammon */
