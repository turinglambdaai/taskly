/**
 * Taskly — interactions, theming and i18n.
 */

document.addEventListener('DOMContentLoaded', () => {
    initSmoothScrolling();
    initScrollAnimations();
    initThemeToggle();
    initLanguageSwitcher();
});

// Smooth scrolling for in-page anchors.
function initSmoothScrolling() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            const targetId = this.getAttribute('href');
            if (targetId === '#' || !targetId || targetId === '#lang-toggle') return;

            const targetElement = document.querySelector(targetId);
            if (targetElement) {
                e.preventDefault();
                const headerOffset = 64;
                const elementPosition = targetElement.getBoundingClientRect().top;
                const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

                window.scrollTo({
                    top: offsetPosition,
                    behavior: 'smooth'
                });
            }
        });
    });
}

// Reveal elements as they scroll into view.
function initScrollAnimations() {
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('is-visible');
                observer.unobserve(entry.target);
            }
        });
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });

    document.querySelectorAll('.animate-on-scroll').forEach(el => observer.observe(el));
}

// ---- theme ----

// The inline head script sets data-theme before the stylesheet loads (no
// flash): from localStorage when the user picked manually, otherwise from
// the OS preference. The toggle flips it and remembers the choice.
const THEME_KEY = 'taskly-theme';

function initThemeToggle() {
    const btn = document.getElementById('theme-btn');
    if (!btn) return;
    btn.addEventListener('click', () => {
        const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
        document.documentElement.dataset.theme = next;
        try { localStorage.setItem(THEME_KEY, next); } catch (_) { /* private mode */ }
    });
}

// ---- i18n ----

// Language policy:
// 1. A user's explicit choice always wins and is persisted.
// 2. With no explicit choice, follow the browser/system locale on every visit.
// 3. Chinese locales use Simplified Chinese; other known locales use English.
// 4. If a locale cannot be detected at all, fall back to Chinese because Taskly's
//    current primary audience is Chinese-speaking.
//
// The v2 key intentionally does not reuse the legacy `taskly_lang` key. Older
// versions wrote the auto-detected language into that key on first visit, so it
// cannot tell an explicit user choice from an automatic choice. Starting fresh
// here restores true system-locale behavior without trapping existing visitors.
const LANGUAGE_OVERRIDE_KEY = 'taskly_lang_override_v2';
const LEGACY_LANGUAGE_KEY = 'taskly_lang';

const translations = {
    en: 'English',
    zh: '简体中文'
};

