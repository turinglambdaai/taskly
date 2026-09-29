// Taskly — online update service (contract: shared/spec/UPDATE.md).
// Feed: update-manifest.json from the latest GitHub Release; integrity:
// sha256 over HTTPS (see UPDATE.md platform table — Ed25519 lands with
// gnutls bindings). Install: tarball → checksum → replace prefix in place
// when writable, otherwise open the releases page.

namespace Taskly {

public class Updater : Object {
    public const string RELEASES_API = "https://api.github.com/repos/turinglambdaai/taskly/releases/latest";
    public const string RELEASES_PAGE = "https://github.com/turinglambdaai/taskly/releases/latest";

    private Soup.Session session;
    private unowned I18n i18n;
    private unowned Config config;
    public bool busy { get; private set; default = false; }

    public Updater(I18n i18n, Config config) {
        this.i18n = i18n;
        this.config = config;
        this.session = new Soup.Session();
        session.user_agent = "Taskly/" + APP_VERSION + " (update-check)";
        session.timeout = 30;
    }

    public struct Manifest {
        public string version;
        public string url;
        public string sha256;
    }

    // MARK: - Check (async, UI-safe)

    /// Silent throttle: at most one launch check per 4 h (config
    /// last-update-check, unix seconds). Returns the manifest when a newer
    /// version exists, null when up to date; throws on hard failures
    /// (callers swallow in silent mode, report in manual mode).
    public async Manifest? check(bool manual) throws Error {
        if (busy) {
            return null;
        }
        var now = (int64) (new DateTime.now_utc().to_unix());
        var last = int64.parse(config.get_value("last-update-check") ?? "0");
        if (!manual && now - last < 4 * 3600) {
            return null;
        }
        config.set_value("last-update-check", now.to_string());
        config.save();

        busy = true;
        try {
            var release_body = yield download_string(RELEASES_API);
            var manifest_url = release_asset_url(release_body, "update-manifest.json");
            if (manifest_url == null) {
                throw new UpdaterError.NO_MANIFEST("release has no update manifest");
            }
            var manifest_body = yield download_string(manifest_url);
            var manifest = parse_manifest(manifest_body);
            if (!version_newer(manifest.version, APP_VERSION)) {
                return null;
            }
            return manifest;
        } finally {
            busy = false;
        }
    }

    /// Download the artifact, verify its sha256, then either replace the
    /// current prefix in place (writable) or open the releases page.
    public async void download_and_install(Manifest manifest) throws Error {
        busy = true;
        try {
            var work = DirUtils.make_tmp("taskly-update-XXXXXX");
            var tar_path = Path.build_filename(work, "taskly-update.tar.gz");
            yield download_to_file(manifest.url, tar_path);

            if (!verify_sha256(tar_path, manifest.sha256)) {
                throw new UpdaterError.CHECKSUM("downloaded archive failed the sha256 check");
            }

            var unpacked = Path.build_filename(work, "unpacked");
            DirUtils.create_with_parents(unpacked, 0755);
            if (!run_sync({ "tar", "-xzf", tar_path, "-C", unpacked })) {
                throw new UpdaterError.UNPACK("tar extraction failed");
            }

            var prefix = install_prefix();
            if (!can_write(prefix)) {
                open_releases_page();
                throw new UpdaterError.NOT_WRITABLE(
                    "install prefix %s is not writable", prefix);
            }

            // Replace after this process exits: unlink-then-copy avoids
            // ETXTBSY on the running binary; ~/.taskly is never touched
            // (UPDATE.md rollout rules).
            var restart_sh = new StringBuilder();
            restart_sh.append_printf(
                "sleep 1\nrm -rf '%s'\ncp -a '%s/.' '%s/'\nrm -rf '%s'\nexec '%s'\n",
                work, unpacked, prefix, work,
                Path.build_filename(prefix, "bin", "taskly"));
            var sh_path = Path.build_filename(work, "restart.sh");
            FileUtils.set_contents(sh_path, restart_sh.str);
            if (!run_sync({ "chmod", "+x", sh_path })) {
                throw new UpdaterError.UNPACK("cannot mark restart script");
            }
            try {
                Process.spawn_async(null, { "/bin/sh", sh_path }, null,
                                    SpawnFlags.LEAVE_DESCRIPTORS_OPEN, null, null);
            } catch (SpawnError e) {
                throw new UpdaterError.UNPACK("cannot launch restart script");
            }
        } finally {
            busy = false;
        }
    }

    public void open_releases_page() {
        try {
            AppInfo.launch_default_for_uri(RELEASES_PAGE, null);
        } catch (Error e) {
            // Nothing sensible left; the dialog already showed the version.
        }
    }

    // MARK: - Environment

    /// Install root of the running binary: …/<prefix>/bin/taskly → …/<prefix>.
    /// Falls back to /usr/local when /proc/self/exe is unavailable.
    public static string install_prefix() {
        try {
            var exe = FileUtils.read_link("/proc/self/exe");
            if (exe != null) {
                var bin_dir = Path.get_dirname(exe);
                if (bin_dir.has_suffix("/bin")) {
                    return Path.get_dirname(bin_dir);
                }
                return bin_dir;
            }
        } catch (Error e) {
            // fall through
        }
        return "/usr/local";
    }

