/* settings_view.vala
 *
 * Окно настроек игры: язык, звук, темы оформления, сложность ИИ, подсказки и режим счёта.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Диалог настроек игры с группировкой по категориям:
 * общие параметры, графика и анимации, управление, подсказки траекторий и лог.
 */
public class SettingsView : PopupView {
    private Gtk.ScrolledWindow? scroller = null;
    private Language built_language;
    private int board_side = 600;
    private uint rebuild_source = 0;
    private ulong settings_handler = 0;

    public SettingsView () {
        base (580);
        build ();
        settings_handler = SettingsStore.shared ().changed.connect (() => {
            // При смене языка перестраиваем интерфейс окна в цикле событий
            if (SettingsStore.shared ().language != built_language && rebuild_source == 0) {
                rebuild_source = Idle.add (() => {
                    rebuild_source = 0;
                    build ();
                    return false;
                });
            }
        });
    }

    public override void dispose () {
        if (settings_handler != 0) {
            SettingsStore.shared ().disconnect (settings_handler);
            settings_handler = 0;
        }
        if (rebuild_source != 0) {
            Source.remove (rebuild_source);
            rebuild_source = 0;
        }
        base.dispose ();
    }

    private int debug_click_count = 0;
    private Gtk.Revealer? debug_revealer = null;

    private void build () {
        UiKit.clear_box (this);
        var s = SettingsStore.shared ();
        built_language = s.language;

        var header = new PopupHeader (Localization.settings_header (), true);
        header.close_button.clicked.connect (() => { close_requested (); });
        var title_click = new Gtk.GestureClick ();
        title_click.released.connect (() => {
            if (debug_click_count < 10) {
                debug_click_count++;
                if (debug_click_count >= 10 && debug_revealer != null) {
                    debug_revealer.reveal_child = true;
                }
            }
        });
        header.title_label.add_controller (title_click);
        append (header);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 24);
        content.margin_start = 24;
        content.margin_end = 24;
        content.margin_top = 20;
        content.margin_bottom = 20;

        // 1. ОБЩИЕ НАСТРОЙКИ
        var general = new SettingsSection ();
        var languages = Language.all_cases ();
        string[] lang_names = new string[languages.length];
        uint selected_idx = 0;
        for (var idx = 0; idx < languages.length; idx++) {
            lang_names[idx] = languages[idx].display_name ();
            if (languages[idx].to_raw () == s.language.to_raw ()) {
                selected_idx = (uint) idx;
            }
        }
        var lang = new Gtk.DropDown.from_strings (lang_names);
        lang.width_request = 180;
        lang.selected = selected_idx;
        lang.notify["selected"].connect (() => {
            if (lang.selected < languages.length) {
                s.set_language (languages[lang.selected]);
            }
        });
        general.add_row (new SettingsRow ("character.bubble", MacColors.BLUE, Localization.settings_language_label (), lang));
        general.add_row (new SettingsRow ("speaker.wave.2.fill", MacColors.PINK, Localization.settings_sound_label (),
            make_switch (s.is_sound_enabled, (v) => { s.set_is_sound_enabled (v); })));

        var ai_diff = new Gtk.DropDown.from_strings (new string[] {
            Localization.settings_ai_master (), Localization.settings_ai_standard ()
        });
        ai_diff.width_request = 180;
        ai_diff.selected = s.ai_difficulty == AIDifficulty.STANDARD ? 1 : 0;
        ai_diff.notify["selected"].connect (() => {
            s.set_ai_difficulty (ai_diff.selected == 1 ? AIDifficulty.STANDARD : AIDifficulty.MASTER);
        });
        general.add_row (new SettingsRow ("brain.head.profile", MacColors.PURPLE, Localization.settings_ai_difficulty_label (), ai_diff));
        content.append (SettingsSection.group (Localization.settings_section_general (), general));

        // 2. ОФОРМЛЕНИЕ И АНИМАЦИИ
        var appearance = new SettingsSection ();

        var theme_dd = new Gtk.DropDown.from_strings (new string[] {
            Localization.settings_theme_wood (), Localization.settings_theme_marble ()
        });
        theme_dd.width_request = 180;
        theme_dd.selected = s.board_theme == BoardTheme.MARBLE ? 1 : 0;
        theme_dd.notify["selected"].connect (() => {
            s.set_board_theme (theme_dd.selected == 1 ? BoardTheme.MARBLE : BoardTheme.WOOD);
        });
        appearance.add_row (new SettingsRow ("paintpalette.fill", MacColors.BROWN, Localization.settings_theme_label (), theme_dd));

        var speed = new Segmented (new string[] { Localization.settings_speed_fast (), Localization.settings_speed_slow () },
            s.game_speed == GameSpeed.SLOW ? 1 : 0, 180);
        speed.changed.connect ((i) => { s.set_game_speed (i == 1 ? GameSpeed.SLOW : GameSpeed.FAST); });
        appearance.add_row (new SettingsRow ("gauge", MacColors.GREEN, Localization.settings_speed_label (), speed));

