# Runs the Flutter widget tests and writes reports/widget_tests.html.
Set-Location $PSScriptRoot
& ..\backend\.venv\Scripts\python.exe tool\widget_report.py
if ($LASTEXITCODE -eq 0) {
    Start-Process (Join-Path $PSScriptRoot "reports\widget_tests.html")
}
