/* window.vala
 *
 * Главное окно приложения: доска с боковыми панелями игроков, кнопки
 * заголовка (статистика, звук, настройки) и модальные оверлеи.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Раскладка основного слоя: [панель чёрных | доска | панель белых].
 * Сторона доски = min(ширина − 280, высота); центральный блок масштабируется пропорционально.
 * Размеры рассчитываются в size_allocate напрямую для предотвращения циклов обратной связи.
 */
public class GameLayout : Gtk.Widget {
    private PlayerPanel black_panel;
    private BoardView board;
    private PlayerPanel white_panel;
    private BoardDiceOverlayLayer dice_layer;
    public int board_side { get; private set; default = 0; }
    public signal void side_changed (int side);

    public GameLayout (PlayerPanel black_panel, BoardView board, PlayerPanel white_panel, GameSession session) {
        this.black_panel = black_panel;
        this.board = board;
        this.white_panel = white_panel;
        black_panel.set_parent (this);
        board.set_parent (this);
        white_panel.set_parent (this);
        dice_layer = new BoardDiceOverlayLayer (session, black_panel, white_panel);
        dice_layer.set_parent (this);
        hexpand = true;
        vexpand = true;
    }

    public override void dispose () {
        black_panel?.unparent ();
        board?.unparent ();
        white_panel?.unparent ();
        dice_layer?.unparent ();
        black_panel = null;
        board = null;
        white_panel = null;
        dice_layer = null;
        base.dispose ();
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        minimum_baseline = -1;
        natural_baseline = -1;
        var pad = GameConfig.WINDOW_PADDING;
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            minimum = GameConfig.CONTROL_PANEL_WIDTH + 200;
            natural = GameConfig.CONTROL_PANEL_WIDTH + 600;
        } else {
            minimum = 200 + pad * 2;
            natural = 600 + pad * 2;
        }
    }

    public override void size_allocate (int width, int height, int baseline) {
        int pw_min = 0;
        int pw_nat = 0;
        black_panel.measure (Gtk.Orientation.HORIZONTAL, -1, out pw_min, out pw_nat, null, null);
        var pw = int.max (GameConfig.CONTROL_PANEL_WIDTH / 2, pw_min);
        var panels_w = pw * 2;
        var pad = GameConfig.WINDOW_PADDING;
        var side = int.max (100, int.min (width - panels_w, height - pad * 2));
        var total_w = side + panels_w;
        var total_h = side + pad * 2;
        var x0 = (width - total_w) / 2;
        var y0 = (height - total_h) / 2;

        allocate_child (black_panel, x0, y0, pw, total_h);
        allocate_child (board, x0 + pw, y0 + pad, side, side);
        allocate_child (white_panel, x0 + pw + side, y0, pw, total_h);
        allocate_child (dice_layer, x0, y0, total_w, total_h);

        if (side != board_side) {
            board_side = side;
            side_changed (side);
        }
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        snapshot_child (black_panel, snapshot);
        snapshot_child (board, snapshot);
        snapshot_child (white_panel, snapshot);
        snapshot_child (dice_layer, snapshot);
    }

    private static void allocate_child (Gtk.Widget w, int x, int y, int cw, int ch) {
        var t = new Gsk.Transform ();
        Graphene.Point p = { x, y };
        t = t.translate (p);
        w.allocate (cw, ch, -1, t);
    }
}

/** Кнопка заголовка окна (TitleBarButton): квадрат 22×22 со скруглением 5. */
public class TitleBarButton : Gtk.Button {
    private SFIcon icon;

    public TitleBarButton (string glyph, string tooltip) {
        UiKit.ensure_css ();
        add_css_class ("lb-tb-btn");
        icon = new SFIcon (glyph, 12);
        set_child (icon);
        tooltip_text = tooltip;
        valign = Gtk.Align.CENTER;
        focus_on_click = false;
    }

    public void set_active_state (bool active) {
        if (active) {
            add_css_class ("active");
        } else {
            remove_css_class ("active");
        }
    }

    public void set_glyph (string g) {
        icon.set_glyph (g);
    }
}

public class Window : Adw.ApplicationWindow {
    public GameSession session { get; private set; }

    private BoardView board_view;
    private PlayerPanel black_panel_view;
    private PlayerPanel white_panel_view;
    private GameLayout layout;
    private Gtk.Overlay overlay;
    private Gtk.Box backdrop;
    private Gtk.Box dim;
    private bool dim_target_visible = false;
    private Adw.SpringAnimation? dim_animation = null;
    private LogTooltipView tooltip_view;

