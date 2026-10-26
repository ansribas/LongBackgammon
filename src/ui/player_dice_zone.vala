/* player_dice_zone.vala
 *
 * Верхняя зона отображения кубиков игрока в боковой панели:
 * карточка костей с подсветкой активного хода (DiceCardBox),
 * анимация броска и выпавших значений (PlayerDiceZone),
 * оверлей перелёта кубиков в лог истории (FlyingLayer, FlyingDie).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Модель траектории анимированного перелёта кубика:
 * координаты источника (слот зоны кубиков) и приёмника (ячейка лога),
 * длительность и временная метка старта.
 */
public class FlyingDie {
    public int id;
    public int value;
    public bool to_log;          // Направление: true — сверху вниз в лог, false — откат из лога вверх
    public bool is_skipped;
    public int64 start_us;
    public double duration;
    public Graphene.Rect from_rect;
    public Graphene.Rect to_rect;
}

/**
 * Зона кубиков игрока (высота 76px):
 * отрисовывает анимацию броска, кубики розыгрыша первого хода или кости текущего хода
 * с эффектом раскрытия дубля (4 кубика) и индикатором пропущенных ходов.
 */
public class PlayerDiceZone : Gtk.DrawingArea {
    private weak PlayerPanel panel;

    public PlayerDiceZone (PlayerPanel panel) {
        this.panel = panel;
        set_content_height (76);
        set_draw_func (draw_cb);
    }

    private GameSession session { get { return panel.session; } }

    /** Режим отображения зоны: 0 — скрыта, 1 — бросок, 2 — розыгрыш первого хода, 3 — кости текущего хода. */
    private int mode () {
        var color = panel.color;
        var show = color == CheckerColor.WHITE ? session.should_show_white_die : session.should_show_black_die;
        if (!show) {
            return 0;
        }
        if (session.is_first_move_rolloff_in_progress) {
            var rolling_this = session.is_rolling && (
                (color == CheckerColor.WHITE && session.rolling_die_index == 0) ||
                (color == CheckerColor.BLACK && session.rolling_die_index == 1));
            if (rolling_this) {
                return 1;
            }
            var rd = color == CheckerColor.WHITE ? session.white_rolloff_dice : session.black_rolloff_dice;
            return rd != null ? 2 : 0;
        }
        if (panel.is_active ()) {
            if (SettingsStore.shared ().use_board_dice_animation && session.board_dice_state != null) {
                return 0;
            }
            if (session.is_rolling) {
                return 1;
            }
            if (session.current_turn_dice.length > 0 && !session.is_game_over) {
                return 3;
            }
        }
        return 0;
    }

    /** Прямоугольник слота кубика текущего хода в локальных координатах зоны. */
    public Graphene.Rect top_slot_rect (int die_id, int count) {
        var w = get_width ();
        var h = 76.0;
        var is_double = count > 2;
        var size = is_double ? 34.0 : 48.0;
        var spacing = 5.0;
        var row_w = size * 2 + spacing;
        var start_x = (w - row_w) / 2.0;
        if (is_double) {
            var total_h = size * 2 + 3;
            var top = (h - total_h) / 2.0;
            var row = die_id / 2;
            var col = die_id % 2;
            return Graphene.Rect ().init ((float) (start_x + col * (size + spacing)),
                                          (float) (top + row * (size + 3)), (float) size, (float) size);
        }
        var n = int.max (1, count);
        var total_w = size * n + spacing * (n - 1);
        var sx = (w - total_w) / 2.0;
        return Graphene.Rect ().init ((float) (sx + die_id * (size + spacing)), (float) ((h - size) / 2.0),
                                      (float) size, (float) size);
    }

    /** Прямоугольник слота кубика розыгрыша первого хода (индекс 0 или 1). */
    public Graphene.Rect rolloff_slot_rect (int idx) {
        var w = get_width ();
        var size = 48.0;
        var spacing = 8.0;
        var start_x = (w - (size * 2 + spacing)) / 2.0;
        return Graphene.Rect ().init ((float) (start_x + idx * (size + spacing)), (float) ((76 - size) / 2.0),
                                      (float) size, (float) size);
    }

