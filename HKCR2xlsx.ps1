
# https://learn.microsoft.com/en-us/windows/win32/sysinfo/merged-view-of-hkey-classes-root

$numcpus = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

function NullToString($Value) {
   "$Value"
}

function NameOf($Path) {
   Split-Path -Leaf -Path $Path
}

function SubKeyOf($RegKey, $Name) {
   try {
      $RegKey.GetSubKeyNames() | Where-Object { (NameOf $_) -ieq $Name} | ForEach-Object { $RegKey.OpenSubKey($_, $false) }
   } catch {
      Write-Error "$_`nregkey = $RegKey, Name = $Name."
   }
}

# function InterfaceID
function SubKeysOf($RegKey, $Name) {
   {
      if ($null -eq $Name) {
         $RegKey
      } else {
         SubKeyOf $RegKey $Name
      }
   }.Invoke() | ForEach-Object {
      $_regkey = $_
      $_regkey.GetSubKeyNames() | ForEach-Object { $_regkey.OpenSubKey($_, $false) }
   }
}

function ValueOf($RegKey, $Name = '') {
   if ($null -eq $RegKey) {
      ''
   } else {
      NullToString($RegKey.GetValue($Name))
   }
}

function ValuesOf($RegKey, $Name) {
   $Values = @{}
   {
      if ($null -eq $Name) {
         $RegKey
      } else {
         SubKeyOf $RegKey $Name
      }
   }.Invoke() | ForEach-Object {
      $_regkey = $_
      $_regkey.GetValueNames() | ForEach-Object { $Values[$_] = $_regkey.GetValue($_) }
   }
   $Values
}

function IsGUID($id) {
   [guid]::TryParse("$id", [ref][guid]::Empty)
}

function SetGUID($item,$id) {
   $item.id = "$id"
   $id = [guid]::Empty
   [guid]::TryParse($item.id, [ref]$id)
   if ($id.Equals([guid]::Empty)) {
      $id = $item.id
   } else {
      $id = $id.Guid
   }
   $item.guid = "$id"
}

function ShellToHashtable($RegKey, $hh) {
   SubKeysOf $RegKey 'shell' | ForEach-Object {
      $hh.shell.(NameOf $_) = @{
         name = ValueOf $_
         command = ValueOf(SubKeyOf $_ 'command')
      }
   }
}

function ShellExToHashtable($RegKey, $hh) {
   $hhshellex = $hh.shellex
   $handlernames = 'Interfaces,ContextMenuHandlers,CopyHookHandlers,DragDropHandlers,PropertySheetHandlers'.Split(',')
   $handlernames | ForEach-Object {
      if (-not $hhshellex.ContainsKey($_)) {
         $hhshellex.$_ = [System.Collections.ArrayList]::new()
      }
   }
   SubKeysOf $RegKey 'shellex' | ForEach-Object {
      $handlerkey = $_
      $handler_type = NameOf $handlerkey
      if (IsGUID $handler_type) {
         $interface = $handler_type
         $interface_clsid = ValueOf $handlerkey
         $hhshellex.Interfaces += "${handler_type}::${interface_clsid}"

         if (0 -lt $Interface.Length -and $groups.Interface.ContainsKey($Interface)) {
            $groups.Interface.($Interface).FileExtensions += $hh.id
         }

         if (0 -lt $interface_clsid.Length -and $groups.CLSID.ContainsKey($interface_clsid)) {
            $groups.CLSID.($interface_clsid).FileExtensions += $hh.id
         }
      } elseif ($handler_type -iin $handlernames) {
         $hhshellex.$handler_type = [System.Collections.ArrayList]::new()
         $handler = $hhshellex.$handler_type
         SubKeysOf $handlerkey | ForEach-Object {
            $handler_id = NameOf $_
            $handler_value = ValueOf $_
            if ($groups.CLSID.ContainsKey($handler_id)) {
               $handler += "${handler_id}::${handler_value}"
            } elseif ($groups.CLSID.ContainsKey($handler_value)) {
               $handler += "${handler_value}::${handler_id}"
            } else {
               $handler += "?${handler_value}::${handler_id}"
               # handler is unrecognizable: there's no CLSID corresponding to it
            }
         }
      }
   }
}