        var mov = new Segmented (new string[] { Localization.settings_movement_type_straight (), Localization.settings_movement_type_arc () },
            s.movement_type == MovementType.ARC ? 1 : 0, 180);
        mov.changed.connect ((i) => { s.set_movement_type (i == 1 ? MovementType.ARC : MovementType.STRAIGHT); });
        appearance.add_row (new SettingsRow ("move.3d", MacColors.TEAL, Localization.settings_movement_type_label (), mov));

        var dice_anim = new Segmented (new string[] { Localization.settings_dice_animation_board (), Localization.settings_dice_animation_panel () },
            s.use_board_dice_animation ? 0 : 1, 230);
        dice_anim.changed.connect ((i) => { s.set_use_board_dice_animation (i == 0); });
        appearance.add_row (new SettingsRow ("die.face.5.fill", MacColors.ORANGE, Localization.settings_dice_animation_label (), dice_anim));

        var score = new Segmented (new string[] {
            Localization.settings_score_display_score (), Localization.settings_score_display_progress ()
        }, s.score_display_mode == ScoreDisplayMode.PROGRESS ? 1 : 0, 230);
        score.changed.connect ((i) => {
            s.set_score_display_mode (i == 1 ? ScoreDisplayMode.PROGRESS : ScoreDisplayMode.SCORE);
        });
        appearance.add_row (new SettingsRow ("percent", MacColors.RED, Localization.settings_score_display_label (), score));
        content.append (SettingsSection.group (Localization.settings_section_appearance (), appearance,
            Localization.settings_section_score_footer ()));

        // 3. УПРАВЛЕНИЕ
        var controls = new SettingsSection ();
        controls.add_row (new SettingsRow ("hand.draw.fill", MacColors.PURPLE, Localization.settings_drag_and_drop_label (),
            make_switch (s.is_drag_and_drop_enabled, (v) => { s.set_is_drag_and_drop_enabled (v); })));
        content.append (SettingsSection.group (Localization.settings_section_controls (), controls));

        // 4. ПОДСКАЗКИ
        var hints = new SettingsSection ();
        hints.add_row (new SettingsRow ("person.fill", MacColors.CYAN, Localization.settings_show_path_player (),
            make_switch (s.show_path_player, (v) => { s.set_show_path_player (v); })));
        hints.add_row (new SettingsRow ("desktopcomputer", MacColors.CYAN, Localization.settings_show_path_computer (),
            make_switch (s.show_path_computer, (v) => { s.set_show_path_computer (v); })));
        content.append (SettingsSection.group (Localization.settings_show_path_label (), hints,
            Localization.settings_section_movement_footer ()));

        // 5. ЛОГ ХОДОВ
        var log_sec = new SettingsSection ();
        var cell_indices_sw = make_switch (s.show_cell_indices, (v) => { s.set_show_cell_indices (v); });
        cell_indices_sw.sensitive = s.highlight_log_paths;
        var hl_sw = make_switch (s.highlight_log_paths, (v) => {
            s.set_highlight_log_paths (v);
            cell_indices_sw.sensitive = v;
        });
        log_sec.add_row (new SettingsRow ("arrowshape.turn.up.right.fill", MacColors.INDIGO, Localization.settings_highlight_log_paths_label (), hl_sw));
        log_sec.add_row (new SettingsRow ("number.circle.fill", MacColors.BLUE, Localization.settings_show_cell_indices_label (), cell_indices_sw));
        content.append (SettingsSection.group (Localization.settings_section_log (), log_sec));

        // 6. ОТЛАДКА (раскрывается по 10 кликам по заголовку)
        debug_revealer = new Gtk.Revealer ();
        debug_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
        debug_revealer.reveal_child = (debug_click_count >= 10);
        var debug = new SettingsSection ();
        debug.add_row (new SettingsRow ("ant.fill", MacColors.GRAY, Localization.settings_debug_export_label (),
            make_switch (s.enable_debug_export, (v) => { s.set_enable_debug_export (v); })));
        debug_revealer.set_child (SettingsSection.group (Localization.settings_section_debug (), debug));
        content.append (debug_revealer);

        scroller = new Gtk.ScrolledWindow ();
        scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scroller.propagate_natural_height = true;
        scroller.set_child (content);
        append (scroller);

        var close = UiKit.button (Localization.settings_close_button (), "lb-btn-blue");
        close.halign = Gtk.Align.CENTER;
        close.margin_top = 20;
        close.margin_bottom = 20;
        close.clicked.connect (() => { close_requested (); });
        append (close);
        update_board_side (board_side);
    }

    public delegate void BoolSetter (bool v);

    private static Gtk.Switch make_switch (bool value, owned BoolSetter setter) {
        var sw = new Gtk.Switch ();
        sw.active = value;
        sw.valign = Gtk.Align.CENTER;
        sw.notify["active"].connect (() => { setter (sw.active); });
        return sw;
    }

    public override void update_board_side (int side) {
        board_side = side;
        if (scroller != null) {
            // Расчёт высоты с учётом шапки (≈58px) и кнопки закрытия с отступами (≈76px)
            scroller.max_content_height = int.max (120, (int) (side * 0.9) - 58 - 76);
        }
    }
}

} /* namespace Longbackgammon */
