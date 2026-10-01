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

        var i18n = Taskly.Services.I18nService.Instance;
        var root = new StackPanel { Spacing = 10 };

        // Category tabs (8 × 12 catalog from Strings/emoji.json).
        var categoryCombo = new ComboBox { MinWidth = 160, HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var id in ListPalette.EmojiCategoryIds)
        {
            categoryCombo.Items.Add(i18n.T("emojiCat_" + id));
        }
        categoryCombo.SelectedIndex = 0;
        root.Children.Add(categoryCombo);

        var emojiGrid = new Grid { ColumnSpacing = 4, RowSpacing = 4 };
        for (var r = 0; r < 2; r++)
        {
            emojiGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        }
        for (var c = 0; c < 6; c++)
        {
            emojiGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        }
        root.Children.Add(emojiGrid);

        void ReloadEmojis()
        {
            emojiGrid.Children.Clear();
            var index = System.Math.Max(0, categoryCombo.SelectedIndex);
            var id = ListPalette.EmojiCategoryIds[index];
            if (!ListPalette.EmojiCategories.TryGetValue(id, out var emojis))
            {
                return;
            }
            for (var i = 0; i < emojis.Length; i++)
            {
                var emoji = emojis[i];
                var button = new Button
                {
                    Content = emoji,
                    FontSize = 18,
                    Padding = new Thickness(6, 4, 6, 4),
                };
                var captured = emoji;
                button.Click += (_, _) =>
                {
                    SelectedEmoji = captured;
                    Hide();
                };
                Grid.SetRow(button, i / 6);
                Grid.SetColumn(button, i % 6);
                emojiGrid.Children.Add(button);
            }
        }
        categoryCombo.SelectionChanged += (_, _) => ReloadEmojis();
        ReloadEmojis();

        Content = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
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

    private static ItemsPanelTemplate CreateWrapPanel()
    {
        var xaml = """<ItemsPanelTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'>
            <controls:WrapPanel Orientation='Horizontal' HorizontalSpacing='4' VerticalSpacing='4'
                xmlns:controls='using:Microsoft.UI.Xaml.Controls'/>
        </ItemsPanelTemplate>""";
        return (ItemsPanelTemplate)Microsoft.UI.Xaml.Markup.XamlReader.Load(xaml);
    }

    private static DataTemplate MakeEmojiTemplate()
    {
        var xaml = """<DataTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'>
            <TextBlock Text='{Binding}' FontSize='18'
                Padding='6,4,6,4' Tag='{Binding}'/>
        </DataTemplate>""";
        return (DataTemplate)Microsoft.UI.Xaml.Markup.XamlReader.Load(xaml);
    }

    public async System.Threading.Tasks.Task<bool> ShowAsyncSafe(Microsoft.UI.Xaml.XamlRoot root)
    {
        XamlRoot = root;
        return await ShowAsync() == ContentDialogResult.Primary || SelectedColor is not null;
    }
}
