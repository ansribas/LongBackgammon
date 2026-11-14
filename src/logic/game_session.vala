/* game_session.vala
 *
 * Основной класс игровой сессии: состояние, жизненный цикл партии,
 * броски кубиков, ходы игрока и компьютера, отмена ходов, логи,
 * сохранение/восстановление.
 *
 * Асинхронные операции реализованы через async/yield-методы Vala и таймеры GLib.
 * Корректная отмена устаревших задач (при старте новой игры или сбросе)
 * контролируется счётчиком поколений партии (gen): корутина завершает работу,
 * если текущее поколение больше не совпадает со значением при её запуске.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Longbackgammon {

/**
 * Игровая сессия. Эмитит сигнал `changed` при любом изменении состояния,
 * чтобы интерфейс мог перерисоваться.
 */
public class GameSession : Object {
    // MARK: - Статистика для финального экрана
    public int white_moves_count = 0;
    public int black_moves_count = 0;
    public int white_doubles_count = 0;
    public int black_doubles_count = 0;
    public int white_total_dice_sum = 0;
    public int black_total_dice_sum = 0;
    public int white_burned_dice_sum = 0;
    public int black_burned_dice_sum = 0;

    // MARK: - Лог ходов (новые записи добавляются в начало массива)
    public TurnRecord[] white_turn_log;
    public TurnRecord[] black_turn_log;
    public int highlighted_log_id = -1;   // −1 — нет подсветки (аналог nil)
    public string white_player_name = "";
    public string black_player_name = "";
    public TurnRecord? current_turn_record = null;
    public TurnDie[] current_turn_dice;

    // MARK: - Флаги состояния
    public bool is_game_started = false;
    public bool is_game_over = false;
    public bool showing_game_over_result = false;
    public bool is_white_first_turn = true;
    public bool is_black_first_turn = true;

    public GameBoard board;
    public CheckerColor current_player = CheckerColor.WHITE;
    public DiceRoll? dice_roll = null;
    public int[] remaining_dice;
    public BoardPoint? selected_point = null;
    public BoardPoint? hovered_target_point = null;
    public bool is_hovering_bear_off_target = false;
    public int checkers_moved_from_head_this_turn = 0;
    public string status_message = "";

    public bool is_auto_playing_black = false;
    public bool is_animating = false;
    public bool is_placing_checkers = false;

    // MARK: - Состояния анимации кубиков
    public bool is_rolling = false;
    public bool is_doubling = false;
    /** 0: четыре кости собраны в пару, 1: кости разложены в сетку 2x2. */
    public double double_division_progress = 1.0;
    public bool is_no_moves_flashing = false;
    public bool is_first_move_rolloff_in_progress = false;
    public bool suppress_dice_cursor = false;
    public bool is_dice_flash_active = false;
    public double dice_flash_opacity = 0.0;
    /** ID единственной фишки, которую нужно анимировать при отмене хода. */
    public int undo_flight_checker_id = -1;
    public bool is_undoing_move = false;
    public BoardDiceState? board_dice_state = null;

    /** Точные координаты слотов кубиков в боковой панели (в системе координат доски). */
    public void dice_slot_centers (CheckerColor color, double board_side, out double x1, out double y1, out double x2, out double y2) {
        var is_right_side = BoardLayout.is_player_on_right_side (color);
        var mid_x = is_right_side ? (board_side + 70.0) : -70.0;
        var mid_y = 74.0;
        var offset = 26.5;
        x1 = mid_x - offset;
        y1 = mid_y;
        x2 = mid_x + offset;
        y2 = mid_y;
    }

    // MARK: - Розыгрыш первого хода (по два кубика у каждого игрока)
    public CheckerColor? rolloff_active_player = CheckerColor.WHITE;
    public DiceRoll? white_rolloff_dice = null;
    public DiceRoll? black_rolloff_dice = null;
    /** Идентификатор анимации переноса кубиков розыгрыша в лог (0 — нет). */
    public int rolloff_animation_id = 0;
    public int rolling_die_index = -1;   // −1 — оба кубика (nil), 0/1 — игрок при roll-off
    public int rolling_dice_value1 = 6;
    public int rolling_dice_value2 = 6;

