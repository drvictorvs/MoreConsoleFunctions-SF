@echo off
setlocal
rem Each path below can be overridden by an environment variable of the same name.
rem Compiles scripts\Source\MoreConsoleFunctions_SFDiagnostics.psc and MoreConsoleFunctions_SF.psc into dist\Data\Scripts with the
rem Creation Kit's Papyrus compiler. Check the paths below first.

rem Your Starfield folder (the one with Starfield.exe)
if not defined STARFIELD set "STARFIELD=C:\Program Files (x86)\Steam\steamapps\common\Starfield"

rem Folder holding the vanilla script sources AND Starfield_Papyrus_Flags.flg
rem (from Tools\ContentResources.zip, extracted in place)
set "BASE=%STARFIELD%\Tools\ContentResources\Scripts\Source"

rem Folder holding CassiopeiaPapyrusExtender.psc
if not defined CASSIOPEIA set "CASSIOPEIA=C:\Modding\Starfield\mods\Cassiopeia Papyrus Extender\Scripts\Source\User"

rem Your mod manager's Scripts folder for this mod. When both scripts compile, the new .pex files
rem are copied there too, so the game can't keep running old ones. Leave empty to skip.
if not defined MOD_SCRIPTS set "MOD_SCRIPTS=C:\Modding\Starfield\mods\MoreConsoleFunctions\Scripts"

set "COMPILER=%STARFIELD%\Tools\Papyrus Compiler\PapyrusCompiler.exe"
set "FLAGS=%BASE%\Starfield_Papyrus_Flags.flg"
set "SOURCE=%~dp0scripts\Source"
set "IMPORTS=%SOURCE%;%CASSIOPEIA%;%BASE%"

if not exist "%COMPILER%" (
  echo Papyrus compiler not found: "%COMPILER%"
  echo Check STARFIELD, and that the Creation Kit is installed.
  goto :done
)
if not exist "%FLAGS%" (
  echo Flags file not found: "%FLAGS%"
  echo Point BASE at the folder that holds Starfield_Papyrus_Flags.flg and the vanilla .psc files.
  goto :done
)
if not exist "%CASSIOPEIA%\CassiopeiaPapyrusExtender.psc" echo Warning: CassiopeiaPapyrusExtender.psc is not in "%CASSIOPEIA%"

rem The script is named, not given as a path: the compiler finds it in the first import
rem folder (scripts\Source), which is also how it works out the script's name.
set "OUT=%~dp0dist\Data\Scripts"
if not exist "%OUT%" mkdir "%OUT%"
set "FAILED="
for %%S in (MoreConsoleFunctions_SFDiagnostics MoreConsoleFunctions_SF) do (
  "%COMPILER%" "%%S.psc" -f="%FLAGS%" -i="%IMPORTS%" -o="%OUT%"
  if errorlevel 1 (
    echo.
    echo *** %%S.psc did NOT compile; its old .pex, if any, is still there.
    set "FAILED=1"
  )
)

echo.
if defined FAILED (
  echo Some scripts failed to compile ^(see above^). Nothing was copied to the mod folder.
  goto :done
)
echo All scripts compiled into "%OUT%".
if defined MOD_SCRIPTS (
  if exist "%MOD_SCRIPTS%\" (
    copy /y "%OUT%\MoreConsoleFunctions_SF.pex" "%MOD_SCRIPTS%\" >nul
    copy /y "%OUT%\MoreConsoleFunctions_SFDiagnostics.pex" "%MOD_SCRIPTS%\" >nul
    echo Copied MoreConsoleFunctions_SF.pex and MoreConsoleFunctions_SFDiagnostics.pex to "%MOD_SCRIPTS%".
    if exist "%MOD_SCRIPTS%\MoreConsoleFunctions_SFNative.pex" echo Old transporter scripts are still there ^(MoreConsoleFunctions_SFNative.pex, MoreConsoleFunctions_SFBridge.pex^): delete them; Transporter-SF replaces them.
  ) else (
    echo MOD_SCRIPTS folder not found: "%MOD_SCRIPTS%" ^(copy the .pex files yourself^)
  )
)

:done
pause