$groups = @{
   CLSID = @{}
   TypeLib = @{}
   ProgID = @{}
   Interface = @{}
   AppID = @{}
   FileExtension = @{}
}

# <#

New-PSDrive -PSProvider Registry -Name 'HKCR' -Root HKEY_CLASSES_ROOT | Out-Null
$subkeys = 0
$subkey = 0
& {
   Get-Item -LiteralPath 'HKCR:\'
   # Get-Item -LiteralPath 'HKCR:\WOW6432Node\'
} | ForEach-Object {
   $global:subkeys = $_.SubKeyCount
   $global:subkey = 0
   SubKeysOf $_
} | ForEach-Object {
   Write-Progress -Id 0 -Activity "collecting $subkeys subkeys at top level of HKEY_CLASSES_ROOT" -PercentComplete (100*(++$subkey)/$subkeys)
   $class = $_
   $className = NameOf $class.Name
   
   if ($className[0] -eq '.') {
      $groups.FileExtension[$className] = @{
         reg = $class
         id = ''
         clsids = [System.Collections.ArrayList]::new()
         OpenWithProgids = [System.Collections.ArrayList]::new()
         OpenWithList = [System.Collections.ArrayList]::new()
         PersistentHandler = ''
         shell = @{}
         shellex = @{}
      }
   } elseif ($className -iin 'CLSID,TypeLib,AppID,Interface'.Split(',')) {
      $class_subkeys = $class.SubKeyCount
      $class_subkey = 0
      SubKeysOf $class | ForEach-Object {
         Write-Progress -Id 1 -ParentId 0 -Activity "collecting $class_subkeys subkeys under $className" -PercentComplete (100*(++$class_subkey)/$class_subkeys)
         $keyname = NameOf $_.Name
         if ($null -eq $keyname) {
            $null = NameOf $_.Name
         } else {
            $groups.$className[$keyname] = @{
               reg = $_
               id = ''
               clsids = [System.Collections.ArrayList]::new()
            }
         }
      }
      Write-Progress -Id 1 -Completed
   } else {
      $groups.ProgID[$className] = @{
         reg = $class
         id = ''
         clsids = [System.Collections.ArrayList]::new()
         OpenWithList = [System.Collections.ArrayList]::new()
         shell = @{}
         shellex = @{}
         ContextMenus = @{}
         FileExtensions = [System.Collections.ArrayList]::new()
      }
   }
}
Write-Progress -Id 0 -Completed

