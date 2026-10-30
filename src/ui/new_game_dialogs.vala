/* new_game_dialogs.vala
 *
 * Диалоги инициализации и жизненного цикла партии:
 * выбор параметров новой игры (NewGameView), подтверждение сброса (ConfirmNewGameView)
 * и предложение восстановления незавершённой игры (RestoreGameView).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Диалог начала новой игры: выбор режима соперника (компьютер или человек),
 * ввод имён игроков, настройка сложности искусственного интеллекта и активация розыгрыша первого хода.
 */
public class NewGameView : PopupView {
    public signal void start_requested ();
    private Gtk.Stack row3_stack;
    private SettingsRow player1_row;
    private Gtk.Entry player1_entry;

    public NewGameView (bool show_close_button) {
        base (440);
        var s = SettingsStore.shared ();

        var header = new PopupHeader (Localization.new_game_header (), show_close_button);
        if (header.close_button != null) {
            header.close_button.clicked.connect (() => { close_requested (); });
        }
        append (header);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 24);
        content.margin_start = 24;
        content.margin_end = 24;
        content.margin_top = 24;
        content.margin_bottom = 24;
        var groups = new Gtk.Box (Gtk.Orientation.VERTICAL, 20);

        // СЕКЦИЯ 1: Выбор соперника, имён и уровня сложности ИИ
        var sec1 = new SettingsSection ();
        var opp = new Segmented (new string[] {
            Localization.settings_opponent_computer (), Localization.settings_opponent_human ()
        }, s.opponent == Opponent.HUMAN ? 1 : 0, 180);
        sec1.add_row (new SettingsRow ("person.2.fill", MacColors.ORANGE, Localization.settings_opponent_label (), opp));

        player1_entry = make_entry (s.white_player_name, (t) => { s.set_white_player_name (t); });
        player1_row = new SettingsRow ("person.fill", MacColors.BLUE, "", player1_entry);
        sec1.add_row (player1_row);

        // Переключаемый ряд: сложность ИИ для компьютера либо имя второго игрока для игры вдвоём
        row3_stack = new Gtk.Stack ();
        row3_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
        row3_stack.transition_duration = 200;

        // Вариант 1: Компьютер -> выбор уровня мастерства
        var ai_diff = new Gtk.DropDown.from_strings (new string[] {
            Localization.settings_ai_master (), Localization.settings_ai_standard ()
        });
        ai_diff.width_request = 150;
        ai_diff.selected = s.ai_difficulty == AIDifficulty.STANDARD ? 1 : 0;
        ai_diff.notify["selected"].connect (() => {
            s.set_ai_difficulty (ai_diff.selected == 1 ? AIDifficulty.STANDARD : AIDifficulty.MASTER);
        });
        var ai_row = new SettingsRow ("brain.head.profile", MacColors.PURPLE, Localization.settings_ai_difficulty_label (), ai_diff);
        row3_stack.add_named (ai_row, "ai");

        // Вариант 2: Человек -> ввод имени второго игрока
        var p2_entry = make_entry (s.black_player_name, (t) => { s.set_black_player_name (t); });
        p2_entry.placeholder_text = Localization.default_player2_name ();
        var p2_row = new SettingsRow ("person.fill", MacColors.ORANGE, Localization.settings_player2_label (), p2_entry);
        row3_stack.add_named (p2_row, "player2");

        var sep = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        sep.add_css_class ("lb-row-sep");
        sec1.append (sep);
        sec1.append (row3_stack);

        opp.changed.connect ((i) => {
            s.set_opponent (i == 1 ? Opponent.HUMAN : Opponent.COMPUTER);
            update_opponent ();
        });
        update_opponent ();
        groups.append (SettingsSection.group (Localization.settings_opponent_label ().up (), sec1));

        // СЕКЦИЯ 2: Настройки партии (розыгрыш первого хода и сторона доски)
        var sec2 = new SettingsSection ();
        var sw = new Gtk.Switch ();
        sw.active = s.is_first_move_rolloff_enabled;
        sw.notify["active"].connect (() => { s.set_is_first_move_rolloff_enabled (sw.active); });
        sec2.add_row (new SettingsRow ("dice.fill", MacColors.TEAL, Localization.settings_first_move_rolloff_label (), sw));

        var side_seg = new Segmented (new string[] {
            Localization.settings_board_side_left (), Localization.settings_board_side_right ()
        }, s.board_side == BoardSide.RIGHT ? 1 : 0, 180);
        side_seg.sensitive = !s.is_board_side_switching;
        side_seg.changed.connect ((i) => {
            if (s.is_board_side_switching) {
                return;
            }
            var target_side = (i == 1 ? BoardSide.RIGHT : BoardSide.LEFT);
            if (s.board_side != target_side) {
                s.set_board_side (target_side);
            }
        });
        s.changed.connect (() => {
            side_seg.sensitive = !s.is_board_side_switching;
            var expected = (s.board_side == BoardSide.RIGHT ? 1 : 0);
            if (side_seg.selected_index != expected) {
                side_seg.set_selected (expected);
            }
        });
        sec2.add_row (new SettingsRow ("rectangle.lefthalf.inset.filled", MacColors.INDIGO, Localization.settings_board_side_label (), side_seg));