    private void draw_cb (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        switch (mode ()) {
        case 1:
            draw_rolling_pair (cr, width, height);
            break;
        case 2:
            var rd = panel.color == CheckerColor.WHITE ? session.white_rolloff_dice : session.black_rolloff_dice;
            if (rd != null) {
                for (var idx = 0; idx < 2; idx++) {
                    if (panel.is_flying (idx == 0 ? 100 : 101)) {
                        continue;
                    }
                    var r = rolloff_slot_rect (idx);
                    DiceDrawing.draw (cr, r.get_x () + 24, r.get_y () + 24, 48, idx == 0 ? rd.die1 : rd.die2);
                }
            }
            break;
        case 3:
            var dice = session.current_turn_dice;
            var is_double = dice.length > 2;
            var size = is_double ? 34.0 : 48.0;
            foreach (var die in dice) {
                var is_flying = panel.is_flying (die.id);
                var is_pending_skip = panel.is_pending_skip (die.id);
                var is_pending_fly = panel.is_pending_fly (die.id);
                var is_pending_unfly = panel.is_pending_unfly (die.id);
                var is_hidden = (die.is_used && !is_pending_fly) || (die.is_skipped && !is_pending_skip) || is_pending_unfly || is_flying;
                if (is_hidden) {
                    continue;
                }
                var r = top_slot_rect (die.id, dice.length);
                var cx = r.get_x () + size / 2;
                var cy = r.get_y () + size / 2;
                var die_size = size;
                var die_alpha = 1.0;
                if (is_double) {
                    // Анимация раскрытия куша: 2 кубика плавно расходятся в сетку 2x2 из 4 кубиков
                    var progress = session.double_division_progress;
                    var col = die.id % 2;
                    var row = die.id / 2;
                    var horizontal_offset = (col == 0 ? -7.0 : 7.0) * (1.0 - progress);
                    var vertical_offset = (row == 0 ? 18.5 : -18.5) * (1.0 - progress);
                    cx += horizontal_offset;
                    cy += vertical_offset;
                    die_size = size * (48.0 / 34.0 + (1.0 - 48.0 / 34.0) * progress);
                    if (row == 1) {
                        die_alpha = double.min (1.0, progress);
                    }
                }
                var skip_progress = die.is_skipped ? panel.skipped_cross_progress (die.id) : 0.0;
                die_alpha *= 1.0 - 0.12 * skip_progress;
                PanelStyle.draw_effect_die (cr, session, cx, cy, die_size, die.value, die_alpha);
                if (die.is_skipped) {
                    DiceDrawing.draw_red_cross (cr, cx, cy, die_size, skip_progress);
                }
            }
            break;
        default:
            break;
        }
    }

    private void draw_rolling_pair (Cairo.Context cr, int width, int height) {
        var size = 48.0;
        var spacing = 8.0;
        var start_x = (width - (size * 2 + spacing)) / 2.0;
        int[] vals = { session.rolling_dice_value1, session.rolling_dice_value2 };
        for (var i = 0; i < 2; i++) {
            var cx = start_x + i * (size + spacing) + size / 2 + GLib.Random.double_range (-2, 2);
            var cy = height / 2.0 + GLib.Random.double_range (-3, 1);
            var rot = GLib.Random.double_range (-5, 5) * Math.PI / 180.0;
            cr.save ();
            cr.translate (cx, cy);
            cr.rotate (rot);
            DiceDrawing.draw_soft_shadow (cr, -size / 2, -size / 2 + 4, size, size, size * 0.18, 8, 0.2);
            DiceDrawing.draw (cr, 0, 0, size, vals[i]);
            cr.restore ();
        }
    }
}

/**
 * Прозрачный оверлей для отрисовки кубиков в полёте между верхней зоной и логом.
 */
public class FlyingLayer : Gtk.DrawingArea {
    private weak PlayerPanel panel;

    public FlyingLayer (PlayerPanel panel) {
        this.panel = panel;
        can_target = false;
        set_draw_func (draw_cb);
    }

    private void draw_cb (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        panel.draw_flying (cr, this);
    }
}

/**
 * Карточка кубиков с анимируемой рамкой активного игрока.
 */
public class DiceCardBox : Gtk.Box {
    public double highlight = 0.0;

    public DiceCardBox () {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class ("lb-card");
        add_css_class ("lb-card-dice");
        overflow = Gtk.Overflow.HIDDEN;
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        base.snapshot (snapshot);

        var w = (float) get_width ();
        var h = (float) get_height ();
        if (w <= 0 || h <= 0) {
            return;
        }

        var r = Gsk.RoundedRect ();
        r.init_from_rect (Graphene.Rect ().init (0.5f, 0.5f, w - 1.0f, h - 1.0f), 12.0f);

        var fg = get_color ();
        var t = (float) highlight;
        var border_color = Gdk.RGBA () {
            red = (1.0f - t) * fg.red + t * 1.0f,
            green = (1.0f - t) * fg.green + t * 0.584f,
            blue = (1.0f - t) * fg.blue + t * 0.0f,
            alpha = (1.0f - t) * 0.12f + t * 1.0f
        };

        float widths[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
        Gdk.RGBA colors[4] = { border_color, border_color, border_color, border_color };
        snapshot.append_border (r, widths, colors);
    }
}

} /* namespace Longbackgammon */
