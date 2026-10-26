/* game_log_store.vala
 *
 * Архив завершённых партий. Хранение — INI (GLib.KeyFile).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Одна запись в архиве завершённых партий. */
public class GameLogEntry : Object {
    public string id;
    public string date;
    public string player_name;
    public string? player_name2;
    public string log_text;

    public GameLogEntry (string id, string date, string player_name, string? player_name2, string log_text) {
        this.id = id;
        this.date = date;
        this.player_name = player_name;
        this.player_name2 = player_name2;
        this.log_text = log_text;
    }
}

/** Хранилище логов завершённых партий (Singleton). */
public class GameLogStore : Object {
    private static GameLogStore? _shared = null;

    public static GameLogStore shared () {
        if (_shared == null) {
            _shared = new GameLogStore ();
        }
        return _shared;
    }

    public signal void changed ();

    private GameLogEntry[] entries;

    public GameLogStore () {
        entries = new GameLogEntry[0];
        load_from_disk ();
    }

    /** Добавляет новую запись и обрезает до максимума. */
    public void add_entry (string player_name, string? player_name2, string log_text) {
        var now = new DateTime.now_utc ();
        var entry = new GameLogEntry (
            Uuid.string_random (),
            now.format_iso8601 (),
            player_name,
            player_name2,
            log_text);

        var new_entries = new GameLogEntry[entries.length + 1];
        new_entries[0] = entry;
        for (var i = 0; i < entries.length; i++) {
            new_entries[i + 1] = entries[i];
        }
        entries = new_entries;

        if (entries.length > GameConfig.LOG_MAX_ENTRIES) {
            var trimmed = new GameLogEntry[GameConfig.LOG_MAX_ENTRIES];
            for (var i = 0; i < trimmed.length; i++) {
                trimmed[i] = entries[i];
            }
            entries = trimmed;
        }
        save_to_disk ();
        changed ();
    }

    public GameLogEntry[] all_entries () {
        return entries;
    }

    public void clear_all () {
        entries = new GameLogEntry[0];
        save_to_disk ();
        changed ();
    }

    // MARK: - Хранение

    private static string escape (string s) {
        return s.replace ("\\", "\\\\").replace ("\n", "\\n");
    }

    private static string unescape (string s) {
        return s.replace ("\\n", "\n").replace ("\\\\", "\\");
    }

    private void save_to_disk () {
        var keyfile = new KeyFile ();
        keyfile.set_integer ("logs", "count", entries.length);
        for (var i = 0; i < entries.length; i++) {
            var prefix = "e%d".printf (i);
            var e = entries[i];
            keyfile.set_string (prefix, "id", e.id);
            keyfile.set_string (prefix, "date", e.date);
            keyfile.set_string (prefix, "p1", escape (e.player_name));
            keyfile.set_string (prefix, "p2", escape (e.player_name2 ?? ""));
            keyfile.set_string (prefix, "text", escape (e.log_text));
        }
        StoragePaths.write_text_file (
            StoragePaths.file_path (GameConfig.LOG_FILE_NAME),
            keyfile.to_data ());
    }

    private void load_from_disk () {
        var text = StoragePaths.read_text_file (StoragePaths.file_path (GameConfig.LOG_FILE_NAME));
        if (text == null || text == "") {
            return;
        }
        var keyfile = new KeyFile ();
        try {
            if (!keyfile.load_from_data (text, text.length, GLib.KeyFileFlags.NONE)) {
                return;
            }
            var n = keyfile.get_integer ("logs", "count");
            var loaded = new GameLogEntry[0];
            for (var i = 0; i < n; i++) {
                var prefix = "e%d".printf (i);
                if (!keyfile.has_group (prefix)) {
                    continue;
                }
                var p2 = keyfile.get_string (prefix, "p2");
                loaded += new GameLogEntry (
                    keyfile.get_string (prefix, "id"),
                    keyfile.get_string (prefix, "date"),
                    unescape (keyfile.get_string (prefix, "p1")),
                    p2 == "" ? null : unescape (p2),
                    unescape (keyfile.get_string (prefix, "text")));
            }
            entries = loaded;
        } catch (Error e) {
            warning ("Log load error: %s", e.message);
        }
    }
}

} /* namespace Longbackgammon */