    private static bool can_write(string dir) {
        return Posix.access(dir, Posix.W_OK) == 0;
    }

    // MARK: - Parsing / comparison

    internal static string? release_asset_url(string api_body, string name) {
        var parser = new Json.Parser();
        try {
            parser.load_from_data(api_body);
        } catch (Error e) {
            return null;
        }
        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
            return null;
        }
        var assets = root.get_object().get_array_member("assets");
        foreach (var asset_node in assets.get_elements()) {
            var asset = asset_node.get_object();
            if (asset.get_string_member("name") == name) {
                return asset.get_string_member("browser_download_url");
            }
        }
        return null;
    }

    internal static Manifest parse_manifest(string body) throws Error {
        var parser = new Json.Parser();
        try {
            parser.load_from_data(body);
        } catch (Error e) {
            throw new UpdaterError.BAD_MANIFEST("manifest unparsable");
        }
        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
            throw new UpdaterError.BAD_MANIFEST("manifest unparsable");
        }
        var obj = root.get_object();
        if (!obj.has_member("version") || !obj.has_member("platforms")) {
            throw new UpdaterError.BAD_MANIFEST("manifest missing fields");
        }
        var platforms = obj.get_object_member("platforms");
        if (!platforms.has_member("linux")) {
            throw new UpdaterError.BAD_MANIFEST("manifest has no linux artifact");
        }
        // Not named `linux`: gcc defines it as a macro, valac's generated
        // C would expand and fail to compile.
        var linux_art = platforms.get_object_member("linux");
        return Manifest() {
            version = obj.get_string_member("version"),
            url = linux_art.get_string_member("url"),
            sha256 = linux_art.get_string_member("sha256"),
        };
    }

    /// Numeric-per-segment semver compare; missing segments are zero.
    internal static bool version_newer(string candidate, string current) {
        var a = candidate.split(".");
        var b = current.split(".");
        for (int i = 0; i < a.length || i < b.length; i++) {
            var x = i < a.length ? int.parse(a[i]) : 0;
            var y = i < b.length ? int.parse(b[i]) : 0;
            if (x != y) {
                return x > y;
            }
        }
        return false;
    }

    // MARK: - Transfer / helpers

    private async string download_string(string url) throws Error {
        var message = new Soup.Message("GET", url);
        if (message == null) {
            throw new UpdaterError.NETWORK("bad url");
        }
        try {
            var bytes = yield session.send_and_read_async(message, Priority.DEFAULT, null);
            if (message.status_code != Soup.Status.OK) {
                throw new UpdaterError.NETWORK("HTTP %u".printf(message.status_code));
            }
            return (string) bytes.get_data();
        } catch (Error e) {
            throw new UpdaterError.NETWORK(e.message);
        }
    }

    private async void download_to_file(string url, string path) throws Error {
        var message = new Soup.Message("GET", url);
        if (message == null) {
            throw new UpdaterError.NETWORK("bad url");
        }
        try {
            var input = yield session.send_async(message, Priority.DEFAULT, null);
            if (message.status_code != Soup.Status.OK) {
                throw new UpdaterError.NETWORK("HTTP %u".printf(message.status_code));
            }
            var output = File.new_for_path(path)
                .create(FileCreateFlags.REPLACE_DESTINATION)
                as FileOutputStream;
            // 8 MB chunks keep memory flat for multi-MB artifacts.
            var buffer = new uint8[8 * 1024 * 1024];
            while (true) {
                var read = yield input.read_async(buffer);
                if (read <= 0) {
                    break;
                }
                size_t written;
                yield output.write_all_async(buffer[0:read], Priority.DEFAULT, null, out written);
            }
            yield output.close_async(Priority.DEFAULT, null);
        } catch (Error e) {
            throw new UpdaterError.NETWORK(e.message);
        }
    }

    internal static bool verify_sha256(string path, string expected) throws Error {
        var lower = expected.down();
        // coreutils sha256sum: present on every desktop distro we target.
        string stdout_text;
        try {
            Process.spawn_sync(null, { "sha256sum", path }, null,
                               SpawnFlags.SEARCH_PATH, null,
                               out stdout_text, null, null);
        } catch (SpawnError e) {
            throw new UpdaterError.CHECKSUM("sha256sum unavailable");
        }
        // First whitespace-separated field of "HASH  path".
        var actual = stdout_text.split(" ")[0].down();
        return actual == lower;
    }

    private static bool run_sync(string[] argv) {
        try {
            int status;
            Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            return status == 0;
        } catch (SpawnError e) {
            return false;
        }
    }
}

public errordomain UpdaterError {
    NETWORK,
    NO_MANIFEST,
    BAD_MANIFEST,
    CHECKSUM,
    UNPACK,
    NOT_WRITABLE,
}
}