# Typelib
#    • HKEY_CLASSES_ROOT\TypeLib\{LIBID}
#       ◦ {LIBID}: The globally unique identifier (GUID) of the type library enclosed in braces.
#          ▪ Major.Minor (e.g., 1.0): A subkey representing the version number of the type library (stored in hexadecimal/decimal representation).
#             • (Default) value: Human-readable description/name of the type library.
#             • FLAGS: Optional flags describing the library behavior.
#             • HELPDIR: Directory path where the help file for the type library is located.
#             • LCID (e.g., 0, 409): Subkeys for specific Locale IDs (like neutral or English).
#                ◦ win32 or win64: Platform-specific subkey indicating the target architecture path to the .tlb or module file.
#                   ▪ (Default) value: Full file path to the type library container file (e.g., a .dll, .ocx, or .tlb).
$subkeys = $groups.TypeLib.Count
$subkey = 0
$groups.TypeLib.GetEnumerator() | ForEach-Object {
   Write-Progress -Id 0 -Activity "normalizing $subkeys collected TypeLibs..." -PercentComplete (100*(++$subkey)/$subkeys)
   $TypeID = $_.Key
   $TypeLib = $_.Value
   if ($TypeLib.ContainsKey('reg')) {
      $null = SetGUID $TypeLib $TypeID
      
      $TypeLibVersion = SubKeysOf $TypeLib.reg | Where-Object { (NameOf $_) -match '^[^.]+[.][^.]+$' } | Select-Object -First 1
      if ($null -eq $TypeLibVersion) {
         $TypeLib.version = ''
         $TypeLib.name = ''
         $TypeLib.lcids = @{}
      } else {
         $TypeLib.version = NameOf $TypeLibVersion
         $TypeLib.name = ValueOf $TypeLibVersion
         $TypeLib.lcids = @{}
         SubKeysOf $TypeLibVersion | ForEach-Object {
            $localekey = $_
            $localekeyname = NameOf $localekey
            if ($localekeyname -match '^[0-9]+$') {
               SubKeysOf $localekey | ForEach-Object {
                  $platform = $_
                  $TypeLib.lcids."$localekeyname.$(NameOf $platform)" = [System.Environment]::ExpandEnvironmentVariables((ValueOf $platform))
               }
            }
         }
      }

      $TypeLib.Remove('reg')
   }
}
Write-Progress -Id 0 -Completed



# HKEY_CLASSES_ROOT\Interface\
#    └── {Interface-GUID}              (The IID, e.g., {00020400-0000-0000-C000-000000000046})
#         ├── (Default)                = "Friendly Name of the Interface"
#         ├── BaseInterface            = "{Base-Interface-GUID}" (Optional)
#         ├── NumMethods               = "Number of methods in the vtable" (Optional)
#         ├── ProxyStubClsid32         = "{Proxy-Stub-CLSID-GUID}"
#         └── TypeLib                  = "{Type-Library-GUID}"
#              └── (Default)           = "{Type-Library-GUID}"
#              └── Version             = "1.0"
# Key Components Explained
#     • {Interface-GUID} (The Root Subkey)
#         ◦ Purpose: This 128-bit unique identifier distinguishes the interface from all others.
#         ◦ Default Value: A string containing the human-readable, friendly name of the interface (e.g., IDispatch or IUnknown).
#     • BaseInterface
#         ◦ Purpose: Identifies the parent interface from which this interface inherits.
#         ◦ Value: The IID of the parent interface. If an interface derives directly from IUnknown (the root of all COM interfaces), this key is often omitted.
#     • NumMethods
#         ◦ Purpose: Specifies the total number of methods contained within the interface’s virtual method table (vtable).
#         ◦ Value: A string or DWORD representing the count. This includes all inherited methods from base interfaces.
#     • ProxyStubClsid32
#         ◦ Purpose: Points to the Class ID (CLSID) of the 32-bit (or 64-bit on modern architecture) proxy/stub DLL responsible for marshaling the interface.
#         ◦ Value: A CLSID GUID. Marshaling packages data packets across thread, process, or network boundaries so different applications can communicate using the interface.
#     • TypeLib
#         ◦ Purpose: References the Type Library that describes the interface's methods, parameters, and types.
#         ◦ Subkeys: Typically includes a Version string value. The TypeLib allows automation controllers (like VBScript or VBA) to perform late binding and discover interface features at runtime.
#
# SynchronousInterface
# AsynchronousInterface @ = InterfaceID -> SynchronousInterface @ -> InterfaceID
#
# AsynchronousInterface
# Distributor
# NumMethods
# ProxyStubClsid
# ProxyStubClsid32
# SynchronousInterface
# TypeLib
# TypeLib\Version
$subkeys = $groups.Interface.Count
$subkey = 0
$r | ForEach-Object -ThrottleLimit $numcpus -Parallel {}
$groups.Interface.GetEnumerator() | ForEach-Object {
   # -ThrottleLimit $numcpus -Parallel
   Write-Progress -Id 0 -Activity "normalizing $subkeys collected Interfaces..." -PercentComplete (100*(++$subkey)/$subkeys)
   $InterfaceID = $_.Key
   $interface = $_.Value
   if ($interface.ContainsKey('reg')) {
      $interfacekey = $interface.reg
      $null = SetGUID $interface $InterfaceID
      $interface.name = ValueOf $interfacekey
      $interface.FileExtensions = [System.Collections.ArrayList]::new()
      $interface.ProgIDs = [System.Collections.ArrayList]::new()
      'AsynchronousInterface,Distributor,NumMethods,ProxyStubClsid,ProxyStubClsid32,SynchronousInterface,TypeLib'.Split(',') | ForEach-Object {
         $interface.$_ = ValueOf(SubKeyOf $interfacekey $_)
      }
      $interface.Remove('reg')
   }
}
Write-Progress -Id 0 -Completed




