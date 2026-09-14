using Taskly.Models;

namespace Taskly.Services;

/// <summary>Input validation limits (cross-platform contract).</summary>
public static class ValidationHelper
{
    public const int MaxTaskTextLength = 1000;
    public const int MaxListNameLength = 100;
    public const int MaxSearchKeywordLength = 200;
    public const int MinYear = 1900;
    public const int MaxYear = 2100;

    public static AppError? ValidateTaskText(string text, I18nService i18n)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return new AppError(i18n.T("errorEnterTaskDesc"), AppErrorType.Validation);
        }

        if (text.Length > MaxTaskTextLength)
        {
            return new AppError(i18n.Format("errorTaskDescTooLong", MaxTaskTextLength), AppErrorType.Validation);
        }

        return null;
    }

    public static AppError? ValidateListName(string name, I18nService i18n)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return new AppError(i18n.T("errorEnterListName"), AppErrorType.Validation);
        }

        if (name.Length > MaxListNameLength)
        {
            return new AppError(i18n.Format("errorListNameTooLong", MaxListNameLength), AppErrorType.Validation);
        }

        return null;
    }
}
