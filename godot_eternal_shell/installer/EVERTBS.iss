; EVE战棋 (EVERTBS) Windows installer — Inno Setup 6
; Same AppId enables upgrade. Before install: silent-uninstall any previous EVE战棋 shell.
; No wizard bitmaps: default Inno look (EVE自走棋 artwork must not be reused).

#define MyAppName "EVE战棋"
#define MyAppNameEn "EVERTBS"
#define MyAppVersion "202610.14.1"
#define MyAppPublisher "EVERTBS"
#define MyAppExeName "EVERTBS.exe"
; Stable GUID — do not change or upgrades break.
#define MyAppId "{{B8F4D3C2-A051-4E7F-9D2B-EVETBSSHELL01}}"
#define MyAppUninstallKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\{B8F4D3C2-A051-4E7F-9D2B-EVETBSSHELL01}_is1"
; Must match shell project.godot config/custom_user_dir_name (user:// = %APPDATA%\EVERTBS).
#define MyUserDir "EVERTBS"

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
OutputBaseFilename=EVERTBS_Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion=2026.10.14.1
VersionInfoProductName={#MyAppName}
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes
CloseApplications=force
CloseApplicationsFilter=EVERTBS.exe,EVERTBS_Setup.exe,EVETBS.exe
RestartApplications=no
SetupMutex=EVERTBS_Setup_Mutex
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"; Flags: checkedonce
; Decorative only — no [Icons]/[Run]/[Code] hooks.
Name: "promo_bilibili"; Description: "去bilibili关注EVE战棋"; GroupDescription: "附加图标:"; Flags: unchecked
Name: "promo_afdian"; Description: "去爱发电支持EVE战棋"; GroupDescription: "附加图标:"; Flags: unchecked

[Files]
Source: "..\builds\windows\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Windows export excludes res://bundled_content — seed MUST land in user:// (%APPDATA%\EVERTBS).
Source: "..\builds\seed\packs\*.pck"; DestDir: "{userappdata}\{#MyUserDir}\content_runtime\packs"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\builds\seed\applied_version.json"; DestDir: "{userappdata}\{#MyUserDir}\online_update"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\{#MyUserDir}"

[Code]
function ExpandUninstallCmd(const Cmd: String; var Exe, Params: String): Boolean;
var
  P: Integer;
  S: String;
begin
  Result := False;
  Exe := '';
  Params := '';
  S := Trim(Cmd);
  if S = '' then
    Exit;
  if S[1] = '"' then
  begin
    Delete(S, 1, 1);
    P := Pos('"', S);
    if P = 0 then
      Exit;
    Exe := Copy(S, 1, P - 1);
    Params := Trim(Copy(S, P + 1, MaxInt));
  end
  else
  begin
    P := Pos(' ', S);
    if P = 0 then
    begin
      Exe := S;
      Params := '';
    end
    else
    begin
      Exe := Copy(S, 1, P - 1);
      Params := Trim(Copy(S, P + 1, MaxInt));
    end;
  end;
  Result := (Exe <> '') and FileExists(Exe);
end;

function RunSilentUninstall(const UninstallCmd: String): Boolean;
var
  Exe, Params: String;
  ResultCode: Integer;
begin
  Result := False;
  if not ExpandUninstallCmd(UninstallCmd, Exe, Params) then
    Exit;
  Params := Trim(Params);
  if Params <> '' then
    Params := Params + ' ';
  Params := Params + '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /FORCECLOSEAPPLICATIONS';
  Log('Silent uninstall: ' + Exe + ' ' + Params);
  Result := Exec(Exe, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function TryUninstallFromKey(RootKey: Integer; const SubKey: String): Boolean;
var
  UninstallString, QuietString: String;
begin
  Result := False;
  if not RegKeyExists(RootKey, SubKey) then
    Exit;
  QuietString := '';
  UninstallString := '';
  RegQueryStringValue(RootKey, SubKey, 'QuietUninstallString', QuietString);
  RegQueryStringValue(RootKey, SubKey, 'UninstallString', UninstallString);
  if QuietString <> '' then
  begin
    Result := RunSilentUninstall(QuietString);
    if Result then
      Exit;
  end;
  if UninstallString <> '' then
    Result := RunSilentUninstall(UninstallString);
end;

procedure ScanUninstallHive(RootKey: Integer; const BaseKey: String);
var
  Names: TArrayOfString;
  I: Integer;
  DisplayName, Publisher, UninstallString: String;
  SubKey: String;
begin
  if not RegGetSubkeyNames(RootKey, BaseKey, Names) then
    Exit;
  for I := 0 to GetArrayLength(Names) - 1 do
  begin
    SubKey := BaseKey + '\' + Names[I];
    DisplayName := '';
    Publisher := '';
    UninstallString := '';
    RegQueryStringValue(RootKey, SubKey, 'DisplayName', DisplayName);
    RegQueryStringValue(RootKey, SubKey, 'Publisher', Publisher);
    RegQueryStringValue(RootKey, SubKey, 'UninstallString', UninstallString);
    if UninstallString = '' then
      Continue;
    { Only our own product lines. Never match EVE自走棋 / EveAutochess / EVE Online. }
    if (Pos('EVE战棋', DisplayName) > 0) or
       (Pos('eve战棋', DisplayName) > 0) or
       (Pos('EVERTBS', DisplayName) > 0) or
       (Pos('EVETBS', DisplayName) > 0) or
       (Pos('烬海征服者', DisplayName) > 0) or
       (Publisher = 'EVERTBS') or
       (Publisher = 'EVETBS') then
    begin
      Log('Found old shell uninstall entry: ' + SubKey + ' / ' + DisplayName);
      TryUninstallFromKey(RootKey, SubKey);
    end;
  end;
end;

procedure RemoveLegacyShortcuts;
var
  Desk, StartMenu: String;
begin
  Desk := ExpandConstant('{userdesktop}');
  StartMenu := ExpandConstant('{userprograms}');
  DeleteFile(Desk + '\烬海征服者.lnk');
  DeleteFile(Desk + '\eve战棋.lnk');
  DeleteFile(StartMenu + '\烬海征服者.lnk');
  DeleteFile(StartMenu + '\eve战棋.lnk');
end;

procedure RemoveLegacyLooseDirs;
var
  Dirs: array[0..1] of String;
  I: Integer;
begin
  { Pre-rename install dir — only if it contains our old EXE }
  Dirs[0] := ExpandConstant('{localappdata}\Programs\EVETBS');
  Dirs[1] := ExpandConstant('{localappdata}\EVERTBS');
  for I := 0 to 1 do
  begin
    if FileExists(Dirs[I] + '\EVETBS.exe') or FileExists(Dirs[I] + '\EVERTBS.exe') then
    begin
      Log('Removing legacy dir: ' + Dirs[I]);
      DelTree(Dirs[I], True, True, True);
    end;
  end;
end;

{ Full content overwrite under Godot user:// (= %APPDATA%\EVERTBS only). }
procedure WipeRuntimeContentPacks;
var
  UserBase, PacksDir, Applied: String;
begin
  UserBase := ExpandConstant('{userappdata}\{#MyUserDir}');
  PacksDir := UserBase + '\content_runtime\packs';
  Applied := UserBase + '\online_update\applied_version.json';
  if DirExists(PacksDir) then
  begin
    Log('Full overwrite: DelTree ' + PacksDir);
    DelTree(PacksDir, True, True, True);
  end;
  if FileExists(Applied) then
  begin
    Log('Full overwrite: delete ' + Applied);
    DeleteFile(Applied);
  end;
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/F /IM EVERTBS.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/F /IM EVETBS.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  { 1) Known AppId uninstall key }
  TryUninstallFromKey(HKCU, '{#MyAppUninstallKey}');
  TryUninstallFromKey(HKLM, '{#MyAppUninstallKey}');
  TryUninstallFromKey(HKLM32, '{#MyAppUninstallKey}');

  { 2) Other uninstall entries of this product (old names) }
  ScanUninstallHive(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall');
  ScanUninstallHive(HKLM, 'Software\Microsoft\Windows\CurrentVersion\Uninstall');
  ScanUninstallHive(HKLM32, 'Software\Microsoft\Windows\CurrentVersion\Uninstall');

  { 3) Loose leftovers from the EVETBS / 烬海征服者 era }
  RemoveLegacyShortcuts;
  RemoveLegacyLooseDirs;

  Result := True;
end;

procedure InitializeWizard();
begin
  { After silent-uninstall, force default dir so sticky tooling paths don't win. }
  WizardForm.DirEdit.Text := ExpandConstant('{localappdata}\Programs\{#MyAppNameEn}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  { Wipe packs, then [Files] rewrites the seed. }
  if CurStep = ssInstall then
    WipeRuntimeContentPacks;
end;
