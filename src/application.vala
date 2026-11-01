/* application.vala
 *
 * Приложение Long Backgammon (Adw.Application).
 * Регистрирует глобальные действия (GAction) и сочетания клавиш:
 * новая игра, настройки, статистика, отмена хода, полноэкранный режим,
 * правила, о программе и выход.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class Application : Adw.Application {
    private SimpleAction? undo_action = null;

    public Application () {
        Object (
            application_id: "io.github.ansribas.LongBackgammon",
            flags: ApplicationFlags.DEFAULT_FLAGS,
            resource_base_path: "/io/github/ansribas/LongBackgammon"
        );
    }

    construct {
        ActionEntry[] action_entries = {
            { "new-game", this.on_new_game_action },
            { "settings", this.on_settings_action },
            { "stats", this.on_stats_action },
            { "rules", this.on_rules_action },
            { "shortcuts", this.on_shortcuts_action },
            { "undo", this.on_undo_action },
            { "fullscreen", this.on_fullscreen_action },
            { "about", this.on_about_action },
            { "quit", this.on_quit_action }
        };
        add_action_entries (action_entries, this);
        undo_action = lookup_action ("undo") as SimpleAction;
        undo_action.set_enabled (false);

        // Назначение стандартных сочетаний клавиш (Ctrl+N, Ctrl+, Ctrl+Alt+S, Ctrl+Z, F11, F1, Ctrl+Q)
        set_accels_for_action ("app.quit", { "<control>q" });
        set_accels_for_action ("app.new-game", { "<control>n" });
        set_accels_for_action ("app.undo", { "<control>z" });
        set_accels_for_action ("app.settings", { "<control>comma" });
        set_accels_for_action ("app.stats", { "<control><alt>s" });
        set_accels_for_action ("app.fullscreen", { "F11", "<control><super>f" });
        set_accels_for_action ("app.shortcuts", { "<control>question" });
        set_accels_for_action ("app.rules", { "F1" });
    }

    public override void startup () {
        base.startup ();

        var display = Gdk.Display.get_default ();
        if (display != null) {
            var icon_theme = Gtk.IconTheme.get_for_display (display);
            var asset_icons = StoragePaths.find_asset_path ("icons", "");
            if (asset_icons != "") {
                icon_theme.add_search_path (asset_icons);
            }
            icon_theme.add_search_path (GLib.Path.build_filename (StoragePaths.data_dir (), "icons"));
            icon_theme.add_search_path (GLib.Path.build_filename (Environment.get_current_dir (), "data", "icons"));
        }

        Gtk.Window.set_default_icon_name ("io.github.ansribas.LongBackgammon");
    }

    public override void activate () {
        base.activate ();
        var win = this.active_window ?? new Longbackgammon.Window (this);
        win.present ();
    }

    /** Доступность «Отменить ход» (canUndoStatusChanged). */
    public void set_undo_enabled (bool enabled) {
        if (undo_action != null) {
            undo_action.set_enabled (enabled);
        }
    }

    private Window? current_window () {
        return this.active_window as Window;
    }

    private void on_new_game_action () {
        current_window ()?.request_new_game ();
    }

    private void on_settings_action () {
        current_window ()?.show_settings ();
    }

    private void on_stats_action () {
        current_window ()?.show_stats ();
    }

    private void on_rules_action () {
        current_window ()?.show_rules ();
    }

    private void on_undo_action () {
        current_window ()?.undo ();
    }

    private void on_fullscreen_action () {
        current_window ()?.toggle_fullscreen ();
    }

    private void on_quit_action () {
        // Сохраняем игру перед выходом (applicationWillTerminate)
        var win = current_window ();
        if (win != null) {
            win.session.save_on_close ();
        }
        quit ();
    }

    private void on_shortcuts_action () {
        var win = current_window ();
        var lang_code = SettingsStore.shared ().language.to_raw ();
        GLib.Environment.set_variable ("LANGUAGE", lang_code, true);
        GLib.Intl.setlocale (GLib.LocaleCategory.MESSAGES, "");

        var builder = new Gtk.Builder.from_resource ("/io/github/ansribas/LongBackgammon/shortcuts-dialog.ui");
        var dialog = builder.get_object ("shortcuts_dialog") as Gtk.ShortcutsWindow;
        if (dialog != null) {
            var grp_game = builder.get_object ("grp_game") as Gtk.ShortcutsGroup;
            if (grp_game != null) {
                grp_game.title = Localization.shortcuts_section_game ();
            }
            var grp_general = builder.get_object ("grp_general") as Gtk.ShortcutsGroup;
            if (grp_general != null) {
                grp_general.title = Localization.shortcuts_section_general ();
            }

            var sc_new_game = builder.get_object ("sc_new_game") as Gtk.ShortcutsShortcut;
            if (sc_new_game != null) {
                sc_new_game.title = Localization.button_new_game ();
            }
            var sc_undo = builder.get_object ("sc_undo") as Gtk.ShortcutsShortcut;
            if (sc_undo != null) {
                sc_undo.title = Localization.menu_undo ();
            }
            var sc_stats = builder.get_object ("sc_stats") as Gtk.ShortcutsShortcut;
            if (sc_stats != null) {
                sc_stats.title = Localization.stats_menu ();
            }
            var sc_rules = builder.get_object ("sc_rules") as Gtk.ShortcutsShortcut;
            if (sc_rules != null) {
                sc_rules.title = Localization.rules_menu_item ();
            }
            var sc_settings = builder.get_object ("sc_settings") as Gtk.ShortcutsShortcut;
            if (sc_settings != null) {
                sc_settings.title = Localization.settings_menu ();
            }
            var sc_shortcuts = builder.get_object ("sc_shortcuts") as Gtk.ShortcutsShortcut;
            if (sc_shortcuts != null) {
                sc_shortcuts.title = Localization.menu_shortcuts ();
            }
            var sc_fullscreen = builder.get_object ("sc_fullscreen") as Gtk.ShortcutsShortcut;
            if (sc_fullscreen != null) {
                sc_fullscreen.title = Localization.menu_fullscreen ();
            }
            var sc_quit = builder.get_object ("sc_quit") as Gtk.ShortcutsShortcut;
            if (sc_quit != null) {
                sc_quit.title = Localization.menu_quit ();
            }

            dialog.set_transient_for (win);
            dialog.present ();
        }
    }

    private void on_about_action () {
        var win = current_window ();
        var lang_code = SettingsStore.shared ().language.to_raw ();
        GLib.Environment.set_variable ("LANGUAGE", lang_code, true);
        GLib.Intl.setlocale (GLib.LocaleCategory.MESSAGES, "");

        string[] developers = { "Aleksey Svetlov" };
        var credits = _("translator-credits");
        var about = new Adw.AboutDialog () {
            application_name = Localization.window_title (),
            application_icon = "io.github.ansribas.LongBackgammon",
            developer_name = "Aleksey Svetlov",
            translator_credits = (credits != "translator-credits") ? credits : null,
            version = Config.PACKAGE_VERSION,
            developers = developers,
            copyright = "© 2026 Aleksey Svetlov",
            license_type = Gtk.License.GPL_3_0,
            website = "https://github.com/ansribas/LongBackgammon",
            issue_url = "https://github.com/ansribas/LongBackgammon/issues",
        };
        about.add_link (Localization.donate_link (), "https://ko-fi.com/ansribas");
        about.present (win);
    }
}

} /* namespace Longbackgammon */