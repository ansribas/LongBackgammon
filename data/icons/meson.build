application_id = 'io.github.ansribas.LongBackgammon'

icon_sizes = ['16x16', '24x24', '32x32', '48x48', '64x64', '128x128', '256x256', '512x512']
foreach size : icon_sizes
  size_dir = 'hicolor' / size / 'apps'
  install_data(
    size_dir / ('@0@.png').format(application_id),
    install_dir: get_option('datadir') / 'icons' / size_dir
  )
endforeach


