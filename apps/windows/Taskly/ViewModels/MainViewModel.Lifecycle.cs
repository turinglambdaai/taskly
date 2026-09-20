using System.Threading;

namespace Taskly.ViewModels;

public partial class MainViewModel
{
    private int _shutdownStarted;

    /// <summary>
    /// Stops product services and releases the selected backend exactly once.
    /// Embedded Rivet builds use this path to join the Racket/runtime threads
    /// before the WinUI process is allowed to exit.
    /// </summary>
    public async Task ShutdownAsync()
    {
        if (Interlocked.Exchange(ref _shutdownStarted, 1) != 0)
        {
            return;
        }

        Reminder.Dispose();
        try
        {
            if (IsConnected)
            {
                await _backend.CloseAsync();
            }
        }
        finally
        {
            IsConnected = false;
            await _backend.DisposeAsync();
        }
    }
}