# https://learn.microsoft.com/en-us/windows/win32/com/appid-key
# Common Values Inside an AppID GUID Key
# Each {GUID} subkey can contain string or binary values that define how the COM server runs and behaves:
#     • (Default): Descriptive name of the application (friendly name).
#     • RunAs: Specifies a user account identity under which the COM server should run (e.g., Interactive User or a specific username).
#     • AuthenticationLevel: Sets the security level for incoming calls (e.g., 1 for None, 4 for Packet, 6 for PktPrivacy).
#     • AccessPermission / LaunchPermission: Binary security descriptors defining access control lists (ACLs) for local and remote activation/launching.
#     • DllSurrogate: Specifies if an in-process (.dll) server runs inside a surrogate executable process like dllhost.exe.
#     • LocalService: service name
#     • ServiceParameters: service parameters
#
# Linkage to CLSID
# COM classes link themselves to an AppID through a value inside their own registration path:
#     • Located at HKEY_CLASSES_ROOT\CLSID\{Class-GUID}
#     • Contains an AppID named value containing the matching {AppID-GUID}, tying the individual class behavior to the broader application configuration.
$subkeys = $groups.AppID.Count
$subkey = 0
[System.Collections.ArrayList]$AppIDsToRemove = @()
$groups.AppID.GetEnumerator() | ForEach-Object {
   Write-Progress -Id 0 -Activity "normalizing $subkeys collected AppIDs..." -PercentComplete (100*(++$subkey)/$subkeys)
   $AppID = $_.Key
   $app = $_.Value
   if ($app.ContainsKey('reg')) {
      $appkey = $app.reg
      if (SetGUID $app $AppID) {
         $app.name = ValueOf $appkey
         'LocalService,ServiceParameters,RunAs,DllSurrogate'.Split(',') | ForEach-Object {
            $app.$_ = ValueOf $appkey $_
         }
         $app.Remove('reg')
      } else {
         $AppID0 = $AppID
         $AppID = ValueOf $appkey 'AppId'
         if ($null -eq $AppID) {
            throw [System.Exception] "$AppID0 has no AppID"
         } else {
            $app = $groups.AppID.$AppID
            if ($null -ne $app) {
               $app.exe = $AppID0
            }
            $AppIDsToRemove += $AppID0
         }
      }
   }
}
$AppIDsToRemove.ForEach({$groups.AppID.Remove($_)})
Write-Progress -Id 0 -Completed



