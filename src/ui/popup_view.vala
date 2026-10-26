/* popup_view.vala
 *
 * Базовый класс модальных всплывающих окон приложения.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/** Базовый класс всплывающего окна: центрированная колонка с фоном, скруглением и адаптивным ограничением высоты. */
public abstract class PopupView : Gtk.Box {
    /** Сигнал запроса закрытия диалога. */
    public signal void close_requested ();

    protected PopupView (int width) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        UiKit.ensure_css ();
        width_request = width;
        add_css_class ("lb-popup");
        overflow = Gtk.Overflow.HIDDEN;
    }

    /**
     * Адаптивная подстройка максимальной высоты под текущий размер игрового поля.
     * @param side Размер стороны доски в пикселях.
     */
    public virtual void update_board_side (int side) {
    }
}

} /* namespace Longbackgammon */