    // MARK: - Кэш легальных ходов
    public MoveOption[] cached_legal_options;

    // MARK: - Сигналы
    public signal void changed ();
    /** Сигнал запуска плавной анимации очистки логов в боковых панелях игроков. */
    public signal void clearing_logs_animated ();
    /** Сигнал запуска плавной анимации каскадного появления строк лога при возобновлении партии. */
    public signal void restoring_logs_animated ();

    // MARK: - Внутренние поля
    internal MoveSnapshot[] move_history;
    /** Поколение партии: меняется при новой игре / восстановлении — отменяет висящие задачи. */
    internal uint gen = 0;
    /** Токен задачи автозавершения хода (аналог currentAsyncWork для triggerAutoEndTurn). */
    internal uint auto_end_token = 0;
    internal int rolloff_anim_counter = 0;
    private CheckerPlacementAnimator placement_animator = new CheckerPlacementAnimator ();

    [CCode (cname = "malloc_trim", cheader_filename = "malloc.h")]
    private extern static int malloc_trim (size_t pad);

    internal static void trim_heap () {
        malloc_trim (0);
    }

    public GameSession () {
        white_turn_log = new TurnRecord[0];
        black_turn_log = new TurnRecord[0];
        remaining_dice = new int[0];
        current_turn_dice = new TurnDie[0];
        cached_legal_options = new MoveOption[0];
        move_history = new MoveSnapshot[0];
        board = GameBoard.in_tray ();

        init_player_names ();

        if (SettingsStore.shared ().is_first_move_rolloff_enabled) {
            is_first_move_rolloff_in_progress = true;
            rolloff_active_player = CheckerColor.WHITE;
            status_message = Localization.status_rolloff_prompt ();
        } else {
            is_first_move_rolloff_in_progress = false;
            rolloff_active_player = null;
            status_message = Localization.status_new_game ();
        }

        // При смене настроек (язык интерфейса, имена игроков, сторона доски) актуализируем статус партии
        SettingsStore.shared ().changed.connect (() => {
            var old_status = status_message;
            update_status_on_language_change ();
            if (!is_game_started) {
                board = GameBoard.in_tray ();
            }
            if (old_status != status_message || !is_game_started) {
                notify_changed ();
            }
        });
    }

    internal void notify_changed () {
        changed ();
    }

    // MARK: - Асинхронные помощники

    /** Асинхронная пауза (аналог Task.sleep). */
    internal async void sleep_async (double seconds) {
        SourceFunc cb = sleep_async.callback;
        var ms = (uint) (seconds * 1000.0);
        Timeout.add (ms, () => {
            cb ();
            return Source.REMOVE;
        });
        yield;
    }

    /** Отложенное действие (аналог DispatchQueue.main.asyncAfter). Отменяется при смене партии. */
    internal void after (double seconds, owned DelayedCallback fn) {
        var g = gen;
        Timeout.add ((uint) (seconds * 1000.0), () => {
            if (g == gen) {
                fn ();
            }
            return Source.REMOVE;
        });
    }

    internal void cancel_all_tasks () {
        gen++;
        auto_end_token++;
        is_placing_checkers = false;
        placement_animator.cancel ();
    }

    // MARK: - Вычисляемые свойства

    public bool should_show_white_die {
        get {
            if (is_first_move_rolloff_in_progress) {
                return white_rolloff_dice != null || (is_rolling && rolling_die_index == 0);
            }
            return dice_roll != null || is_rolling || is_doubling;
        }
    }

    public bool should_show_black_die {
        get {
            if (is_first_move_rolloff_in_progress) {
                return black_rolloff_dice != null || (is_rolling && rolling_die_index == 1);
            }
            return dice_roll != null || is_rolling || is_doubling;
        }
    }

    public int white_pip_count {
        get { return calculate_pip_count (CheckerColor.WHITE); }
    }

    public int black_pip_count {
        get { return calculate_pip_count (CheckerColor.BLACK); }
    }

    public bool is_black_computer {
        get { return SettingsStore.shared ().is_black_computer; }
    }

    /** Ход компьютера (чёрные против компьютера). */
    public bool is_computer_turn {
        get {
            if (is_first_move_rolloff_in_progress) {
                if (rolloff_active_player != null) {
                    return rolloff_active_player == CheckerColor.BLACK && is_black_computer;
                }
            }
            return current_player == CheckerColor.BLACK && is_black_computer;
        }
    }

