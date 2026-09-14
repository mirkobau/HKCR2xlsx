# HKCR2xlsx
HKEY_CLASSES_ROOT to xlsx (Exce) exporter - a tool which helps analyze the links between CLSIDs, Interfaces, Typelibs, AppIDs, ProgIDs, and File Extensions in Windows Registry

## code status
As of today, 2026-09-14, the code is working pretty good but there is a *HUGE* need of comments.

Many improvements are needed, but it will happen when I'll have time.

## A little explanation
Under HKCR you can find keys of different types: CLSID, Interface, Typelib, AppID, ProgID, and File Extension

Each type is linked to one or more of the others by a _guid_ or simply by name.

This PowerShell script generates a multi-sheet XLSX file (modern so-called "Excel format").
Each sheet represents a key type and contains a single table of all elements of that type.

Some columns in each table point to an element which can be found (hopefully) in one of the other tables.

I tried the best to make all values readable, or at least scriptable.

Have fun.

## Improvements
1. Add flag to identify nonexistent paths
2. Add support for other types; for example, the 'MIME' subtree is completely not implemented here.