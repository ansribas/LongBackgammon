/* board_view.vala
 *
 * Игровая доска: полная отрисовка на Cairo (поля, фишки, подсветки,
 * зоны выноса) и обработка взаимодействия мышью (клики и drag-and-drop).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Позиция фишки для анимации (в долях стороны доски, чтобы не зависеть от размеров). */
public class CPoint {
    public double x;
    public double y;

    public CPoint (double x, double y) {
        this.x = x;
        this.y = y;
    }
}

/** Активное перемещение фишки (координаты в долях стороны доски). */
public class CMove {
    public double sx;
    public double sy;
    public double ex;
    public double ey;
    public double t0;
    public double duration;
    /** true — пружина (возврат после неудачного перетаскивания), false — easeInOut. */
    public bool spring;
    public double arc_scale;
    public bool is_top_half;
    public double scale;
    public double lift;
    public CheckerColor color;
    public bool is_drag_drop;

    public CMove (double sx, double sy, double ex, double ey, double t0, double duration,
                  bool spring = false, double arc_scale = 0.0, bool is_top_half = false,
                  CheckerColor color = CheckerColor.WHITE, bool is_drag_drop = false) {
        this.sx = sx;
        this.sy = sy;
        this.ex = ex;
        this.ey = ey;
        this.t0 = t0;
        this.duration = duration;
        this.spring = spring;
        this.arc_scale = arc_scale;
        this.is_top_half = is_top_half;
        this.scale = is_drag_drop ? 1.08 : 1.0;
        this.lift = is_drag_drop ? 0.4 : 0.0;
        this.color = color;
        this.is_drag_drop = is_drag_drop;
    }
}

public class BoardView : Gtk.DrawingArea {
    public GameSession session { get; construct set; }
    public bool overlay_presented { get; set; default = false; }

    public signal void new_game_requested ();

    // Цвет подсветки ходов из лога (насыщенный синий)
    private const double LOG_BLUE_R = 0.0;
    private const double LOG_BLUE_G = 0.478;
    private const double LOG_BLUE_B = 1.0;

    // Минимальная дистанция смещения курсора в пикселях для старта перетаскивания
    private const double DRAG_MIN_DISTANCE = 10.0;

    // Растровые текстуры доски и фишек (при отсутствии используется векторный fallback)
    private Cairo.ImageSurface? board_img = null;
    private Cairo.ImageSurface? white_img = null;
    private Cairo.ImageSurface? black_img = null;

    // Курсор-кубик (BoardCursorArea.diceCursor)
    private Gdk.Cursor? dice_cursor = null;
    private Gdk.Cursor? pointer_cursor = null;
    private double mouse_x = -1;
    private double mouse_y = -1;
    private bool mouse_inside = false;

    // Анимация перемещения фишек (позиции — в долях стороны доски)
    private HashTable<uint8, CPoint> cur_pos;
    private HashTable<uint8, CPoint> prev_pos;
    private HashTable<uint8, CMove> active_moves;
    private GameBoard? prev_board = null;
    private bool anim_inited = false;

    // Перетаскивание фишки мышью
    private bool drag_candidate = false;   // нажатие пришлось на фишку, которую можно тащить
    private bool dragging = false;
    private bool drag_occurred = false;    // был ли drag в этом press-цикле
    private bool press_consumed = false;   // нажатие уже обработано (курсор-кубик)
    private uint8 drag_id = 255;
    private uint8 dropped_checker_id = 255;
    private BoardPoint drag_point = BoardPoint.P1;
    private CheckerColor drag_color = CheckerColor.WHITE;
    // Координаты перетаскивания — в пространстве доски (пиксели после вычитания ox/oy)
    private double drag_x = 0;
    private double drag_y = 0;
    private double drag_origin_x = 0;
    private double drag_origin_y = 0;
    private double drag_base_x = 0;
    private double drag_base_y = 0;

    // Анимация подсветки хода из лога (easeInOut 0.2, как в HistoryLogView)
    private int log_shown_id = -1;
    private double log_anim_t0 = 0;
    private bool log_fading_out = false;

    public BoardView (GameSession session) {
        Object (session: session);
    }

    construct {
        set_draw_func (draw_cb);
        session.changed.connect (() => {
            on_board_changed ();
            on_log_highlight_changed ();
            update_cursor ();
            queue_draw ();
        });
        SettingsStore.shared ().changed.connect (() => {
            load_images ();
            update_cursor ();
            queue_draw ();
        });
        notify["overlay-presented"].connect (() => { update_cursor (); });
        load_images ();

        // Обработка кликов: pressed — бросок костей при активном курсоре-кубике,
        // released — выбор фишек, ход, вынос или сброс выделения.
        var gesture = new Gtk.GestureClick ();
        gesture.pressed.connect ((g, n, xx, yy) => {
            press_consumed = false;
            drag_occurred = false;
            if (!overlay_presented && session.show_dice_cursor && inside_board (xx, yy)) {
                press_consumed = true;
                handle_board_tap ();
            }
        });
        gesture.released.connect ((g, n, xx, yy) => {
            var skip = drag_occurred || press_consumed;
            drag_occurred = false;
            press_consumed = false;
            if (!skip) {
                handle_click (xx, yy);
            }
        });
        add_controller (gesture);

        var drag = new Gtk.GestureDrag ();
        drag.drag_begin.connect (on_drag_begin);
        drag.drag_update.connect (on_drag_update);
        drag.drag_end.connect (on_drag_end);
        add_controller (drag);

        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect ((x, y) => {
            mouse_inside = true;
            mouse_x = x;
            mouse_y = y;
            if (!dragging) {
                double ox, oy;
                board_origin (out ox, out oy);
                update_hover_target (x - ox, y - oy, board_side ());
            }
            update_cursor ();
        });
        motion.motion.connect ((x, y) => {
            mouse_inside = true;
            mouse_x = x;
            mouse_y = y;
            if (!dragging) {
                double ox, oy;
                board_origin (out ox, out oy);
                update_hover_target (x - ox, y - oy, board_side ());
            }
            update_cursor ();
        });
        motion.leave.connect (() => {
            mouse_inside = false;
            session.hovered_target_point = null;
            session.is_hovering_bear_off_target = false;
            set_cursor (null);
            queue_draw ();
        });
        add_controller (motion);

        add_tick_callback (on_anim_tick);
    }

