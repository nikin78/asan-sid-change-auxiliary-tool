@{
    # Project-wide PSScriptAnalyzer settings for SID_Change_Aux_Tool.bat (hybrid Batch + PowerShell 5.1 WinForms/TUI).
    # Keep all bug, syntax, encoding, automatic-variable, unused-variable, and unused-parameter checks active.
    # Exclude only stylistic rules that conflict with interactive Console TUI / WinForms / internal module helpers.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingPositionalParameters',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseApprovedVerbs',
        'PSUseSingularNouns',
        'PSAvoidUsingInvokeExpression'
    )
}
