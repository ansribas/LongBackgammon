/* localization_manager.vala
 *
 * Менеджер локализации интерфейса на основе JSON-словарей.
 * Автоматически обнаруживает все доступные языковые файлы (<код>.json)
 * в каталогах приложения и кеширует их словари в памяти.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class LocalizationManager {
    private static LocalizationManager? _instance = null;

    public static LocalizationManager shared () {
        if (_instance == null) {
            _instance = new LocalizationManager ();
        }
        return _instance;
    }

    private HashTable<string, string> translation_files;
    private HashTable<string, HashTable<string, string>> cache;

    private LocalizationManager () {
        translation_files = new HashTable<string, string> (str_hash, str_equal);
        cache = new HashTable<string, HashTable<string, string>> (str_hash, str_equal);
        scan_and_preload ();
    }

    public Language[] available_languages () {
        var list = new GenericArray<Language> ();

        // Русский и английский первыми для удобства выбора
        if (translation_files.lookup ("ru") != null) {
            list.add (Language.get ("ru"));
        }
        if (translation_files.lookup ("en") != null) {
            list.add (Language.get ("en"));
        }

        // Остальные языки по алфавиту
        var other_codes = new GenericArray<string> ();
        translation_files.foreach ((code, path) => {
            if (code != "ru" && code != "en") {
                other_codes.add (code);
            }
        });

        other_codes.sort ((a, b) => {
            return GLib.strcmp (a, b);
        });

        for (var i = 0; i < other_codes.length; i++) {
            list.add (Language.get (other_codes[i]));
        }

        // Гарантия наличия хотя бы ru и en
        if (list.length == 0) {
            list.add (Language.get ("ru"));
            list.add (Language.get ("en"));
        }

        var result = new Language[list.length];
        for (var i = 0; i < list.length; i++) {
            result[i] = list[i];
        }
        return result;
    }

    public string display_name_for_language (Language lang) {
        var dict = get_dictionary (lang.to_raw ());
        var name = dict.lookup ("languageName");
        if (name != null && name != "") {
            return name;
        }
        if (lang.to_raw () == "ru") return "Русский";
        if (lang.to_raw () == "en") return "English";
        return lang.to_raw ().up ();
    }

    public void scan_and_preload () {
        discover_translation_files ();
        translation_files.foreach ((code, path) => {
            load_dictionary (code);
        });
    }

    public void reload () {
        cache.remove_all ();
        translation_files.remove_all ();
        scan_and_preload ();
    }

    public string string_for_key (string key, Language lang) {
        var dict = get_dictionary (lang.to_raw ());
        var val = dict.lookup (key);
        if (val != null && val != "") {
            return val;
        }

        // Fallback: Английский, затем Русский
        if (lang.to_raw () != "en") {
            var en_dict = get_dictionary ("en");
            var en_val = en_dict.lookup (key);
            if (en_val != null && en_val != "") {
                return en_val;
            }
        }
        if (lang.to_raw () != "ru") {
            var ru_dict = get_dictionary ("ru");
            var ru_val = ru_dict.lookup (key);
            if (ru_val != null && ru_val != "") {
                return ru_val;
            }
        }

        return key;
    }

    public string format_string (string key, Language lang, string[] replacements) {
        var result = string_for_key (key, lang);
        for (var i = 0; i + 1 < replacements.length; i += 2) {
            var placeholder = "{" + replacements[i] + "}";
            result = result.replace (placeholder, replacements[i + 1]);
        }
        return result;
    }

    private HashTable<string, string> get_dictionary (string lang_code) {
        var existing = cache.lookup (lang_code);
        if (existing != null) {
            return existing;
        }
        return load_dictionary (lang_code);
    }

    private HashTable<string, string> load_dictionary (string lang_code) {
        var existing = cache.lookup (lang_code);
        if (existing != null) {
            return existing;
        }

        // 1. Попробуем встроенный GResource
        var res_path = "/org/gnome/longbackgammon/translations/" + lang_code + ".json";
        try {
            var bytes = GLib.resources_lookup_data (res_path, GLib.ResourceLookupFlags.NONE);
            unowned uint8[] data = bytes.get_data ();
            var contents = (string) data;
            if (contents != null && contents != "") {
                var dict = parse_json_dict (contents);
                cache.insert (lang_code, dict);
                return dict;
            }
        } catch (Error e) {
            // Фолбэк на внешние файлы
        }

        var path = translation_files.lookup (lang_code);
        if (path == null) {
            path = StoragePaths.find_asset_path ("translations", lang_code + ".json");
        }

        if (path != null && path != "") {
            var contents = StoragePaths.read_text_file (path);
            if (contents != null && contents != "") {
                var dict = parse_json_dict (contents);
                cache.insert (lang_code, dict);
                return dict;
            }
        }

        var empty_dict = new HashTable<string, string> (str_hash, str_equal);
        cache.insert (lang_code, empty_dict);
        return empty_dict;
    }

    private void discover_translation_files () {
        var dirs = new GenericArray<string> ();

        // 1. Поиск по StoragePaths
        var en_path = StoragePaths.find_asset_path ("translations", "en.json");
        if (en_path != "") {
            dirs.add (GLib.Path.get_dirname (en_path));
        }

        // 2. Дополнительные возможные пути
        dirs.add (GLib.Path.build_filename (StoragePaths.data_dir (), "translations"));
        var cwd = Environment.get_current_dir ();
        dirs.add (GLib.Path.build_filename (cwd, "data", "translations"));
        dirs.add (GLib.Path.build_filename (cwd, "..", "data", "translations"));
        dirs.add ("/usr/local/share/longbackgammon/translations");
        dirs.add ("/usr/share/longbackgammon/translations");
        dirs.add ("/app/share/longbackgammon/translations");

        for (var i = 0; i < dirs.length; i++) {
            var dir_path = dirs[i];
            if (!FileUtils.test (dir_path, FileTest.IS_DIR)) {
                continue;
            }
            try {
                var dir = Dir.open (dir_path, 0);
                string? name = null;
                while ((name = dir.read_name ()) != null) {
                    if (name.has_suffix (".json") && name.length > 5) {
                        var code = name.substring (0, name.length - 5).down ();
                        if (code.length >= 2 && code.length <= 10 && translation_files.lookup (code) == null) {
                            var full_path = GLib.Path.build_filename (dir_path, name);
                            translation_files.insert (code, full_path);
                        }
                    }
                }
            } catch (Error e) {
                // Игнорируем ошибки доступа к отдельным каталогам
            }
        }

        // 3. Гарантированный поиск известных языков через StoragePaths
        string[] known_codes = {
            "az", "de", "en", "es", "fr", "hy", "it", "ka", "kk", "ru", "tg", "tk", "tr", "uz"
        };
        foreach (var code in known_codes) {
            if (translation_files.lookup (code) == null) {
                var p = StoragePaths.find_asset_path ("translations", code + ".json");
                if (p != "") {
                    translation_files.insert (code, p);
                }
            }
        }
    }

    public static HashTable<string, string> parse_json_dict (string contents) {
        var dict = new HashTable<string, string> (str_hash, str_equal);
        int i = 0;
        int len = contents.length;
        while (i < len) {
            // Поиск открывающей кавычки ключа
            while (i < len && contents[i] != '"') i++;
            if (i >= len) break;
            i++;
            var key_sb = new StringBuilder ();
            while (i < len && contents[i] != '"') {
                if (contents[i] == '\\' && i + 1 < len) {
                    i++;
                    char c = contents[i];
                    if (c == 'n') key_sb.append_c ('\n');
                    else if (c == 't') key_sb.append_c ('\t');
                    else if (c == '"') key_sb.append_c ('"');
                    else if (c == '\\') key_sb.append_c ('\\');
                    else key_sb.append_c (c);
                } else {
                    key_sb.append_c (contents[i]);
                }
                i++;
            }
            if (i >= len) break;
            i++;
            string key = key_sb.str;

            // Поиск двоеточия
            while (i < len && contents[i] != ':') i++;
            if (i >= len) break;
            i++;

            // Поиск открывающей кавычки значения
            while (i < len && contents[i] != '"') i++;
            if (i >= len) break;
            i++;

            var val_sb = new StringBuilder ();
            while (i < len && contents[i] != '"') {
                if (contents[i] == '\\' && i + 1 < len) {
                    i++;
                    char c = contents[i];
                    if (c == 'n') val_sb.append_c ('\n');
                    else if (c == 't') val_sb.append_c ('\t');
                    else if (c == '"') val_sb.append_c ('"');
                    else if (c == '\\') val_sb.append_c ('\\');
                    else if (c == 'u' && i + 4 < len) {
                        string hex = contents.substring (i + 1, 4);
                        ulong uc_val = 0;
                        ulong.try_parse (hex, out uc_val, null, 16);
                        val_sb.append_unichar ((unichar) uc_val);
                        i += 4;
                    } else val_sb.append_c (c);
                } else {
                    val_sb.append_c (contents[i]);
                }
                i++;
            }
            if (i >= len) break;
            i++;
            string val = val_sb.str;
            dict.insert (key, val);
        }
        return dict;
    }
}

} /* namespace Longbackgammon */