    private void load_images () {
        var theme = SettingsStore.shared ().board_theme;
        board_img = load_asset (theme.board_asset_name ());
        white_img = load_asset (theme.checker_asset_name (CheckerColor.WHITE));
        black_img = load_asset (theme.checker_asset_name (CheckerColor.BLACK));

        pointer_cursor = new Gdk.Cursor.from_name ("pointer", null);
        var cursor_name = theme.dice_cursor_asset_name ();
        var res_cursor_path = "/org/gnome/longbackgammon/images/" + cursor_name;
        bool cursor_loaded = false;
        try {
            // Сначала пробуем встроенный ресурс (всегда доступен в Flatpak / GNOME Builder)
            var pb = new Gdk.Pixbuf.from_resource_at_scale (res_cursor_path, 60, 60, true);
            var tex = texture_for_pixbuf (pb);
            dice_cursor = new Gdk.Cursor.from_texture (tex, 30, 30, null);
            cursor_loaded = true;
        } catch (Error e) {
            // Ресурс не найден, пробуем файловую систему
        }

        if (!cursor_loaded) {
            var cursor_path = StoragePaths.find_asset_path ("images", cursor_name);
            if (cursor_path != "") {
                try {
                    var pb = new Gdk.Pixbuf.from_file_at_scale (cursor_path, 60, 60, true);
                    var tex = texture_for_pixbuf (pb);
                    dice_cursor = new Gdk.Cursor.from_texture (tex, 30, 30, null);
                } catch (Error e) {
                    warning ("Cannot load dice cursor asset '%s': %s", cursor_path, e.message);
                    dice_cursor = null;
                }
            } else {
                warning ("Dice cursor asset '%s' was not found", cursor_name);
            }
        }
    }

    [CCode (cname = "gdk_texture_new_for_pixbuf")]
    private extern static Gdk.Texture texture_for_pixbuf (Gdk.Pixbuf pixbuf);

    private Cairo.ImageSurface? load_asset (string name) {
        var res_path = "/org/gnome/longbackgammon/images/" + name;
        try {
            var bytes = GLib.resources_lookup_data (res_path, GLib.ResourceLookupFlags.NONE);
            size_t offset = 0;
            var surface = new Cairo.ImageSurface.from_png_stream ((data) => {
                var remaining = bytes.length - offset;
                var to_copy = size_t.min (data.length, remaining);
                if (to_copy == 0) {
                    return Cairo.Status.READ_ERROR;
                }
                Memory.copy (data, ((uint8*) bytes.get_data ()) + offset, to_copy);
                offset += to_copy;
                return Cairo.Status.SUCCESS;
            });
            if (surface.status () == Cairo.Status.SUCCESS) {
                return surface;
            }
        } catch (Error e) {
            // Фолбэк на файловую систему
        }

        var path = StoragePaths.find_asset_path ("images", name);
        if (path == "") {
            return null;
        }
        var s = new Cairo.ImageSurface.from_png (path);
        if (s.get_width () > 0 && s.get_height () > 0) {
            return s;
        }
        return null;
    }

    // MARK: - Геометрия

    private double board_side () {
        var side = double.min (get_width (), get_height ());
        return side > 0 ? side : 512.0;
    }

    private void board_origin (out double ox, out double oy) {
        var side = board_side ();
        ox = (get_width () - side) / 2.0;
        oy = (get_height () - side) / 2.0;
    }

    private bool inside_board (double x, double y) {
        double ox, oy;
        board_origin (out ox, out oy);
        var side = board_side ();
        var px = x - ox;
        var py = y - oy;
        return px >= 0 && py >= 0 && px <= side && py <= side;
    }

    /** Позиция фишки index в стопке точки (пиксели доски). */
    private void stack_position (BoardPoint point, int index, double side, out double x, out double y) {
        var diameter = BoardLayout.checker_diameter (side);
        BoardLayout.position (point, side, out x, out y);
        y += BoardLayout.stack_offset (index, diameter, point.stack_direction ());
    }

    private int stack_count (BoardPoint point) {
        var stack = session.board.stack_at (point);
        return (stack == null) ? 0 : stack.checker_ids.length;
    }

    private static bool contains_point (BoardPoint[] arr, BoardPoint p) {
        foreach (var x in arr) {
            if (x == p) {
                return true;
            }
        }
        return false;
    }

    // MARK: - Анимация перемещения фишек

    /** Целевые позиции всех фишек в долях стороны доски. */
    private HashTable<uint8, CPoint> build_positions () {
        var map = new HashTable<uint8, CPoint> (null, null);
        for (var raw = 1; raw <= 24; raw++) {
            var point = (BoardPoint) raw;
            var stack = session.board.stack_at (point);
            if (stack == null) {
                continue;
            }
            for (var i = 0; i < stack.checker_ids.length; i++) {
                double x, y;
                stack_position (point, i, 1.0, out x, out y);
                map.insert (stack.checker_ids[i], new CPoint (x, y));
            }
        }
        uint8[] wb = session.board.white_borne_off_ids;
        for (var i = 0; i < wb.length; i++) {
            double bx, by;
            BoardLayout.bear_off_position (CheckerColor.WHITE, i, 1.0, out bx, out by);
            map.insert (wb[i], new CPoint (bx, by));
        }
        uint8[] bb = session.board.black_borne_off_ids;
        for (var i = 0; i < bb.length; i++) {
            double bx, by;
            BoardLayout.bear_off_position (CheckerColor.BLACK, i, 1.0, out bx, out by);
            map.insert (bb[i], new CPoint (bx, by));
        }
        return map;
    }

