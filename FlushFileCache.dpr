program FlushFileCache;

{$APPTYPE CONSOLE}

{$SetPEFlags $0001}

uses
   Windows;

type
   SYSTEM_INFORMATION_CLASS = (
      SystemFileCacheInformation = 21,
      SystemMemoryListInformation = 80,
      SystemCombinePhysicalMemoryInformation = 130
   );

   SYSTEM_FILECACHE_INFORMATION = record
      CurrentSize : NativeUInt;
      PeakSize : NativeUInt;
      PageFaultCount : ULONG;
      MinimumWorkingSet : NativeInt;
      MaximumWorkingSet : NativeInt;
      CurrentSizeIncludingTransitionInPages : NativeUInt;
      PeakSizeIncludingTransitionInPages : NativeUInt;
      TransitionRePurposeCount : ULONG;
      Flags : ULONG;
   end;
   PSYSTEM_FILECACHE_INFORMATION = ^SYSTEM_FILECACHE_INFORMATION;

   MEMORY_COMBINE_INFORMATION_EX = record
      Handle : THandle;
      PagesCombined : Cardinal;
      Flags : ULONG;
   end;
   PMEMORY_COMBINE_INFORMATION_EX = ^MEMORY_COMBINE_INFORMATION_EX;

   SYSTEM_MEMORY_LIST_COMMAND = (
      MemoryCaptureAccessedBits,
      MemoryCaptureAndResetAccessedBits,
      MemoryEmptyWorkingSets,
      MemoryFlushModifiedList,
      MemoryPurgeStandbyList,
      MemoryPurgeLowPriorityStandbyList,
      MemoryCommandMax
   );

var
   NtSetSystemInformation : function  (
      SystemInformationClass: SYSTEM_INFORMATION_CLASS;
      SystemInformation: Pointer; //  __in_bcount_opt(SystemInformationLength) PVOID SystemInformation,
      SystemInformationLength: ULONG) : Integer; stdcall;

function SendMemoryCommand(command : SYSTEM_MEMORY_LIST_COMMAND) : Integer;
var
   buf : Integer;
begin
   buf:=Integer(command);
   Result:=NtSetSystemInformation(SystemMemoryListInformation, @buf, SizeOf(buf))
end;

function SetPrivilege(hToken : THandle; lpszPrivilege : PChar; bEnablePrivilege : Boolean) : Boolean;
var
   tp : TTokenPrivileges;
   luid : TLargeInteger;
   rl : DWORD;
begin
   if (not LookupPrivilegeValue(nil, lpszPrivilege, luid)) then
   begin
      Result := False;
      Exit;
   end;

   tp.PrivilegeCount := 1;
   tp.Privileges[0].Luid := luid;
   if bEnablePrivilege then
      tp.Privileges[0].Attributes := SE_PRIVILEGE_ENABLED
   else tp.Privileges[0].Attributes := 0;

   if (not AdjustTokenPrivileges(hToken, FALSE, tp, sizeof(TOKEN_PRIVILEGES), nil, rl)) then
   begin
      Result := False;
      Exit;
   end;

   Result := (GetLastError() <> ERROR_NOT_ALL_ASSIGNED);
end;

var
   ntdll : HMODULE;
   processToken : THandle;
   info : SYSTEM_FILECACHE_INFORMATION;
   infoex : MEMORY_COMBINE_INFORMATION_EX;
   command : Integer;
   option : String;
   full : Boolean;
begin
   WriteLn('RAM Reduct v1.1 - www.DelphiTools.info&GFOXSH'#13#10);

   case ParamCount of
      0 : option:='';
      1 : option:=ParamStr(1);
   else
      option:='help';
   end;

   full:=False;
   if option<>'' then begin
      if option='full' then
         full:=True
      else begin
         Writeln('  help    Show this help');
         Writeln('  full    Flush everything (slow)');
      end;
   end;

   // Get NtSetSystemInformation
   ntdll := LoadLibrary('NTDLL.DLL');
   NtSetSystemInformation := GetProcAddress(ntdll, 'NtSetSystemInformation');
   if not Assigned(NtSetSystemInformation) then begin
      Writeln('Unsupported OS version');
      Exit;
   end;

   if (OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY, processToken) = FALSE) then begin
      Writeln('Failed to open privileges token');
      Exit;
   end;

   // System working set
   if SetPrivilege(processToken, 'SeIncreaseQuotaPrivilege', True) then begin

      ZeroMemory(@info, sizeof(info));
      info.MinimumWorkingSet := -1;
      info.MaximumWorkingSet := -1;
      if NtSetSystemInformation(SystemFileCacheInformation, @info, sizeof(info))>=0 then
         Writeln('Flushed system working set')
      else Writeln('Failed to flush system working set');

   end else Writeln('Failed to obtain IncreaseQuotaPrivilege');

   if SetPrivilege(processToken, 'SeProfileSingleProcessPrivilege', True) then begin

      // Working set (vista+)
      command := Integer(MemoryEmptyWorkingSets);
      if NtSetSystemInformation(SystemMemoryListInformation, @command, sizeof(command))>=0 then
         Writeln('Emptied working set')
      else Writeln('Failed to empty working set');

      // Standby priority-0 list (vista+)
      if SendMemoryCommand(MemoryPurgeLowPriorityStandbyList)>=0 then
          Writeln('Purged standby priority-0 list')
      else Writeln('Failed to purge standby priority-0 list');

      // Combine memory lists (win10+)
      ZeroMemory(@infoex, sizeof(infoex));
      if NtSetSystemInformation(SystemCombinePhysicalMemoryInformation, @infoex, sizeof(infoex))>=0 then
         Writeln('Flushed combine memory lists')
      else Writeln('Failed to flush combine memory lists');

      if full then begin
         // Standby list (vista+)
         if SendMemoryCommand(MemoryPurgeStandbyList)>=0 then
            Writeln('Purged standby list')
         else Writeln('Failed to purge standby list');

         // Modified page list (vista+)
         if SendMemoryCommand(MemoryFlushModifiedList)>=0 then
            Writeln('Flushed modified page list')
         else Writeln('Failed to flush modified page list');
      end;

   end else Writeln('Failed to obtain ProfileSingleProcessPrivilege');
end.
