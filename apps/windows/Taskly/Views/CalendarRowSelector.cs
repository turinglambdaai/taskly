using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Taskly.Models;

namespace Taskly.Views;

/// <summary>Picks the group-header or task-row template for calendar time
/// line rows (PRODUCT-SPEC §4b).</summary>
public sealed class CalendarRowSelector : DataTemplateSelector
{
    public DataTemplate? HeaderTemplate { get; set; }
    public DataTemplate? TaskTemplate { get; set; }

    protected override DataTemplate? SelectTemplateCore(object item) =>
        item is CalendarSectionHeader ? HeaderTemplate : TaskTemplate;

    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container) =>
        SelectTemplateCore(item);
}