    private void on_board_changed () {
        var targets = build_positions ();

        if (!anim_inited) {
            cur_pos = copy_positions (targets);
            prev_pos = targets;
            active_moves = new HashTable<uint8, CMove> (null, null);
            prev_board = session.board.clone ();
            anim_inited = true;
            return;
        }

        if (session.board.is_in_tray ()) {
            cur_pos = copy_positions (targets);
            prev_pos = copy_positions (targets);
            active_moves.remove_all ();
            prev_board = session.board.clone ();
            queue_draw ();
            return;
        }

        if (prev_board == null) {
            prev_board = session.board.clone ();
        }

        var now = GLib.get_monotonic_time () / 1000000.0;
        var duration = SettingsStore.shared ().animation_speed.checker_move_duration;
        targets.foreach ((key, tgt) => {
            var old = prev_pos.lookup (key);

            // При отмене хода (Undo) анимируется только возвращаемая фишка;
            // остальные фишки стопки мгновенно принимают восстановленное положение.
            if (session.is_undoing_move && (int) key != session.undo_flight_checker_id) {
                cur_pos.insert (key, new CPoint (tgt.x, tgt.y));
                active_moves.remove (key);
                return;
            }

            if (old == null) {
                cur_pos.insert (key, new CPoint (tgt.x, tgt.y));
                return;
            }
            if (old.x != tgt.x || old.y != tgt.y) {
                // Анимация стартует из текущей (возможно, промежуточной) позиции
                var from = cur_pos.lookup (key);
                var sx = (from != null) ? from.x : old.x;
                var sy = (from != null) ? from.y : old.y;

                BoardPoint? from_point;
                int from_idx;
                prev_board.find_checker_location (key, out from_point, out from_idx);

                BoardPoint? to_point;
                int to_idx;
                session.board.find_checker_location (key, out to_point, out to_idx);

                var color = (key < 15) ? CheckerColor.WHITE : CheckerColor.BLACK;

                double arc_scale = 0.0;
                var is_top = (from_point != null) ? from_point.is_top_half () :
                             (to_point != null ? to_point.is_top_half () : (color == CheckerColor.BLACK));

                var is_dropped = (key == dropped_checker_id);
                var is_placing = session.is_placing_checkers;
                if (!is_placing && !is_dropped && SettingsStore.shared ().is_arc_movement_enabled) {
                    if (from_point != null && to_point != null && from_point.is_top_half () != to_point.is_top_half ()) {
                        // Переход через середину доски между верхней и нижней половиной — прямой
                        arc_scale = 0.0;
                    } else {
                        // Коэффициент дуги в зависимости от разницы высот стопок
                        if (from_point == null || to_point == null) {
                            arc_scale = 1.0;
                        } else {
                            var diff = from_idx - to_idx;
                            if (diff <= 0) {
                                arc_scale = 1.0;
                            } else {
                                var red = double.min (1.0, (double) diff / 6.0);
                                arc_scale = double.max (0.12, 1.0 - red * 0.88);
                            }
                        }
                    }
                }

                var move_dur = is_placing ? PlacementAnimation.SPRING_RESPONSE : duration;
                active_moves.insert (key, new CMove (sx, sy, tgt.x, tgt.y, now, move_dur, is_placing, is_placing ? 0.0 : arc_scale, is_top, color, is_dropped));
            }
        });
        prev_pos = copy_positions (targets);
        prev_board = session.board.clone ();
    }

    private HashTable<uint8, CPoint> copy_positions (HashTable<uint8, CPoint> src) {
        var copy = new HashTable<uint8, CPoint> (null, null);
        src.foreach ((key, v) => {
            copy.insert (key, new CPoint (v.x, v.y));
        });
        return copy;
    }

    /** Плавная интерполяция ease-in-out по кубической кривой Безье (0.42, 0, 0.58, 1). */
    private static double ease_in_out (double t) {
        if (t <= 0) {
            return 0;
        }
        if (t >= 1) {
            return 1;
        }
        // Решаем x(u) = t методом Ньютона для кривой Безье (0.42,0)-(0.58,1)
        double u = t;
        for (var i = 0; i < 8; i++) {
            var x = 3 * (1 - u) * (1 - u) * u * 0.42 + 3 * (1 - u) * u * u * 0.58 + u * u * u - t;
            var dx = 3 * (1 - u) * (1 - u) * 0.42 + 6 * (1 - u) * u * (0.58 - 0.42) + 3 * u * u * (1 - 0.58);
            if (Math.fabs (dx) < 1e-6) {
                break;
            }
            u -= x / dx;
            u = double.max (0, double.min (1, u));
        }
        return 3 * (1 - u) * u * u + u * u * u;
    }

    /** Затухающие гармонические колебания пружины (response, dampingFraction). */
    private static double spring_value (double t, double response = PlacementAnimation.SPRING_RESPONSE, double damping = PlacementAnimation.SPRING_DAMPING) {
        var resp = response > 0.001 ? response : PlacementAnimation.SPRING_RESPONSE;
        var damp = damping > 0.001 ? damping : PlacementAnimation.SPRING_DAMPING;
        var omega = 2 * Math.PI / resp;
        var zeta = damp;
        var wd = omega * Math.sqrt (1 - zeta * zeta);
        return 1.0 - Math.exp (-zeta * omega * t) * (Math.cos (wd * t) + zeta / Math.sqrt (1 - zeta * zeta) * Math.sin (wd * t));
    }