// Dictionary mode (index.html): elements carry data-i18n keys and the
// Chinese copy lives in the markup as the default; this table holds both
// languages. manual.html still uses the older per-element data-en/data-zh
// attributes — applied by the attribute pass below, so both pages keep
// working from this one script.
const i18n = {
    en: {
        'nav.features': 'Features',
        'nav.manual': 'Manual',
        'nav.cli': 'CLI',
        'nav.release': 'Release',
        'nav.theme': 'Toggle theme',
        'hero.eyebrow': 'Open source · Local-first · Native on every desktop',
        'hero.h1a': 'Organize your life,',
        'hero.h1b': 'one task at a time.',
        'hero.lead': 'Taskly is a clean, focused task manager with keyboard-friendly scheduling shortcuts, a built-in CLI for automation, and native apps for every desktop. Your data stays yours.',
        'hero.download': 'Download Taskly',
        'hero.download-mac': 'Download for macOS',
        'hero.download-win': 'Download for Windows',
        'hero.download-linux': 'Download for Linux',
        'hero.github': 'View on GitHub',
        'hero.shotAlt': 'Taskly main window on macOS — smart lists, my lists and task rows',
        'features.title': 'Designed to fade into the background.',
        'features.subtitle': 'Calm colors, thoughtful typography, and nothing you don\u2019t need. So you can focus on doing, not managing.',
        'f1.title': 'Scheduling shortcuts',
        'f1.body': 'Add a modifier to any task: \u201cStandup @9am\u201d, \u201cBuy milk +1d\u201d, \u201cShip @5pm fri\u201d. Taskly extracts the time and leaves the rest as the task. No dials, no calendars.',
        'f1.tag': 'See the syntax \u2192',
        'f2.title': 'Private by design',
        'f2.body': 'Your tasks live in a local SQLite database. No account, no cloud, no tracking.',
        'f3.title': 'Truly cross-platform',
        'f3.body': 'Native apps for macOS, Windows, and Linux \u2014 same clean interface everywhere.',
        'f4.title': 'Sync on your terms',
        'f4.body': 'Point Taskly at any cloud-synced folder (iCloud, Dropbox, Syncthing\u2026) and your database follows you across devices. WAL mode keeps concurrent access safe.',
        'f4.tag': 'Bring your own cloud.',
        'cli.title': 'A CLI that speaks JSON',
        'cli.body': 'Taskly ships as a single binary \u2014 GUI and CLI in one. Script it, pipe it, hand it to an AI agent. Stable exit codes, structured output, no surprises.',
        'cli.tag': 'Single binary. Zero config.',
        'lists.title': 'Organized lists',
        'lists.body': 'Separate Work, Life, and Ideas into color-coded lists that stay out of each other\u2019s way.',
        'release.eyebrow': 'Release',
        'release.title': 'Three desktops. One core.',
        'release.subtitle': 'Taskly ships on macOS (SwiftUI), Windows (WinUI 3), and Linux (GTK4) \u2014 one shared Racket core behind thin first-party hosts, a JSON CLI pinned by a 61-case golden suite, and a single local SQLite file. Download, install, done.',
        'r1.title': 'Three native hosts · One core',
        'r1.body': 'SwiftUI on macOS, WinUI 3 on Windows, GTK4 on Linux \u2014 first-party feel on every desktop, with all logic in one Racket CS core driving them over typed RPC.',
        'r2.title': 'In-app updates · all platforms',
        'r2.body': 'Silent checks at launch plus a manual check in Settings. The backend verifies an Ed25519-signed update manifest and downloads the artifact; the host installs it \u2014 your data is never touched.',
        'r3.title': 'Agent CLI · Golden-pinned',
        'r3.body': 'A headless CLI with stable JSON output and exit codes: `taskly add "Buy milk" --due tomorrow --json`. Byte-level cross-platform parity is pinned by a 61-case golden suite in CI.',
        'r4.title': 'Open core · AGPL-3.0',
        'r4.body': 'The desktop core is open source \u2014 free to use, fork, and study. The data format and CLI are documented contracts, not accidents.',
        'cta.download': 'Download from Releases',
        'cta.download-mac': 'Download for macOS',
        'cta.download-win': 'Download for Windows',
        'cta.download-linux': 'Download for Linux',
        'cta.all-releases': 'All releases',
        'cta.manual': 'Read the manual',
        'release.note': 'Every release carries SHA256SUMS plus a signed update manifest; macOS builds are ad-hoc signed \u2014 clear the Gatekeeper quarantine with `xattr -cr /Applications/Taskly.app` on first launch.',
        'footer.changelog': 'Changelog',
        'footer.license': 'AGPL-3.0 license.'
    },
    zh: {
        'nav.features': '功能',
        'nav.manual': '手册',
        'nav.cli': '命令行',
        'nav.release': '发布',
        'nav.theme': '切换主题',
        'hero.eyebrow': '开源 · 本地优先 · 每个桌面都原生',
        'hero.h1a': '规划你的生活，',
        'hero.h1b': '一次一件。',
        'hero.lead': 'Taskly 是一款清爽、专注的任务管理器：支持便捷的排程速记、内置命令行工具便于自动化，并为每个桌面平台提供原生应用。数据始终归你所有。',
        'hero.download': '下载 Taskly',
        'hero.download-mac': '下载 macOS 版',
        'hero.download-win': '下载 Windows 版',
        'hero.download-linux': '下载 Linux 版',
        'hero.github': '在 GitHub 查看',
        'hero.shotAlt': 'Taskly 主窗口（macOS）：智能清单、我的列表与任务行',
        'features.title': '设计，是为了退到幕后。',
        'features.subtitle': '宁静的色彩、考究的排版，没有多余的东西。让你专注于执行，而非管理。',
        'f1.title': '排程速记',
        'f1.body': '给任务加个修饰符：「Standup @9am」「买牛奶 +1d」「发布 @5pm fri」。Taskly 提取时间，剩下就是任务。无需拨盘，无需翻日历。',
        'f1.tag': '查看完整语法 →',
        'f2.title': '隐私优先',
        'f2.body': '任务存储在本地 SQLite 数据库。无需账号，无云端，无追踪。',
        'f3.title': '真正的跨平台',
        'f3.body': 'macOS、Windows、Linux 原生应用，到处都是同样清爽的界面。',
        'f4.title': '按你的方式同步',
        'f4.body': '将 Taskly 指向任意云同步文件夹（iCloud、Dropbox、Syncthing…），数据库便会跟随你穿梭设备。WAL 模式确保并发访问安全。',
        'f4.tag': '自带你的云。',
        'cli.title': '会输出 JSON 的命令行',
        'cli.body': 'Taskly 以单一二进制发布——GUI 与 CLI 合为一体。脚本化、管道传递、交给 AI 代理。稳定的退出码、结构化输出，毫无意外。',
        'cli.tag': '单文件，零配置。',
        'lists.title': '井井有条的列表',
        'lists.body': '将工作、生活与创意分入各自着色的列表，互不干扰。',
        'release.eyebrow': '发布',
        'release.title': '三大桌面，一个核心。',
        'release.subtitle': 'Taskly 覆盖 macOS（SwiftUI）、Windows（WinUI 3）与 Linux（GTK4）——共享 Racket 核心驱动轻薄的第一方宿主，JSON CLI 由 61 例 golden 套件钉死，数据就是单个本地 SQLite 文件。下载安装即用。',
        'r1.title': '三端原生 · 一个核心',
        'r1.body': 'macOS 用 SwiftUI，Windows 用 WinUI 3，Linux 用 GTK4——每个平台都是第一方手感，全部逻辑在一个 Racket CS 核心里经类型化 RPC 驱动它们。',
        'r2.title': '应用内更新 · 三平台',
        'r2.body': '启动时静默检查 + 设置里手动检查。后端验证 Ed25519 签名的更新清单并下载产物，宿主负责安装——绝不碰你的数据。',
        'r3.title': 'Agent CLI · Golden 钉死',
        'r3.body': '无头 CLI，稳定的 JSON 输出与退出码：`taskly add "买牛奶" --due tomorrow --json`。跨平台字节级一致由 CI 中的 61 例 golden 套件钉死。',
        'r4.title': '开放核心 · AGPL-3.0',
        'r4.body': '桌面核心开源——自由使用、分叉与研究。数据格式与 CLI 都是成文的契约，而非偶然。',
        'cta.download': '从 Releases 下载',
        'cta.download-mac': '下载 macOS 版',
        'cta.download-win': '下载 Windows 版',
        'cta.download-linux': '下载 Linux 版',
        'cta.all-releases': '全部版本',
        'cta.manual': '阅读手册',
        'release.note': '每个版本都带 SHA256SUMS 与签名更新清单；macOS 包为 ad-hoc 签名——首次启动如被 Gatekeeper 拦截，执行 `xattr -cr /Applications/Taskly.app` 即可。',
        'footer.changelog': '更新日志',
        'footer.license': 'AGPL-3.0 协议。'
    }
};