    private TitleBarButton stats_btn;
    private TitleBarButton sound_btn;
    private TitleBarButton settings_btn;
    private Gtk.MenuButton menu_btn;

    // Состояние оверлеев (как @State в ContentView)
    private bool is_settings_presented = false;
    private bool is_rules_presented = false;
    private bool is_stats_presented = false;
    private bool is_new_game_presented = false;
    private bool can_close_new_game = true;
    private bool show_confirm_new_game = false;
    private bool show_restore_game = false;
    private bool last_game_over_result = false;

    private PopupHost? main_popup = null;
    private string main_kind = "";
    private PopupHost? modal_popup = null;
    private string modal_kind = "";

    public Window (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        UiKit.ensure_css ();
        PanelStyle.ensure_css ();
        title = Localization.window_title ();
        icon_name = "io.github.ansribas.LongBackgammon";
        set_size_request (GameConfig.MIN_WINDOW_WIDTH, GameConfig.MIN_WINDOW_HEIGHT);
        apply_default_size ();

        session = new GameSession ();
        build_ui ();

        session.changed.connect (on_session_changed);
        SettingsStore.shared ().changed.connect (on_settings_changed);

        // Сохраняем незавершённую игру при закрытии окна (saveOnClose)
        close_request.connect (() => {
            session.save_on_close ();
            return false;
        });

        // Стартовый сценарий (ContentView.onAppear)
        Idle.add (() => {
            can_close_new_game = false;
            close_all_overlays ();
            if (SavedGameStore.shared ().has_saved_game) {
                present_restore ();
            } else {
                is_new_game_presented = true;
            }
            sync_overlays ();
            return false;
        });
    }

    /** Стартовый размер: высота = 4/5 высоты экрана, ширина = высота доски + панели. */
    private void apply_default_size () {
        var h = 720;
        var display = Gdk.Display.get_default ();
        if (display != null) {
            var monitors = display.get_monitors ();
            if (monitors.get_n_items () > 0) {
                var mon = (Gdk.Monitor) monitors.get_item (0);
                var geo = mon.get_geometry ();
                h = (int) (geo.height * 0.8);
            }
        }
        h = int.max (h, GameConfig.MIN_WINDOW_HEIGHT);
        var header_h = 47;
        var w = (h - header_h) + GameConfig.CONTROL_PANEL_WIDTH;
        default_width = int.max (w, GameConfig.MIN_WINDOW_WIDTH);
        default_height = h;
    }

    private void build_ui () {
        var header = new Adw.HeaderBar ();

        // Главное меню приложения
        menu_btn = new Gtk.MenuButton ();
        menu_btn.icon_name = "open-menu-symbolic";
        menu_btn.primary = true;
        menu_btn.menu_model = build_menu ();
        header.pack_start (menu_btn);

        // Панель действий справа: Настройки, Звук, Статистика
        settings_btn = new TitleBarButton ("gearshape.fill", Localization.settings_menu ());
        settings_btn.clicked.connect (show_settings);
        header.pack_end (settings_btn);

        sound_btn = new TitleBarButton ("speaker.wave.2.fill", "");
        sound_btn.clicked.connect (() => {
            var s = SettingsStore.shared ();
            s.set_is_sound_enabled (!s.is_sound_enabled);
        });
        header.pack_end (sound_btn);

        stats_btn = new TitleBarButton ("chart.bar.fill", Localization.stats_menu ());
        stats_btn.clicked.connect (show_stats);
        header.pack_end (stats_btn);
        update_sound_button ();

        black_panel_view = new PlayerPanel (session, CheckerColor.BLACK);
        board_view = new BoardView (session);
        board_view.new_game_requested.connect (request_new_game);
        white_panel_view = new PlayerPanel (session, CheckerColor.WHITE);
        layout = new GameLayout (black_panel_view, board_view, white_panel_view, session);
        layout.side_changed.connect ((side) => {
            if (main_popup != null) {
                var pv = main_popup.content as PopupView;
                if (pv != null) {
                    pv.update_board_side (side);
                }
            }
        });

        // Клик по фону окна вокруг доски — сброс выбора фишки
        var bg_click = new Gtk.GestureClick ();
        bg_click.pressed.connect ((n, x, y) => {
            var picked = layout.pick (x, y, Gtk.PickFlags.DEFAULT);
            if (picked == layout) {
                session.select_point_none ();
            }
        });
        layout.add_controller (bg_click);

        overlay = new Gtk.Overlay ();
        overlay.set_child (layout);

        // Прозрачный слой: клик мимо окна закрывает оверлеи
        backdrop = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        backdrop.hexpand = true;
        backdrop.vexpand = true;
        backdrop.can_target = false;
        var bclick = new Gtk.GestureClick ();
        bclick.pressed.connect (() => { on_backdrop_clicked (); });
        backdrop.add_controller (bclick);
        overlay.add_overlay (backdrop);
        overlay.set_measure_overlay (backdrop, false);

        // Полупрозрачный слой диалогов восстановления/подтверждения: клик мимо — мигание
        dim = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        dim.add_css_class ("lb-dim");
        dim.hexpand = true;
        dim.vexpand = true;
        dim.opacity = 0.0;
        dim.visible = false;
        var dclick = new Gtk.GestureClick ();
        dclick.pressed.connect (() => { flash_modal (); });
        dim.add_controller (dclick);
        overlay.add_overlay (dim);
        overlay.set_measure_overlay (dim, false);

        // Глобальный слой подсказок лога (не перехватывает мышь)
        tooltip_view = new LogTooltipView (session);
        tooltip_view.can_target = false;
        overlay.add_overlay (tooltip_view);
        overlay.set_measure_overlay (tooltip_view, false);
        LogTooltipState.shared ().container = overlay;

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (header);
        toolbar_view.set_content (overlay);
        set_content (toolbar_view);
    }

