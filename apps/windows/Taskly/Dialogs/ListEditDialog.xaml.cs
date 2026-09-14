using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Taskly.Models;
using Taskly.Repositories;
using Taskly.ViewModels;

namespace Taskly.Dialogs;

/// <summary>Create / edit a list: name, emoji, color (with clear buttons).</summary>
public sealed partial class ListEditDialog : ContentDialog
{
    private readonly MainViewModel _vm;
    private readonly TodoList? _existing;
    private string? _icon;
    private int? _color;
    private bool _clearIcon;
    private bool _clearColor;

    public ListEditDialog(MainViewModel vm, TodoList? existing)
    {
        InitializeComponent();
        _vm = vm;
        _existing = existing;

        Title = existing is null ? vm.T("dialogCreateList") : vm.T("dialogEditList");
        PrimaryButtonText = vm.T("dialogConfirm");
        CloseButtonText = vm.T("dialogCancel");
        NameBox.PlaceholderText = vm.T("dialogInputListName");
        IconLabel.Text = vm.T("dialogListIcon");
        ColorLabel.Text = vm.T("dialogListColor");
        ClearIconButton.Content = vm.T("dialogClearIcon");
        ClearIconButton2.Content = vm.T("dialogClearColor");

        if (existing is not null)
        {
            NameBox.Text = existing.Name;
            _icon = existing.Icon;
            _color = existing.Color;
        }

        PrimaryButtonClick += async (_, args) =>
        {
            var name = NameBox.Text.Trim();
            if (name.Length == 0)
            {
                args.Cancel = true; // blank name keeps the dialog open
                return;
            }

            if (_existing is null)
            {
                await _vm.CreateListAsync(name, _icon, _color);
            }
            else
            {
                await _vm.UpdateListAsync(_existing.Id, name, _icon, _color, _clearIcon, _clearColor);
            }
        };

        RefreshVisuals();
    }

    private void RefreshVisuals()
    {
        IconText.Text = _icon ?? "✚";
        ClearIconButton.Visibility = _icon is null ? Visibility.Collapsed : Visibility.Visible;

        var hex = unchecked((uint)(_color ?? Models.TodoList.DefaultColor));
        ColorSwatch.Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(
            0xFF,
            (byte)((hex >> 16) & 0xFF),
            (byte)((hex >> 8) & 0xFF),
            (byte)(hex & 0xFF)));
        ClearIconButton2.Visibility = _color is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void OnPickIcon(object sender, RoutedEventArgs e)
    {
        var picker = new EmojiPickerDialog(_icon);
        if (await picker.ShowAsyncSafe(XamlRoot))
        {
            _icon = picker.SelectedEmoji;
            RefreshVisuals();
        }
    }

    private async void OnPickColor(object sender, RoutedEventArgs e)
    {
        var picker = new ColorPickerDialog(_color);
        if (await picker.ShowAsyncSafe(XamlRoot))
        {
            _color = picker.SelectedColor;
            RefreshVisuals();
        }
    }

    private void OnClearIcon(object sender, RoutedEventArgs e)
    {
        _icon = null;
        _clearIcon = true;
        RefreshVisuals();
    }

    private void OnClearColor(object sender, RoutedEventArgs e)
    {
        _color = null;
        _clearColor = true;
        RefreshVisuals();
    }
}