    /** Проверяет возможность текущего игрока выполнить бросок костей. */
    public bool can_roll {
        get {
            if (!is_game_started || dice_roll != null || is_rolling || is_doubling || is_no_moves_flashing || is_game_over || is_animating) {
                return false;
            }
            if (is_first_move_rolloff_in_progress) {
                if (white_rolloff_dice != null && black_rolloff_dice != null) {
                    return true;
                }
                if (rolloff_active_player == null) {
                    return false;
                }
                return rolloff_active_player == CheckerColor.WHITE ? white_rolloff_dice == null : black_rolloff_dice == null;
            }
            return true;
        }
    }

    /** Доступна ли отмена последнего полухода в текущем раунде. */
    public bool can_undo {
        get {
            return !is_animating && move_history.length > 0 && !is_game_over
                   && !is_computer_turn && remaining_dice.length > 0;
        }
    }

    /** Определяет необходимость отображения интерактивного курсора-кубика на доске. */
    public bool show_dice_cursor {
        get {
            var is_rolloff_resolving = is_first_move_rolloff_in_progress
                && white_rolloff_dice != null && black_rolloff_dice != null;
            return can_roll && !is_computer_turn && !suppress_dice_cursor && !is_rolloff_resolving;
        }
    }

    public bool is_game_in_progress {
        get { return is_game_started && !is_placing_checkers && !is_game_over && !showing_game_over_result; }
    }

    /** Ходы подсвеченной записи лога. */
    public LogMove[] active_log_moves () {
        if (highlighted_log_id < 0) {
            return new LogMove[0];
        }
        foreach (var r in white_turn_log) {
            if (r.id == highlighted_log_id) {
                return r.moves;
            }
        }
        foreach (var r in black_turn_log) {
            if (r.id == highlighted_log_id) {
                return r.moves;
            }
        }
        return new LogMove[0];
    }

    /** Цвет игрока, которому принадлежит запись лога с указанным id. */
    public bool find_log_record (int id, out TurnRecord? record, out CheckerColor color) {
        foreach (var r in white_turn_log) {
            if (r.id == id) {
                record = r;
                color = CheckerColor.WHITE;
                return true;
            }
        }
        foreach (var r in black_turn_log) {
            if (r.id == id) {
                record = r;
                color = CheckerColor.BLACK;
                return true;
            }
        }
        record = null;
        color = CheckerColor.WHITE;
        return false;
    }

    /** Точки, затронутые подсвеченной записью лога. */
    public BoardPoint[] log_highlight_points () {
        var result = new BoardPoint[0];
        foreach (var m in active_log_moves ()) {
            foreach (var s in m.steps) {
                if (!contains_point (result, s.from)) {
                    result += s.from;
                }
                if (s.to != null && !contains_point (result, s.to)) {
                    result += s.to;
                }
            }
        }
        return result;
    }

    internal static bool contains_point (BoardPoint[] arr, BoardPoint p) {
        foreach (var x in arr) {
            if (x == p) {
                return true;
            }
        }
        return false;
    }

    /** Можно ли вынести выбранную фишку. */
    public bool can_bear_off_selected {
        get {
            if (selected_point == null) {
                return false;
            }
            foreach (var o in options_from (selected_point)) {
                if (o.to == null) {
                    return true;
                }
            }
            return false;
        }
    }

    /** Все точки назначения (для подсветки). */
    public BoardPoint[] target_points () {
        var result = new BoardPoint[0];
        if (selected_point == null) {
            return result;
        }
        foreach (var o in options_from (selected_point)) {
            if (o.to != null && !o.is_illegal_prime && !contains_point (result, o.to)) {
                result += o.to;
            }
        }
        return result;
    }

    /** Потенциальные точки назначения (включая заблокированные). */
    public BoardPoint[] potential_targets () {
        var result = new BoardPoint[0];
        if (selected_point == null || remaining_dice.length == 0) {
            return result;
        }
        foreach (var die in remaining_dice) {
            var target = PlayerPath.point_from (selected_point, die, current_player);
            if (target != null && !contains_point (result, target)) {
                result += target;
            }
        }
        return result;
    }

