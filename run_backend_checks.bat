@echo off
cd /d "D:\Codebases\flutter\finance-tracker-personal\backend"

echo ======================================
echo Installing dependencies...
echo ======================================
python -m pip install --upgrade pip
pip install -r requirements.txt
pip install ruff

echo.
echo ======================================
echo Running Ruff linting...
echo ======================================
ruff check . --output-format=github
set RUFF_EXIT=%ERRORLEVEL%

echo.
echo ======================================
echo Running pytest...
echo ======================================
python -m pytest --tb=short -q
set PYTEST_EXIT=%ERRORLEVEL%

echo.
echo ======================================
echo Summary:
echo ======================================
echo Ruff exit code: %RUFF_EXIT%
echo Pytest exit code: %PYTEST_EXIT%

if %RUFF_EXIT% equ 0 (
    echo Ruff: PASSED
) else (
    echo Ruff: FAILED
)

if %PYTEST_EXIT% equ 0 (
    echo Pytest: PASSED
) else (
    echo Pytest: FAILED
)

pause