    /** Обновляет текущие позиции по активным перемещениям. */
    private bool update_moves_now () {
        if (active_moves == null || cur_pos == null || active_moves.size () == 0) {
            return false;
        }
        var now = GLib.get_monotonic_time () / 1000000.0;
        uint8[] to_remove = new uint8[0];

        active_moves.foreach ((key, m) => {
            var elapsed = now - m.t0;
            var total = m.spring ? (m.duration > 0 ? m.duration : PlacementAnimation.SPRING_RESPONSE) : m.duration;
            if (elapsed >= total || total <= 0) {
                cur_pos.insert (key, new CPoint (m.ex, m.ey));
                m.scale = 1.0;
                m.lift = 0.0;
                to_remove += key;
                return;
            }
            var e = m.spring ? spring_value (double.max (0, elapsed), total, PlacementAnimation.SPRING_DAMPING) : ease_in_out (elapsed / total);

            if (m.arc_scale > 0 && !m.spring) {
                // Расчёт параболической дуги полёта фишки с подъёмом и динамической тенью
                var lift_factor = 4.0 * e * (1.0 - e);
                var base_x = m.sx + (m.ex - m.sx) * e;
                var base_y = m.sy + (m.ey - m.sy) * e;

                var dx = m.ex - m.sx;
                var dy = m.ey - m.sy;
                var dist = Math.hypot (dx, dy);

                double norm_x = 0;
                double norm_y = m.is_top_half ? 1 : -1;
                if (dist > 0.001) {
                    var ux = dx / dist;
                    var uy = dy / dist;
                    var n1_x = -uy;
                    var n1_y = ux;
                    var n2_x = uy;
                    var n2_y = -ux;

                    if (Math.fabs (n1_y) > 0.001) {
                        if (m.is_top_half) {
                            norm_x = (n1_y > 0) ? n1_x : n2_x;
                            norm_y = (n1_y > 0) ? n1_y : n2_y;
                        } else {
                            norm_x = (n1_y < 0) ? n1_x : n2_x;
                            norm_y = (n1_y < 0) ? n1_y : n2_y;
                        }
                    } else {
                        var mid_x = (m.sx + m.ex) / 2.0;
                        var to_center_x = 0.5 - mid_x;
                        norm_x = (n1_x * to_center_x >= 0) ? n1_x : n2_x;
                        norm_y = (n1_x * to_center_x >= 0) ? n1_y : n2_y;
                    }
                }

                var diameter = BoardLayout.checker_diameter (1.0);
                var base_arc_height = double.min (double.max (dist * 0.32, diameter * 0.55), diameter * 1.6);
                var max_arc_height = base_arc_height * m.arc_scale;

                var arc_off_x = norm_x * max_arc_height * lift_factor;
                var arc_off_y = norm_y * max_arc_height * lift_factor;

                cur_pos.insert (key, new CPoint (base_x + arc_off_x, base_y + arc_off_y));
                m.scale = 1.0 + lift_factor * 0.20;
                m.lift = lift_factor;
            } else {
                cur_pos.insert (key, new CPoint (m.sx + (m.ex - m.sx) * e, m.sy + (m.ey - m.sy) * e));
                if (m.is_drag_drop) {
                    var factor = double.max (0.0, 1.0 - double.min (1.0, elapsed / total));
                    m.scale = 1.0 + 0.08 * factor;
                    m.lift = 0.4 * factor;
                } else {
                    m.scale = 1.0;
                    m.lift = 0.0;
                }
            }
        });

        foreach (var k in to_remove) {
            active_moves.remove (k);
        }
        return true;
    }

    private bool on_anim_tick (Gtk.Widget widget, Gdk.FrameClock frame) {
        var redraw = update_moves_now ();
        if (log_shown_id >= 0 || log_fading_out) {
            var t = (GLib.get_monotonic_time () / 1000000.0) - log_anim_t0;
            if (t <= 0.25) {
                redraw = true;
            } else if (log_fading_out) {
                log_fading_out = false;
                log_shown_id = -1;
                redraw = true;
            }
        }
        if (redraw) {
            queue_draw ();
        }
        return GLib.Source.CONTINUE;
    }

    private void on_log_highlight_changed () {
        var id = session.highlighted_log_id;
        if (id >= 0) {
            if (id != log_shown_id || log_fading_out) {
                log_shown_id = id;
                log_fading_out = false;
                log_anim_t0 = GLib.get_monotonic_time () / 1000000.0;
            }
        } else if (log_shown_id >= 0 && !log_fading_out) {
            log_fading_out = true;
            log_anim_t0 = GLib.get_monotonic_time () / 1000000.0;
        }
    }

    // MARK: - Курсор

    private void update_cursor () {
        if (!mouse_inside) {
            return;
        }
        if (!overlay_presented && session.show_dice_cursor && inside_board (mouse_x, mouse_y)) {
            set_cursor (dice_cursor != null ? dice_cursor : pointer_cursor);
            return;
        }
        if (overlay_presented || dragging) {
            set_cursor (dragging ? pointer_cursor : null);
            return;
        }
        double ox, oy;
        board_origin (out ox, out oy);
        var px = mouse_x - ox;
        var py = mouse_y - oy;
        var side = board_side ();
        var hand = false;
        if (green_target_at (px, py, side) != null || bear_off_area_hit (px, py, side)) {
            hand = true;
        } else {
            int idx;
            var point = checker_at (px, py, side, out idx);
            if (point != null) {
                var stack = session.board.stack_at (point);
                hand = stack != null && stack.color == session.current_player
                       && idx == stack.checker_ids.length - 1;
            }
        }
        set_cursor (hand ? pointer_cursor : null);
    }

    // MARK: - Определение элементов под курсором (Hit-testing)

    /** Зелёная мишень хода (верхний слой, zIndex 1000). */
    private BoardPoint? green_target_at (double px, double py, double side) {
        if (session.selected_point == null || session.is_computer_turn) {
            return null;
        }
        var r = BoardLayout.checker_diameter (side) / 2.0;
        foreach (var t in session.target_points ()) {
            double tx, ty;
            stack_position (t, stack_count (t), side, out tx, out ty);
            if (Math.hypot (px - tx, py - ty) <= r) {
                return t;
            }
        }
        return null;
    }

    private bool is_bear_off_available (CheckerColor color) {
        return session.current_player == color && session.can_bear_off_selected && !session.is_computer_turn;
    }

    /** Кнопки выноса: кружок на месте следующей фишки и капсула на весь столбец накопителя. */
    private bool bear_off_area_hit (double px, double py, double side) {
        var color = session.current_player;
        if (!is_bear_off_available (color)) {
            return false;
        }
        var diameter = BoardLayout.checker_diameter (side);
        var count = session.board.borne_off_count (color);
        double nx, ny;
        BoardLayout.bear_off_position (color, count, side, out nx, out ny);
        if (Math.hypot (px - nx, py - ny) <= diameter / 2.0) {
            return true;
        }
        double sx, sy;
        BoardLayout.bear_off_position (color, 0, side, out sx, out sy);
        var cx = (sx + nx) / 2.0;
        var cy = (sy + ny) / 2.0;
        var spacing = diameter * 1.01;
        var h = count > 0 ? (count + 1) * spacing + diameter : diameter * 2;
        var w = diameter * 1.5;
        // Капсула: прямоугольник со скруглёнными концами радиуса w/2
        var dx = Math.fabs (px - cx);
        var dy = Math.fabs (py - cy);
        if (dx > w / 2.0 || dy > h / 2.0) {
            return false;
        }
        var straight = h / 2.0 - w / 2.0;
        if (dy <= straight) {
            return true;
        }
        return Math.hypot (dx, dy - straight) <= w / 2.0;
    }