    // MARK: - Pip Count

    public int calculate_pip_count (CheckerColor color) {
        if (!is_game_started || is_placing_checkers) {
            return 360;
        }
        unowned BoardPoint[] route = PlayerPath.route_ref (color);
        var total = 0;
        for (var i = 0; i < route.length; i++) {
            var stack = board.stack_at (route[i]);
            if (stack != null && stack.color == color) {
                total += stack.checker_ids.length * (route.length - i);
            }
        }
        return total;
    }

    public double progress_percentage (CheckerColor color) {
        var pips = (double) calculate_pip_count (color);
        var progress = (1.0 - (pips / 360.0)) * 100.0;
        return double.min (100.0, double.max (0.0, progress));
    }

    public double white_progress { get { return progress_percentage (CheckerColor.WHITE); } }
    public double black_progress { get { return progress_percentage (CheckerColor.BLACK); } }

    /** Количество фишек вынесенных за борт цветом. */
    public int borne_off_count_for (CheckerColor color) {
        return board.borne_off_count (color);
    }

    // MARK: - Доступные ходы

    public MoveOption[] options_from (BoardPoint point) {
        var result = new MoveOption[0];
        if (remaining_dice.length == 0) {
            return result;
        }
        foreach (var o in cached_legal_options) {
            if (o.from == point) {
                result += o;
            }
        }
        return result;
    }

    // MARK: - Выбор точки (аналог didSet у selectedPoint)

    /** Устанавливает выбранную точку с фишкой; при сбросе обновляет подсказку статуса. */
    public void set_selected_point (BoardPoint? point) {
        if (selected_point != point) {
            hovered_target_point = null;
            is_hovering_bear_off_target = false;
        }
        selected_point = point;
        if (selected_point == null && dice_roll != null && remaining_dice.length > 0 && !is_animating
            && !is_game_over && !is_rolling && !is_computer_turn) {
            status_message = Localization.status_select_checker ();
        }
    }

    /** Сброс выбора фишки (клик по пустому месту / по панели). */
    public void select_point_none () {
        hovered_target_point = null;
        is_hovering_bear_off_target = false;
        if (selected_point != null) {
            set_selected_point (null);
            notify_changed ();
        }
    }

    // MARK: - Управление показом экрана победы

    /** Управляет отображением финального экрана завершения партии. */
    public void set_showing_game_over_result (bool value) {
        var old = showing_game_over_result;
        showing_game_over_result = value;
        if (!value && old) {
            is_game_started = false;
        }
        notify_changed ();
    }

    public void set_game_started (bool value) {
        is_game_started = value;
        notify_changed ();
    }

    // MARK: - Кубики текущего хода

    public void consume_die (int value) {
        foreach (var d in current_turn_dice) {
            if (!d.is_used && !d.is_skipped && d.value == value) {
                d.is_used = true;
                break;
            }
        }
        if (current_turn_record != null) {
            foreach (var d in current_turn_record.dice) {
                if (!d.is_used && !d.is_skipped && d.value == value) {
                    d.is_used = true;
                    break;
                }
            }
        }
    }

    internal static int[] move_values (DiceRoll roll) {
        if (roll.is_double) {
            return { roll.die1, roll.die1, roll.die1, roll.die1 };
        }
        return { roll.die1, roll.die2 };
    }

    internal static int sum_ints (int[] a) {
        var s = 0;
        foreach (var v in a) {
            s += v;
        }
        return s;
    }

    internal static bool same_roll (DiceRoll? a, DiceRoll? b) {
        if (a == null || b == null) {
            return a == b;
        }
        return a.die1 == b.die1 && a.die2 == b.die2;
    }

    internal static int[] remove_at (int[] arr, int index) {
        var result = new int[0];
        for (var i = 0; i < arr.length; i++) {
            if (i != index) {
                result += arr[i];
            }
        }
        return result;
    }

