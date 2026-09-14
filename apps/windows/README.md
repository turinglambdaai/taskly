# Taskly for Windows (WinUI 3 + C#)

Native Windows app: WinUI 3 / Windows App SDK (Fluent), .NET 10. The binary is
dual-mode — `Taskly.exe` with no arguments opens the Fluent window; any
argument routes to the agent CLI (console attached to the parent terminal).

## Build

Requires Windows 10 19041+ and .NET SDK 10 with the `windows` workloads
(Windows App SDK NuGet restores automatically):

```powershell
dotnet build apps/windows/Taskly/Taskly.csproj -c Release
dotnet run --project apps/windows/Taskly            # GUI
dotnet run --project apps/windows/Taskly -- list --json
```

## Publish (self-contained exe)

```powershell
dotnet publish apps/windows/Taskly/Taskly.csproj -c Release -r win-x64 `
  --self-contained true -p:WindowsAppSDKSelfContained=true `
  -o publish/windows-x64
```

Installer/auto-update: Velopack (`vpk pack`) — same pipeline as the 0.6.x
releases; MSIX packaging is available by flipping `WindowsPackageType`.

## Layout

| Path | Contents |
|---|---|
| `Program.cs` | Dual-mode entry (CLI before WinUI init) + Velopack hooks |
| `App.xaml` | Warm palette as Light/Dark theme dictionaries |
| `Views/` | MainWindow, ListPane, TaskPane, dialogs |
| `Data/`, `Repositories/`, `Services/`, `Models/`, `Cli/` | Contract layer, ported from the proven 0.6.x core |
| `Strings/` | zh/en JSON synced from `shared/i18n` (CI-verified) |

## Status / known deltas vs 0.6.4

- Feature-complete per `shared/spec/PRODUCT-SPEC.md` except: task-row inline
  editing opens the detail dialog (native Fluent editing is on the roadmap);
  quick-add adopts the CLI date semantics (pure-date intent clears the time —
  the 0.6.x GUI quirk is fixed).
- First build must happen on a Windows machine/CI runner (WinUI 3 cannot
  build on macOS/Linux). CI: `.github/workflows/native.yml` (windows job).
- Toast notifications use Microsoft.Toolkit.Uwp.Notifications (unpackaged
  AUMID shortcut auto-created); failures disable toasts for the session.