    /** Фишка под курсором (верхняя по z: больший индекс в стопке рисуется выше). */
    private BoardPoint? checker_at (double px, double py, double side, out int index) {
        var r = BoardLayout.checker_diameter (side) / 2.0;
        BoardPoint? best = null;
        int best_idx = -1;
        index = -1;
        for (var raw = 1; raw <= 24; raw++) {
            var point = (BoardPoint) raw;
            var count = stack_count (point);
            for (var i = 0; i < count; i++) {
                double x, y;
                stack_position (point, i, side, out x, out y);
                if (Math.hypot (px - x, py - y) <= r && i >= best_idx) {
                    best = point;
                    best_idx = i;
                }
            }
        }
        index = best_idx;
        return best;
    }

    // MARK: - Клики

    /** Обработка клика по нейтральной области игрового поля. */
    private void handle_board_tap () {
        if (overlay_presented) {
            return;
        }
        if (!session.is_game_started) {
            new_game_requested ();
            return;
        }
        if (session.is_computer_turn) {
            return;
        }
        if (session.can_roll) {
            session.roll_dice ();
        } else {
            session.select_point_none ();
        }
    }

    private void handle_click (double x, double y) {
        if (overlay_presented || !inside_board (x, y)) {
            return;
        }
        double ox, oy;
        board_origin (out ox, out oy);
        handle_click_board (x - ox, y - oy, board_side ());
    }

    /** Публичный вход для тестов: клик в координатах виджета заданного размера. */
    public void handle_board_click_at (double x, double y, int awidth, int aheight, int press_count = 1) {
        var side = double.min (awidth, aheight);
        if (overlay_presented || side <= 0) {
            return;
        }
        var px = x - (awidth - side) / 2.0;
        var py = y - (aheight - side) / 2.0;
        if (px < 0 || py < 0 || px > side || py > side) {
            return;
        }
        if (session.show_dice_cursor) {
            handle_board_tap ();
            return;
        }
        handle_click_board (px, py, side);
    }

    private void handle_click_board (double px, double py, double side) {
        if (session.is_animating) {
            return;
        }
        // 1. Мишени ходов — поверх всех фишек
        var target = green_target_at (px, py, side);
        if (target != null && session.selected_point != null) {
            session.apply_move (target, session.selected_point);
            return;
        }
        // 2. Зоны выноса за борт
        if (bear_off_area_hit (px, py, side)) {
            session.bear_off_selected ();
            return;
        }
        // 3. Фишки — любая фишка выбирает свою точку (ActiveCheckersLayer.onTapGesture)
        int idx;
        var point = checker_at (px, py, side, out idx);
        if (point != null) {
            if (session.is_game_started) {
                session.select (point);
            }
            return;
        }
        // 4. Пустое поле
        handle_board_tap ();
    }

    // MARK: - Перетаскивание (DraggableCheckerView)

    private void on_drag_begin (Gtk.GestureDrag gesture, double start_x, double start_y) {
        drag_candidate = false;
        dragging = false;
        if (overlay_presented || !SettingsStore.shared ().is_drag_and_drop_enabled) {
            return;
        }
        if (!session.is_game_started || session.show_dice_cursor || session.is_computer_turn
            || session.is_animating) {
            return;
        }
        double ox, oy;
        board_origin (out ox, out oy);
        var side = board_side ();
        var px = start_x - ox;
        var py = start_y - oy;
        int idx;
        var point = checker_at (px, py, side, out idx);
        if (point == null) {
            return;
        }
        var stack = session.board.stack_at (point);
        // canSelect: своя верхняя фишка; hasLegalMoves: есть ходы из точки
        if (stack == null || stack.color != session.current_player || idx != stack.checker_ids.length - 1) {
            return;
        }
        if (session.options_from (point).length == 0) {
            return;
        }
        drag_candidate = true;
        drag_id = stack.checker_ids[idx];
        drag_point = point;
        drag_color = stack.color;
        stack_position (point, idx, side, out drag_base_x, out drag_base_y);
        drag_origin_x = px;
        drag_origin_y = py;
        drag_x = drag_base_x;
        drag_y = drag_base_y;
    }

    private void on_drag_update (Gtk.GestureDrag gesture, double off_x, double off_y) {
        if (!drag_candidate) {
            return;
        }
        if (!dragging) {
            if (Math.hypot (off_x, off_y) < DRAG_MIN_DISTANCE) {
                return;
            }
            dragging = true;
            drag_occurred = true;  // блокируем клик (released) для этого press-цикла
            gesture.set_state (Gtk.EventSequenceState.CLAIMED);
            if (session.selected_point != drag_point) {
                session.select (drag_point);
            }
        }
        // Фишка смещается на величину перемещения мыши от базовой позиции
        drag_x = drag_base_x + off_x;
        drag_y = drag_base_y + off_y;
        update_hover_target (drag_x, drag_y, board_side ());
        update_cursor ();
        queue_draw ();
    }

    private void on_drag_end (Gtk.GestureDrag gesture, double off_x, double off_y) {
        var was_dragging = dragging;
        drag_candidate = false;
        session.hovered_target_point = null;
        session.is_hovering_bear_off_target = false;
        if (!was_dragging) {
            return;
        }
        drag_x = drag_base_x + off_x;
        drag_y = drag_base_y + off_y;
        var side = board_side ();
        var diameter = BoardLayout.checker_diameter (side);

        // Ближайшая цель в радиусе двух диаметров
        var best_dist = diameter * 2.0;
        BoardPoint? best_target = null;
        foreach (var t in session.target_points ()) {
            double tx, ty;
            stack_position (t, stack_count (t), side, out tx, out ty);
            var d = Math.hypot (drag_x - tx, drag_y - ty);
            if (d < best_dist) {
                best_dist = d;
                best_target = t;
            }
        }

        dragging = false;
        if (best_target != null) {
            // Доводка фишки в точку назначения от текущего положения курсора без резких скачков
            plant_drag_position (side);
            dropped_checker_id = drag_id;
            session.apply_move (best_target, drag_point, true);
            dropped_checker_id = 255;
        } else if (session.can_bear_off_selected) {
            double bx, by;
            BoardLayout.bear_off_position (drag_color, session.board.borne_off_count (drag_color), side, out bx, out by);
            if (Math.hypot (drag_x - bx, drag_y - by) < diameter * 3) {
                plant_drag_position (side);
                dropped_checker_id = drag_id;
                session.bear_off_selected (true);
                dropped_checker_id = 255;
            } else {
                spring_back (side);
            }
        } else {
            spring_back (side);
        }
        drag_id = 255;
        update_cursor ();
        queue_draw ();
    }