        groups.append (SettingsSection.group (Localization.settings_game_settings_section ().up (), sec2));
        content.append (groups);

        // Кнопка запуска партии
        var start = UiKit.button (Localization.button_start_game (), "lb-btn-blue", "lb-btn-wide");
        start.hexpand = true;
        start.margin_top = 10;
        start.clicked.connect (() => { start_requested (); });
        content.append (start);
        append (content);
    }

    public delegate void TextSetter (string t);

    private static Gtk.Entry make_entry (string text, owned TextSetter setter) {
        var e = new Gtk.Entry ();
        e.add_css_class ("lb-entry");
        e.text = text;
        e.width_request = 140;
        e.max_width_chars = 12;
        e.width_chars = 10;
        e.changed.connect (() => { setter (e.text); });
        return e;
    }

    private void update_opponent () {
        var computer = SettingsStore.shared ().opponent == Opponent.COMPUTER;
        player1_row.title_label.label = computer ? Localization.settings_player_name_label ()
                                                  : Localization.settings_player1_label ();
        player1_entry.placeholder_text = computer ? Localization.default_player_name ()
                                                   : Localization.default_player1_name ();
        row3_stack.visible_child_name = computer ? "ai" : "player2";
    }
}

/**
 * Диалог предупреждения о прерывании активной партии при начале новой игры.
 */
public class ConfirmNewGameView : PopupView {
    public signal void confirmed ();
    public signal void cancelled ();
    private Flasher flasher;

    public ConfirmNewGameView (GameSession session) {
        base (420);
        flasher = new Flasher (this);

        var header = new PopupHeader (Localization.confirm_new_game_title (), false);
        append (header);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

        var msg = UiKit.label (Localization.confirm_new_game_message (session.player_name (session.current_player)),
            "lb-body", 0.5f);
        msg.wrap = true;
        msg.justify = Gtk.Justification.CENTER;
        msg.margin_start = 24;
        msg.margin_end = 24;
        msg.margin_top = 24;
        msg.margin_bottom = 24;
        append (msg);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
        buttons.homogeneous = true;
        buttons.margin_start = 24;
        buttons.margin_end = 24;
        buttons.margin_top = 24;
        buttons.margin_bottom = 24;
        var ok = UiKit.button (Localization.confirm_new_game_start (), "lb-btn-blue", "lb-btn-mid");
        ok.clicked.connect (() => { confirmed (); });
        buttons.append (ok);
        var cancel = UiKit.button (Localization.confirm_new_game_cancel (), "lb-btn-gray", "lb-btn-mid");
        cancel.clicked.connect (() => { cancelled (); });
        buttons.append (cancel);
        append (buttons);
    }

    /** Визуальное мигание рамкой окна при клике мимо модального окна. */
    public void flash () {
        flasher.flash ();
    }

    public override void dispose () {
        flasher.stop ();
        base.dispose ();
    }
}

/**
 * Диалог предложения продолжить ранее сохранённую партию либо засчитать поражение/сброс.
 */
public class RestoreGameView : PopupView {
    public signal void continue_requested ();
    public signal void forfeit_requested ();
    private Flasher flasher;

    public RestoreGameView (string player_name) {
        base (380);
        flasher = new Flasher (this);

        var header = new PopupHeader (Localization.restore_game_title (), false);
        append (header);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 24);
        content.margin_start = 24;
        content.margin_end = 24;
        content.margin_top = 24;
        content.margin_bottom = 24;
        var icon = new SFIcon ("arrow.triangle.2.circlepath", 52, UiKit.rgba (MacColors.ORANGE));
        icon.halign = Gtk.Align.CENTER;
        icon.margin_top = 8;
        content.append (icon);

        var msg = UiKit.label (Localization.restore_game_message (player_name), "lb-body", 0.5f);
        msg.wrap = true;
        msg.justify = Gtk.Justification.CENTER;
        content.append (msg);

        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        buttons.homogeneous = true;
        buttons.margin_bottom = 8;
        var cont = UiKit.button (Localization.restore_game_continue (), "lb-btn-blue", "lb-btn-wide");
        cont.clicked.connect (() => { continue_requested (); });
        buttons.append (cont);
        var forfeit = UiKit.button (Localization.restore_game_forfeit (), "lb-btn-red80", "lb-btn-wide");
        forfeit.clicked.connect (() => { forfeit_requested (); });
        buttons.append (forfeit);
        content.append (buttons);
        append (content);
    }

    /** Визуальное мигание рамкой окна при клике мимо модального окна. */
    public void flash () {
        flasher.flash ();
    }

    public override void dispose () {
        flasher.stop ();
        base.dispose ();
    }
}

} /* namespace Longbackgammon */
