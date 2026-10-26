/* storage.vala
 *
 * Общие пути и утилиты хранения данных приложения.
 * Данные хранятся в $XDG_DATA_HOME/longbackgammon (обычно ~/.local/share).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class StoragePaths {
    /** Каталог данных приложения. */
    public static string data_dir () {
        var data_home = Environment.get_variable ("XDG_DATA_HOME");
        if (data_home == null || data_home == "") {
            data_home = Environment.get_home_dir () + "/.local/share";
        }
        var dir_path = GLib.Path.build_filename (data_home, GameConfig.LOG_SUBDIRECTORY_NAME);
        return dir_path;
    }

    /** Гарантирует существование каталога данных. */
    public static void ensure_data_dir () {
        var path = data_dir ();
        if (FileUtils.test (path, FileTest.IS_DIR)) {
            return;
        }
        try {
            var dir = File.new_for_path (path);
            dir.make_directory_with_parents (null);
        } catch (Error e) {
            warning ("Cannot create data dir: %s", e.message);
        }
    }

    /** Полный путь к файлу внутри каталога данных. */
    public static string file_path (string file_name) {
        ensure_data_dir ();
        return GLib.Path.build_filename (data_dir (), file_name);
    }

    /** Простое чтение текстового файла или null. */
    public static string? read_text_file (string path) {
        try {
            string contents;
            size_t length;
            FileUtils.get_contents (path, out contents, out length);
            return contents;
        } catch (Error e) {
            // Файла нет или ошибка чтения — возвращаем null
        }
        return null;
    }

    /** Простая (неатомарная) запись текстового файла. */
    public static void write_text_file (string path, string text) {
        try {
            FileUtils.set_contents (path, text);
        } catch (Error e) {
            warning ("Cannot write file %s: %s", path, e.message);
        }
    }
public static bool read_binary_file (string path, out uint8[] contents) {
        try {
            FileUtils.get_data (path, out contents);
            return true;
        } catch (Error e) {
            contents = new uint8[0];
            return false;
        }
    }

    public static bool write_binary_file (string path, uint8[] contents) {
        try {
            FileUtils.set_data (path, contents);
            return true;
        } catch (Error e) {
            warning ("Cannot write file %s: %s", path, e.message);
            return false;
        }
    }

    /** Находит файл ресурса (звук/изображение) по подкаталогу и имени. */
    public static string find_asset_path (string subdir, string name) {
        // 1) Каталог данных пользователя
        var user = GLib.Path.build_filename (data_dir (), subdir, name);
        if (FileUtils.test (user, FileTest.EXISTS)) {
            return user;
        }

        // 2) Относительно исполняемого файла (через /proc/self/exe)
        try {
            var exe = FileUtils.read_link ("/proc/self/exe");
            var exe_dir = GLib.Path.get_dirname (exe);
            string[] exe_candidates = {
                GLib.Path.build_filename (exe_dir, "..", "..", "share", "longbackgammon", subdir, name),
                GLib.Path.build_filename (exe_dir, "..", "share", "longbackgammon", subdir, name),
                GLib.Path.build_filename (exe_dir, "..", "..", "data", subdir, name)
            };
            for (var i = 0; i < exe_candidates.length; i++) {
                if (FileUtils.test (exe_candidates[i], FileTest.EXISTS)) {
                    return exe_candidates[i];
                }
            }
        } catch (Error e) {
            // /proc может быть недоступен (например, Sandbox)
        }

        // 3) Стандартные префиксы установки (включая /app — Flatpak)
        string[] prefixes = { "/usr/local", "/usr", "/app" };
        for (var i = 0; i < prefixes.length; i++) {
            var p = GLib.Path.build_filename (prefixes[i], "share", "longbackgammon", subdir, name);
            if (FileUtils.test (p, FileTest.EXISTS)) {
                return p;
            }
        }

        // Builder may launch the native build from its build directory, whose
        // working directory is unrelated to the source tree. Use Meson's source
        // directory as a reliable development fallback for uninstalled assets.
        var source_asset = GLib.Path.build_filename (Config.SOURCE_DATA_DIR, subdir, name);
        if (FileUtils.test (source_asset, FileTest.EXISTS)) {
            return source_asset;
        }

        // 4) Относительно текущей директории (запуск из дерева исходников)
        var cwd = Environment.get_current_dir ();
        string[] cwd_candidates = {
            GLib.Path.build_filename (cwd, "data", subdir, name),
            GLib.Path.build_filename (cwd, "..", "data", subdir, name)
        };
        for (var i = 0; i < cwd_candidates.length; i++) {
            if (FileUtils.test (cwd_candidates[i], FileTest.EXISTS)) {
                return cwd_candidates[i];
            }
        }

        return "";
    }
}

/** Тип отложенного колбэка (используется игровой сессией и UI). */
public delegate void DelayedCallback ();

/** Вспомогательные операции с массивами (Vala: нет `+=` для публичных полей). */
public class ArrUtil {
    public static TurnRecord[] append_rec (TurnRecord[] a, TurnRecord v) {
        var r = new TurnRecord[a.length + 1];
        for (var i = 0; i < a.length; i++) { r[i] = a[i]; }
        r[a.length] = v;
        return r;
    }
    public static string[] append_str (string[] a, string v) {
        var r = new string[a.length + 1];
        for (var i = 0; i < a.length; i++) { r[i] = a[i]; }
        r[a.length] = v;
        return r;
    }
    public static LogMove[] append_move (LogMove[] a, LogMove v) {
        var r = new LogMove[a.length + 1];
        for (var i = 0; i < a.length; i++) { r[i] = a[i]; }
        r[a.length] = v;
        return r;
    }
    public static uint8[] append_u8 (uint8[] a, uint8 v) {
        var r = new uint8[a.length + 1];
        for (var i = 0; i < a.length; i++) { r[i] = a[i]; }
        r[a.length] = v;
        return r;
    }
}

} /* namespace Longbackgammon */
