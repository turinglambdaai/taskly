using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Taskly;

public partial class App : Application
{
    public static Window? MainWindow { get; private set; }

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        MainWindow = new Views.MainWindow();
        MainWindow.Activate();
    }
}
