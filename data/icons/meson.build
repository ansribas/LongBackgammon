application_id = 'org.gnome.longbackgammon'

scalable_dir = 'hicolor' / 'scalable' / 'apps'
install_data(
  scalable_dir / ('@0@.svg').format(application_id),
  install_dir: get_option('datadir') / 'icons' / scalable_dir
)

symbolic_dir = 'hicolor' / 'symbolic' / 'apps'
install_data(
  symbolic_dir / ('@0@-symbolic.svg').format(application_id),
  install_dir: get_option('datadir') / 'icons' / symbolic_dir
)

icon_sizes = ['16x16', '24x24', '32x32', '48x48', '64x64', '128x128', '256x256', '512x512']
foreach size : icon_sizes
  size_dir = 'hicolor' / size / 'apps'
  install_data(
    size_dir / ('@0@.png').format(application_id),
    install_dir: get_option('datadir') / 'icons' / size_dir
  )
endforeach

install_data(
  'hicolor' / '64x64' / 'apps' / ('@0@.png').format(application_id),
  install_dir: get_option('datadir') / 'app-info' / 'icons' / 'flatpak' / '64x64'
)
install_data(
  'hicolor' / '128x128' / 'apps' / ('@0@.png').format(application_id),
  install_dir: get_option('datadir') / 'app-info' / 'icons' / 'flatpak' / '128x128'
)


