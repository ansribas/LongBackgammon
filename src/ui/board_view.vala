/* board_view.vala
 *
 * Игровая доска: полная отрисовка на Cairo (поля, фишки, подсветки,
 * зоны выноса) и обработка взаимодействия мышью (клики и drag-and-drop).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class BoardView : Gtk.DrawingArea {
    public GameSession session { get; construct set; }
    public bool overlay_presented { get; set; default = false; }

    public signal void new_game_requested ();

    // Цвет подсветки ходов из лога (насыщенный синий)

    // Минимальная дистанция смещения курсора в пикселях для старта перетаскивания
    private const double DRAG_MIN_DISTANCE = 10.0;

    // Предмасштабированные под текущий размер доски и HiDPI-масштаб поверхности
    private Cairo.ImageSurface? cached_board_surface = null;
    private Cairo.ImageSurface? cached_white_static_sprite = null;
    private Cairo.ImageSurface? cached_black_static_sprite = null;
    private Cairo.ImageSurface? cached_white_fly_piece = null;
    private Cairo.ImageSurface? cached_black_fly_piece = null;
    private int cached_board_px = 0;
    private int cached_scale_factor = 0;
    private double cached_sprite_pad = 0.0;

    // Кэшированные объекты Pango для отрисовки цифр в мишенях без покадровых аллокаций
    private Pango.Layout? cached_pango_layout = null;
    private Pango.FontDescription? cached_circle_font = null;

    // Кэш статичного слоя (доска + подсветки + неподвижные фишки) на время полёта/перетаскивания
    private Cairo.ImageSurface? static_board_surface = null;
    private bool static_board_dirty = true;

    // Отслеживание состояния сессии для отсечения холостых перерисовок доски
    private BoardPoint? last_selected_point = null;
    private BoardPoint? last_hovered_target = null;
    private bool last_hovering_bear_off = false;
    private CheckerColor last_current_player = CheckerColor.WHITE;
    private bool last_can_bear_off = false;
    private int last_remaining_dice_len = -1;
    private BoardTheme last_board_theme = SettingsStore.shared ().board_theme;
    private BoardSide last_board_side = SettingsStore.shared ().board_side;

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
    private uint anim_tick_id = 0;

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
    private bool log_fade_in_done = false;

    public BoardView (GameSession session) {
        Object (session: session);
    }

    construct {
        set_draw_func (draw_cb);
        session.changed.connect (() => {
            var board_changed = on_board_changed ();
            var log_changed = on_log_highlight_changed ();
            var rem_len = session.remaining_dice.length;
            var sel_changed = (session.selected_point != last_selected_point)
                           || (session.hovered_target_point != last_hovered_target)
                           || (session.is_hovering_bear_off_target != last_hovering_bear_off)
                           || (session.current_player != last_current_player)
                           || (session.can_bear_off_selected != last_can_bear_off)
                           || (rem_len != last_remaining_dice_len);
            if (sel_changed) {
                last_selected_point = session.selected_point;
                last_hovered_target = session.hovered_target_point;
                last_hovering_bear_off = session.is_hovering_bear_off_target;
                last_current_player = session.current_player;
                last_can_bear_off = session.can_bear_off_selected;
                last_remaining_dice_len = rem_len;
                static_board_dirty = true;
            }
            update_cursor ();
            if (board_changed || sel_changed || log_changed) {
                queue_draw ();
            }
        });
        SettingsStore.shared ().changed.connect (() => {
            var cur_theme = SettingsStore.shared ().board_theme;
            if (cur_theme != last_board_theme) {
                last_board_theme = cur_theme;
                load_images ();
            }
            var cur_side = SettingsStore.shared ().board_side;
            if (cur_side != last_board_side) {
                var old_side = last_board_side;
                last_board_side = cur_side;
                animate_board_side_change (old_side);
                SoundManager.shared ().play_board_side_switch_animation ();
            }
            static_board_dirty = true;
            update_cursor ();
            queue_draw ();
        });
        notify["overlay-presented"].connect (() => { update_cursor (); });
        load_images ();
        init_checker_positions ();

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
            if (mouse_inside && Math.hypot (x - mouse_x, y - mouse_y) < 1.5) {
                return;
            }
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
            if (session.hovered_target_point != null || session.is_hovering_bear_off_target) {
                session.hovered_target_point = null;
                session.is_hovering_bear_off_target = false;
                last_hovered_target = null;
                last_hovering_bear_off = false;
                static_board_dirty = true;
                queue_draw ();
            }
            set_cursor (null);
        });
        add_controller (motion);
    }

    private void invalidate_scaled_cache () {
        cached_board_surface = null;
        cached_white_static_sprite = null;
        cached_black_static_sprite = null;
        cached_white_fly_piece = null;
        cached_black_fly_piece = null;
        cached_board_px = 0;
        cached_scale_factor = 0;
        static_board_dirty = true;
    }

    private void load_images () {
        var theme = SettingsStore.shared ().board_theme;
        invalidate_scaled_cache ();

        pointer_cursor = new Gdk.Cursor.from_name ("pointer", null);
        var cursor_name = theme.dice_cursor_asset_name ();
        var res_cursor_path = "/io/github/ansribas/LongBackgammon/images/" + cursor_name;
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
        var res_path = "/io/github/ansribas/LongBackgammon/images/" + name;
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
    private inline void stack_position (BoardPoint point, int index, double side, out double x, out double y, BoardSide? side_option = null) {
        BoardGeometry.stack_position (point, index, side, out x, out y, side_option);
    }

    private int stack_count (BoardPoint point) {
        var stack = session.board.stack_at (point);
        return (stack == null) ? 0 : stack.checker_ids.length;
    }

    private static inline bool contains_point (BoardPoint[] arr, BoardPoint p) {
        return BoardGeometry.contains_point (arr, p);
    }

    // MARK: - Анимация перемещения фишек

    /** Инициализация позиций фишек при создании доски. */
    private void init_checker_positions () {
        var targets = build_positions (last_board_side);
        cur_pos = copy_positions (targets);
        prev_pos = copy_positions (targets);
        active_moves = new HashTable<uint8, CMove> (null, null);
        prev_board = session.board.clone ();
        anim_inited = true;
        static_board_dirty = true;
    }

    /** Целевые позиции всех фишек в долях стороны доски. */
    private HashTable<uint8, CPoint> build_positions (BoardSide? side_option = null) {
        return BoardGeometry.build_positions (session.board, side_option);
    }

    private double frame_now_sec () {
        return GLib.get_monotonic_time () / 1000000.0;
    }

    private void ensure_anim_tick () {
        var need = (active_moves != null && active_moves.size () > 0)
                   || log_fading_out
                   || (log_shown_id >= 0 && !log_fade_in_done);
        if (need && anim_tick_id == 0) {
            anim_tick_id = add_tick_callback (on_anim_tick);
        }
    }

    private bool on_board_changed () {
        if (anim_inited && prev_board != null
            && prev_board.equals_exact (session.board)) {
            return false;
        }

        var targets = build_positions ();

        if (!anim_inited) {
            cur_pos = copy_positions (targets);
            prev_pos = targets;
            active_moves = new HashTable<uint8, CMove> (null, null);
            prev_board = session.board.clone ();
            anim_inited = true;
            static_board_dirty = true;
            return true;
        }

        if (session.board.is_in_tray () && !session.is_placing_checkers) {
            cur_pos = copy_positions (targets);
            prev_pos = copy_positions (targets);
            active_moves.remove_all ();
            prev_board = session.board.clone ();
            static_board_dirty = true;
            queue_draw ();
            return true;
        }

        if (prev_board == null) {
            prev_board = session.board.clone ();
        }

        var now = frame_now_sec ();
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
                             (to_point != null ? to_point.is_top_half () : !BoardLayout.is_player_on_right_side (color));

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
                active_moves.insert (key, new CMove (sx, sy, tgt.x, tgt.y, now, move_dur, is_placing, is_placing ? 0.0 : arc_scale, is_top, color, is_dropped, to_idx));
            }
        });
        prev_pos = copy_positions (targets);
        prev_board = session.board.clone ();
        static_board_dirty = true;
        ensure_anim_tick ();
        return true;
    }

    /** Анимация переворота доски (сбор в накопители без пружины с четким перелетом). */
    private void animate_board_side_change (BoardSide old_side) {
        if (cur_pos == null || prev_pos == null || active_moves == null) {
            cur_pos = build_positions (old_side);
            prev_pos = copy_positions (cur_pos);
            active_moves = new HashTable<uint8, CMove> (null, null);
            prev_board = session.board.clone ();
            anim_inited = true;
        }

        // До начала партии собираем фишки в накопители при смене стороны
        if (!session.is_game_started) {
            session.board = GameBoard.in_tray ();
        }
        var targets = build_positions (last_board_side);

        var now = frame_now_sec ();
        var move_dur = 0.90;

        targets.foreach ((key, tgt) => {
            var from = cur_pos.lookup (key) ?? prev_pos.lookup (key);
            if (from == null) {
                cur_pos.insert (key, new CPoint (tgt.x, tgt.y));
                return;
            }
            if (from.x == tgt.x && from.y == tgt.y) {
                return;
            }
            BoardPoint? to_point;
            int to_idx;
            session.board.find_checker_location (key, out to_point, out to_idx);
            var delay = (double) int.max (0, to_idx) * 0.06;
            var color = (key < 15) ? CheckerColor.WHITE : CheckerColor.BLACK;
            var is_top = (to_point != null) ? to_point.is_top_half () : !BoardLayout.is_player_on_right_side (color);
            active_moves.insert (
                key,
                new CMove (from.x, from.y, tgt.x, tgt.y, now + delay, move_dur, false, 0.0, is_top, color, false, to_idx)
            );
        });

        prev_pos = copy_positions (targets);
        prev_board = session.board.clone ();
        static_board_dirty = true;
        ensure_anim_tick ();
    }

    public int active_moves_count () {
        return (active_moves != null) ? (int) active_moves.size () : 0;
    }

    private HashTable<uint8, CPoint> copy_positions (HashTable<uint8, CPoint> src) {
        var copy = new HashTable<uint8, CPoint> (null, null);
        src.foreach ((key, v) => {
            copy.insert (key, new CPoint (v.x, v.y));
        });
        return copy;
    }

    private static inline double ease_in_out (double t) {
        return BoardGeometry.ease_in_out (t);
    }

    private static inline double spring_value (double t, double response = PlacementAnimation.SPRING_RESPONSE, double damping = PlacementAnimation.SPRING_DAMPING) {
        return BoardGeometry.spring_value (t, response, damping);
    }

    /** Обновляет текущие позиции по активным перемещениям. */
    private bool update_moves_now (double now) {
        if (active_moves == null || cur_pos == null || active_moves.size () == 0) {
            return false;
        }
        uint8[] to_remove = new uint8[0];

        active_moves.foreach ((key, m) => {
            var elapsed = now - m.t0;
            if (elapsed <= 0) {
                cur_pos.insert (key, new CPoint (m.sx, m.sy));
                m.scale = 1.0;
                m.lift = 0.0;
                return;
            }
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

        if (to_remove.length > 0) {
            foreach (var k in to_remove) {
                active_moves.remove (k);
            }
            static_board_dirty = true;
        }
        return true;
    }

    private bool on_anim_tick (Gtk.Widget widget, Gdk.FrameClock frame) {
        var ft = frame.get_frame_time ();
        var now = (ft > 0 ? ft : GLib.get_monotonic_time ()) / 1000000.0;
        var redraw = update_moves_now (now);
        if (log_shown_id >= 0 || log_fading_out) {
            var t = now - log_anim_t0;
            if (t <= 0.25) {
                redraw = true;
            } else if (log_fading_out) {
                log_fading_out = false;
                log_shown_id = -1;
                redraw = true;
            } else if (!log_fade_in_done) {
                log_fade_in_done = true;
                redraw = true;
            }
        }
        if (redraw) {
            queue_draw ();
        }
        var keep_running = (active_moves != null && active_moves.size () > 0)
                           || log_fading_out
                           || (log_shown_id >= 0 && !log_fade_in_done);
        if (!keep_running) {
            anim_tick_id = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    private bool on_log_highlight_changed () {
        var id = session.highlighted_log_id;
        if (id >= 0) {
            if (id != log_shown_id || log_fading_out) {
                log_shown_id = id;
                log_fading_out = false;
                log_fade_in_done = false;
                log_anim_t0 = frame_now_sec ();
                ensure_anim_tick ();
                return true;
            }
        } else if (log_shown_id >= 0 && !log_fading_out) {
            log_fading_out = true;
            log_anim_t0 = frame_now_sec ();
            ensure_anim_tick ();
            return true;
        }
        return false;
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
        if (session.is_animating || session.is_placing_checkers || session.is_computer_turn) {
            set_cursor (null);
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

    private inline BoardPoint? green_target_at (double px, double py, double side) {
        return BoardGeometry.green_target_at (session, px, py, side);
    }

    private inline bool bear_off_area_hit (double px, double py, double side) {
        return BoardGeometry.bear_off_area_hit (session, px, py, side);
    }

    private inline BoardPoint? checker_at (double px, double py, double side, out int index) {
        return BoardGeometry.checker_at (session, px, py, side, out index);
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
            static_board_dirty = true;
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
        if (session.hovered_target_point != null || session.is_hovering_bear_off_target) {
            session.hovered_target_point = null;
            session.is_hovering_bear_off_target = false;
            last_hovered_target = null;
            last_hovering_bear_off = false;
            static_board_dirty = true;
        }
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
        static_board_dirty = true;

        var should_bear_off = false;
        if (session.can_bear_off_selected) {
            double bx, by;
            BoardLayout.bear_off_position (drag_color, session.board.borne_off_count (drag_color), side, out bx, out by);
            var dist = Math.hypot (drag_x - bx, drag_y - by);
            var tray_margin = diameter * 1.5;
            bool in_bear_off_tray;
            if (BoardLayout.is_player_on_right_side (drag_color)) {
                in_bear_off_tray = drag_x >= (0.943 * side - tray_margin);
            } else {
                in_bear_off_tray = drag_x <= (0.057 * side + tray_margin);
            }
            if (dist < diameter * 3.0 || in_bear_off_tray) {
                if (best_target == null || dist < best_dist || in_bear_off_tray) {
                    should_bear_off = true;
                }
            }
        }

        if (should_bear_off) {
            plant_drag_position (side);
            dropped_checker_id = drag_id;
            session.bear_off_selected (true);
            dropped_checker_id = 255;
        } else if (best_target != null) {
            // Доводка фишки в точку назначения от текущего положения курсора без резких скачков
            plant_drag_position (side);
            dropped_checker_id = drag_id;
            session.apply_move (best_target, drag_point, true);
            dropped_checker_id = 255;
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
        var now = frame_now_sec ();
        var return_duration = (SettingsStore.shared ().game_speed == GameSpeed.SLOW) ? 0.65 : 0.50;
        active_moves.insert (drag_id, new CMove (drag_x / side, drag_y / side,
            drag_base_x / side, drag_base_y / side, now, return_duration, true, 0.0, false, drag_color, true));
        static_board_dirty = true;
        ensure_anim_tick ();
        session.select_point_none ();
    }

    /** Обновляет точку назначения или зону сброса под курсором или перетаскиваемой фишкой. */
    private void update_hover_target (double px, double py, double side) {
        if (session.selected_point == null) {
            if (session.hovered_target_point != null || session.is_hovering_bear_off_target) {
                session.hovered_target_point = null;
                session.is_hovering_bear_off_target = false;
                last_hovered_target = null;
                last_hovering_bear_off = false;
                static_board_dirty = true;
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
            last_hovered_target = found_target;
            last_hovering_bear_off = hovering_bear_off;
            static_board_dirty = true;
            queue_draw ();
        }
    }

    // MARK: - Кэширование предмасштабированных поверхностей и статичного слоя

    private Cairo.ImageSurface build_static_checker_sprite (Cairo.ImageSurface? img, CheckerColor color,
                                                            double diameter, double pad, int scale_factor) {
        var sprite_logical = (int) Math.ceil (pad * 2.0);
        var sprite_px = int.max (1, sprite_logical * scale_factor);
        var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, sprite_px, sprite_px);
        surf.set_device_scale (scale_factor, scale_factor);
        var cr = new Cairo.Context (surf);

        var r = diameter / 2.0;
        var base_shadow_a = (color == CheckerColor.WHITE) ? 0.22 : 0.35;
        var shadow_y = 2.0 * (diameter / 36.0);
        var shadow_r = 1.0 * (diameter / 36.0);

        cr.set_source_rgba (0, 0, 0, base_shadow_a * 0.4);
        cr.arc (pad + 1, pad + shadow_y, r + shadow_r, 0, 2 * Math.PI);
        cr.fill ();
        cr.set_source_rgba (0, 0, 0, base_shadow_a * 0.6);
        cr.arc (pad + 1, pad + shadow_y, r + shadow_r * 0.5, 0, 2 * Math.PI);
        cr.fill ();

        if (img != null) {
            cr.save ();
            cr.arc (pad, pad, r, 0, 2 * Math.PI);
            cr.clip ();
            paint_image (cr, img, pad - r, pad - r, diameter, diameter);
            cr.restore ();
        } else {
            if (color == CheckerColor.WHITE) {
                cr.set_source_rgb (0.97, 0.97, 0.98);
            } else {
                cr.set_source_rgb (0.12, 0.12, 0.14);
            }
            cr.arc (pad, pad, r, 0, 2 * Math.PI);
            cr.fill ();
        }
        return surf;
    }

    private Cairo.ImageSurface build_fly_checker_piece (Cairo.ImageSurface? img, CheckerColor color,
                                                        double diameter, int scale_factor) {
        var fly_diam = diameter * 1.25;
        var fly_px = int.max (1, (int) Math.ceil (fly_diam * scale_factor));
        var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, fly_px, fly_px);
        var cr = new Cairo.Context (surf);
        var half = fly_px / 2.0;

        if (img != null) {
            cr.arc (half, half, half, 0, 2 * Math.PI);
            cr.clip ();
            paint_image (cr, img, 0, 0, fly_px, fly_px);
        } else {
            if (color == CheckerColor.WHITE) {
                cr.set_source_rgb (0.97, 0.97, 0.98);
            } else {
                cr.set_source_rgb (0.12, 0.12, 0.14);
            }
            cr.arc (half, half, half, 0, 2 * Math.PI);
            cr.fill ();
        }
        return surf;
    }

    private void ensure_scaled_assets (double side) {
        var sf = int.max (1, get_scale_factor ());
        var target_px = (int) Math.round (side * sf);
        if (target_px <= 0) {
            return;
        }
        if (cached_board_surface != null && cached_board_px == target_px && cached_scale_factor == sf) {
            return;
        }
        cached_board_px = target_px;
        cached_scale_factor = sf;
        static_board_dirty = true;

        var theme = SettingsStore.shared ().board_theme;
        var raw_board = load_asset (theme.board_asset_name ());
        var raw_white = load_asset (theme.checker_asset_name (CheckerColor.WHITE));
        var raw_black = load_asset (theme.checker_asset_name (CheckerColor.BLACK));

        cached_board_surface = new Cairo.ImageSurface (Cairo.Format.RGB24, target_px, target_px);
        cached_board_surface.set_device_scale (sf, sf);
        var bcr = new Cairo.Context (cached_board_surface);
        if (raw_board != null) {
            paint_image (bcr, raw_board, 0, 0, side, side);
        } else {
            bcr.set_source_rgb (0.30, 0.18, 0.08);
            bcr.rectangle (0, 0, side, side);
            bcr.fill ();
            var pad = side * 0.035;
            bcr.set_source_rgb (0.83, 0.58, 0.28);
            bcr.rectangle (pad, pad, side - 2 * pad, side - 2 * pad);
            bcr.fill ();
        }

        var diameter = BoardLayout.checker_diameter (side);
        var r = diameter / 2.0;
        var shadow_y = 2.0 * (diameter / 36.0);
        var shadow_r = 1.0 * (diameter / 36.0);
        cached_sprite_pad = Math.ceil (r + shadow_y + shadow_r + 2.0);

        cached_white_static_sprite = build_static_checker_sprite (raw_white, CheckerColor.WHITE, diameter, cached_sprite_pad, sf);
        cached_black_static_sprite = build_static_checker_sprite (raw_black, CheckerColor.BLACK, diameter, cached_sprite_pad, sf);
        cached_white_fly_piece = build_fly_checker_piece (raw_white, CheckerColor.WHITE, diameter, sf);
        cached_black_fly_piece = build_fly_checker_piece (raw_black, CheckerColor.BLACK, diameter, sf);
    }

    private void ensure_static_board_surface (double side) {
        ensure_scaled_assets (side);
        if (cached_board_px <= 0) {
            return;
        }
        if (static_board_surface == null
            || static_board_surface.get_width () != cached_board_px
            || static_board_surface.get_height () != cached_board_px) {
            static_board_surface = new Cairo.ImageSurface (Cairo.Format.RGB24, cached_board_px, cached_board_px);
            static_board_surface.set_device_scale (cached_scale_factor, cached_scale_factor);
            static_board_dirty = true;
        }
        if (!static_board_dirty) {
            return;
        }
        static_board_dirty = false;

        var scr = new Cairo.Context (static_board_surface);
        draw_board_background (scr, side);
        draw_highlights (scr, side);
        draw_static_checkers (scr, side);
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

        // Статичный слой (фон + подсветки + неподвижные фишки) берётся из кэша;
        // поверх рисуются только летящие/перетаскиваемые фишки и стрелки истории.
        ensure_static_board_surface (side);
        if (static_board_surface != null) {
            cr.set_source_surface (static_board_surface, 0, 0);
            cr.paint ();
        } else {
            draw_board_background (cr, side);
            draw_highlights (cr, side);
            draw_static_checkers (cr, side);
        }
        draw_dynamic_checkers (cr, side);
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
        if (cached_board_surface != null) {
            cr.set_source_surface (cached_board_surface, 0, 0);
            cr.paint ();
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

    private Pango.Layout get_cached_pango_layout (Cairo.Context cr) {
        if (cached_pango_layout == null) {
            cached_pango_layout = create_pango_layout ("");
        }
        Pango.cairo_update_layout (cr, cached_pango_layout);
        return cached_pango_layout;
    }

    private void draw_circle_with_number (Cairo.Context cr, double x, double y, double diameter,
                                          double r, double g, double b, double a, int number, bool show_number) {
        cr.set_source_rgba (r, g, b, a);
        cr.arc (x, y, diameter / 2, 0, 2 * Math.PI);
        cr.fill ();
        if (!show_number) {
            return;
        }
        var layout = get_cached_pango_layout (cr);
        if (cached_circle_font == null) {
            cached_circle_font = new Pango.FontDescription ();
            cached_circle_font.set_family ("sans-serif");
            cached_circle_font.set_weight (Pango.Weight.NORMAL);
        }
        cached_circle_font.set_absolute_size (diameter * 0.45 * Pango.SCALE);
        layout.set_font_description (cached_circle_font);
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

    private void draw_static_checkers (Cairo.Context cr, double side) {
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
    }

    private void draw_dynamic_checkers (Cairo.Context cr, double side) {
        var diameter = BoardLayout.checker_diameter (side);

        // Анимированные фишки в полёте рисуются поверх всех статичных стопок (в порядке возрастания stack_index)
        if (active_moves != null && active_moves.size () > 0) {
            uint8[] keys = new uint8[0];
            active_moves.foreach ((cid, mv) => {
                keys += cid;
            });
            for (var i = 0; i < keys.length - 1; i++) {
                for (var j = i + 1; j < keys.length; j++) {
                    var ma = active_moves.lookup (keys[i]);
                    var mb = active_moves.lookup (keys[j]);
                    if (ma != null && mb != null) {
                        if (ma.stack_index > mb.stack_index || (ma.stack_index == mb.stack_index && keys[i] > keys[j])) {
                            var tmp = keys[i];
                            keys[i] = keys[j];
                            keys[j] = tmp;
                        }
                    }
                }
            }
            foreach (var cid in keys) {
                if (dragging && cid == drag_id) {
                    continue;
                }
                var mv = active_moves.lookup (cid);
                var p = lookup_pos (cid);
                if (mv != null && p != null) {
                    var x = p.x * side;
                    var y = p.y * side;
                    draw_checker (cr, x, y, diameter, mv.color, mv.scale, mv.lift);
                }
            }
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
        if (scale == 1.0 && lift == 0.0) {
            var sprite = (color == CheckerColor.WHITE) ? cached_white_static_sprite : cached_black_static_sprite;
            if (sprite != null) {
                cr.set_source_surface (sprite, x - cached_sprite_pad, y - cached_sprite_pad);
                cr.paint ();
                return;
            }
        }

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

        var fly_piece = (color == CheckerColor.WHITE) ? cached_white_fly_piece : cached_black_fly_piece;
        if (fly_piece != null) {
            var fw = fly_piece.get_width ();
            var fh = fly_piece.get_height ();
            cr.save ();
            cr.translate (x - r, y - r);
            cr.scale (eff_diameter / fw, eff_diameter / fh);
            cr.set_source_surface (fly_piece, 0, 0);
            cr.get_source ().set_filter (Cairo.Filter.BILINEAR);
            cr.paint ();
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

    private inline void draw_history_log (Cairo.Context cr, double side) {
        BoardHistoryRenderer.draw_history_log (cr, side, session, log_shown_id, log_anim_t0, log_fading_out, frame_now_sec ());
    }
}
} /* namespace Longbackgammon */