# Structure of a CLSID Key
# Inside the registry, a specific CLSID key looks like this:
# HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\{CLSID-GUID}
# Under this main curly-braced GUID folder, Windows uses standard subkeys and values to define how the object runs:
#     • Default Value (Unnamed): Holds a human-readable description or name of the COM class (e.g., "Recycle Bin" or a specific application handler).
#     • InprocServer32: Points to a 32-bit or 64-bit Dynamic Link Library (.dll) file that runs directly inside the client application's process space.
#         ◦ Default value: Path to the DLL file (e.g., C:\Windows\System32\shell32.dll).
#         ◦ Value ThreadingModel: Defines threading rules (e.g., Apartment, Free, or Both).
#     • LocalServer32: Points to a standalone Executable (.exe) file that runs the COM object in its own separate process.
#         ◦ Default value: Path to the executable file.
#     • ProgID / VersionIndependentProgID: Links the cryptic GUID to a friendly programmatic identifier name (e.g., Excel.Application).
#     • AppID: Connects the CLSID to a specific Application ID settings group for security and DCOM permissions.
#
#    TypeLib = TypeID
#    AppID => AppID
$subkeys = $groups.CLSID.Count
$subkey = 0
$groups.CLSID.GetEnumerator() | ForEach-Object {
   Write-Progress -Id 0 -Activity "normalizing $subkeys collected CLSIDs..." -PercentComplete (100*(++$subkey)/$subkeys)
   $CLSID = $_.Key
   $class = $_.Value
   if ($class.ContainsKey('reg')) {
      $classkey = $class.reg
      $null = SetGUID $class $CLSID
      $class.name = ValueOf $classkey
      $class.TypeLibIsInterface = $false
      $class.InterfaceTypeLib = ''
      $class.FileExtensions = [System.Collections.ArrayList]::new()
      'InprocServer32,InprocHandler32,LocalServer32,ProgID,VersionIndependentProgID,AppID,TypeLib'.Split(',') | ForEach-Object {
         $classproperty = $_
         $groupkey = $classproperty -replace 'VersionIndependentProgID','ProgID'
         $class.$classproperty = ValueOf(SubKeyOf $classkey $classproperty)
         $classproperty = $class.$classproperty
         if ($groups.ContainsKey($groupkey) -and 0 -lt $classproperty.Length) {

            # sometimes a TypeLib guid does not exist because it is actually an interface guid,
            # so here we search into interfaces then jump to the correct TypeLib.
            if ($groupkey -ieq 'TypeLib' -and -not $groups.TypeLib.ContainsKey($classproperty) -and $groups.Interface.ContainsKey($classproperty)) {
               $class.TypeLibIsInterface = $true
               $class.InterfaceTypeLib = $groups.Interface.$classproperty.TypeLib
               $groupkey = 'Interface'
               $groups.Interface.$classproperty.clsids += $class.id
            }
            try {
               if ($groups.$groupkey.ContainsKey($classproperty)) {
                  $groups.$groupkey.$classproperty.clsids += $class.id
               }
            } catch {
               Write-Error "$_`n`$groups.`$groupkey.`$classproperty += `$class.id ==> `$groups.$groupkey.$classproperty += $($class.id)."
            }
         }
      }
      $class.Remove('reg')
      $class.Remove('clsids')
   }
}
Write-Progress -Id 0 -Completed



# ProgID (also '*')
#    @ = (description)
#    CLSID
#    [-or-]
#    CurVer
#    [-or-]
#    OpenWithList
#       (each key is an EXE name, to be found in PATH)
#    ContextMenus
#       <shortname>
#          shell
#             <shortname> or runas to get Admin rights
#                command @ = (command line with variables)
#                MUIVerb = menu item to show
#    shell
#       new
#          command @ = (command line with variables)
#       open
#          command @ = (command line with variables)
#       print
#          command @ = (command line with variables)
#       printto
#          command @ = (command line with variables)
#    shellex
#       ContextMenuHandlers
#          Name @ = CLSID
#          or
#          {CLSID} @ = Name
#       CopyHookHandlers
#          Name @ = CLSID
#          or
#          {CLSID} @ = Name
#       DragDropHandlers
#          Name @ = CLSID
#          or
#          {CLSID} @ = Name
#       PropertySheetHandlers
#          Name @ = CLSID
#          or
#          {CLSID} @ = Name
$subkeys = $groups.ProgID.Count
$subkey = 0
$groups.ProgID.GetEnumerator() | ForEach-Object {
   Write-Progress -Id 0 -Activity "normalizing $subkeys collected ProgIDs..." -PercentComplete (100*(++$subkey)/$subkeys)
   $ProgIDName = $_.Key
   $progid = $_.Value
   if ($progid.ContainsKey('reg')) {
      $progidkey = $progid.reg
      $null = SetGUID $progid $ProgIDName
      $progid.name = ValueOf $progidkey
      'CLSID,CurVer'.Split(',') | ForEach-Object {
         $progid.$_ = ValueOf(SubKeyOf $progidkey $_)
      }
      SubKeysOf $progidkey 'OpenWithList' | ForEach-Object { $progid.OpenWithList += NameOf $_ }

      # TODO: ContextMenus

      if ($progid.CLSID.Length -eq 0 -and $progid.CurVer.Length -eq 0) {
         ShellToHashtable $progidkey $progid
         ShellExToHashtable $progidkey $progid
      }
      $progid.Remove('reg')
   }
}
Write-Progress -Id 0 -Completed



