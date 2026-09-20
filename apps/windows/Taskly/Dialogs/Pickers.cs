using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Taskly.Repositories;

namespace Taskly.Dialogs;

/// <summary>Emoji picker (6 categories × 8, fixed order).</summary>
public sealed class EmojiPickerDialog : ContentDialog
{
    public string? SelectedEmoji { get; private set; }

    private readonly string? _current;

    public EmojiPickerDialog(string? current)
    {
        _current = current;
        Title = Taskly.Services.I18nService.Instance.T("dialogSelectIcon");
        CloseButtonText = Taskly.Services.I18nService.Instance.T("dialogCancel");

        var grid = new Grid();
        for (var r = 0; r < ListPalette.EmojiCategories.Length; r++)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Auto) });
        }

        for (var r = 0; r < ListPalette.EmojiCategories.Length; r++)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            foreach (var emoji in ListPalette.EmojiCategories[r])
            {
                var button = new Button
                {
                    Content = emoji,
                    FontSize = 18,
                    Padding = new Thickness(6, 4, 6, 4),
                    Background = emoji == current ? new SolidColorBrush(Windows.UI.Color.FromArgb(0x40, 0xC1, 0x5F, 0x3C)) : null,
                };
                var captured = emoji;
                button.Click += (_, _) =>
                {
                    SelectedEmoji = captured;
                    Hide();
                };
                row.Children.Add(button);
            }

            Grid.SetRow(row, r);
            grid.Children.Add(row);
        }

        Content = new ScrollViewer { Content = grid, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    public async System.Threading.Tasks.Task<bool> ShowAsyncSafe(Microsoft.UI.Xaml.XamlRoot root)
    {
        XamlRoot = root;
        return await ShowAsync() == ContentDialogResult.Primary || SelectedEmoji is not null;
    }
}

/// <summary>Color picker: the 10 preset swatches, fixed order.</summary>
public sealed class ColorPickerDialog : ContentDialog
{
    public int? SelectedColor { get; private set; }

    public ColorPickerDialog(int? current)
    {
        Title = Taskly.Services.I18nService.Instance.T("dialogSelectColor");
        CloseButtonText = Taskly.Services.I18nService.Instance.T("dialogCancel");

        var wrap = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (var hexString in ListPalette.Colors)
        {
            var hex = Convert.ToUInt32(hexString.TrimStart('#'), 16);
            var color = Windows.UI.Color.FromArgb(0xFF,
                (byte)((hex >> 16) & 0xFF), (byte)((hex >> 8) & 0xFF), (byte)(hex & 0xFF));
            var button = new Button
            {
                CornerRadius = new CornerRadius(16),
                Padding = new Thickness(4),
                Content = new Ellipse
                {
                    Width = 26,
                    Height = 26,
                    Fill = new SolidColorBrush(color),
                },
            };
            var argb = unchecked((int)(0xFF000000u | hex));
            button.Click += (_, _) =>
            {
                SelectedColor = argb;
                Hide();
            };
            wrap.Children.Add(button);
        }

        Content = wrap;
    }

    public async System.Threading.Tasks.Task<bool> ShowAsyncSafe(Microsoft.UI.Xaml.XamlRoot root)
    {
        XamlRoot = root;
        return await ShowAsync() == ContentDialogResult.Primary || SelectedColor is not null;
    }
}