    /** Ставит анимируемую позицию фишки туда, где её отпустили. */
    private void plant_drag_position (double side) {
        cur_pos.insert (drag_id, new CPoint (drag_x / side, drag_y / side));
        prev_pos.insert (drag_id, new CPoint (drag_x / side, drag_y / side));
    }

    /** Фишка отпущена в недопустимом месте: пружинный возврат и снятие выделения. */
    private void spring_back (double side) {
        var now = GLib.get_monotonic_time () / 1000000.0;
        var return_duration = (SettingsStore.shared ().game_speed == GameSpeed.SLOW) ? 0.65 : 0.50;
        active_moves.insert (drag_id, new CMove (drag_x / side, drag_y / side,
            drag_base_x / side, drag_base_y / side, now, return_duration, true, 0.0, false, drag_color, true));
        session.select_point_none ();
    }

    /** Обновляет точку назначения или зону сброса под курсором или перетаскиваемой фишкой. */
    private void update_hover_target (double px, double py, double side) {
        if (session.selected_point == null) {
            if (session.hovered_target_point != null || session.is_hovering_bear_off_target) {
                session.hovered_target_point = null;
                session.is_hovering_bear_off_target = false;
                queue_draw ();
            }
            return;
        }

        var diameter = BoardLayout.checker_diameter (side);
        BoardPoint? found_target = null;
        var targets = session.target_points ();
        foreach (var t in targets) {
            double tx, ty;
            stack_position (t, stack_count (t), side, out tx, out ty);
            if (Math.hypot (px - tx, py - ty) <= diameter * 0.75) {
                found_target = t;
                break;
            }
        }
        if (found_target == null) {
            foreach (var tp in session.potential_targets ()) {
                double tx, ty;
                stack_position (tp, stack_count (tp), side, out tx, out ty);
                if (Math.hypot (px - tx, py - ty) <= diameter * 0.75) {
                    found_target = tp;
                    break;
                }
            }
        }

        bool hovering_bear_off = false;
        if (session.can_bear_off_selected) {
            double bx, by;
            var color = session.current_player;
            BoardLayout.bear_off_position (color, session.board.borne_off_count (color), side, out bx, out by);
            if (Math.hypot (px - bx, py - by) <= diameter * 1.5) {
                hovering_bear_off = true;
            }
        }

        if (session.hovered_target_point != found_target || session.is_hovering_bear_off_target != hovering_bear_off) {
            session.hovered_target_point = found_target;
            session.is_hovering_bear_off_target = hovering_bear_off;
            queue_draw ();
        }
    }

    // MARK: - Главная отрисовка

    private void draw_cb (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        var side = double.min (width, height);
        if (side <= 0) {
            return;
        }
        var ox = (width - side) / 2.0;
        var oy = (height - side) / 2.0;

        cr.save ();
        cr.translate (ox, oy);

        // Последовательный рендеринг слоёв доски снизу вверх:
        // фон -> подсветки доступных ходов -> стопки фишек -> траектории истории
        draw_board_background (cr, side);
        draw_highlights (cr, side);
        draw_checkers (cr, side);
        draw_history_log (cr, side);

        cr.restore ();
    }

    private void paint_image (Cairo.Context cr, Cairo.ImageSurface img, double x, double y, double w, double h) {
        var iw = img.get_width ();
        var ih = img.get_height ();
        cr.save ();
        cr.translate (x, y);
        cr.scale (w / iw, h / ih);
        cr.set_source_surface (img, 0, 0);
        cr.get_source ().set_filter (Cairo.Filter.GOOD);
        cr.paint ();
        cr.restore ();
    }

    // MARK: - Фон доски

    private void draw_board_background (Cairo.Context cr, double side) {
        if (board_img != null) {
            paint_image (cr, board_img, 0, 0, side, side);
            return;
        }
        // Векторный fallback (если изображение не найдено)
        cr.set_source_rgb (0.30, 0.18, 0.08);
        cr.rectangle (0, 0, side, side);
        cr.fill ();
        var pad = side * 0.035;
        cr.set_source_rgb (0.83, 0.58, 0.28);
        cr.rectangle (pad, pad, side - 2 * pad, side - 2 * pad);
        cr.fill ();
    }

    // MARK: - Подсветки (BoardHighlightsView)

    private void draw_circle_with_number (Cairo.Context cr, double x, double y, double diameter,
                                          double r, double g, double b, double a, int number, bool show_number) {
        cr.set_source_rgba (r, g, b, a);
        cr.arc (x, y, diameter / 2, 0, 2 * Math.PI);
        cr.fill ();
        if (!show_number) {
            return;
        }
        var layout = Pango.cairo_create_layout (cr);
        var font = new Pango.FontDescription ();
        font.set_family ("sans-serif");
        font.set_weight (Pango.Weight.NORMAL);
        font.set_absolute_size (diameter * 0.45 * Pango.SCALE);
        layout.set_font_description (font);
        layout.set_text (number.to_string (), -1);
        int lw, lh;
        layout.get_pixel_size (out lw, out lh);
        cr.set_source_rgba (1, 1, 1, 0.8);
        cr.move_to (x - lw / 2.0, y - lh / 2.0);
        Pango.cairo_show_layout (cr, layout);
    }

