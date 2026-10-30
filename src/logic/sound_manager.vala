/* sound_manager.vala
 *
 * Проигрывание звуковых эффектов.
 * Использует системный плеер (paplay / pw-play / aplay), чтобы не зависеть
 * от внешних библиотек. Звуки ищутся в каталогах данных и разработки.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

public class SoundManager {
    private static SoundManager? _shared = null;

    public static SoundManager shared () {
        if (_shared == null) {
            _shared = new SoundManager ();
        }
        return _shared;
    }

    private string? player = null;
    private string[] player_candidates;
    private int player_index = -1;

    private SoundManager () {
        // Приоритет: PipeWire/PulseAudio (host), GStreamer (Flatpak/GNOME SDK),
        // ALSA и ffplay как последний резерв.
        player_candidates = new string[] { "pw-play", "paplay", "gst-launch-1.0", "aplay", "ffplay" };
        for (var i = 0; i < player_candidates.length; i++) {
            if (find_in_path (player_candidates[i])) {
                player = player_candidates[i];
                player_index = i;
                break;
            }
        }
        if (Environment.get_variable ("LONGBACKGAMMON_DEBUG_SOUND") != null) {
            stderr.printf ("[sound] player=%s index=%d\n",
                player == null ? "NONE" : player,
                player_index);
        }
    }

    private static bool find_in_path (string name) {
        var path = Environment.get_variable ("PATH");
        if (path == null) {
            return false;
        }
        var dirs = path.split (":");
        for (var i = 0; i < dirs.length; i++) {
            var full = GLib.Path.build_filename (dirs[i], name);
            if (FileUtils.test (full, FileTest.IS_EXECUTABLE)) {
                return true;
            }
        }
        return false;
    }

    /** Находит файл звука по имени (без расширения). */
    private static string find_sound_file (string name) {
        return StoragePaths.find_asset_path ("sounds", name + ".wav");
    }

    private void play (string name) {
        if (!SettingsStore.shared ().is_sound_enabled) {
            return;
        }
        if (player == null) {
            if (Environment.get_variable ("LONGBACKGAMMON_DEBUG_SOUND") != null) {
                stderr.printf ("[sound] no player found in PATH\n");
            }
            return;
        }
        var file = find_sound_file (name);
        if (file == "") {
            if (Environment.get_variable ("LONGBACKGAMMON_DEBUG_SOUND") != null) {
                stderr.printf ("[sound] file not found for '%s'\n", name);
            }
            return;
        }
        if (!try_play (player, file)) {
            // Пробуем остальных плееров по очереди
            for (var i = 0; i < player_candidates.length; i++) {
                if (i == player_index) {
                    continue;
                }
                if (try_play (player_candidates[i], file)) {
                    player = player_candidates[i];
                    player_index = i;
                    return;
                }
            }
        }
    }

    private static bool try_play (string cmdname, string file) {
        string cmd;
        if (cmdname == "ffplay") {
            cmd = "ffplay -nodisp -autoexit -loglevel quiet %s".printf (Shell.quote (file));
        } else if (cmdname == "gst-launch-1.0") {
            // GStreamer: работает и в системном окружении, и внутри Flatpak/GNOME Builder
            cmd = "gst-launch-1.0 -q filesrc location=%s ! wavparse ! autoaudiosink".printf (Shell.quote (file));
        } else {
            cmd = "%s %s".printf (cmdname, Shell.quote (file));
        }
        if (Environment.get_variable ("LONGBACKGAMMON_DEBUG_SOUND") != null) {
            stderr.printf ("[sound] -> %s\n", cmd);
        }
        try {
            Process.spawn_command_line_async (cmd);
            return true;
        } catch (Error e) {
            if (Environment.get_variable ("LONGBACKGAMMON_DEBUG_SOUND") != null) {
                stderr.printf ("[sound] ERROR: %s\n", e.message);
            }
            return false;
        }
    }

    public void play_dice_roll () {
        play ("diceroll0%d".printf (1 + GLib.Random.int_range (0, GameConfig.DICE_ROLL_SOUNDS_COUNT)));
    }

    public void play_checker_move () {
        play ("checkermove");
    }

    public void play_new_game_start () {
        play ("newgame");
    }

    public void play_victory () {
        play ("victory");
    }

    public void play_undo () {
        // Системный плеер для короткого звука отмены
        if (!SettingsStore.shared ().is_sound_enabled) {
            return;
        }
        play ("checkermove");
    }

    [CCode (cname = "kill", cheader_filename = "signal.h")]
    private extern static int kill (GLib.Pid pid, int sig);

    private Pid placement_pid = 0;
    private uint panels_dock_timeout_id = 0;
    private static int16[]? cached_step_samples = null;
    private static int cached_step_frames = 0;

    public void play_placement_step () {
        play ("placement_step");
    }

    /** Воспроизводит звук вставания боковых панелей на свои места при смене стороны доски. */
    public void play_panels_dock_in_place () {
        play ("paneldock");
    }

    /**
     * Запускает звук расстановки фишек и последующий звук вставания панелей на свои места при смене стороны доски.
     */
    public void play_board_side_switch_animation () {
        if (!SettingsStore.shared ().is_sound_enabled) {
            return;
        }
        // 1. Звук каскада фишек (деревянные щелчки приземления)
        play_dynamic_placement (30, 0.30f);

        // 2. Отменяем предыдущую задачу стыковки панелей при быстром повторном переключении
        if (panels_dock_timeout_id != 0) {
            GLib.Source.remove (panels_dock_timeout_id);
            panels_dock_timeout_id = 0;
        }

        // Задержка под момент завершения 1.0-секундной анимации панелей (870 мс + 130 мс пик paneldock ≈ 1.00 с)
        panels_dock_timeout_id = GLib.Timeout.add (870, () => {
            panels_dock_timeout_id = 0;
            play_panels_dock_in_place ();
            return GLib.Source.REMOVE;
        });
    }

    /** Останавливает звук расстановки (при сбросе/отмене партии). */
    public void stop_placement () {
        if (placement_pid > 0) {
            kill (placement_pid, 15);
            Process.close_pid (placement_pid);
            placement_pid = 0;
        }
        if (panels_dock_timeout_id != 0) {
            GLib.Source.remove (panels_dock_timeout_id);
            panels_dock_timeout_id = 0;
        }
    }

    /**
     * Динамический звук последовательной расстановки фишек:
     * Генерирует один непрерывный аудиофайл с точными временными сдвигами для каждого шага
     * (задержка до приземления 430мс, шаг 51мс, стереопанорамирование, громкость 30%).
     * Воспроизводится один раз без задержек и расхождения по времени.
     */
    public void play_dynamic_placement (int count, float volume = 0.30f) {
        if (!SettingsStore.shared ().is_sound_enabled || count <= 0) {
            return;
        }
        stop_placement ();

        var cache_dir = GLib.Path.build_filename (GLib.Environment.get_user_cache_dir (), "longbackgammon");
        var dest_path = GLib.Path.build_filename (cache_dir, "placement_%d.wav".printf (count));

        if (!FileUtils.test (dest_path, FileTest.EXISTS)) {
            if (!generate_dynamic_placement_wav (dest_path, count, volume)) {
                return;
            }
        }

        if (player != null) {
            play_tracked (player, dest_path, out placement_pid);
        }
    }

    private bool play_tracked (string cmdname, string file, out Pid pid) {
        pid = 0;
        string cmd;
        if (cmdname == "ffplay") {
            cmd = "ffplay -nodisp -autoexit -loglevel quiet %s".printf (Shell.quote (file));
        } else if (cmdname == "gst-launch-1.0") {
            cmd = "gst-launch-1.0 -q filesrc location=%s ! wavparse ! autoaudiosink".printf (Shell.quote (file));
        } else {
            cmd = "%s %s".printf (cmdname, Shell.quote (file));
        }
        try {
            string[] argv;
            Shell.parse_argv (cmd, out argv);
            Pid child_pid;
            Process.spawn_async (null, argv, null, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, out child_pid);
            pid = child_pid;
            ChildWatch.add (child_pid, (p, status) => {
                Process.close_pid (p);
                if (placement_pid == p) {
                    placement_pid = 0;
                }
            });
            return true;
        } catch (Error e) {
            return false;
        }
    }

    private static int16[]? load_placement_step_samples (out int nframes) {
        nframes = 0;
        var path = find_sound_file ("placement_step");
        if (path == "" || !FileUtils.test (path, FileTest.EXISTS)) {
            return null;
        }
        uint8[] data;
        try {
            FileUtils.get_data (path, out data);
        } catch (Error e) {
            return null;
        }
        if (data.length < 44) {
            return null;
        }
        if (data[0] != 'R' || data[1] != 'I' || data[2] != 'F' || data[3] != 'F'
            || data[8] != 'W' || data[9] != 'A' || data[10] != 'V' || data[11] != 'E') {
            return null;
        }
        size_t offset = 12;
        while (offset + 8 <= data.length) {
            uint32 chunk_sz = (uint32) data[offset + 4]
                            | ((uint32) data[offset + 5] << 8)
                            | ((uint32) data[offset + 6] << 16)
                            | ((uint32) data[offset + 7] << 24);
            if (data[offset] == 'd' && data[offset + 1] == 'a' && data[offset + 2] == 't' && data[offset + 3] == 'a') {
                offset += 8;
                if (offset + chunk_sz > data.length) {
                    chunk_sz = (uint32) (data.length - offset);
                }
                var sample_count = (int) (chunk_sz / 2);
                int16[] samples = new int16[sample_count];
                for (var i = 0; i < sample_count; i++) {
                    var idx = offset + i * 2;
                    samples[i] = (int16) ((uint16) data[idx] | ((uint16) data[idx + 1] << 8));
                }
                nframes = sample_count / 2;
                return samples;
            }
            offset += 8 + chunk_sz + (chunk_sz % 2);
        }
        return null;
    }

    private static bool generate_dynamic_placement_wav (string dest_path, int count, float volume) {
        if (cached_step_samples == null) {
            cached_step_samples = load_placement_step_samples (out cached_step_frames);
        }
        if (cached_step_samples == null || cached_step_frames <= 0) {
            return false;
        }

        var framerate = 48000;
        var flight_delay = (int) (PlacementAnimation.AUDIO_FLIGHT_DELAY * framerate);
        var step_interval = (int) (PlacementAnimation.STEP_INTERVAL * framerate);
        var tail_frames = 4800;
        var total_frames = flight_delay + (count - 1) * step_interval + cached_step_frames + tail_frames;

        var out_l = new float[total_frames];
        var out_r = new float[total_frames];

        for (var i = 0; i < count; i++) {
            var off = flight_delay + i * step_interval;
            var pan = (i % 2 == 0) ? -0.20 : 0.20;
            var pan_l = Math.cos ((pan + 1.0) * Math.PI / 4.0);
            var pan_r = Math.sin ((pan + 1.0) * Math.PI / 4.0);

            for (var f = 0; f < cached_step_frames; f++) {
                var sl = ((float) cached_step_samples[f * 2]) / 32768.0f;
                var sr = ((float) cached_step_samples[f * 2 + 1]) / 32768.0f;
                out_l[off + f] += (float) (sl * volume * pan_l);
                out_r[off + f] += (float) (sr * volume * pan_r);
            }
        }

        var pcm_bytes = total_frames * 4;
        var total_bytes = 44 + pcm_bytes;
        var wav_data = new uint8[total_bytes];

        // "RIFF"
        wav_data[0] = 'R'; wav_data[1] = 'I'; wav_data[2] = 'F'; wav_data[3] = 'F';
        uint32 riff_sz = (uint32) (total_bytes - 8);
        wav_data[4] = (uint8) (riff_sz & 0xFF);
        wav_data[5] = (uint8) ((riff_sz >> 8) & 0xFF);
        wav_data[6] = (uint8) ((riff_sz >> 16) & 0xFF);
        wav_data[7] = (uint8) ((riff_sz >> 24) & 0xFF);

        // "WAVE" + "fmt "
        wav_data[8] = 'W'; wav_data[9] = 'A'; wav_data[10] = 'V'; wav_data[11] = 'E';
        wav_data[12] = 'f'; wav_data[13] = 'm'; wav_data[14] = 't'; wav_data[15] = ' ';
        wav_data[16] = 16; wav_data[17] = 0; wav_data[18] = 0; wav_data[19] = 0;
        wav_data[20] = 1; wav_data[21] = 0; // PCM
        wav_data[22] = 2; wav_data[23] = 0; // Stereo
        // Sample rate 48000
        wav_data[24] = 0x80; wav_data[25] = 0xBB; wav_data[26] = 0; wav_data[27] = 0;
        // Byte rate 192000
        wav_data[28] = 0x00; wav_data[29] = 0xEE; wav_data[30] = 0x02; wav_data[31] = 0;
        wav_data[32] = 4; wav_data[33] = 0;
        wav_data[34] = 16; wav_data[35] = 0;

        // "data"
        wav_data[36] = 'd'; wav_data[37] = 'a'; wav_data[38] = 't'; wav_data[39] = 'a';
        uint32 data_sz = (uint32) pcm_bytes;
        wav_data[40] = (uint8) (data_sz & 0xFF);
        wav_data[41] = (uint8) ((data_sz >> 8) & 0xFF);
        wav_data[42] = (uint8) ((data_sz >> 16) & 0xFF);
        wav_data[43] = (uint8) ((data_sz >> 24) & 0xFF);

        var byte_idx = 44;
        for (var f = 0; f < total_frames; f++) {
            var sl = (int) (out_l[f] * 32767.0f);
            var sr = (int) (out_r[f] * 32767.0f);
            var val_l = (int16) int.max (-32768, int.min (32767, sl));
            var val_r = (int16) int.max (-32768, int.min (32767, sr));

            wav_data[byte_idx++] = (uint8) (((uint16) val_l) & 0xFF);
            wav_data[byte_idx++] = (uint8) ((((uint16) val_l) >> 8) & 0xFF);
            wav_data[byte_idx++] = (uint8) (((uint16) val_r) & 0xFF);
            wav_data[byte_idx++] = (uint8) ((((uint16) val_r) >> 8) & 0xFF);
        }

        try {
            var parent = Path.get_dirname (dest_path);
            if (!FileUtils.test (parent, FileTest.EXISTS)) {
                DirUtils.create_with_parents (parent, 0755);
            }
            FileUtils.set_data (dest_path, wav_data);
            return true;
        } catch (Error e) {
            stderr.printf ("[sound] Error writing %s: %s\n", dest_path, e.message);
            return false;
        }
    }
}

} /* namespace Longbackgammon */