    internal static int index_of (int[] arr, int value) {
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                return i;
            }
        }
        return -1;
    }

    internal static int[] copy_int_array (int[] src) {
        var copy = new int[src.length];
        for (var i = 0; i < src.length; i++) {
            copy[i] = src[i];
        }
        return copy;
    }

    internal static int[] sorted_desc (int[] src) {
        var a = copy_int_array (src);
        for (var i = 0; i < a.length; i++) {
            for (var j = i + 1; j < a.length; j++) {
                if (a[j] > a[i]) {
                    var t = a[i];
                    a[i] = a[j];
                    a[j] = t;
                }
            }
        }
        return a;
    }

    /** Удаляет использованные кубики по индексам (от большего к меньшему) и отмечает их в текущем ходе. */
    internal void remove_used_dice (int[] indices) {
        foreach (var index in sorted_desc (indices)) {
            if (index < remaining_dice.length) {
                var val = remaining_dice[index];
                remaining_dice = remove_at (remaining_dice, index);
                consume_die (val);
            }
        }
    }

    /** Удаляет первый кубик с указанным значением (для поэтапной анимации). */
    internal void remove_die_by_value (int value) {
        var idx = index_of (remaining_dice, value);
        if (idx >= 0) {
            remaining_dice = remove_at (remaining_dice, idx);
            consume_die (value);
        }
    }

    internal void insert_log_record (CheckerColor color, TurnRecord record) {
        if (color == CheckerColor.WHITE) {
            var arr = new TurnRecord[0];
            arr += record;
            foreach (var r in white_turn_log) {
                arr += r;
            }
            white_turn_log = arr;
        } else {
            var arr = new TurnRecord[0];
            arr += record;
            foreach (var r in black_turn_log) {
                arr += r;
            }
            black_turn_log = arr;
        }
    }

    internal static int non_rolloff_count (TurnRecord[] log) {
        var n = 0;
        foreach (var r in log) {
            if (!r.is_rolloff && r.game_result_is_win == null) {
                n++;
            }
        }
        return n;
    }

    // MARK: - Жизненный цикл: конец хода, новая игра, форсированный сброс

    public void end_turn () {
        GameLifecycleController.end_turn (this);
    }

        public delegate void PlacementCompletion ();

    /**
     * Анимированно перемещает все находящиеся на доске фишки в накопители.
     * Фишки последовательно снимаются сверху стопок на пунктах доски и укладываются в накопители снизу вверх.
     */
    public void animate_checkers_to_tray (owned PlacementCompletion? completion = null) {
        placement_animator.animate_checkers_to_tray (this, (owned) completion);
    }

    /** Сброс партии без старта новой (после подтверждения «Новая игра»). */
    public void force_new_game (
        bool record_abandonment = true,
        bool animated = false,
        owned PlacementCompletion? completion = null
    ) {
        GameLifecycleController.force_new_game (this, record_abandonment, animated, (owned) completion);
    }

    /** Новая партия. */
    public void new_game (bool silent = false, bool animated = true) {
        GameLifecycleController.new_game (this, silent, animated);
    }

        /** Анимирует последовательную расстановку фишек на доске. */
    public void animate_placement (
        GameBoard target_board,
        bool play_placement_sound = true,
        bool play_new_game_sound_on_completion = false,
        owned PlacementCompletion? completion = null
    ) {
        placement_animator.animate_placement (this, target_board, play_placement_sound, play_new_game_sound_on_completion, (owned) completion);
    }

    internal void reset_stats () {
        white_moves_count = 0;
        black_moves_count = 0;
        white_doubles_count = 0;
        black_doubles_count = 0;
        white_total_dice_sum = 0;
        black_total_dice_sum = 0;
        white_burned_dice_sum = 0;
        black_burned_dice_sum = 0;
    }

    // MARK: - Вспомогательные методы

    public string player_name (CheckerColor color) {
        return color == CheckerColor.WHITE ? white_player_name : black_player_name;
    }

    public bool is_computer_player (CheckerColor color) {
        return color == CheckerColor.BLACK && is_black_computer;
    }

    public void init_player_names () {
        var store = SettingsStore.shared ();
        if (store.opponent == Opponent.COMPUTER) {
            white_player_name = store.white_player_name.strip () == ""
                ? Localization.default_player_name () : store.white_player_name;
            black_player_name = Localization.settings_opponent_computer ();
        } else {
            white_player_name = store.white_player_name.strip () == ""
                ? Localization.default_player1_name () : store.white_player_name;
            black_player_name = store.black_player_name.strip () == ""
                ? Localization.default_player2_name () : store.black_player_name;
        }
    }

    public void update_status_on_language_change () {
        init_player_names ();
        if (is_game_over) {
            status_message = (current_player == CheckerColor.WHITE) ? Localization.victory_white () : Localization.victory_black ();
        } else if (is_first_move_rolloff_in_progress) {
            if (white_rolloff_dice != null && black_rolloff_dice != null) {
                var w_sum = white_rolloff_dice.die1 + white_rolloff_dice.die2;
                var b_sum = black_rolloff_dice.die1 + black_rolloff_dice.die2;
                if (w_sum == b_sum) {
                    status_message = Localization.status_rolloff_tie ();
                } else {
                    var winner = w_sum > b_sum ? CheckerColor.WHITE : CheckerColor.BLACK;
                    status_message = Localization.status_rolloff_result (player_name (winner));
                }
            } else {
                status_message = is_computer_turn ? Localization.status_rolloff_ai () : Localization.status_rolloff_prompt ();
            }
        } else if (dice_roll == null) {
            status_message = is_computer_turn ? Localization.status_computer_moving () : Localization.status_roll_dice ();
        } else if (is_animating && is_computer_turn) {
            status_message = Localization.status_computer_moving ();
        } else {
            status_message = (selected_point == null) ? Localization.status_select_checker () : Localization.status_select_target ();
        }
    }

    // MARK: - Запись в лог (GameSession+Log)

    /** Записывает выполненный ход в текущую запись лога. */
    public void record_move_in_log (MoveOption move, IntermediateStep[] steps) {
        GameLogExporter.record_move_in_log (this, move, steps);
    }

    /** Обновляет кэш легальных ходов по текущему состоянию. */
    public void update_available_moves_cache () {
        if (remaining_dice.length == 0) {
            cached_legal_options = new MoveOption[0];
            return;
        }
        var is_first_turn = (current_player == CheckerColor.WHITE) ? is_white_first_turn : is_black_first_turn;
        var all = MoveValidator.all_moves (
            board,
            current_player,
            remaining_dice,
            checkers_moved_from_head_this_turn,
            dice_roll != null && dice_roll.is_double,
            is_first_turn);
        cached_legal_options = MoveValidator.filter_legal_moves (
            all, board, current_player, remaining_dice,
            checkers_moved_from_head_this_turn,
            dice_roll != null && dice_roll.is_double,
            is_first_turn);
    }

    /** Строка текущих кубиков: "3, 5" и т.п. */
    public string current_dice_string () {
        var parts = new string[remaining_dice.length];
        for (var i = 0; i < remaining_dice.length; i++) {
            parts[i] = remaining_dice[i].to_string ();
        }
        return string.joinv (", ", parts);
    }

    /** Имя текущего игрока-человека (при ходе компьютера — имя его соперника). */
    public string current_human_player_name {
        owned get {
            if (is_computer_player (current_player)) {
                return player_name (current_player.opposite ());
            }
            return player_name (current_player);
        }
    }

    /** Завершение партии: фиксация победы, запись статистики и отложенный показ итогового окна. */
    public void handle_delayed_victory () {
        GameLifecycleController.handle_delayed_victory (this);
    }

        // MARK: - Бросок кубиков (GameSession+RollDice)

    /** Основной метод броска кубиков. */
    public void roll_dice () {
        DiceController.roll_dice (this);
    }

    public void apply_dice_roll (DiceRoll roll) {
        DiceController.apply_dice_roll (this, roll);
    }

    internal async void handle_rolloff_tie (DiceRoll w_roll, DiceRoll b_roll, uint g) {
        yield DiceController.handle_rolloff_tie (this, w_roll, b_roll, g);
    }

    internal async void handle_rolloff_win (CheckerColor winner, DiceRoll w_roll, DiceRoll b_roll, uint g) {
        yield DiceController.handle_rolloff_win (this, winner, w_roll, b_roll, g);
    }

    /** Автобросок компьютера после задержки. */
    public void auto_play_if_needed () {
        ComputerTurnController.auto_play_if_needed (this);
    }

    // MARK: - Ход компьютера (GameSession+Computer)

    /** Полный цикл хода компьютера. */
    public async void perform_computer_turn (uint g) {
        yield ComputerTurnController.perform_computer_turn (this, g);
    }

    /** Проверяет после хода, нужно ли автоматически завершить ход. */
    public void check_and_auto_end_turn () {
        GameLifecycleController.check_and_auto_end_turn (this);
    }

    /** Отложенное завершение хода. Проверяет, что состояние игры не изменилось за время ожидания. */
    public void trigger_auto_end_turn (double delay, DiceRoll? current_roll) {
        GameLifecycleController.trigger_auto_end_turn (this, delay, current_roll);
    }

        // MARK: - Логика ходов игрока (GameSession+Moves)

    /** Применяет одиночный ход: перемещает фишку, записывает в лог, обновляет кэш. */
    public void apply (MoveOption move, bool is_dragged = false) {
        MoveController.apply (this, move, is_dragged);
    }

    /** Разбивает составной ход на промежуточные шаги (по одному кубику). */
    public IntermediateStep[] intermediate_steps (MoveOption move) {
        return MoveController.intermediate_steps (this, move);
    }

    /** Завершится ли ход игрока после указанного перемещения. */
    public bool will_turn_end_after (MoveOption move) {
        return MoveController.will_turn_end_after (this, move);
    }

    /** Обрабатывает клик игрока по ячейке доски. */
    public void select (BoardPoint point) {
        MoveController.select (this, point);
    }

    /** Быстрый ход (двойной клик): вынос за борт или ближайшая точка. */
    public void quick_move (BoardPoint point) {
        MoveController.quick_move (this, point);
    }

    /** Основной метод перемещения фишки from → to. */
    public void apply_move (BoardPoint to, BoardPoint from, bool is_dragged = false) {
        MoveController.apply_move (this, to, from, is_dragged);
    }

    /** Вынос выбранной фишки за борт. */
    public void bear_off_selected (bool is_dragged = false) {
        MoveController.bear_off_selected (this, is_dragged);
    }

    /** Сохраняет снимок состояния для отмены хода (только для игрока). */
    public void save_snapshot () {
        MoveController.save_snapshot (this);
    }

    // MARK: - Отмена хода (GameSession+Undo)

    public void undo_move () {
        MoveController.undo_move (this);
    }

    // MARK: - Генерация текста лога партии

    /** Имя игрока на английском для логов (GameLogStore). */
    public string english_player_name (CheckerColor color) {
        return GameLogExporter.english_player_name (color);
    }

    /** Текстовый дамп состояния на английском (для GameLogStore). */
    public string generate_log_text () {
        return GameLogExporter.generate_log_text (this);
    }

    /** Сохраняет лог завершённой партии в GameLogStore. */
    public void save_game_log () {
        GameLogExporter.save_game_log (this);
    }

    /** Локализованный дамп состояния (для копирования в буфер обмена). */
    public string debug_export_text () {
        return GameLogExporter.debug_export_text (this);
    }

    /** После копирования отладочной информации — временное сообщение в статусе (2 с). */
    public void show_debug_copied_status () {
        var old_status = status_message;
        status_message = Localization.debug_export_success_prefix () + Localization.debug_export_success ();
        notify_changed ();
        after (2.0, () => {
            status_message = old_status;
            notify_changed ();
        });
    }

    // MARK: - Сохранение и форфейт при закрытии

    public void save_on_close () {
        GameSessionStorage.save_on_close (this);
    }

    /** Завершает текущую игру форфейтом: текущий игрок проигрывает. */
    public void forfeit_current_game () {
        GameSessionStorage.forfeit_current_game (this);
    }

    /** Сохраняет текущее состояние игры в SavedGameStore. */
    public void save_to_store () {
        GameSessionStorage.save_to_store (this);
    }

    /** Восстанавливает игру из структуры сохранённых данных партии. */
    public void restore_from_store (SavedGameData data) {
        GameSessionStorage.restore_from_store (this, data);
    }

    /** Настройка тестовой расстановки перед победным ходом дублем 2-2. */
    public void setup_test_last_move () {
        GameSessionStorage.setup_test_last_move (this);
    }
}

} /* namespace Longbackgammon */