# '.*' = extension
#    @ = ProgID
#    DefaultIcon @ = exe/dll name
#    OpenWithList
#    OpenWithProgIDs
#    PersistentHandler
#    Shell
#    ShellNew
#    ShellEx --> Classes\Interface\...\ProxyStubClsid32 --> CLSID
#       InterfaceID1 -> CLSID
#       InterfaceID2 -> CLSID
#       ...
$subkeys = $groups.FileExtension.Count
$subkey = 0
$r | ForEach-Object -ThrottleLimit $numcpus -Parallel {}
$groups.FileExtension.GetEnumerator() | ForEach-Object {
   # -ThrottleLimit $numcpus -Parallel
   Write-Progress -Id 0 -Activity "normalizing $subkeys collected FileExtensions..." -PercentComplete (100*(++$subkey)/$subkeys)
   $FileExtensionID = $_.Key
   $FileExtension = $_.Value
   if ($FileExtension.ContainsKey('reg')) {
      $FileExtensionkey = $FileExtension.reg
      $null = SetGUID $FileExtension $FileExtensionID
      $FileExtension.name = ValueOf $FileExtensionkey

      if (0 -lt $FileExtension.name.Length -and $group.ProgID.ContainsKey($FileExtension.name)) {
         $group.ProgID.($FileExtension.name).FileExtensions += $FileExtension.id
      }

      $FileExtension.OpenWithProgids += (ValuesOf $FileExtensionkey 'OpenWithProgIDs').Keys
      $FileExtension.OpenWithProgids | ForEach-Object { $group.ProgID.$_.FileExtensions += $FileExtension.id }

      # TODO/FIXME: add handling of 'shell' subkeys where present
      $FileExtension.OpenWithList += SubKeysOf $FileExtensionkey 'OpenWithList' | ForEach-Object { NameOf $_ }

      $FileExtension.PersistentHandler = ValueOf(SubKeyOf $FileExtensionkey 'PersistentHandler')
      if (0 -lt $FileExtension.PersistentHandler.length) {
         $groups.CLSID.FileExtensions += $FileExtension.id
      }

      ShellToHashtable $FileExtensionkey $FileExtension
      ShellExToHashtable $FileExtensionkey $FileExtension

      $FileExtension.Remove('reg')
   }
}
Write-Progress -Id 0 -Completed


ConvertTo-Json -Depth 8 -InputObject $groups > groups.json
#>
<#
ConvertTo-Json -Depth 8 -InputObject $groups.CLSID | clip
ConvertTo-Json -Depth 8 -InputObject $groups.TypeLib | clip
ConvertTo-Json -Depth 8 -InputObject $groups.Interface | clip
ConvertTo-Json -Depth 8 -InputObject $groups.AppID | clip
ConvertTo-Json -Depth 8 -InputObject $groups.ProgID | clip
ConvertTo-Json -Depth 8 -InputObject $groups.FileExtension | clip
#>
$groups = Get-Content -Raw groups.json | ConvertFrom-Json -Depth 8 -AsHashtable

