// Taskly — install-cli/uninstall-cli: shell wrapper at ~/.local/bin/taskly +
// idempotent PATH block in ~/.zshrc (macOS) / ~/.bashrc (Linux).

namespace Taskly {

public class CliInstaller : Object {

    private static string bin_dir() {
        return Path.build_filename(Config.home_directory(), ".local", "bin");
    }

    private static string link_path() {
        return Path.build_filename(bin_dir(), "taskly");
    }

    public static int install() {
        var exe = "";
        try {
            exe = GLib.FileUtils.read_link("/proc/self/exe");
        } catch (Error e) {
            exe = "";
        }
        if (exe.length == 0) {
            exe = Environment.find_program_in_path("taskly") ?? "taskly";
        }

        var dir = bin_dir();
        var link = link_path();
        DirUtils.create_with_parents(dir, 0755);

        var script = "#!/bin/sh\nexec \"%s\" \"$@\"\n".printf(exe.replace("\"", "\\\""));
        try {
            FileUtils.set_contents(link, script);
        } catch (Error e) {
            stderr.printf("Install failed: %s\n", e.message);
            return 1;
        }
        Posix.chmod(link, 493); // 0755 octal

        var needs_restart = false;
        if (!path_contains_bin_dir()) {
            needs_restart = ensure_path_in_shell_rc();
        }

        print("taskly command installed to %s\n", link);
        if (needs_restart) {
            print("\nPlease open a new terminal window for the PATH change to take effect.\n");
        }
        return 0;
    }

    public static int uninstall() {
        var link = link_path();
        if (!FileUtils.test(link, FileTest.EXISTS)) {
            stderr.printf("taskly command was not installed (nothing to remove).\n");
            return 1;
        }
        if (FileUtils.remove(link) != 0) {
            stderr.printf("Uninstall failed: cannot remove %s\n", link);
            return 1;
        }
        print("taskly command removed from %s\n", link);
        return 0;
    }

    private static bool path_contains_bin_dir() {
        var path = Environment.get_variable("PATH") ?? "";
        foreach (var entry in path.split(":")) {
            if (entry == bin_dir()) {
                return true;
            }
        }
        return false;
    }

    private static bool ensure_path_in_shell_rc() {
        var rc = Path.build_filename(Config.home_directory(), ".zshrc");
        var marker = "# Added by Taskly";
        string content = "";
        try {
            FileUtils.get_contents(rc, out content);
        } catch (Error e) {
            content = "";
        }
        if (content.contains(marker) || content.contains(".local/bin")) {
            return false;
        }

        var block = "\n# Added by Taskly\nexport PATH=\"$HOME/.local/bin:$PATH\"\n";
        var updated = (content.length == 0 || content.has_suffix("\n"))
            ? content + block
            : content + "\n" + block;
        try {
            FileUtils.set_contents(rc, updated);
            return true;
        } catch (Error e) {
            return false;
        }
    }
}

}