    private GLib.Menu build_menu () {
        var menu = new GLib.Menu ();
        var s1 = new GLib.Menu ();
        s1.append (Localization.button_new_game (), "app.new-game");
        menu.append_section (null, s1);
        var s2 = new GLib.Menu ();
        s2.append (Localization.settings_menu (), "app.settings");
        s2.append (Localization.stats_menu (), "app.stats");
        menu.append_section (null, s2);
        var s3 = new GLib.Menu ();
        s3.append (Localization.menu_undo (), "app.undo");
        s3.append (Localization.menu_fullscreen (), "app.fullscreen");
        menu.append_section (null, s3);
        var s4 = new GLib.Menu ();
        s4.append (Localization.rules_menu_item (), "app.rules");
        s4.append (Localization.app_menu_about (), "app.about");
        s4.append (Localization.menu_quit (), "app.quit");
        menu.append_section (null, s4);
        return menu;
    }

    private void update_sound_button () {
        var on = SettingsStore.shared ().is_sound_enabled;
        sound_btn.set_glyph (on ? "speaker.wave.2.fill" : "speaker.slash.fill");
        sound_btn.tooltip_text = on ? Localization.sound_mute_tooltip () : Localization.sound_unmute_tooltip ();
        sound_btn.set_active_state (!on);
    }

    private Language menu_language = Language.RUSSIAN;
    private bool menu_language_set = false;

    private void on_settings_changed () {
        update_sound_button ();
        var lang = SettingsStore.shared ().language;
        if (!menu_language_set || lang != menu_language) {
            menu_language_set = true;
            menu_language = lang;
            title = Localization.window_title ();
            settings_btn.tooltip_text = Localization.settings_menu ();
            stats_btn.tooltip_text = Localization.stats_menu ();
            menu_btn.menu_model = build_menu ();
        }
    }

    private void on_session_changed () {
        var app = application as Application;
        if (app != null) {
            app.set_undo_enabled (session.can_undo);
        }
        // Экран победы (onChange(of: showingGameOverResult))
        if (session.showing_game_over_result != last_game_over_result) {
            last_game_over_result = session.showing_game_over_result;
            if (last_game_over_result) {
                is_settings_presented = false;
                is_rules_presented = false;
                is_stats_presented = false;
                is_new_game_presented = false;
            }
            sync_overlays ();
        }
    }

    // MARK: - Оверлеи

    private void close_all_overlays () {
        is_settings_presented = false;
        is_rules_presented = false;
        is_stats_presented = false;
        is_new_game_presented = false;
        if (session.showing_game_over_result) {
            session.set_showing_game_over_result (false);
            last_game_over_result = false;
        }
    }

    private string desired_main_kind () {
        if (is_settings_presented) {
            return "settings";
        }
        if (is_rules_presented) {
            return "rules";
        }
        if (session.showing_game_over_result) {
            return "gameover";
        }
        if (is_stats_presented) {
            return "stats";
        }
        if (is_new_game_presented) {
            return "newgame";
        }
        return "";
    }

