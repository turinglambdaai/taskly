// Taskly entry point. Dual-mode contract: ANY argument routes to the CLI
// before any GTK initialization (headless-safe); no arguments opens the GUI.

namespace Taskly {

public class TasklyApp : Adw.Application {

    public TasklyApp() {
        Object(application_id: "app.taskly.Taskly", flags: GLib.ApplicationFlags.FLAGS_NONE);
    }

    protected override void activate() {
        // Keep one window per process (second launch focuses nothing new).
        unowned GLib.List<Gtk.Window> windows = get_windows();
        if (windows.length() > 0) {
            windows.nth_data(0).present();
            return;
        }

        var config = new Config();
        var i18n = new I18n(config.language());
        var db = new SQLiteDatabase();

        var last = config.last_db_path();
        db.set_database_path(last ?? Config.default_database_path());
        try {
            db.ensure_connected();
        } catch (GLib.Error e) {
            stderr.printf("Cannot open database: %s\n", e.message);
        }

        var ctx = new AppContext(db, i18n, config);
        var ui = new TasklyUi(ctx);
        ui.build(this);
    }

    public static int main(string[] args) {
        // CLI: subcommands run headless, before any Adw/GTK initialization.
        if (args.length > 1) {
            string[] cli_args = args[1:args.length];
            return CliEngine.run(cli_args);
        }

        // Force the dark/light scheme to follow the desktop; the warm palette
        // applies via CSS on top of the native Adwaita widgets.
        var app = new TasklyApp();
        return app.run(args);
    }
}

}
