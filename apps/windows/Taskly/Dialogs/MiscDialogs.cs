using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Taskly.Dialogs;

/// <summary>Generic confirmation dialog (destructive primary).</summary>
public sealed class ConfirmDialog : ContentDialog
{
    public ConfirmDialog(string title, string message, string confirmText, string cancelText)
    {
        Title = title;
        PrimaryButtonText = confirmText;
        CloseButtonText = cancelText;
        DefaultButton = ContentDialogButton.Primary;
        Content = new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 360,
        };
    }
}

/// <summary>About box.</summary>
public sealed class AboutDialog : ContentDialog
{
    public AboutDialog(string content, string confirmText)
    {
        Title = Taskly.Services.I18nService.Instance.T("menuAbout");
        CloseButtonText = confirmText;
        DefaultButton = ContentDialogButton.Close;
        Content = new TextBlock
        {
            Text = content,
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 360,
            TextAlignment = TextAlignment.Center,
        };
    }
}
