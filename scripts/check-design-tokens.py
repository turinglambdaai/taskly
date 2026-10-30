#!/usr/bin/env python3
"""Keep Taskly's shared palette aligned and enforce useful contrast floors."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

TOKENS = {
    "accentLight": "C94F30",
    "accentDark": "E8704F",
    "lightBackground": "FFFFFF",
    "lightSidebar": "F3F2F1",
    "lightSurface": "FFFFFF",
    "lightDivider": "E1DFDD",
    "lightOnSurface": "1D1D1F",
    "lightSecondaryText": "5F5D5B",
    "lightTertiaryText": "767370",
    "lightInputBorder": "8A8785",
    "darkBackground": "1E1E1E",
    "darkSidebar": "272424",
    "darkSurface": "323234",
    "darkDivider": "3B3939",
    "darkOnSurface": "F5F5F7",
    "darkSecondaryText": "B2AEAC",
    "darkTertiaryText": "A8A5A3",
    "darkInputBorder": "777371",
}


def channel(value: int) -> float:
    normalized = value / 255
    return normalized / 12.92 if normalized <= 0.04045 else ((normalized + 0.055) / 1.055) ** 2.4


def luminance(hex_value: str) -> float:
    red, green, blue = (int(hex_value[index:index + 2], 16) for index in (0, 2, 4))
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)


def contrast(first: str, second: str) -> float:
    high, low = sorted((luminance(first), luminance(second)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def require(path: str, fragments: list[str]) -> None:
    content = (ROOT / path).read_text(encoding="utf-8")
    missing = [fragment for fragment in fragments if fragment not in content]
    if missing:
        raise SystemExit(f"{path} does not implement canonical tokens: {missing}")


def main() -> None:
    require(
        "macos-host/Sources/RivetHost/Theme.swift",
        [f"0x{value}" for value in TOKENS.values()],
    )
    require(
        "linux/src/main.cpp",
        [f'"#{value}"' for value in TOKENS.values()],
    )
    require(
        "windows/MainWindow.xaml",
        [f'Color="#{value}"' for value in (
            TOKENS["accentLight"], TOKENS["accentDark"],
            TOKENS["lightSecondaryText"], TOKENS["lightTertiaryText"],
            TOKENS["darkSecondaryText"], TOKENS["darkTertiaryText"],
        )],
    )

    checks = {
        "light primary text": ("lightOnSurface", "lightBackground", 4.5),
        "light secondary text": ("lightSecondaryText", "lightBackground", 4.5),
        "light tertiary text": ("lightTertiaryText", "lightBackground", 4.5),
        "light action accent": ("accentLight", "lightBackground", 4.5),
        "light input boundary": ("lightInputBorder", "lightBackground", 3.0),
        "dark primary text": ("darkOnSurface", "darkBackground", 4.5),
        "dark secondary text": ("darkSecondaryText", "darkBackground", 4.5),
        "dark tertiary text": ("darkTertiaryText", "darkBackground", 4.5),
        "dark action accent": ("accentDark", "darkBackground", 4.5),
        "dark input boundary": ("darkInputBorder", "darkBackground", 3.0),
    }
    for label, (foreground, background, minimum) in checks.items():
        ratio = contrast(TOKENS[foreground], TOKENS[background])
        if ratio < minimum:
            raise SystemExit(f"{label}: {ratio:.2f}:1 is below {minimum:.1f}:1")
        print(f"ok: {label} {ratio:.2f}:1")


if __name__ == "__main__":
    main()