    private void draw_highlights (Cairo.Context cr, double side) {
        var selected = session.selected_point;
        if (selected == null) {
            return;
        }
        var theme = SettingsStore.shared ().board_theme;
        var diameter = BoardLayout.checker_diameter (side);
        var opts = session.options_from (selected);

        // 1. Зелёные кружки доступных ходов (по одному на точку назначения)
        var seen = new BoardPoint[0];
        foreach (var o in opts) {
            if (o.to == null || o.is_illegal_prime || contains_point (seen, o.to)) {
                continue;
            }
            seen += o.to;
            double x, y;
            stack_position (o.to, stack_count (o.to), side, out x, out y);
            var is_emp = (session.hovered_target_point == o.to);
            double r, g, b, a;
            theme.get_move_color (is_emp, out r, out g, out b, out a);
            draw_circle_with_number (cr, x, y, diameter, r, g, b, a, o.die, true);
        }

        // 1.1 Красные кружки заблокированных ходов (potentialTargets − targetPoints)
        var legal = session.target_points ();
        foreach (var tp in session.potential_targets ()) {
            if (contains_point (legal, tp)) {
                continue;
            }
            double x, y;
            stack_position (tp, stack_count (tp), side, out x, out y);
            var steps = PlayerPath.steps_between (selected, tp, session.current_player);
            var is_emp = (session.hovered_target_point == tp);
            double r, g, b, a;
            theme.get_illegal_move_color (is_emp, out r, out g, out b, out a);
            draw_circle_with_number (cr, x, y, diameter, r, g, b, a, steps < 0 ? 0 : steps, true);
        }

        // 2. Красная подсветка запрещённых блоков (prime) — в центре точки
        var prime_seen = new BoardPoint[0];
        foreach (var o in opts) {
            if (o.to == null || !o.is_illegal_prime || contains_point (prime_seen, o.to)) {
                continue;
            }
            prime_seen += o.to;
            double x, y;
            BoardLayout.position (o.to, side, out x, out y);
            var is_emp = (session.hovered_target_point == o.to);
            double r, g, b, a;
            theme.get_illegal_move_color (is_emp, out r, out g, out b, out a);
            draw_circle_with_number (cr, x, y, diameter, r, g, b, a, o.die, true);
        }

        // 3. Зелёный кружок выноса за борт
        if (session.can_bear_off_selected) {
            var color = session.current_player;
            double x, y;
            BoardLayout.bear_off_position (color, session.board.borne_off_count (color), side, out x, out y);
            int die = 0;
            var has = false;
            foreach (var o in opts) {
                if (o.to == null) {
                    die = o.die;
                    has = true;
                    break;
                }
            }
            var is_emp = session.is_hovering_bear_off_target;
            double r, g, b, a;
            theme.get_move_color (is_emp, out r, out g, out b, out a);
            draw_circle_with_number (cr, x, y, diameter, r, g, b, a, die, has);
        }
    }

    // MARK: - Фишки (ActiveCheckersLayer + накопители выноса)

    private void draw_checkers (Cairo.Context cr, double side) {
        var diameter = BoardLayout.checker_diameter (side);

        // Накопители выноса — ниже активных фишек
        draw_borne_off (cr, side, diameter, CheckerColor.WHITE, session.board.white_borne_off_ids);
        draw_borne_off (cr, side, diameter, CheckerColor.BLACK, session.board.black_borne_off_ids);

        // zIndex = 100 + stackIndex: рисуем по слоям индекса стопки
        var max_count = 0;
        for (var raw = 1; raw <= 24; raw++) {
            max_count = int.max (max_count, stack_count ((BoardPoint) raw));
        }
        var targets = session.target_points ();
        for (var layer = 0; layer < max_count; layer++) {
            for (var raw = 1; raw <= 24; raw++) {
                var point = (BoardPoint) raw;
                var stack = session.board.stack_at (point);
                if (stack == null || layer >= stack.checker_ids.length) {
                    continue;
                }
                var cid = stack.checker_ids[layer];
                if (dragging && cid == drag_id) {
                    continue;
                }
                if (active_moves != null && active_moves.lookup (cid) != null) {
                    continue; // Летит в верхнем слое (zIndex 2000)
                }
                double x, y;
                stack_position (point, layer, side, out x, out y);
                var p = lookup_pos (cid);
                if (p != null) {
                    x = p.x * side;
                    y = p.y * side;
                }

                var is_top = layer == stack.checker_ids.length - 1;
                if (is_top && session.selected_point == point && !contains_point (targets, point)) {
                    draw_checker_selection_glow (cr, x, y, diameter, session.options_from (point).length > 0);
                }

                draw_checker (cr, x, y, diameter, stack.color, 1.0, 0.0);

                if (is_top && session.selected_point == point && !contains_point (targets, point)) {
                    draw_selection_ring (cr, x, y, diameter, session.options_from (point).length > 0);
                }
            }
        }

        // Анимированные фишки в полёте рисуются поверх всех статичных стопок
        if (active_moves != null && active_moves.size () > 0) {
            active_moves.foreach ((cid, mv) => {
                if (dragging && cid == drag_id) {
                    return;
                }
                var p = lookup_pos (cid);
                if (p != null) {
                    var x = p.x * side;
                    var y = p.y * side;
                    draw_checker (cr, x, y, diameter, mv.color, mv.scale, mv.lift);
                }
            });
        }

        // Перетаскиваемая фишка — поверх всего (zIndex 1000), вместе с радиальным свечением и рамкой выбора
        if (dragging && drag_id != 255) {
            if (session.selected_point == drag_point) {
                draw_checker_selection_glow (cr, drag_x, drag_y, diameter, session.options_from (drag_point).length > 0);
            }
            draw_checker (cr, drag_x, drag_y, diameter, drag_color, 1.08, 0.4);
            if (session.selected_point == drag_point) {
                draw_selection_ring (cr, drag_x, drag_y, diameter, session.options_from (drag_point).length > 0);
            }
        }
    }

