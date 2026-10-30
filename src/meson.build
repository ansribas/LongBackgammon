longbackgammon_logic_sources = files(
  'logic/storage.vala',
  'logic/localization_manager.vala',
  'logic/models.vala',
  'logic/game_config.vala',
  'logic/player_path.vala',
  'logic/game_board.vala',
  'logic/move_validator.vala',
  'logic/ai_weights.vala',
  'logic/computer_ai.vala',
  'logic/advanced_ai.vala',
  'logic/turn_record.vala',
  'logic/settings_store.vala',
  'logic/stats_store.vala',
  'logic/game_log_store.vala',
  'logic/saved_game_store.vala',
  'logic/game_session.vala',
  'logic/sound_manager.vala',
  'ui/board_layout.vala',
)

longbackgammon_ui_sources = files(
  'ui/dice_drawing.vala',
  'ui/dice_overlay.vala',
  'ui/board_view.vala',
  'ui/player_panel.vala',
  'ui/log_views.vala',
  'ui/player_dice_zone.vala',
  'ui/player_score_block.vala',
  'ui/ui_kit.vala',
  'ui/popup_view.vala',
  'ui/settings_view.vala',
  'ui/rules_view.vala',
  'ui/statistics_view.vala',
  'ui/new_game_dialogs.vala',
  'ui/game_over_view.vala',
)

longbackgammon_common_sources = longbackgammon_logic_sources + longbackgammon_ui_sources

longbackgammon_resources = gnome.compile_resources('longbackgammon-resources',
  'longbackgammon.gresource.xml',
  c_name: 'longbackgammon',
  source_dir: [meson.current_source_dir(), meson.project_source_root() / 'data']
)

longbackgammon_sources = files(
  'main.vala',
  'application.vala',
  'window.vala',
) + longbackgammon_common_sources + [longbackgammon_resources]

longbackgammon_deps = [
  config_dep,
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gtk4'),
  dependency('libadwaita-1', version: '>= 1.4'),
]

executable('longbackgammon', longbackgammon_sources,
  dependencies: longbackgammon_deps,
  include_directories: config_inc,
  install: true,
  link_args: ['-lm'],
)
