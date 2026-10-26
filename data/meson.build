desktop_file = i18n.merge_file(
        input: 'org.gnome.longbackgammon.desktop.in',
       output: 'org.gnome.longbackgammon.desktop',
         type: 'desktop',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'applications'
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

appstream_file = i18n.merge_file(
        input: 'org.gnome.longbackgammon.metainfo.xml.in',
       output: 'org.gnome.longbackgammon.metainfo.xml',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'metainfo'
)

appstreamcli = find_program('appstreamcli', required: false, disabler: true)
test('Validate appstream file', appstreamcli,
     args: ['validate', '--no-net', '--explain', appstream_file])

install_data('org.gnome.longbackgammon.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

compile_schemas = find_program('glib-compile-schemas', required: false, disabler: true)
test('Validate schema file',
     compile_schemas,
     args: ['--strict', '--dry-run', meson.current_source_dir()])


service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'org.gnome.longbackgammon.service.in',
  output: 'org.gnome.longbackgammon.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

# Звуковые эффекты
install_data(
  'sounds/checkermove.wav',
  'sounds/diceroll01.wav',
  'sounds/diceroll02.wav',
  'sounds/diceroll03.wav',
  'sounds/newgame.wav',
  'sounds/placement_step.wav',
  'sounds/victory.wav',
  install_dir: get_option('datadir') / 'longbackgammon' / 'sounds'
)

# Изображения доски и фишек (темы оформления: «Дерево» и «Мрамор»)
install_data(
  'images/board.png',
  'images/white.png',
  'images/black.png',
  'images/dicecursor.png',
  'images/marble_board.png',
  'images/marble_white.png',
  'images/marble_black.png',
  'images/marble_dicecursor.png',
  'images/wood_board.png',
  'images/wood_white.png',
  'images/wood_black.png',
  'images/wood_dicecursor.png',
  install_dir: get_option('datadir') / 'longbackgammon' / 'images'
)

# Файлы локализации (en.json, ru.json, etc.)
install_data(
  'translations/az.json',
  'translations/de.json',
  'translations/en.json',
  'translations/es.json',
  'translations/fr.json',
  'translations/hy.json',
  'translations/it.json',
  'translations/ka.json',
  'translations/kk.json',
  'translations/ru.json',
  'translations/tg.json',
  'translations/tk.json',
  'translations/tr.json',
  'translations/uz.json',
  install_dir: get_option('datadir') / 'longbackgammon' / 'translations'
)

subdir('icons')