Import-Module ImportExcel

$excelfile = $PSCommandPath -replace '.ps1$',''
$excelfile = "$excelfile.xlsx"

$groups.TypeLib.Values | ForEach-Object {
   [pscustomobject]@{
      id = $_.id
      guid = $_.guid
      name = $_.name
      clsids = $_.clsids -join ','
      version = $_.version
      lcids = ($_.lcids.GetEnumerator() | ForEach-Object { "$($_.Key)::$($_.Value)" }) -join ', '
   }
} | Export-Excel -Path $excelfile -WorksheetName 'TypeLibs'

$groups.Interface.Values | ForEach-Object {
   [pscustomobject]@{
      id = $_.id
      guid = $_.guid
      name = $_.name
      clsids = $_.clsids -join ','
      ProgIDs = $_.ProgIDs -join ','
      NumMethods = $_.NumMethods
      TypeLib = $_.TypeLib
      FileExtensions = $_.FileExtensions -join ','
      ProxyStubClsid = $_.ProxyStubClsid
      AsynchronousInterface = $_.AsynchronousInterface
      ProxyStubClsid32 = $_.ProxyStubClsid32
      Distributor = $_.Distributor
      SynchronousInterface = $_.SynchronousInterface
   }
} | Export-Excel -Path $excelfile -WorksheetName 'Interfaces'

$groups.AppID.Values | ForEach-Object {
   [pscustomobject]@{
      id = $_.id
      guid = $_.guid
      name = $_.name
      clsids = $_.clsids -join ','
      LocalService = $_.LocalService
      ServiceParameters = $_.ServiceParameters
      DllSurrogate = $_.DllSurrogate
      RunAs = $_.RunAs
      exe = $_.exe
   }
} | Export-Excel -Path $excelfile -WorksheetName 'AppIDs'

$groups.CLSID.Values | ForEach-Object {
   [pscustomobject]@{
      id = $_.id
      guid = $_.guid
      name = $_.name
      FileExtensions = $_.FileExtensions -join ','
      TypeLib = $_.TypeLib
      TypeLibIsInterface = $_.TypeLibIsInterface
      InterfaceTypeLib = $_.InterfaceTypeLib
      AppID = $_.AppID
      ProgID = $_.ProgID
      VersionIndependentProgID = $_.VersionIndependentProgID
      LocalServer32 = $_.LocalServer32
      InprocServer32 = $_.InprocServer32
      InprocHandler32 = $_.InprocHandler32
   }
} | Export-Excel -Path $excelfile -WorksheetName 'CLSIDs'

$groups.ProgID.Values | ForEach-Object {
   [pscustomobject]@{
      id = $_.id
      guid = $_.guid
      name = $_.name
      clsids = $_.clsids -join ','
      CLSID = $_.CLSID
      FileExtensions = $_.FileExtensions -join ','
      CurVer = $_.CurVer
      OpenWithList = $_.OpenWithList -join ','
      shell = ($_.shell.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.command)::$($_.Value.name)" }) -join ','
      shellex = @($_.shellex.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value -join ',')" }) -join '; '
      ContextMenus = $_.ContextMenus
   }
} | Export-Excel -Path $excelfile -WorksheetName 'ProgIDs'

$groups.FileExtension.Values | ForEach-Object {
   [pscustomobject]@{
      id = $_.id
      guid = $_.guid
      name = $_.name
      clsids = $_.clsids -join ','
      PersistentHandler = $_.PersistentHandler
      OpenWithList = $_.OpenWithList -join ','
      shell = ($_.shell.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.command)::$($_.Value.name)" }) -join ','
      shellex = @($_.shellex.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value -join ',')" }) -join '; '
      OpenWithProgids = $_.OpenWithProgids -join ','
   }
} | Export-Excel -Path $excelfile -WorksheetName 'FileExtensions'
