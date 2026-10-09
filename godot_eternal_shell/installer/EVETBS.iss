; 烬海征服者 (EVETBS) Windows installer — Inno Setup 6
; Same AppId enables upgrade. Before install: silent-uninstall any previous shell.

#define MyAppName "烬海征服者"
#define MyAppNameEn "EVETBS"
#define MyAppVersion "202610.9.1"
#define MyAppPublisher "EVETBS"
#define MyAppExeName "EVETBS.exe"
; Stable GUID — do not change or upgrades break.
#define MyAppId "{{B8F4D3C2-A051-4E7F-9D2B-EVETBSSHELL01}}"
#define MyAppUninstallKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\{B8F4D3C2-A051-4E7F-9D2B-EVETBSSHELL01}_is1"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppNameEn}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\builds\windows
OutputBaseFilename=EVETBS_Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
WizardImageFile=wizard_side.bmp
WizardSmallImageFile=wizard_small.bmp
WizardImageStretch=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion=2026.10.9.1
VersionInfoProductName={#MyAppName}
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes
CloseApplications=force
CloseApplicationsFilter=EVETBS.exe,EVETBS_Setup.exe
SetupMutex=EVETBS_Setup_Mutex

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\builds\windows\EVETBS.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
