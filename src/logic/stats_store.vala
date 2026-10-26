/* stats_store.vala
 *
 * Модель и хранилище статистики игроков.
 * Хранение — INI-файл (GLib.KeyFile), без внешних зависимостей.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Типы побед в Длинных нардах. */
public enum VictoryType {
    OIN,
    MARS,
    HOME_MARS
}

/** Статистика конкретного игрока. */
public class PlayerStats : Object {
    public int games_played = 0;
    public int losses = 0;
    public int oin_victories = 0;
    public int mars_victories = 0;
    public int home_mars_victories = 0;

    public int total_points {
        get { return (oin_victories * 1) + (mars_victories * 2) + (home_mars_victories * 3) - losses; }
    }

    public double win_rate {
        get {
            var total_wins = oin_victories + mars_victories + home_mars_victories;
            if (games_played <= 0) {
                return 0.0;
            }
            return ((double) total_wins / (double) games_played) * 100.0;
        }
    }
}

/** Глобальное хранилище статистики (Singleton). */
public class StatsStore : Object {
    private static StatsStore? _shared = null;

    public static StatsStore shared () {
        if (_shared == null) {
            _shared = new StatsStore ();
        }
        return _shared;
    }

    public signal void changed ();

    public HashTable<string, PlayerStats> player_stats;

    public StatsStore () {
        player_stats = new HashTable<string, PlayerStats> (str_hash, str_equal);
        load ();
    }

    /** Фиксация победы игрока. */
    public void record_victory (string player_name, VictoryType type) {
        var stats = player_stats.lookup (player_name);
        if (stats == null) {
            stats = new PlayerStats ();
        }
        stats.games_played++;
        switch (type) {
        case VictoryType.OIN:
            stats.oin_victories++;
            break;
        case VictoryType.MARS:
            stats.mars_victories++;
            break;
        case VictoryType.HOME_MARS:
            stats.home_mars_victories++;
            break;
        }
        player_stats.insert (player_name, stats);
        save ();
        changed ();
    }

    /** Фиксация поражения. */
    public void record_loss (string player_name) {
        var stats = player_stats.lookup (player_name);
        if (stats == null) {
            stats = new PlayerStats ();
        }
        stats.games_played++;
        stats.losses++;
        player_stats.insert (player_name, stats);
        save ();
        changed ();
    }

    public void reset () {
        player_stats.remove_all ();
        save ();
        changed ();
    }

    // MARK: - Сохранение/загрузка (INI)

    private void save () {
        var keyfile = new KeyFile ();
        var list = new PlayerStatsEntry[0];
        player_stats.foreach ((name, stats) => {
            list += new PlayerStatsEntry (name, stats);
        });
        keyfile.set_integer ("stats", "count", list.length);

        for (var i = 0; i < list.length; i++) {
            var prefix = "p%d".printf (i);
            keyfile.set_string (prefix, "name", list[i].name);
            keyfile.set_integer (prefix, "games_played", list[i].stats.games_played);
            keyfile.set_integer (prefix, "losses", list[i].stats.losses);
            keyfile.set_integer (prefix, "oin", list[i].stats.oin_victories);
            keyfile.set_integer (prefix, "mars", list[i].stats.mars_victories);
            keyfile.set_integer (prefix, "home_mars", list[i].stats.home_mars_victories);
        }

        StoragePaths.write_text_file (StoragePaths.file_path (GameConfig.STATS_FILE_NAME), keyfile.to_data ());
    }

    private void load () {
        var text = StoragePaths.read_text_file (StoragePaths.file_path (GameConfig.STATS_FILE_NAME));
        if (text == null || text == "") {
            return;
        }
        var keyfile = new KeyFile ();
        try {
            if (!keyfile.load_from_data (text, text.length, GLib.KeyFileFlags.NONE)) {
                return;
            }
            var n = keyfile.get_integer ("stats", "count");
            for (var i = 0; i < n; i++) {
                var prefix = "p%d".printf (i);
                if (!keyfile.has_group (prefix)) {
                    continue;
                }
                var name = keyfile.get_string (prefix, "name");
                var stats = new PlayerStats ();
                stats.games_played = keyfile.get_integer (prefix, "games_played");
                stats.losses = keyfile.get_integer (prefix, "losses");
                stats.oin_victories = keyfile.get_integer (prefix, "oin");
                stats.mars_victories = keyfile.get_integer (prefix, "mars");
                stats.home_mars_victories = keyfile.get_integer (prefix, "home_mars");
                player_stats.insert (name, stats);
            }
        } catch (Error e) {
            warning ("Stats load error: %s", e.message);
        }
    }
}
/** Вспомогательная связка имя → статистика для сериализации. */
public class PlayerStatsEntry {
    public string name;
    public PlayerStats stats;

    public PlayerStatsEntry (string name, PlayerStats stats) {
        this.name = name;
        this.stats = stats;
    }
}

} /* namespace Longbackgammon */