    private bool is_overlay_presented () {
        return is_settings_presented || is_rules_presented || session.showing_game_over_result
               || is_new_game_presented || is_stats_presented || show_confirm_new_game;
    }

    private void sync_overlays () {
        var kind = desired_main_kind ();
        if (kind != main_kind) {
            dismiss_popup (main_popup);
            main_popup = null;
            main_kind = kind;
            if (kind != "") {
                var w = create_main_view (kind);
                var pv = w as PopupView;
                if (pv != null) {
                    pv.update_board_side (layout.board_side > 0 ? layout.board_side : 600);
                }
                main_popup = show_popup (w, backdrop);
            }
        }
        backdrop.can_target = kind != "";

        var modal = show_restore_game ? "restore" : (show_confirm_new_game ? "confirm" : "");
        if (modal != modal_kind) {
            dismiss_popup (modal_popup);
            modal_popup = null;
            modal_kind = modal;
            if (modal == "confirm") {
                var v = new ConfirmNewGameView (session);
                v.confirmed.connect (() => {
                    show_confirm_new_game = false;
                    can_close_new_game = true;
                    is_new_game_presented = true;
                    session.force_new_game ();
                    sync_overlays ();
                });
                v.cancelled.connect (() => {
                    show_confirm_new_game = false;
                    sync_overlays ();
                });
                modal_popup = show_popup (v, dim);
            }
        }
        set_modal_dim_visible (modal != "");

        board_view.overlay_presented = is_overlay_presented ();
        settings_btn.set_active_state (is_settings_presented);
        stats_btn.set_active_state (is_stats_presented);
    }

    /** Добавляет всплывающее окно поверх указанного слоя и запускает анимацию появления. */
    private PopupHost show_popup (Gtk.Widget content, Gtk.Widget above) {
        var host = new PopupHost (content);
        overlay.add_overlay (host);
        overlay.set_measure_overlay (host, false);
        // Поверх подложки, но под слоем подсказок
        host.insert_after (overlay, above);
        tooltip_view.insert_before (overlay, null);
        host.animate_in ();
        return host;
    }

    private void dismiss_popup (PopupHost? host) {
        if (host == null) {
            return;
        }
        host.hidden.connect (() => {
            overlay.remove_overlay (host);
        });
        host.animate_out ();
    }

    /** Плавная анимация появления фонового затемнения (scrim) для модальных окон. */
    private void set_modal_dim_visible (bool visible) {
        if (visible == dim_target_visible) {
            return;
        }
        dim_target_visible = visible;
        if (visible) {
            dim.visible = true;
            dim.can_target = true;
        } else {
            dim.can_target = false;
        }
        if (dim_animation != null) {
            dim_animation.pause ();
        }
        var from = dim.opacity / 0.15;
        var to = visible ? 1.0 : 0.0;
        var target = new Adw.CallbackAnimationTarget ((value) => {
            dim.opacity = double.max (0.0, double.min (1.0, value * 0.15));
        });
        var stiffness = Math.pow (2 * Math.PI / 0.55, 2);
        dim_animation = new Adw.SpringAnimation (dim, from, to,
            new Adw.SpringParams (0.825, 1.0, stiffness), target);
        dim_animation.epsilon = 0.002;
        dim_animation.done.connect (() => {
            if (!dim_target_visible) {
                dim.opacity = 0.0;
                dim.visible = false;
            }
        });
        dim_animation.play ();
    }

    private Gtk.Widget create_main_view (string kind) {
        switch (kind) {
        case "settings":
            var v = new SettingsView ();
            v.close_requested.connect (() => {
                is_settings_presented = false;
                sync_overlays ();
            });
            return v;
        case "rules":
            var v = new RulesView ();
            v.close_requested.connect (() => {
                is_rules_presented = false;
                sync_overlays ();
            });
            return v;
        case "gameover":
            var v = new GameOverView (session);
            v.new_game_requested.connect (() => {
                session.set_showing_game_over_result (false);
                last_game_over_result = false;
                can_close_new_game = true;
                is_new_game_presented = true;
                sync_overlays ();
            });
            v.close_requested.connect (() => {
                session.set_showing_game_over_result (false);
                last_game_over_result = false;
                sync_overlays ();
            });
            return v;
        case "stats":
            var v = new StatisticsView ();
            v.close_requested.connect (() => {
                is_stats_presented = false;
                sync_overlays ();
            });
            return v;
        default:
            var v = new NewGameView (can_close_new_game);
            v.start_requested.connect (() => {
                is_new_game_presented = false;
                sync_overlays ();
                session.new_game ();
            });
            v.close_requested.connect (() => {
                is_new_game_presented = false;
                sync_overlays ();
            });
            return v;
        }
    }