const pageMetadata = {
    en: {
        title: 'Taskly — Organize your life',
        description: 'Taskly is a clean, focused task manager with keyboard-friendly scheduling shortcuts and an AI-friendly JSON CLI. One shared Racket core (Rivet) drives native SwiftUI, WinUI 3, and GTK4 hosts on macOS, Windows, and Linux — your data stays in one local SQLite file.'
    },
    zh: {
        title: 'Taskly — 简洁专注的任务管理器',
        description: 'Taskly 是一款清爽、专注的任务管理器：键盘友好的排程速记、面向 AI 的 JSON CLI。一个共享的 Racket 核心（Rivet）驱动 macOS、Windows 与 Linux 原生应用——数据就是单个本地 SQLite 文件。'
    }
};

function readLanguageOverride() {
    try {
        const saved = localStorage.getItem(LANGUAGE_OVERRIDE_KEY);
        return saved === 'zh' || saved === 'en' ? saved : null;
    } catch (_) {
        return null;
    }
}

function detectBrowserLanguage() {
    const locale = (navigator.languages && navigator.languages[0]) || navigator.language || '';
    if (!locale) return 'zh';
    return String(locale).toLowerCase().startsWith('zh') ? 'zh' : 'en';
}

function initLanguageSwitcher() {
    // Clean up the ambiguous legacy value once the new policy is active.
    try { localStorage.removeItem(LEGACY_LANGUAGE_KEY); } catch (_) { /* private mode */ }

    const override = readLanguageOverride();
    applyLanguage(override || detectBrowserLanguage(), false);

    // Follow a live OS/browser language change only while the user has not made
    // an explicit choice on this site.
    window.addEventListener('languagechange', () => {
        if (!readLanguageOverride()) {
            applyLanguage(detectBrowserLanguage(), false);
        }
    });
}

