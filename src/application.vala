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
            application_id: "org.gnome.longbackgammon",
            flags: ApplicationFlags.DEFAULT_FLAGS,
            resource_base_path: "/org/gnome/longbackgammon"
        );
    }

    construct {
        ActionEntry[] action_entries = {
            { "new-game", this.on_new_game_action },
            { "settings", this.on_settings_action },
            { "stats", this.on_stats_action },
            { "rules", this.on_rules_action },
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
        set_accels_for_action ("app.rules", { "<control>question", "F1" });
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

        Gtk.Window.set_default_icon_name ("org.gnome.longbackgammon");

        ensure_user_desktop_integration ();
    }

    private void ensure_user_desktop_integration () {
        try {
            var home = Environment.get_home_dir ();
            var icon_dir = GLib.Path.build_filename (home, ".local", "share", "icons", "hicolor", "scalable", "apps");
            var apps_dir = GLib.Path.build_filename (home, ".local", "share", "applications");
            var bin_dir = GLib.Path.build_filename (home, ".local", "bin");
            DirUtils.create_with_parents (icon_dir, 0755);
            DirUtils.create_with_parents (apps_dir, 0755);
            DirUtils.create_with_parents (bin_dir, 0755);

            try {
                var exe = FileUtils.read_link ("/proc/self/exe");
                var bin_target = GLib.Path.build_filename (bin_dir, "longbackgammon");
                if (exe != "" && !FileUtils.test (bin_target, FileTest.EXISTS)) {
                    File.new_for_path (exe).make_symbolic_link (bin_target);
                }
            } catch (Error e) {
            }

            var hicolor_dir = GLib.Path.build_filename (home, ".local", "share", "icons", "hicolor");
            var index_theme = GLib.Path.build_filename (hicolor_dir, "index.theme");
            if (!FileUtils.test (index_theme, FileTest.EXISTS)) {
                var sys_index = "/usr/share/icons/hicolor/index.theme";
                if (FileUtils.test (sys_index, FileTest.EXISTS)) {
                    File.new_for_path (sys_index).copy (File.new_for_path (index_theme), FileCopyFlags.NONE);
                }
            }

            var target_icon = GLib.Path.build_filename (icon_dir, "org.gnome.longbackgammon.svg");
            var target_desktop = GLib.Path.build_filename (apps_dir, "org.gnome.longbackgammon.desktop");

            var src_icon = StoragePaths.find_asset_path ("icons", "hicolor/scalable/apps/org.gnome.longbackgammon.svg");
            if (src_icon == "") {
                src_icon = GLib.Path.build_filename (Environment.get_current_dir (), "data", "icons", "hicolor", "scalable", "apps", "org.gnome.longbackgammon.svg");
            }
            if (FileUtils.test (src_icon, FileTest.EXISTS) && !FileUtils.test (target_icon, FileTest.EXISTS)) {
                var src_file = File.new_for_path (src_icon);
                var dst_file = File.new_for_path (target_icon);
                src_file.copy (dst_file, FileCopyFlags.OVERWRITE);
            }

            if (!FileUtils.test (target_desktop, FileTest.EXISTS)) {
                var desktop_content = "[Desktop Entry]\n" +
                                      "Name=LongBackgammon\n" +
                                      "Name[ru]=Длинные нарды\n" +
                                      "Comment=Classic Long Backgammon Board Game\n" +
                                      "Comment[ru]=Классическая настольная игра Длинные нарды\n" +
                                      "Exec=longbackgammon\n" +
                                      "Icon=org.gnome.longbackgammon\n" +
                                      "Terminal=false\n" +
                                      "Type=Application\n" +
                                      "Categories=Game;BoardGame;\n" +
                                      "StartupNotify=true\n" +
                                      "StartupWMClass=org.gnome.longbackgammon\n";
                FileUtils.set_contents (target_desktop, desktop_content);
            }
        } catch (Error e) {
            // Игнорируем ошибки при фоновом создании
        }
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

    private void on_about_action () {
        var win = current_window ();
        string[] developers = { "Алексей" };
        var about = new Adw.AboutDialog () {
            application_name = Localization.window_title (),
            application_icon = "org.gnome.longbackgammon",
            developer_name = "Алексей",
            translator_credits = _("translator-credits"),
            version = "0.1.0",
            developers = developers,
            copyright = "© 2026 Алексей",
        };
        about.present (win);
    }
}

} /* namespace Longbackgammon */