    /** Клик мимо всплывающего окна (прозрачная подложка ContentView). */
    private void on_backdrop_clicked () {
        is_settings_presented = false;
        is_rules_presented = false;
        is_stats_presented = false;
        if (session.showing_game_over_result) {
            session.set_showing_game_over_result (false);
            last_game_over_result = false;
        }
        if (can_close_new_game) {
            is_new_game_presented = false;
        }
        sync_overlays ();
    }

    private void flash_modal () {
        if (modal_popup == null) {
            return;
        }
        var r = modal_popup.content as RestoreGameView;
        if (r != null) {
            r.flash ();
        }
        var c = modal_popup.content as ConfirmNewGameView;
        if (c != null) {
            c.flash ();
        }
    }

    /** Блокирующий диалог открыт — вместо действия мигает рамкой. */
    private bool modal_blocks () {
        if (show_restore_game || show_confirm_new_game) {
            flash_modal ();
            return true;
        }
        return false;
    }

    private void present_restore () {
        var data = SavedGameStore.shared ().load ();
        if (data == null) {
            is_new_game_presented = true;
            return;
        }
        var name = data.current_player == CheckerColor.WHITE ? data.white_player_name : data.black_player_name;
        var v = new RestoreGameView (name);
        v.continue_requested.connect (() => {
            var d = SavedGameStore.shared ().load ();
            if (d != null) {
                session.restore_from_store (d);
            }
            show_restore_game = false;
            SavedGameStore.shared ().clear ();
            sync_overlays ();
        });
        v.forfeit_requested.connect (() => {
            forfeit_saved_game ();
            show_restore_game = false;
            can_close_new_game = true;
            is_new_game_presented = true;
            sync_overlays ();
        });
        show_restore_game = true;
        modal_kind = "restore";
        modal_popup = show_popup (v, dim);
        set_modal_dim_visible (true);
    }

    /** «Сдаться»: поражение текущему игроку сохранённой партии, победа сопернику. */
    private void forfeit_saved_game () {
        var data = SavedGameStore.shared ().load ();
        if (data != null) {
            var loser = data.current_player;
            var winner = loser.opposite ();
            var loser_name = loser == CheckerColor.WHITE ? data.white_player_name : data.black_player_name;
            var winner_name = winner == CheckerColor.WHITE ? data.white_player_name : data.black_player_name;
            if (!(loser == CheckerColor.BLACK && data.is_black_computer)) {
                StatsStore.shared ().record_loss (loser_name);
            }
            if (!(winner == CheckerColor.BLACK && data.is_black_computer)) {
                StatsStore.shared ().record_victory (winner_name, VictoryType.OIN);
            }
        }
        SavedGameStore.shared ().clear ();
        session.force_new_game ();
    }

    // MARK: - Команды (меню, кнопки заголовка, горячие клавиши)

    public void show_settings () {
        if (modal_blocks ()) {
            return;
        }
        if (is_settings_presented) {
            is_settings_presented = false;
        } else {
            close_all_overlays ();
            is_settings_presented = true;
        }
        sync_overlays ();
    }

    public void show_rules () {
        if (modal_blocks ()) {
            return;
        }
        close_all_overlays ();
        is_rules_presented = true;
        sync_overlays ();
    }

    public void show_stats () {
        if (modal_blocks ()) {
            return;
        }
        if (is_stats_presented) {
            is_stats_presented = false;
        } else {
            close_all_overlays ();
            is_stats_presented = true;
        }
        sync_overlays ();
    }

    public void request_new_game () {
        if (modal_blocks ()) {
            return;
        }
        // Подтверждение, если игра начата и не окончена (включая розыгрыш первого хода)
        if (session.is_game_started && !session.is_game_over) {
            close_all_overlays ();
            show_confirm_new_game = true;
        } else {
            can_close_new_game = true;
            close_all_overlays ();
            is_new_game_presented = true;
        }
        sync_overlays ();
    }

    public void undo () {
        if (session.can_undo) {
            session.undo_move ();
        }
    }

    public void toggle_fullscreen () {
        if (fullscreened) {
            unfullscreen ();
        } else {
            fullscreen ();
        }
    }
}

} /* namespace Longbackgammon */