window.setLanguage = function (lang) {
    if (lang !== 'zh' && lang !== 'en') return;
    applyLanguage(lang, true);
};

function applyLanguage(lang, persist) {
    if (persist) {
        try { localStorage.setItem(LANGUAGE_OVERRIDE_KEY, lang); } catch (_) { /* private mode */ }
    }

    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    document.documentElement.dataset.language = lang;

    // Dictionary pass (index.html): data-i18n keys resolved against the
    // table, set as textContent — no HTML injection path.
    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        const text = i18n[lang] && i18n[lang][key];
        if (text) el.textContent = text;
    });
    document.querySelectorAll('[data-i18n-alt]').forEach(el => {
        const text = i18n[lang] && i18n[lang][el.getAttribute('data-i18n-alt')];
        if (text) el.setAttribute('alt', text);
    });
    const themeBtn = document.getElementById('theme-btn');
    if (themeBtn && i18n[lang] && i18n[lang]['nav.theme']) {
        themeBtn.setAttribute('aria-label', i18n[lang]['nav.theme']);
    }

    // Attribute pass (manual.html): per-element data-en/data-zh.
    // - Leaf elements (no element children): set innerText directly.
    // - Elements with inline markup in their data-* attribute (e.g. <code>,
    //   <strong>): the attribute is author-controlled and safe to render as
    //   innerHTML, so we use that path to support mixed text+markup.
    document.querySelectorAll('[data-en], [data-zh]').forEach(el => {
        const text = el.getAttribute('data-' + lang);
        if (!text) return;

        const hasElementChildren = Array.from(el.children).some(c => c.nodeType === 1);
        if (!hasElementChildren) {
            el.innerText = text;
        } else if (/<\w/.test(text)) {
            el.innerHTML = text;
        }
    });

    const currentLangLabel = document.getElementById('current-lang-label');
    if (currentLangLabel && translations[lang]) {
        currentLangLabel.innerText = translations[lang];
    }

    const metadata = pageMetadata[lang];
    if (metadata) {
        document.title = metadata.title;
        const description = document.querySelector('meta[name="description"]');
        if (description) description.setAttribute('content', metadata.description);
    }
}