    /** Радиальное свечение вокруг выбранной или перетаскиваемой фишки (CheckerSelectionGlowView). */
    private void draw_checker_selection_glow (Cairo.Context cr, double x, double y, double diameter, bool has_legal) {
        var theme = SettingsStore.shared ().board_theme;
        double r = 1.0, g = 1.0, b = 1.0;
        if (!has_legal) {
            r = GameConfig.ILLEGAL_MOVE_R;
            g = GameConfig.ILLEGAL_MOVE_G;
            b = GameConfig.ILLEGAL_MOVE_B;
        } else if (theme == BoardTheme.MARBLE) {
            r = 0.72;
            g = 0.45;
            b = 0.18;
        } else {
            r = 1.0;
            g = 0.96;
            b = 0.85;
        }

        var glow_size = 1.4;
        var radius = diameter * glow_size / 2.0;
        var start_radius = diameter * 0.20;

        var pattern = new Cairo.Pattern.radial (x, y, start_radius, x, y, radius);
        pattern.add_color_stop_rgba (0.0, r, g, b, 0.55);
        pattern.add_color_stop_rgba (0.6, r, g, b, 0.35);
        pattern.add_color_stop_rgba (0.85, r, g, b, 0.12);
        pattern.add_color_stop_rgba (1.0, r, g, b, 0.0);

        cr.save ();
        cr.set_source (pattern);
        cr.arc (x, y, radius, 0, 2 * Math.PI);
        cr.fill ();
        cr.restore ();
    }

    /** Рамка выбора: strokeBorder с padding(-2) — жёлтая при наличии ходов, иначе красная. */
    private void draw_selection_ring (Cairo.Context cr, double x, double y, double diameter, bool has_legal) {
        var lw = double.max (2.0, diameter * 0.06);
        if (has_legal) {
            cr.set_source_rgba (GameConfig.SELECTED_CHECKER_R, GameConfig.SELECTED_CHECKER_G,
                GameConfig.SELECTED_CHECKER_B, GameConfig.SELECTED_CHECKER_A);
        } else {
            cr.set_source_rgba (GameConfig.ILLEGAL_MOVE_R, GameConfig.ILLEGAL_MOVE_G,
                GameConfig.ILLEGAL_MOVE_B, GameConfig.ILLEGAL_MOVE_A);
        }
        cr.set_line_width (lw);
        cr.new_path ();
        cr.arc (x, y, diameter / 2.0 + 2.0 - lw / 2.0, 0, 2 * Math.PI);
        cr.stroke ();
    }

    private void draw_borne_off (Cairo.Context cr, double side, double diameter, CheckerColor color, uint8[] ids) {
        for (var i = 0; i < ids.length; i++) {
            var cid = ids[i];
            if (active_moves != null && active_moves.lookup (cid) != null) {
                continue; // Летит в верхнем слое
            }
            double x, y;
            BoardLayout.bear_off_position (color, i, side, out x, out y);
            var p = lookup_pos (cid);
            if (p != null) {
                x = p.x * side;
                y = p.y * side;
            }
            draw_checker (cr, x, y, diameter, color, 1.0, 0.0);
        }
    }

    private CPoint? lookup_pos (uint8 id) {
        if (cur_pos == null) {
            return null;
        }
        return cur_pos.lookup (id);
    }

    /** Фишка (CheckerPieceView): изображение по кругу + тень (radius 1, x 1, y 2) с эффектом подъема. */
    private void draw_checker (Cairo.Context cr, double x, double y, double diameter, CheckerColor color,
                               double scale = 1.0, double lift = 0.0) {
        var eff_diameter = diameter * scale;
        var r = eff_diameter / 2.0;
        var base_shadow_a = (color == CheckerColor.WHITE) ? 0.22 : 0.35;
        var shadow_a = base_shadow_a + lift * 0.15;
        var shadow_y = (2.0 + lift * 10.0) * (diameter / 36.0);
        var shadow_r = (1.0 + lift * 8.0) * (diameter / 36.0);

        // Мягкая тень: два слоя для имитации размытия и отрыва от доски
        cr.set_source_rgba (0, 0, 0, shadow_a * 0.4);
        cr.arc (x + 1, y + shadow_y, r + shadow_r, 0, 2 * Math.PI);
        cr.fill ();
        cr.set_source_rgba (0, 0, 0, shadow_a * 0.6);
        cr.arc (x + 1, y + shadow_y, r + shadow_r * 0.5, 0, 2 * Math.PI);
        cr.fill ();

        var img = (color == CheckerColor.WHITE) ? white_img : black_img;
        if (img != null) {
            cr.save ();
            cr.arc (x, y, r, 0, 2 * Math.PI);
            cr.clip ();
            paint_image (cr, img, x - r, y - r, eff_diameter, eff_diameter);
            cr.restore ();
            return;
        }

        // Векторный fallback
        if (color == CheckerColor.WHITE) {
            cr.set_source_rgb (0.97, 0.97, 0.98);
        } else {
            cr.set_source_rgb (0.12, 0.12, 0.14);
        }
        cr.arc (x, y, r, 0, 2 * Math.PI);
        cr.fill ();
    }

    // MARK: - История (HistoryLogView)

    private void draw_history_log (Cairo.Context cr, double side) {
        if (!SettingsStore.shared ().highlight_log_paths || log_shown_id < 0) {
            return;
        }
        TurnRecord? record;
        CheckerColor color;
        if (!session.find_log_record (log_shown_id, out record, out color) || record == null) {
            return;
        }
        var t = ((GLib.get_monotonic_time () / 1000000.0) - log_anim_t0) / 0.2;
        var e = ease_in_out (double.min (1.0, double.max (0.0, t)));
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
                if (!contains_point (points, s.from)) {
                    points += s.from;
                }
                if (s.to != null && !contains_point (points, s.to)) {
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
                var font = new Pango.FontDescription ();
                font.set_family ("sans-serif");
                font.set_weight (Pango.Weight.BOLD);
                font.set_absolute_size (diameter * 0.44 * Pango.SCALE);
                layout.set_font_description (font);
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
    private int count_bearoff_steps (LogMove move, int limit) {
        var n = 0;
        for (var i = 0; i < limit && i < move.steps.length; i++) {
            if (move.steps[i].to == null) {
                n++;
            }
        }
        return n;
    }

    /** Стрелка (ArrowShape): квадратичная дуга к центру доски, наконечник 30°, тень. */
    private void draw_arrow (Cairo.Context cr, double fx, double fy, double tx, double ty, double progress,
                             double start_radius, double end_radius, double width, double side) {
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
