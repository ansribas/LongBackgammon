/* rules_view.vala
 *
 * Справочник классических правил длинных нард.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Окно правил игры с карточками по разделам:
 * цель, перемещение, кубики, правило головы, запрет запирания, дом, исходы и подсказки.
 */
public class RulesView : PopupView {
    private Gtk.ScrolledWindow scroller;

    public RulesView () {
        base (520);
        remove_css_class ("lb-popup");
        add_css_class ("lb-popup");
        add_css_class ("lb-popup-rules");

        var header = new PopupHeader (Localization.rules_title (), true);
        header.close_button.clicked.connect (() => { close_requested (); });
        append (header);
        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
        content.margin_start = 16;
        content.margin_end = 16;
        content.margin_top = 16;
        content.margin_bottom = 16;
        string[,] sections = {
            { "🎯", Localization.rules_goal_title (), Localization.rules_goal_text () },
            { "🔄", Localization.rules_movement_title (), Localization.rules_movement_text () },
            { "🎲", Localization.rules_dice_title (), Localization.rules_dice_text () },
            { "📍", Localization.rules_head_title (), Localization.rules_head_text () },
            { "🚫", Localization.rules_block_title (), Localization.rules_block_text () },
            { "🏠", Localization.rules_home_title (), Localization.rules_home_text () },
            { "🏆", Localization.rules_victory_title (), Localization.rules_victory_text () },
            { "💡", Localization.rules_tip_title (), Localization.rules_tip_text () }
        };
        for (var i = 0; i < 8; i++) {
            content.append (rule_section (sections[i, 0], sections[i, 1], sections[i, 2]));
        }

        scroller = new Gtk.ScrolledWindow ();
        scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scroller.propagate_natural_height = true;
        scroller.vexpand = true;
        scroller.set_child (content);
        append (scroller);

        append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
        var close = UiKit.button (Localization.settings_close_button (), "lb-btn-blue");
        close.halign = Gtk.Align.CENTER;
        close.margin_top = 20;
        close.margin_bottom = 20;
        close.clicked.connect (() => { close_requested (); });
        append (close);
    }

    /**
     * Создаёт визуальную карточку правила: иконка-эмодзи, заголовок и форматированный текст.
     */
    private static Gtk.Widget rule_section (string icon, string title, string text) {
        var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
        card.add_css_class ("lb-rule-card");
        var head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        head.append (UiKit.label (icon, "lb-title2"));
        var t = UiKit.label (title, "lb-headline");
        t.wrap = true;
        t.hexpand = true;
        head.append (t);
        card.append (head);
        var body = UiKit.label (text, "lb-subheadline lb-secondary");
        body.wrap = true;
        body.natural_wrap_mode = Gtk.NaturalWrapMode.WORD;
        var attrs = new Pango.AttrList ();
        attrs.insert (Pango.attr_line_height_new_absolute (16 * Pango.SCALE + 4 * Pango.SCALE));
        body.attributes = attrs;
        card.append (body);
        return card;
    }

    public override void update_board_side (int side) {
        // Шапка ≈ 58px, нижняя панель с кнопкой ≈ 77px
        scroller.max_content_height = int.max (120, (int) (side * 0.9) - 58 - 77);
    }
}

} /* namespace Longbackgammon */
