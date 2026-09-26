project('taskly', 'vala', 'c',
  version: '1.0.0',
  meson_version: '>= 0.59.0',
  default_options: ['warning_level=2'])

gnome = import('gnome')

vala_deps = [
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('sqlite3'),
  dependency('libnotify'),
]

sources = files(
  'src/models.vala',
  'src/config.vala',
  'src/dateparser.vala',
  'src/i18n.vala',
  'src/palette.vala',
  'src/database.vala',
  'src/clijson.vala',
  'src/cli.vala',
  'src/cliinstaller.vala',
  'src/reminder.vala',
  'src/ui.vala',
  'src/calendarview.vala',
  'src/dialogs.vala',
  'src/taskly.vala',
)

i18n_resources = [
  'resources/i18n/zh.json',
  'resources/i18n/en.json',
]

executable('taskly', sources,
  vala_args: ['--target-glib=2.72', '--pkg=posix'],
  dependencies: vala_deps,
  install: true)

# i18n tables (byte-identical copies of shared/i18n), installed next to the
# binary's data dir; the loader also checks the source dir for dev runs.
install_data(i18n_resources,
  install_dir: get_option('prefix') / get_option('datadir') / 'taskly' / 'i18n')

# Desktop entry + app icon + metainfo
install_data('resources/taskly.desktop',
  install_dir: get_option('prefix') / get_option('datadir') / 'applications')
install_data('resources/taskly.svg',
  install_dir: get_option('prefix') / get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
  rename: ['app.taskly.Taskly.svg'])
install_data('flatpak/app.metainfo.xml',
  install_dir: get_option('prefix') / get_option('datadir') / 'metainfo',
  rename: ['app.taskly.Taskly.metainfo.xml'])

# ---- contract tests (date parser, flat-JSON i18n, CLI JSON escaping) ----

test_sources = files(
  'src/models.vala',
  'src/config.vala',
  'src/dateparser.vala',
  'src/i18n.vala',
  'src/palette.vala',
  'src/database.vala',
  'src/clijson.vala',
  'tests/core-test.vala',
)

test('core-contract', executable('taskly-core-test', test_sources,
  vala_args: ['--target-glib=2.72', '--pkg=posix'],
  dependencies: vala_deps),
  env: ['TASKLY_I18N_DIR=' + meson.current_source_dir() / 'resources' / 'i18n'])
