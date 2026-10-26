# tests/meson.build

# 1. Регрессионный тест правил и алгоритмов логики
logic_test = executable('longbackgammon-logic-test',
  longbackgammon_logic_sources + files('logic_test.vala'),
  dependencies: longbackgammon_deps,
  include_directories: config_inc,
  link_args: ['-lm'],
)
test('logic-test', logic_test, workdir: meson.project_source_root())

# 2. Тест игровой сессии: полные партии, ходы ИИ и лог ходов
session_test = executable('longbackgammon-session-test',
  longbackgammon_logic_sources + files('session_test.vala'),
  dependencies: [config_dep, dependency('glib-2.0'), dependency('gio-2.0')],
  include_directories: config_inc,
  link_args: ['-lm'],
)
test('session-test', session_test, workdir: meson.project_source_root(), timeout: 120)

# 3. UI-тест интерактивности доски (BoardView)
ui_test = executable('longbackgammon-ui-test',
  longbackgammon_common_sources + files('ui_test.vala') + [longbackgammon_resources],
  dependencies: longbackgammon_deps,
  include_directories: config_inc,
  link_args: ['-lm'],
)

display_present = run_command('sh', '-c', 'test -n "$DISPLAY" || test -n "$WAYLAND_DISPLAY"', check: false).returncode() == 0
xvfb_run = find_program('xvfb-run', required: false)
if display_present
  test('ui-test', ui_test, workdir: meson.project_source_root(), is_parallel: false, timeout: 60)
elif xvfb_run.found()
  test('ui-test', xvfb_run, args: ['-a', ui_test], workdir: meson.project_source_root(), timeout: 60)
endif
